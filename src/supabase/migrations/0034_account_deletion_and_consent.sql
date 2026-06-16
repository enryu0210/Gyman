-- =====================================================================
-- 0034_account_deletion_and_consent.sql
--
-- (1) 회원 탈퇴 로그 + (2) 이용약관/개인정보 동의 기록.
--   운톡 불만 #1(탈퇴 불가)·계정 복구 + develop_plan §4 Phase 3.5(약관·동의) 대응.
--
-- 탈퇴 처리 방식(사용자 결정): **익명화**.
--   실제 익명화(PII 제거)와 auth 계정 삭제는 service_role 이 필요해
--   Edge Function `delete-account` 가 수행한다(클라 anon 키로는 불가).
--   본 마이그레이션은 그 함수가 적재할 **로그 테이블**과, 가입 시 받는
--   **동의 기록 테이블**만 만든다.
--
-- ⚠ 익명화 순서(중요): member_profiles.user_id 는 auth.users 에
--   ON DELETE CASCADE 로 묶여 있다(0003). auth 계정을 먼저 지우면
--   회원 프로필까지 cascade 삭제된다. 그래서 Edge Function 은
--   "user_id=NULL 로 분리 + PII 익명화 → 그 다음 auth 계정 삭제" 순서를 지킨다.
--
-- 멱등: CREATE TABLE IF NOT EXISTS / DROP POLICY IF EXISTS → CREATE POLICY.
-- 참고: docs/untok_improvement_plan.md §5 A, src/supabase/functions/delete-account.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. 탈퇴 로그 — service_role(Edge Function)이 적재, 운영자만 read.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS account_deletion_logs (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- 삭제된 auth.users.id. 계정이 이미 사라지므로 FK 를 걸지 않고 값만 보관.
  deleted_user_id uuid,
  role            text,             -- 탈퇴 시점 역할(참고)
  reason          text,             -- 사유 코드(예: 'not_using', 'privacy', 'etc')
  detail          text,             -- 자유 입력(선택)
  created_at      timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE account_deletion_logs ENABLE ROW LEVEL SECURITY;

-- 클라이언트 INSERT 정책을 두지 않는다 → anon/authenticated 는 쓸 수 없음.
-- 적재는 service_role(Edge Function)이 RLS 를 우회해 수행.
-- 운영자(관리자 프로필 보유자)만 사유 통계를 read.
DROP POLICY IF EXISTS deletion_admin_read ON account_deletion_logs;
CREATE POLICY deletion_admin_read ON account_deletion_logs
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM admin_profiles a
      WHERE a.user_id = auth.uid() AND a.deleted_at IS NULL
    )
  );


-- ---------------------------------------------------------------------
-- 2. 동의 기록 — 가입 시 이용약관/개인정보 동의 시점·버전 보관.
--    사용자 본인이 INSERT/SELECT(upsert). 역할 무관(가입 직후 기록).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_consents (
  user_id         uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  -- 동의한 문서 버전(날짜 문자열). 문서 개정 시 재동의 추적용.
  terms_version   text NOT NULL,
  privacy_version text NOT NULL,
  agreed_at       timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE user_consents ENABLE ROW LEVEL SECURITY;

-- 본인 행만 읽고 쓴다(upsert). user_id 위변조는 WITH CHECK 가 막음.
DROP POLICY IF EXISTS consent_self_rw ON user_consents;
CREATE POLICY consent_self_rw ON user_consents
  FOR ALL USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());


-- ---------------------------------------------------------------------
-- 검증 SQL (적용 후 SQL Editor):
--   SELECT polname FROM pg_policies
--   WHERE tablename IN ('account_deletion_logs', 'user_consents');
--   → deletion_admin_read / consent_self_rw
--
--   -- 회원 계정으로: user_consents upsert 됨 / account_deletion_logs INSERT 거부
--   -- 관리자 계정으로: account_deletion_logs SELECT 됨
-- ---------------------------------------------------------------------
