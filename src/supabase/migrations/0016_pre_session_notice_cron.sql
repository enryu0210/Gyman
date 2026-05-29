-- =====================================================================
-- 0016_pre_session_notice_cron.sql
-- Phase 1.8 — 수업 전날 회원 안내 메시지 자동 적재 (기본 템플릿)
--
-- 결정(계획서 §4 1.8 갱신본):
--   계획서 원문은 "Edge Function + cron"이었으나, 현재 워크플로가
--   SQL Editor 수동 적용 방식이고 Edge Function 배포 파이프라인이 없어
--   **순수 SQL(plpgsql 함수 + pg_cron)** 로 구현한다.
--   또한 FCM/회원앱(발송 채널)이 아직 없으므로 본 작업의 범위는
--   "발송"이 아니라 **draft 안내를 발송 큐에 자동 적재**까지다.
--   실제 발송(draft→approved→sent)과 검수 UI는 1.9 AI 검수 허브에서 통합.
--
-- 동작 요약:
--   매일 1회(KST 09:00) 실행 → '내일(KST)' 예정된 scheduled 수업을 스캔 →
--   회원별 기본 템플릿 안내 메시지를 outgoing_notifications 에 status='draft'
--   (ai_generated=false) 로 적재. 트레이너가 검수 후 승인해야 회원에게 도달.
--
-- 멱등 핵심:
--   outgoing_notifications 에는 원래 세션 참조 컬럼이 없어 같은 수업에 대한
--   중복 적재를 막을 수 없었다. 본 마이그레이션에서 source_session_id 를 추가하고
--   부분 유니크 인덱스 + INSERT 시 NOT EXISTS 가드로 이중 방지한다.
--
-- 참고: docs/develop_plan.md §4 Phase 1.8, 와이어프레임 06_ai_review.md
--       (pre_session 안내도 검수 허브에서 draft 로 노출됨)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. outgoing_notifications 에 세션 출처 컬럼 추가 (멱등 + audit)
--    어떤 수업에 대한 안내인지 추적 + 중복 적재 방지의 기준 키.
--    수업이 삭제되면 안내도 의미가 없으므로 ON DELETE CASCADE.
-- ---------------------------------------------------------------------
ALTER TABLE outgoing_notifications
  ADD COLUMN IF NOT EXISTS source_session_id uuid
  REFERENCES sessions(id) ON DELETE CASCADE;

-- 같은 수업에 대해 pre_session 안내는 최대 1건만 존재하도록 강제.
-- 부분 인덱스: source_session_id 가 NULL 인 다른 트리거(재등록 등)는 영향 없음.
CREATE UNIQUE INDEX IF NOT EXISTS uq_notif_pre_session
  ON outgoing_notifications(source_session_id)
  WHERE trigger_type = 'pre_session';


-- ---------------------------------------------------------------------
-- 2. 적재 함수 enqueue_pre_session_notices()
--    SECURITY DEFINER: 여러 트레이너의 행을 한 번에 insert 하므로
--    outgoing_notifications 의 RLS(trainer_id = auth.uid())를 우회해야 한다.
--    cron(postgres 롤)이 호출하거나 관리 목적 수동 호출용.
--    반환값: 이번 실행에서 새로 적재한 건수 (테스트/모니터링용).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION enqueue_pre_session_notices()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inserted integer;
  -- '내일'은 트레이너/회원 생활 기준(KST)으로 판단해야 함. timestamptz 는 UTC 저장이라
  -- 단순 +1 day 가 아니라 KST 로 변환한 날짜로 비교한다.
  v_tomorrow_kst date := (now() AT TIME ZONE 'Asia/Seoul')::date + 1;
  -- 발송 예정 시각: 수업 전날(=오늘) 저녁 20:00 KST. 와이어프레임 06 기준.
  -- (실제 발송기는 아직 없음 — 본 값은 검수/표시용 메타데이터)
  v_scheduled_for timestamptz :=
    (date_trunc('day', now() AT TIME ZONE 'Asia/Seoul') + interval '20 hours')
      AT TIME ZONE 'Asia/Seoul';
