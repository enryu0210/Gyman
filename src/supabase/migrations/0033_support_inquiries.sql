-- =====================================================================
-- 0033_support_inquiries.sql
--
-- 앱 내 문의 채널 (운톡 불만 #5 "문의할 곳이 없어 리뷰란이 민원게시판" 해결).
--   → 회원/트레이너가 앱에서 직접 문의를 남기면 DB에 적재되고,
--     운영자(관리자 프로필 보유자)가 "문의함" 화면에서 확인·처리한다.
--
-- 설계 결정:
--   - mailto 가 아니라 **인앱 수신**(사용자 선택). 외부 메일 앱 의존 0.
--   - 센터 단위가 아닌 **앱 전역 운영 문의** — 베타엔 운영자 1명이라
--     "관리자 프로필 보유자는 전체 조회"로 둔다(다중 운영자는 추후 범위 분리).
--   - '알람'은 현재 FCM 미도입이라 관리자 대시보드의 **미처리 건수 배지**로 대체.
--
-- 멱등: CREATE TABLE IF NOT EXISTS / DROP POLICY IF EXISTS → CREATE POLICY.
-- 참고: docs/untok_improvement_plan.md §5 B, docs/develop_plan.md §4 Phase 3.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. 테이블
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS support_inquiries (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- 작성자. 탈퇴해도 문의 본문은 남기되 작성자 추적은 끊기도록 SET NULL.
  user_id     uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  -- 작성 시점 역할(참고용 라벨). 운영자가 누가 보냈는지 가늠.
  role        text,
  message     text NOT NULL,
  -- 재현/버전 추적용. 클라가 앱 버전 문자열을 같이 보냄.
  app_version text,
  -- 처리 상태: open(미처리) / handled(처리완료).
  status      text NOT NULL DEFAULT 'open',
  created_at  timestamptz NOT NULL DEFAULT now(),
  handled_at  timestamptz
);

-- 운영자 문의함은 "미처리 최신순" 조회가 기본 — 부분 인덱스로 가볍게.
CREATE INDEX IF NOT EXISTS idx_support_open
  ON support_inquiries(created_at DESC) WHERE status = 'open';


-- ---------------------------------------------------------------------
-- 2. RLS
-- ---------------------------------------------------------------------
ALTER TABLE support_inquiries ENABLE ROW LEVEL SECURITY;

-- 2-1) 작성: 로그인 사용자가 **본인 명의로만** INSERT (위변조 차단).
DROP POLICY IF EXISTS support_insert_own ON support_inquiries;
CREATE POLICY support_insert_own ON support_inquiries
  FOR INSERT WITH CHECK (user_id = auth.uid());

-- 2-2) 조회(본인): 내가 보낸 문의는 내가 본다.
DROP POLICY IF EXISTS support_select_own ON support_inquiries;
CREATE POLICY support_select_own ON support_inquiries
  FOR SELECT USING (user_id = auth.uid());

-- 2-3) 조회(운영자): 관리자 프로필 보유자는 전체 문의를 본다.
--      current_user_role()='admin' 으로 안 보는 이유: 트레이너 겸 관리자는
--      역할 우선순위상 role=trainer 라, 겸직 운영자도 보게 admin_profiles 존재로 판정.
DROP POLICY IF EXISTS support_admin_read ON support_inquiries;
CREATE POLICY support_admin_read ON support_inquiries
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM admin_profiles a
      WHERE a.user_id = auth.uid() AND a.deleted_at IS NULL
    )
  );

-- 2-4) 처리(운영자): 상태를 handled 로 바꾼다(본문은 수정 안 함, 클라가 status만 UPDATE).
DROP POLICY IF EXISTS support_admin_update ON support_inquiries;
CREATE POLICY support_admin_update ON support_inquiries
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM admin_profiles a
      WHERE a.user_id = auth.uid() AND a.deleted_at IS NULL
    )
  ) WITH CHECK (
    EXISTS (
      SELECT 1 FROM admin_profiles a
      WHERE a.user_id = auth.uid() AND a.deleted_at IS NULL
    )
  );


-- ---------------------------------------------------------------------
-- 검증 SQL (적용 후 SQL Editor):
--   -- 정책 4개 확인
--   SELECT polname FROM pg_policies WHERE tablename = 'support_inquiries';
--   → support_insert_own / support_select_own / support_admin_read / support_admin_update
--
--   -- 회원 계정으로: 본인 문의 INSERT 됨 / 남의 문의 SELECT 0행
--   -- 관리자 계정으로: 전체 SELECT 됨 + status='handled' UPDATE 됨
-- ---------------------------------------------------------------------
