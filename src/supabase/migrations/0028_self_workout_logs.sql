-- =====================================================================
-- 0028_self_workout_logs.sql
--
-- 회원 셀프 운동 기록 테이블 신설 — S4 / develop_plan §4 2.5.
--
-- 배경(기획서 답변 11): 회원이 혼자 운동한 날 "어떤 동작에서 어디가 아팠고
--   어떻게 했더니 나아졌다"를 남기면 좋다. 단, **무조건 간단 입력**이어야 한다
--   (복잡한 엑셀은 회원이 안 씀 — 인터뷰 실패 사례). 그래서 필드는 3개로 최소화:
--     logged_at(날짜) / workout(운동 한 줄) / note(통증·컨디션 메모).
--
-- ⚠ session_records(트레이너가 쓰는 수업 기록)와 다른 테이블인 이유:
--   - session_records : 트레이너가 작성, 계약/수업(session)에 종속. next_memo 등 트레이너 전용.
--   - self_workout_logs : **회원이 직접** 작성, 수업과 무관한 자율 운동 일지.
--   책임·작성 주체·가시성이 달라 분리한다.
--
-- 가시성(body_measurements 와 정반대):
--   - 회원   : 본인 기록 rw(작성/수정/삭제).
--   - 트레이너: 담당 회원 기록 read-only(통증 내역을 보고 수업에 반영 — 케어 가치).
--             쓰기는 못 함(셀프 기록은 회원의 것).
--
-- 식별자 정책(0013 이후): member_id 는 member_profiles.id(PK) 참조.
--   회원이 INSERT 시 member_id 를 넘기지 않아도 되도록 DEFAULT 를
--   current_member_profile_id() 로 둔다. 위변조는 RLS WITH CHECK 가 막는다.
--
-- 멱등: CREATE TABLE/INDEX IF NOT EXISTS, DROP POLICY IF EXISTS → CREATE.
--
-- 참고: docs/develop_plan.md §4 Phase 2 2.5, 0009(헬퍼)·0013(member_id 정책)·0023(가시성 대칭 사례).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. 테이블
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS self_workout_logs (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- 작성 회원. 회원이 직접 넘기지 않아도 되도록 본인 프로필 id 를 기본값으로.
  -- 회원 삭제(hard)되면 일지도 함께 정리.
  member_id   uuid NOT NULL
                DEFAULT current_member_profile_id()
                REFERENCES member_profiles(id) ON DELETE CASCADE,

  -- 기록 날짜(시각 불필요 → date). 기본 오늘.
  logged_at   date NOT NULL DEFAULT CURRENT_DATE,

  -- 운동 내용 한 줄(예: "하체 - 스쿼트, 레그프레스"). 메모만 남길 수도 있어 nullable.
  workout     text,

  -- 통증·컨디션 메모(예: "스쿼트 때 왼쪽 무릎 시큰 → 무게 낮추니 괜찮음"). nullable.
  note        text,

  created_at  timestamptz NOT NULL DEFAULT now(),

  -- 운동/메모가 둘 다 비면 의미 없는 빈 기록 → 최소 하나는 있어야 한다.
  -- (앱은 trim 후 빈 값을 NULL 로 보내므로 빈 문자열은 사실상 NULL 로 들어온다)
  CONSTRAINT self_log_not_blank CHECK (workout IS NOT NULL OR note IS NOT NULL)
);

-- 회원별 + 날짜 내림차순(최신 먼저) 조회가 주 패턴 → 복합 인덱스.
CREATE INDEX IF NOT EXISTS idx_self_log_member_date
  ON self_workout_logs(member_id, logged_at DESC);


-- ---------------------------------------------------------------------
-- 2. RLS
-- ---------------------------------------------------------------------
ALTER TABLE self_workout_logs ENABLE ROW LEVEL SECURITY;

-- 2-1) 회원: 본인 기록만 전부 다룰 수 있음(조회/작성/수정/삭제).
--      WITH CHECK 로 member_id 위변조 차단 — 남의 id 로는 INSERT/UPDATE 불가.
DROP POLICY IF EXISTS self_log_member_rw ON self_workout_logs;
CREATE POLICY self_log_member_rw ON self_workout_logs
  FOR ALL
  USING (member_id = current_member_profile_id())
  WITH CHECK (member_id = current_member_profile_id());

-- 2-2) 트레이너: 담당 회원 기록 read-only. 쓰기 권한 없음(FOR SELECT).
DROP POLICY IF EXISTS self_log_trainer_read ON self_workout_logs;
CREATE POLICY self_log_trainer_read ON self_workout_logs
  FOR SELECT
  USING (
    current_user_role() = 'trainer'
    AND is_member_of_trainer(member_id)
  );


-- ---------------------------------------------------------------------
-- 검증 SQL (적용 후 SQL Editor):
--   -- 1) 테이블/컬럼/기본값
--   SELECT column_name, data_type, column_default, is_nullable
--   FROM information_schema.columns WHERE table_name = 'self_workout_logs';
--
--   -- 2) RLS 정책 2개(member rw=ALL / trainer read=SELECT)
--   SELECT polname, cmd FROM pg_policies WHERE tablename = 'self_workout_logs';
--   → self_log_member_rw(ALL) / self_log_trainer_read(SELECT) 기대.
-- ---------------------------------------------------------------------
