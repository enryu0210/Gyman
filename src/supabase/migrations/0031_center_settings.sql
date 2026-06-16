-- =====================================================================
-- 0031_center_settings.sql
--
-- 트레이너 온보딩 / 센터 규정·멘트 관리 — Phase 3.2 (C2 전반부).
--
-- 담는 것 3가지:
--   1. (correctness 수정) 0029 admin RLS 게이트를 current_admin_center_id() 기준으로
--      교체 — 트레이너 겸 관리자도 센터 전체를 보게 한다.
--   2. centers UPDATE 정책 — 관리자가 본인 센터 규정(rules)을 수정.
--   3. center_faqs 테이블 — 센터별 PT 규정 FAQ(멘트). 관리자 입력 → 회원/트레이너 열람.
--      2.4 에서 "준비 중"으로 비워둔 FaqCategory.ptPolicy 자리를 채운다.
--
-- 멱등: DROP POLICY IF EXISTS → CREATE / CREATE TABLE IF NOT EXISTS /
--        CREATE OR REPLACE. 부분 적용 후 재실행 안전.
--
-- 참고: docs/develop_plan.md §4 Phase 3.2, 0029(admin RLS),
--        0028(회원 INSERT DEFAULT 패턴), assets 인터뷰 답변 18.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. admin RLS 게이트 수정 — 겸직 관리자(트레이너 겸 admin) 커버
--
-- 배경: 역할 우선순위가 trainer > admin > member(0029)라, 트레이너이면서
--   관리자인 사람은 current_user_role() 이 'trainer' 를 돌려준다. 그래서 0029 의
--   `current_user_role() = 'admin'` 게이트를 통과하지 못해, 대시보드에서 본인
--   담당 회원만 보였다(센터 전체 X). 트레이너 1명일 땐 우연히 같았지만 다트레이너
--   센터에서 다른 트레이너 데이터가 조용히 빠지는 잠복 버그.
--
-- 해결: current_admin_center_id() 는 역할과 무관하게 admin_profiles 보유자면
--   센터를 돌려주고(없으면 NULL), `center_id = NULL` 은 거짓이라 비관리자는 자동
--   차단된다. 따라서 `current_user_role()='admin'` 조건은 불필요할 뿐 아니라
--   겸직자를 배제하므로 제거하고, center_id 매칭만 남긴다.
-- ---------------------------------------------------------------------

DROP POLICY IF EXISTS member_admin_read ON member_profiles;
CREATE POLICY member_admin_read ON member_profiles
  FOR SELECT USING (center_id = current_admin_center_id());

DROP POLICY IF EXISTS trainer_admin_read ON trainer_profiles;
CREATE POLICY trainer_admin_read ON trainer_profiles
  FOR SELECT USING (center_id = current_admin_center_id());

DROP POLICY IF EXISTS contract_admin_read ON pt_contracts;
CREATE POLICY contract_admin_read ON pt_contracts
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM member_profiles m
      WHERE m.id = pt_contracts.member_id
        AND m.center_id = current_admin_center_id()
    )
  );

DROP POLICY IF EXISTS sessions_admin_read ON sessions;
CREATE POLICY sessions_admin_read ON sessions
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM pt_contracts c
      JOIN member_profiles m ON m.id = c.member_id
      WHERE c.id = sessions.contract_id
        AND m.center_id = current_admin_center_id()
    )
  );


-- ---------------------------------------------------------------------
-- 2. centers — 관리자가 본인 센터 규정(rules)·정보 수정
--
-- 읽기는 0010 centers_authenticated_read(모든 인증 사용자)로 이미 가능.
-- 쓰기는 본인 센터 한정. WITH CHECK 로 다른 센터로 바꿔치기 방지.
-- ---------------------------------------------------------------------

DROP POLICY IF EXISTS centers_admin_update ON centers;
CREATE POLICY centers_admin_update ON centers
  FOR UPDATE
  USING (id = current_admin_center_id())
  WITH CHECK (id = current_admin_center_id());


-- ---------------------------------------------------------------------
-- 3. center_faqs — 센터별 PT 규정 FAQ(멘트)
--
-- 회원이 직접 INSERT 하지 않지만, 관리자가 center_id 를 안 넘겨도 되도록
-- DEFAULT current_admin_center_id() 를 둔다(0028 회원 패턴과 동일 취지).
-- 위변조는 RLS WITH CHECK 가 막는다.
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS center_faqs (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  center_id  uuid NOT NULL DEFAULT current_admin_center_id() REFERENCES centers(id),
  question   text NOT NULL,
  answer     text NOT NULL,
  -- 노출 순서(작을수록 위). 관리자가 우선순위를 조정.
  sort_order int  NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_center_faqs_center ON center_faqs(center_id);

-- updated_at 자동 갱신(0011 touch_updated_at 재사용)
DROP TRIGGER IF EXISTS trg_center_faqs_touch ON center_faqs;
CREATE TRIGGER trg_center_faqs_touch
  BEFORE UPDATE ON center_faqs
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

ALTER TABLE center_faqs ENABLE ROW LEVEL SECURITY;

-- 관리자: 본인 센터 FAQ 전체 read/write(추가·수정·삭제).
DROP POLICY IF EXISTS center_faq_admin_rw ON center_faqs;
CREATE POLICY center_faq_admin_rw ON center_faqs
  FOR ALL
  USING (center_id = current_admin_center_id())
  WITH CHECK (center_id = current_admin_center_id());

-- 회원: 본인 센터의 살아있는 FAQ read.
DROP POLICY IF EXISTS center_faq_member_read ON center_faqs;
CREATE POLICY center_faq_member_read ON center_faqs
  FOR SELECT USING (
    deleted_at IS NULL
    AND center_id = (
      SELECT center_id FROM member_profiles
      WHERE id = current_member_profile_id()
    )
  );

-- 트레이너: 본인 센터의 살아있는 FAQ read(온보딩 시 규정 숙지용).
DROP POLICY IF EXISTS center_faq_trainer_read ON center_faqs;
CREATE POLICY center_faq_trainer_read ON center_faqs
  FOR SELECT USING (
    deleted_at IS NULL
    AND center_id = (
      SELECT center_id FROM trainer_profiles
      WHERE user_id = auth.uid()
    )
  );


-- ---------------------------------------------------------------------
-- 검증 SQL (적용 후 SQL Editor):
--
--   -- 1) admin RLS 4개가 center_id 기준으로 바뀌었는지(겸직 커버)
--   SELECT polname, pg_get_expr(polqual, polrelid) AS using_expr
--   FROM pg_policy
--   WHERE polname IN ('member_admin_read','trainer_admin_read',
--                     'contract_admin_read','sessions_admin_read');
--   → using_expr 에 current_user_role() 가 없고 current_admin_center_id() 만 보이면 OK.
--
--   -- 2) centers UPDATE 정책
--   SELECT polname FROM pg_policy WHERE polname = 'centers_admin_update';
--
--   -- 3) center_faqs 테이블 + 정책 3개
--   SELECT polname FROM pg_policy
--   WHERE polrelid = 'center_faqs'::regclass;
--   → center_faq_admin_rw / center_faq_member_read / center_faq_trainer_read.
--
--   -- 4) 트레이너 겸 관리자로 로그인한 클라에서 대시보드가 '센터 전체' 를 보이는지
--   --    (본인 담당 외 다른 트레이너 회원/계약까지 잡히면 수정 성공).
-- ---------------------------------------------------------------------
