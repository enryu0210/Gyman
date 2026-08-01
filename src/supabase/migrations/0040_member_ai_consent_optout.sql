-- =====================================================================
-- 0040_member_ai_consent_optout.sql
--
-- 회원에게 AI 사용 동의에 대한 **거부권**을 준다 (legal_docs_gap_check.md A-2).
--
-- 문제:
--   개인정보 처리방침 §4 는 "회원이 AI 사용에 동의한 경우에만" 외부 LLM 에
--   전달한다고 단언하는데, 실제로 ai_consent 를 켜는 UI 는 **트레이너의 회원
--   수정 다이얼로그에만** 있었다. 회원은 본인 상태를 보지도, 끄지도 못했다.
--   즉 문안이 사실과 다르다.
--
-- 왜 컬럼을 새로 만드나 (ai_consent 를 회원이 직접 끄게 하면 안 되나):
--   member_profiles 의 RLS 는 회원(member_self_rw)·트레이너(member_by_trainer)
--   둘 다 FOR ALL 이라, 회원이 ai_consent 를 false 로 내려도 **트레이너가 곧바로
--   다시 true 로 올릴 수 있다.** 그러면 "거부권"이 아니라 줄다리기가 된다.
--   두 사실은 애초에 별개다:
--     ai_consent               = 트레이너가 "회원에게 동의를 받았다"고 기록한 값
--     ai_consent_member_optout = 회원 본인이 "그래도 싫다"고 표시한 값
--   그래서 컬럼을 나누고, 각자 자기 것만 건드리게 한다.
--
-- 판정은 생성 컬럼 ai_consent_effective 하나로 통일 — 두 값을 읽는 쪽마다
-- AND 를 직접 쓰면 언젠가 한 군데가 빠진다. 그 한 군데가 "동의 없이 전송"이다.
--
-- 멱등: ADD COLUMN IF NOT EXISTS / CREATE OR REPLACE FUNCTION /
--       DROP TRIGGER IF EXISTS → CREATE.
--
-- 참고: docs/legal_docs_gap_check.md A-2, 0003(원본 컬럼), 0010(RLS), 0013(헬퍼).
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1. 회원 거부 플래그
-- ---------------------------------------------------------------------

-- 기본 false = "거부하지 않음". 기존 행의 동작은 그대로 유지된다.
-- (fail-closed 는 ai_consent 쪽이 이미 담당 — 기본 false)
ALTER TABLE member_profiles
  ADD COLUMN IF NOT EXISTS ai_consent_member_optout boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN member_profiles.ai_consent_member_optout IS
  '회원 본인이 AI 사용을 거부했는지. 회원만 변경 가능(트리거로 강제). '
  'true 면 트레이너가 ai_consent 를 켜도 ai_consent_effective 는 false.';


-- ---------------------------------------------------------------------
-- 2. 실효 동의 — 이 값 하나만 보면 된다
-- ---------------------------------------------------------------------

-- STORED 생성 컬럼: 두 값이 바뀔 때 DB 가 알아서 다시 계산한다.
-- 앱/Edge Function 은 이 컬럼만 읽으면 되고, 조합을 잘못 쓸 여지가 없다.
-- ai_consent 는 NOT NULL DEFAULT false 라 NULL 처리 불필요.
ALTER TABLE member_profiles
  ADD COLUMN IF NOT EXISTS ai_consent_effective boolean
    GENERATED ALWAYS AS (ai_consent AND NOT ai_consent_member_optout) STORED;

COMMENT ON COLUMN member_profiles.ai_consent_effective IS
  'AI 전송 허용 여부의 유일한 판정 기준 = ai_consent AND NOT ai_consent_member_optout. '
  '읽기 전용(생성 컬럼).';


