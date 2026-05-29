-- =====================================================================
-- 0020_verify_invite_code.sql
-- 가입 전 초대 코드 검증 RPC
--
-- 왜:
--   회원가입(Supabase Auth)은 코드와 무관하게 계정을 만든다. "유효한 초대 코드가
--   있어야만 가입"되게 하려면, 계정 생성 '전에' 코드 유효성을 확인해야 한다.
--   claim_member_profile 은 auth.uid()가 필요(가입 후)라 사전 검증엔 못 쓴다.
--   → 로그인 전(anon)에도 호출 가능한, "미사용 코드 존재 여부"만 반환하는 함수.
--
-- 보안: boolean 만 반환(회원 정보 노출 0). 코드는 8자리 랜덤이라 탐색 위험 낮음.
-- 멱등: CREATE OR REPLACE.
-- 참고: docs/develop_plan.md §4 Phase 2(회원 온보딩), 0019(invite_code/claim).
-- =====================================================================

CREATE OR REPLACE FUNCTION verify_invite_code(p_code text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM member_profiles
     WHERE invite_code = upper(trim(p_code))
       AND user_id IS NULL
       AND deleted_at IS NULL
  );
$$;

-- 가입 전(anon)에도 호출 가능해야 함.
GRANT EXECUTE ON FUNCTION verify_invite_code(text) TO anon, authenticated;

-- ---------------------------------------------------------------------
-- 검증 SQL:
--   SELECT verify_invite_code('<유효코드>');   -- true
--   SELECT verify_invite_code('WRONG');        -- false
-- ---------------------------------------------------------------------
