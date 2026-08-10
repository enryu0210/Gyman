-- =====================================================================
-- 0041_consent_coverage.sql
--
-- 약관·처리방침 대조(docs/legal_docs_gap_check.md)에서 나온 두 공백을 닫는다.
--
--   (C) **앱 미가입 회원의 동의를 받을 방법이 없다.**
--       0013 이후 member_profiles.user_id 는 nullable 이라 트레이너가 회원을
--       대신 등록할 수 있다. 그런데 그 사람은 약관을 본 적도, user_consents 에
--       행이 있을 수도 없다(PK 가 auth.users.id 라 계정 없이는 기록 불가).
--       → 트레이너가 "본인에게 동의를 받았다"를 확인하게 하고, 그 확인 사실
--         (누가·언제)을 남긴다.
--
--   (D-4) **민감정보 동의가 분리돼 있지 않다.**
--       부상 이력·인바디·체형 사진은 건강정보라 다른 개인정보와 **별도 동의**가
--       필요한데, 가입 동의는 [이용약관]·[개인정보 처리방침] 2개뿐이었다.
--       → user_consents 에 민감정보 동의 버전 컬럼을 더한다.
--
-- ⚠ **배포 순서 주의 — 앱과 함께 나가야 한다.**
--    아래 3번 트리거는 동의 확인 없는 회원 INSERT 를 **거부**한다. 이 마이그레이션만
--    먼저 적용하면 구버전 앱의 [회원 추가]가 그 순간부터 실패한다. 0040 때와 같은
--    종류의 결합이지만, 그때는 서버(Edge Function) 재배포로 끝났고 이번엔
--    **사용자 기기의 앱**이라 통제가 늦다. 마이그레이션 적용과 앱 재배포를 붙일 것.
--
-- 멱등: ADD COLUMN IF NOT EXISTS / DROP TRIGGER IF EXISTS → CREATE TRIGGER.
-- 참고: docs/legal_docs_gap_check.md §C·§D-4, 0034(user_consents), 0040(트리거 선례).
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1. 민감정보(건강정보) 처리 동의 기록 — D-4
--
--    **nullable 인 이유:** 이 컬럼이 생기기 전에 가입한 사용자는 민감정보 동의를
--    한 적이 없다. NOT NULL DEFAULT 를 주면 "동의한 적 없는 사람이 동의한 것으로"
--    기록돼 A 등급(사실과 다름) 문제를 새로 만든다. NULL = "아직 안 받음" 이다.
--
--    **선택 동의라 가입을 막지 않는다.** 동의 안 해도 예약·수업기록 열람·채팅은
--    되고, 체형분석·인바디 추이·수업 영상만 제한된다(처리방침 제3항과 같은 말).
-- ---------------------------------------------------------------------
ALTER TABLE user_consents
  ADD COLUMN IF NOT EXISTS sensitive_version text;

COMMENT ON COLUMN user_consents.sensitive_version IS
  '민감정보(건강정보) 처리에 동의한 문서 버전. NULL = 동의하지 않음(또는 이 컬럼 '
  '도입 전 가입자). 약관/처리방침과 달리 선택 동의라 가입의 전제 조건이 아니다.';

ALTER TABLE user_consents
  ADD COLUMN IF NOT EXISTS sensitive_agreed_at timestamptz;

COMMENT ON COLUMN user_consents.sensitive_agreed_at IS
  '민감정보 동의 시각. 철회하면 sensitive_version 과 함께 NULL 로 되돌린다.';


-- ---------------------------------------------------------------------
-- 2. 앱 미가입 회원의 오프라인 동의 확인 기록 — C
--
--    누가·언제 확인했는지를 남긴다. "확인했다"는 트레이너의 진술이지 회원의
--    동의 자체가 아니다 — 그래서 컬럼명이 consent 가 아니라 confirmed 다.
--    (AI 동의의 ai_consent 와 같은 구조: 동의 주체는 회원, 입력 주체는 트레이너)
-- ---------------------------------------------------------------------
ALTER TABLE member_profiles
  ADD COLUMN IF NOT EXISTS offline_consent_confirmed_at timestamptz;

COMMENT ON COLUMN member_profiles.offline_consent_confirmed_at IS
  '트레이너가 "회원 본인(미성년자면 법정대리인)에게 수집·이용 동의를 받았다"고 '
  '확인한 시각. NULL 인 기존 행은 이 컬럼 도입(0041) 이전에 등록된 회원 — '
  '소급 확인이 불가능하므로 NULL 을 허용하되, 신규 INSERT 는 3번 트리거가 막는다.';

