-- =====================================================================
-- 0017_ai_call_logs.sql
-- Phase 1.11 — LLM 호출 감사 로그 + 일일 호출 한도(비용 가드)의 근거 테이블
--
-- 왜:
--   - 비용 폭주 방지: 트레이너별 "오늘 성공 호출 수"를 세서 한도 초과 시 차단
--     (develop_plan §7 "LLM 비용 폭주").
--   - audit: 어떤 트레이너가 어떤 회원/트리거로 호출했고 성공/실패했는지 추적
--     (develop_plan §6 "AI 생성 콘텐츠 audit log").
--   - 실제 프롬프트/PII 는 여기 저장하지 않는다 — 마스킹된 스냅샷은
--     outgoing_notifications.ai_prompt_snapshot 에. 본 표는 메타데이터만.
--
-- 멱등 패턴(CLAUDE.md): CREATE TABLE IF NOT EXISTS / CREATE INDEX IF NOT EXISTS /
--   DROP POLICY IF EXISTS → CREATE POLICY.
-- 참고: docs/develop_plan.md §4 1.11, §6, §7.
-- =====================================================================

CREATE TABLE IF NOT EXISTS ai_call_logs (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trainer_id    uuid NOT NULL REFERENCES trainer_profiles(user_id),
  -- 어떤 회원 대상이었는지(있으면). member 삭제와 무관하게 로그는 남도록 FK 미설정.
  member_id     uuid,
  function_name text NOT NULL,            -- 예: 'generate-message-draft'
  trigger_type  text,                     -- pre_session / renewal_* 등
  -- 'success' : LLM 응답 받아 draft 적재 성공
  -- 'failed'  : LLM/네트워크 오류 (앱은 수동 입력으로 폴백)
  -- 'blocked' : 동의 거부 / 한도 초과 등 사전 차단
  status        text NOT NULL,
  model         text,                     -- 사용 모델 (gemini-3.5-flash 등)
  error         text,                     -- 실패 사유 요약 (PII 금지)
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- "오늘 트레이너별 성공 호출 수" 빠른 집계용.
CREATE INDEX IF NOT EXISTS idx_ai_call_logs_trainer_day
  ON ai_call_logs(trainer_id, created_at);

-- ---------------------------------------------------------------------
-- RLS: 트레이너는 본인 로그만 읽고 쓴다.
--   Edge Function 이 트레이너 JWT 컨텍스트로 동작하므로 service_role 불필요.
--   WITH CHECK 까지 명시 — INSERT 시 trainer_id 위조 차단.
-- ---------------------------------------------------------------------
ALTER TABLE ai_call_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ai_logs_trainer_rw ON ai_call_logs;
CREATE POLICY ai_logs_trainer_rw ON ai_call_logs
  FOR ALL
  USING (trainer_id = auth.uid())
  WITH CHECK (trainer_id = auth.uid());

-- ---------------------------------------------------------------------
-- 검증 SQL:
--   -- 오늘 내 성공 호출 수 (Edge Function 의 한도 체크와 동일 식)
--   SELECT count(*) FROM ai_call_logs
--   WHERE status = 'success'
--     AND created_at >= (now() AT TIME ZONE 'Asia/Seoul')::date;
-- ---------------------------------------------------------------------
