-- =====================================================================
-- 0019_member_invite_code.sql
-- 회원 초대 코드 + 계정 연결(claim) — 회원 앱 온보딩의 토대 (Phase 2)
--
-- 흐름:
--   1) 트레이너가 회원을 등록하면 invite_code 가 자동 발급(DB default).
--   2) 트레이너가 그 코드를 회원에게 전달.
--   3) 회원이 앱에서 가입(Supabase Auth) → 코드 입력.
--   4) claim_member_profile(code) 가 그 회원 레코드의 user_id 를 가입 계정과 연결.
--
-- 왜 SECURITY DEFINER RPC 인가:
--   가입 직후 회원은 아직 어떤 member_profiles 행과도 연결돼 있지 않아 RLS
--   (member_by_trainer)로는 그 행을 SELECT/UPDATE 할 수 없다. 그렇다고
--   member_profiles UPDATE 를 일반 authenticated 에게 열면 위험.
--   → 코드 일치 + 미연결 행에만 한정해 연결하는 좁은 RPC 로 처리.
--
-- 멱등: ADD COLUMN IF NOT EXISTS / DROP CONSTRAINT IF EXISTS / CREATE OR REPLACE.
-- 참고: docs/develop_plan.md §4 Phase 2(회원 온보딩), 0013(user_id nullable).
-- =====================================================================

-- 1) invite_code 컬럼 + 신규 행 자동 발급(default) + UNIQUE
ALTER TABLE member_profiles ADD COLUMN IF NOT EXISTS invite_code text;

-- 8자리 대문자 hex 코드. 신규 회원 INSERT 시 자동 생성.
ALTER TABLE member_profiles
  ALTER COLUMN invite_code
  SET DEFAULT upper(substr(md5(gen_random_uuid()::text), 1, 8));

-- 기존 회원(코드 없는 행) 백필.
UPDATE member_profiles
   SET invite_code = upper(substr(md5(gen_random_uuid()::text), 1, 8))
 WHERE invite_code IS NULL;

ALTER TABLE member_profiles
  DROP CONSTRAINT IF EXISTS member_profiles_invite_code_unique;
ALTER TABLE member_profiles
  ADD CONSTRAINT member_profiles_invite_code_unique UNIQUE (invite_code);


-- 2) 연결 RPC — 코드로 본인 계정에 회원 프로필 연결.
--    반환: 연결된 member_profiles.id (실패=NULL).
CREATE OR REPLACE FUNCTION claim_member_profile(p_code text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id  uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  -- 이미 연결된 회원이면 그 id 반환(멱등 — 재시도/중복 입력 안전).
  SELECT id INTO v_id
    FROM member_profiles
   WHERE user_id = v_uid AND deleted_at IS NULL
   LIMIT 1;
  IF v_id IS NOT NULL THEN
    RETURN v_id;
  END IF;

  -- 미사용 코드와 일치하는 회원에만 연결. 대소문자/공백 무시.
  UPDATE member_profiles
     SET user_id = v_uid
   WHERE invite_code = upper(trim(p_code))
     AND user_id IS NULL
     AND deleted_at IS NULL
  RETURNING id INTO v_id;

  RETURN v_id; -- 일치/미사용 행 없으면 NULL
END;
$$;

-- 가입한(authenticated) 사용자가 호출할 수 있도록 권한 부여.
GRANT EXECUTE ON FUNCTION claim_member_profile(text) TO authenticated;

-- ---------------------------------------------------------------------
-- 검증 SQL:
--   SELECT id, name, invite_code, user_id FROM member_profiles ORDER BY created_at;
--   -- (회원 계정으로 로그인한 상태에서) SELECT claim_member_profile('CODE1234');
--   --   → 연결된 member id 반환, 잘못된 코드면 NULL.
-- ---------------------------------------------------------------------