-- 기본값을 auth.uid() 로 두어 클라이언트가 트레이너 id 를 실어 보내지 않아도 되게.
-- (self_workout_logs.member_id DEFAULT current_member_profile_id() 와 같은 패턴)
ALTER TABLE member_profiles
  ADD COLUMN IF NOT EXISTS offline_consent_confirmed_by uuid
    DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE SET NULL;

COMMENT ON COLUMN member_profiles.offline_consent_confirmed_by IS
  '위 확인을 한 트레이너의 auth.users.id. 트레이너 계정이 삭제돼도 확인 시각은 '
  '남아야 하므로 ON DELETE SET NULL (CASCADE 로 기록을 지우면 안 된다).';


-- ---------------------------------------------------------------------
-- 3. 동의 확인 없는 신규 회원 등록을 막는다 — C 의 실제 게이트
--
--    **왜 UI 체크박스로 끝내지 않는가:** 그러면 게이트가 아니라 권고가 된다.
--    A-2(AI 동의)에서 얻은 교훈 그대로 — 화면에서만 막으면 다른 경로(직접 API
--    호출, 미래의 일괄 등록 기능)가 조용히 우회한다. 개인정보 수집의 적법 근거가
--    걸린 값이라 fail-closed 로 둔다.
--
--    CHECK 제약을 못 쓰는 이유: 기존 행이 전부 NULL 이라 제약 추가 자체가 실패한다.
--    "신규 INSERT 에만" 이라는 조건은 트리거로만 표현된다.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION require_offline_consent_confirmation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  -- service_role(서버) 컨텍스트는 JWT 의 sub 가 없어 auth.uid() 가 NULL 이다.
  -- 마이그레이션·백필·관리 작업은 통과시킨다(0040 의 같은 판단).
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.offline_consent_confirmed_at IS NULL THEN
    RAISE EXCEPTION
      '회원 본인에게 개인정보 수집·이용 동의를 받았는지 확인해 주세요.'
      USING ERRCODE = '23514';   -- check_violation
  END IF;

  -- 확인 시각을 미래로 적어 넣는 것을 막는다(기록의 신뢰성).
  -- 클라이언트 시계가 조금 앞설 수 있어 5분 여유를 둔다.
  IF NEW.offline_consent_confirmed_at > now() + interval '5 minutes' THEN
    RAISE EXCEPTION '동의 확인 시각이 올바르지 않습니다.'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_require_offline_consent ON member_profiles;
CREATE TRIGGER trg_require_offline_consent
  BEFORE INSERT ON member_profiles
  FOR EACH ROW
  EXECUTE FUNCTION require_offline_consent_confirmation();

COMMIT;


-- ---------------------------------------------------------------------
-- 검증 SQL (적용 후 SQL Editor)
--
-- (1) 컬럼이 생겼는지
--   SELECT column_name, is_nullable FROM information_schema.columns
--   WHERE table_name='member_profiles'
--     AND column_name LIKE 'offline_consent%';
--   → 2건, 둘 다 is_nullable='YES'
--
--   SELECT column_name FROM information_schema.columns
--   WHERE table_name='user_consents' AND column_name LIKE 'sensitive%';
--   → sensitive_version / sensitive_agreed_at
--
-- (2) ★ 핵심 — 트레이너 계정으로 동의 확인 없이 등록하면 거부되는지
--   INSERT INTO member_profiles (name) VALUES ('동의없음테스트');
--   → ERROR: 회원 본인에게 개인정보 수집·이용 동의를 받았는지 확인해 주세요.
--
-- (3) 확인 시각을 넣으면 통과하고, 확인자가 자동으로 채워지는지
--   INSERT INTO member_profiles (name, offline_consent_confirmed_at)
--   VALUES ('동의확인테스트', now())
--   RETURNING id, offline_consent_confirmed_by;
--   → offline_consent_confirmed_by = 현재 로그인한 트레이너의 auth.uid()
--
-- (4) 미래 시각 차단
--   INSERT INTO member_profiles (name, offline_consent_confirmed_at)
--   VALUES ('미래시각', now() + interval '1 day');
--   → ERROR: 동의 확인 시각이 올바르지 않습니다.
--
-- (5) 기존 회원 UPDATE 는 영향 없는지 (트리거가 INSERT 전용)
--   UPDATE member_profiles SET goal='테스트' WHERE id='<기존_MEMBER_ID>';
--   → 성공 (offline_consent_confirmed_at 이 NULL 이어도 통과해야 한다)
--
-- (6) 뒷정리
--   DELETE FROM member_profiles WHERE name IN ('동의확인테스트');
-- ---------------------------------------------------------------------