BEGIN
  INSERT INTO outgoing_notifications (
    trainer_id, target_member_id, source_session_id,
    trigger_type, content, status, ai_generated, scheduled_for
  )
  SELECT
    c.trainer_id,
    c.member_id,
    s.id,
    'pre_session',
    -- 기본 템플릿(비-AI). 회원 이름 + 수업 시각 + 트레이너 서명.
    m.name || '님, 안녕하세요! 내일 '
      || to_char(s.scheduled_at AT TIME ZONE 'Asia/Seoul', 'MM월 DD일 HH24시 MI분')
      || ' 수업 예정입니다. 오늘 컨디션은 어떠신가요? 내일 뵙겠습니다!'
      || E'\n\n- ' || t.name || ' 트레이너 드림',
    'draft',
    false,
    v_scheduled_for
  FROM sessions s
  JOIN pt_contracts   c ON c.id = s.contract_id    AND c.deleted_at IS NULL
  JOIN member_profiles m ON m.id = c.member_id      AND m.deleted_at IS NULL
  JOIN trainer_profiles t ON t.user_id = c.trainer_id AND t.deleted_at IS NULL
  -- 아직 진행 예정인 수업만 (done/no_show/late_cancel/canceled 제외)
  WHERE s.status = 'scheduled'
    AND (s.scheduled_at AT TIME ZONE 'Asia/Seoul')::date = v_tomorrow_kst
    -- 멱등: 같은 수업에 대한 pre_session 안내가 이미 있으면 건너뜀
    AND NOT EXISTS (
      SELECT 1 FROM outgoing_notifications n
      WHERE n.source_session_id = s.id
        AND n.trigger_type = 'pre_session'
    );

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  RETURN v_inserted;
END;
$$;

COMMENT ON FUNCTION enqueue_pre_session_notices() IS
  'Phase 1.8: 내일(KST) 예정 수업에 대한 pre_session 안내 draft 를 적재. 멱등. 반환=신규 적재 건수.';


-- ---------------------------------------------------------------------
-- 3. pg_cron 일일 스케줄 등록 (가드 처리)
--    pg_cron 미설치 환경에서도 본 파일이 깨지지 않도록 존재 여부를 먼저 확인.
--    설치돼 있으면 동일 잡을 재등록(멱등), 없으면 안내만 출력.
--
--    pg_cron 은 UTC 기준으로 동작 → '0 0 * * *' = 매일 00:00 UTC = 09:00 KST.
--    아침에 적재해 두면 트레이너가 낮 동안 검수, 예정 발송 20:00 KST 전 처리 가능.
--
--    ※ pg_cron 미설치 시: Supabase 대시보드 > Database > Extensions 에서
--      pg_cron 활성화 후 본 블록(또는 0016 전체)을 재실행하면 등록됨.
-- ---------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    -- 기존 동일 이름 잡 제거 후 재등록 (멱등)
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'enqueue-pre-session-notices') THEN
      PERFORM cron.unschedule('enqueue-pre-session-notices');
    END IF;

    PERFORM cron.schedule(
      'enqueue-pre-session-notices',
      '0 0 * * *',
      'SELECT public.enqueue_pre_session_notices();'
    );

    RAISE NOTICE 'pg_cron 잡 "enqueue-pre-session-notices" 등록 완료 (매일 00:00 UTC / 09:00 KST).';
  ELSE
    RAISE NOTICE 'pg_cron 미설치 — 대시보드 > Database > Extensions 에서 pg_cron 활성화 후 0016 을 재실행하세요. (함수 자체는 이미 생성됨, 수동 호출 가능)';
  END IF;
END
$$;


-- ---------------------------------------------------------------------
-- 검증 SQL (SQL Editor 에서 수동 확인):
--
--   -- 1) 컬럼/인덱스 적용 확인
--   SELECT column_name FROM information_schema.columns
--   WHERE table_name = 'outgoing_notifications' AND column_name = 'source_session_id';
--   SELECT indexname FROM pg_indexes WHERE indexname = 'uq_notif_pre_session';
--
--   -- 2) 함수 즉시 실행(오늘 기준 '내일' 수업 적재). 반환값 = 적재 건수.
--   SELECT enqueue_pre_session_notices();
--
--   -- 3) 다시 실행해도 0 이어야 함(멱등 확인)
--   SELECT enqueue_pre_session_notices();
--
--   -- 4) 적재된 draft 확인
--   SELECT target_member_id, trigger_type, status, scheduled_for, left(content, 40)
--   FROM outgoing_notifications WHERE trigger_type = 'pre_session'
--   ORDER BY created_at DESC;
--
--   -- 5) cron 잡 등록 확인 (pg_cron 활성화된 경우)
--   SELECT jobname, schedule, command FROM cron.job
--   WHERE jobname = 'enqueue-pre-session-notices';
-- ---------------------------------------------------------------------
