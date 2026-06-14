-- =====================================================================
-- 0029_admin_profiles.sql
--
-- 관리자(센터장) 인프라 신설 — Phase 3.1-A (관리자 대시보드 토대).
--
-- 배경(인터뷰 답변 17·18): 센터 관리자는 트레이너별 재등록/매출/노쇼율,
--   만료 임박·이탈 위험 회원을 보고 싶어 한다. "관리자용 앱은 따로"가 요구라
--   trainer/member 와 별개의 admin 역할·프로필을 만든다.
--
-- 계정 생성(베타 결정): **수동 SQL 등록**. 가입/초대 UI 없이 SQL Editor 로
--   admin_profiles 에 직접 INSERT 한다(베타엔 관리자 1명, 친구네 센터장).
--   예) INSERT INTO admin_profiles(user_id, center_id, name)
--       VALUES ('<auth.users.id>', '<centers.id>', '센터장이름');
--
-- 권한 범위: 관리자는 **본인 center_id 의 데이터만** 읽는다(read-only).
--   - member_profiles / trainer_profiles : center_id 직접 비교.
--   - pt_contracts / sessions            : 회원(member_profiles.center_id) 경유.
--   계약/회원/트레이너의 center_id 가 일관되게 채워져 있어야 대시보드에 잡힌다.
--
-- 멱등: CREATE TABLE IF NOT EXISTS / CREATE OR REPLACE / DROP POLICY IF EXISTS.
--
-- 참고: docs/develop_plan.md §4 Phase 3, 0009(current_user_role)·0013(헬퍼)·0010(RLS 패턴).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. admin_profiles 테이블
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS admin_profiles (
  user_id    uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  -- 관리 대상 센터. 관리자는 이 센터의 데이터만 본다.
  center_id  uuid REFERENCES centers(id),
  name       text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_admin_center ON admin_profiles(center_id);


-- ---------------------------------------------------------------------
-- 2. 헬퍼 함수
-- ---------------------------------------------------------------------

-- 2-1) current_user_role() 에 admin 분기 추가.
--      우선순위: trainer > admin > member (한 사람이 여러 프로필이면 상위 역할).
CREATE OR REPLACE FUNCTION current_user_role() RETURNS user_role
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT
    CASE
      WHEN EXISTS (
        SELECT 1 FROM trainer_profiles
        WHERE user_id = auth.uid() AND deleted_at IS NULL
      )
        THEN 'trainer'::user_role
      WHEN EXISTS (
        SELECT 1 FROM admin_profiles
        WHERE user_id = auth.uid() AND deleted_at IS NULL
      )
        THEN 'admin'::user_role
      WHEN EXISTS (
        SELECT 1 FROM member_profiles
        WHERE user_id = auth.uid() AND deleted_at IS NULL
      )
        THEN 'member'::user_role
    END
$$;

-- 2-2) 현재 로그인 관리자의 center_id (없으면 NULL). admin RLS 에서 센터 범위 판정.
CREATE OR REPLACE FUNCTION current_admin_center_id() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT center_id FROM admin_profiles
  WHERE user_id = auth.uid()
    AND deleted_at IS NULL
  LIMIT 1
$$;


-- ---------------------------------------------------------------------
-- 3. RLS
-- ---------------------------------------------------------------------

-- 3-0) admin_profiles 자체 — 본인 행만 read(역할 판정용). 쓰기는 SQL(서버)만.
ALTER TABLE admin_profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS admin_self_read ON admin_profiles;
CREATE POLICY admin_self_read ON admin_profiles
  FOR SELECT USING (user_id = auth.uid());

-- 3-1) member_profiles — 관리자는 본인 센터 회원 read.
DROP POLICY IF EXISTS member_admin_read ON member_profiles;
CREATE POLICY member_admin_read ON member_profiles
  FOR SELECT USING (
    current_user_role() = 'admin'
    AND center_id = current_admin_center_id()
  );

-- 3-2) trainer_profiles — 관리자는 본인 센터 트레이너 read.
DROP POLICY IF EXISTS trainer_admin_read ON trainer_profiles;
CREATE POLICY trainer_admin_read ON trainer_profiles
  FOR SELECT USING (
    current_user_role() = 'admin'
    AND center_id = current_admin_center_id()
  );

-- 3-3) pt_contracts — 관리자는 본인 센터 회원의 계약 read(매출/잔여 집계용).
DROP POLICY IF EXISTS contract_admin_read ON pt_contracts;
CREATE POLICY contract_admin_read ON pt_contracts
  FOR SELECT USING (
    current_user_role() = 'admin'
    AND EXISTS (
      SELECT 1 FROM member_profiles m
      WHERE m.id = pt_contracts.member_id
        AND m.center_id = current_admin_center_id()
    )
  );

-- 3-4) sessions — 관리자는 본인 센터 회원의 수업 read(노쇼율 집계용).
DROP POLICY IF EXISTS sessions_admin_read ON sessions;
CREATE POLICY sessions_admin_read ON sessions
  FOR SELECT USING (
    current_user_role() = 'admin'
    AND EXISTS (
      SELECT 1 FROM pt_contracts c
      JOIN member_profiles m ON m.id = c.member_id
      WHERE c.id = sessions.contract_id
        AND m.center_id = current_admin_center_id()
    )
  );

-- centers 는 0010 의 centers_authenticated_read(모든 인증 사용자 read)로 이미 노출됨 —
-- 관리자도 본인 센터 정보를 읽을 수 있어 별도 정책 불필요.


-- ---------------------------------------------------------------------
-- 검증 SQL (적용 후 SQL Editor):
--   -- 1) 테이블
--   SELECT column_name FROM information_schema.columns WHERE table_name='admin_profiles';
--
--   -- 2) 헬퍼 2개
--   SELECT proname FROM pg_proc
--   WHERE proname IN ('current_user_role','current_admin_center_id');
--
--   -- 3) admin RLS 정책 5개
--   SELECT tablename, polname FROM pg_policies
--   WHERE polname LIKE '%admin%';
--   → admin_self_read / member_admin_read / trainer_admin_read /
--     contract_admin_read / sessions_admin_read 기대.
--
--   -- 4) 관리자 등록 예시(본인 auth.users.id, 대상 centers.id 로 치환)
--   --   INSERT INTO admin_profiles(user_id, center_id, name)
--   --   VALUES ('<uuid>', '<center_uuid>', '센터장');
-- ---------------------------------------------------------------------