-- ---------------------------------------------------------------------
-- 3. 거부 플래그는 회원 본인만 — RLS 로는 막을 수 없어 트리거로 강제
--
--    PostgreSQL 의 RLS 는 행 단위라 "이 컬럼만 못 쓰게"가 안 된다.
--    컬럼 단위 GRANT 도 여기선 못 쓴다 — 회원·트레이너가 **같은 authenticated
--    role** 이라 컬럼 권한을 좁히면 트레이너의 이름·연락처 수정까지 막힌다.
--    남는 수단이 BEFORE UPDATE 트리거다.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION guard_ai_consent_optout()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  -- 이 컬럼이 안 바뀌는 UPDATE 는 통과(대부분의 경우).
  IF NEW.ai_consent_member_optout IS NOT DISTINCT FROM OLD.ai_consent_member_optout THEN
    RETURN NEW;
  END IF;

  -- service_role(서버) 컨텍스트는 JWT 의 sub 가 없어 auth.uid() 가 NULL 이다.
  -- 탈퇴 처리(delete-account) 같은 서버 작업은 통과시킨다.
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  -- 그 외에는 프로필 주인 본인만 허용. 트레이너·관리자 전부 여기서 막힌다.
  IF OLD.user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION
      'AI 사용 거부 설정은 회원 본인만 변경할 수 있습니다.'
      USING ERRCODE = '42501';   -- insufficient_privilege
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_ai_consent_optout ON member_profiles;
CREATE TRIGGER trg_guard_ai_consent_optout
  BEFORE UPDATE ON member_profiles
  FOR EACH ROW
  EXECUTE FUNCTION guard_ai_consent_optout();

COMMIT;


-- ---------------------------------------------------------------------
-- 검증 SQL (적용 후 SQL Editor)
--
-- (1) 컬럼·생성식 확인
--   SELECT column_name, is_generated, generation_expression
--   FROM information_schema.columns
--   WHERE table_name='member_profiles'
--     AND column_name IN ('ai_consent','ai_consent_member_optout','ai_consent_effective');
--   → ai_consent_effective 만 is_generated='ALWAYS'
--
-- (2) 실효값 계산 — 트레이너가 켜도 회원이 거부하면 false 여야 한다
--   UPDATE member_profiles SET ai_consent=true WHERE id='<MEMBER_ID>';
--   SELECT ai_consent, ai_consent_member_optout, ai_consent_effective
--     FROM member_profiles WHERE id='<MEMBER_ID>';           → t / f / t
--   -- 회원 계정으로 로그인해서 앱의 [설정 > AI 사용] 을 끈 뒤 다시 조회 → t / t / f
--
-- (3) ★ 트레이너가 회원의 거부를 못 뒤집는지 — 이게 이 마이그레이션의 핵심
--   -- 트레이너 계정으로:
--   UPDATE member_profiles SET ai_consent_member_optout=false WHERE id='<MEMBER_ID>';
--   → ERROR: AI 사용 거부 설정은 회원 본인만 변경할 수 있습니다. (42501)
--
-- (4) 트레이너의 정상 수정은 여전히 되는지 (트리거가 과잉 차단하지 않는지)
--   UPDATE member_profiles SET goal='체중감량' WHERE id='<MEMBER_ID>';   → 성공
--   UPDATE member_profiles SET ai_consent=false WHERE id='<MEMBER_ID>';  → 성공
--
-- (5) 회원 본인은 켜고 끌 수 있는지
--   -- 회원 계정으로:
--   UPDATE member_profiles SET ai_consent_member_optout=true
--     WHERE id = current_member_profile_id();                            → 성공
--   UPDATE member_profiles SET ai_consent_member_optout=false
--     WHERE id = current_member_profile_id();                            → 성공 (철회 가능)
--
-- (6) 생성 컬럼은 쓰기 불가
--   UPDATE member_profiles SET ai_consent_effective=true WHERE id='<MEMBER_ID>';
--   → ERROR: column "ai_consent_effective" can only be updated to DEFAULT
-- ---------------------------------------------------------------------
