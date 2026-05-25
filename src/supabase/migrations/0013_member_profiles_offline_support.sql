-- =====================================================================
-- 0013_member_profiles_offline_support.sql
--
-- 트레이너가 회원의 Supabase Auth 계정 생성 전에도 회원 정보를 등록·관리할 수
-- 있도록 member_profiles 스키마를 변경한다.
--
-- 베타 단계 회원 등록 흐름:
--   (1) 트레이너가 회원 정보만 등록 (user_id = NULL)
--   (2) 회원이 앱 가입 → Supabase Auth 계정 생성
--   (3) 트레이너가 매핑: UPDATE member_profiles SET user_id = ? WHERE id = ?
--   (4) 매핑 후 회원이 본인 정보/계약 조회 가능
--
-- 핵심 변경:
--   1. member_profiles에 id uuid PK 추가, user_id는 nullable UNIQUE FK
--   2. pt_contracts / member_notes / body_assessments / outgoing_notifications 의
--      member_id(또는 target_member_id) FK가 member_profiles(id)를 참조하도록 변경
--   3. 신규 헬퍼 함수 current_member_profile_id()
--   4. RLS 정책 6곳 갱신 — 회원 측은 current_member_profile_id() 경유
--
-- 베타 시점 가정: 기존 member_profiles / pt_contracts / member_notes 데이터 0건.
--                실제 운영 환경에서 적용 시에는 매핑 로직 별도 검토 필요.
--
-- 참고: docs/data_model.md §2.2 (갱신 예정)
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1. member_profiles 스키마 변경
-- ---------------------------------------------------------------------

-- id 컬럼 추가 (각 기존 행에 자동 uuid 발급)
ALTER TABLE member_profiles
  ADD COLUMN id uuid NOT NULL DEFAULT gen_random_uuid();

-- PK 교체: user_id → id
ALTER TABLE member_profiles DROP CONSTRAINT member_profiles_pkey;
ALTER TABLE member_profiles ADD CONSTRAINT member_profiles_pkey PRIMARY KEY (id);

-- user_id: NOT NULL 해제 + UNIQUE 추가 (1:1 매핑 보장)
ALTER TABLE member_profiles ALTER COLUMN user_id DROP NOT NULL;
ALTER TABLE member_profiles
  ADD CONSTRAINT member_profiles_user_id_unique UNIQUE (user_id);

-- 매핑 안 된 회원도 트레이너가 보기 좋게 — display_name 등 별도 컬럼은 추후 결정.
-- 일단 기존 name 컬럼 그대로 사용 (회원 가입 전에도 트레이너가 표시).


-- ---------------------------------------------------------------------
-- 2. 다른 테이블의 FK 대상 변경 (user_id → id)
-- ---------------------------------------------------------------------

-- pt_contracts.member_id
ALTER TABLE pt_contracts DROP CONSTRAINT pt_contracts_member_id_fkey;
ALTER TABLE pt_contracts
  ADD CONSTRAINT pt_contracts_member_id_fkey
  FOREIGN KEY (member_id) REFERENCES member_profiles(id);

-- member_notes.member_id (ON DELETE CASCADE 유지)
ALTER TABLE member_notes DROP CONSTRAINT IF EXISTS member_notes_member_id_fkey;
ALTER TABLE member_notes
  ADD CONSTRAINT member_notes_member_id_fkey
  FOREIGN KEY (member_id) REFERENCES member_profiles(id) ON DELETE CASCADE;

-- body_assessments.member_id
ALTER TABLE body_assessments DROP CONSTRAINT IF EXISTS body_assessments_member_id_fkey;
ALTER TABLE body_assessments
  ADD CONSTRAINT body_assessments_member_id_fkey
  FOREIGN KEY (member_id) REFERENCES member_profiles(id);

-- outgoing_notifications.target_member_id
ALTER TABLE outgoing_notifications
  DROP CONSTRAINT IF EXISTS outgoing_notifications_target_member_id_fkey;
ALTER TABLE outgoing_notifications
  ADD CONSTRAINT outgoing_notifications_target_member_id_fkey
  FOREIGN KEY (target_member_id) REFERENCES member_profiles(id);


-- ---------------------------------------------------------------------
-- 3. 헬퍼 함수 갱신/추가
-- ---------------------------------------------------------------------

-- 현재 로그인된 회원의 member_profiles.id 반환 (없으면 NULL).
-- RLS 정책 다수에서 호출되므로 STABLE + SECURITY DEFINER.
CREATE OR REPLACE FUNCTION current_member_profile_id() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT id FROM member_profiles
  WHERE user_id = auth.uid()
    AND deleted_at IS NULL
  LIMIT 1
$$;

-- is_member_of_trainer: 시그니처 동일. 다만 호출 측에서 user_id가 아닌
-- member_profiles.id를 전달해야 함을 RLS 정책 본문에서 명시한다.
-- 함수 본문은 그대로 — pt_contracts.member_id 가 이제 member_profiles.id 이므로 일관됨.
CREATE OR REPLACE FUNCTION is_member_of_trainer(p_member_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT EXISTS (
    SELECT 1 FROM pt_contracts
    WHERE member_id  = p_member_id
      AND trainer_id = auth.uid()
      AND deleted_at IS NULL
  )
$$;


-- ---------------------------------------------------------------------
-- 4. RLS 정책 갱신
--    회원 측 정책들이 auth.uid() 대신 current_member_profile_id() 를 쓰도록.
-- ---------------------------------------------------------------------

-- member_profiles.member_by_trainer: user_id → id 로 트레이너 권한 검증
DROP POLICY IF EXISTS member_by_trainer ON member_profiles;
CREATE POLICY member_by_trainer ON member_profiles
  FOR ALL USING (
    current_user_role() = 'trainer'
    AND is_member_of_trainer(id)
  );

-- trainer_profiles.trainer_read_by_member: pt_contracts.member_id 비교 변경
DROP POLICY IF EXISTS trainer_read_by_member ON trainer_profiles;
CREATE POLICY trainer_read_by_member ON trainer_profiles
  FOR SELECT USING (
    current_user_role() = 'member'
    AND EXISTS (
      SELECT 1 FROM pt_contracts
      WHERE pt_contracts.trainer_id = trainer_profiles.user_id
        AND pt_contracts.member_id  = current_member_profile_id()
        AND pt_contracts.deleted_at IS NULL
    )
  );

-- pt_contracts.contract_member_read
DROP POLICY IF EXISTS contract_member_read ON pt_contracts;
CREATE POLICY contract_member_read ON pt_contracts
  FOR SELECT USING (member_id = current_member_profile_id());

-- sessions.sessions_member_read
DROP POLICY IF EXISTS sessions_member_read ON sessions;
CREATE POLICY sessions_member_read ON sessions
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM pt_contracts c
      WHERE c.id = sessions.contract_id
        AND c.member_id = current_member_profile_id()
    )
  );

-- session_records.records_member_read
DROP POLICY IF EXISTS records_member_read ON session_records;
CREATE POLICY records_member_read ON session_records
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM sessions s
      JOIN pt_contracts c ON c.id = s.contract_id
      WHERE s.id = session_records.session_id
        AND c.member_id = current_member_profile_id()
    )
  );

-- body_assessments.assess_member_read_after_review
DROP POLICY IF EXISTS assess_member_read_after_review ON body_assessments;
CREATE POLICY assess_member_read_after_review ON body_assessments
  FOR SELECT USING (
    member_id = current_member_profile_id()
    AND trainer_comment IS NOT NULL
    AND length(trim(trainer_comment)) > 0
  );

-- outgoing_notifications.notif_member_read_sent_only
DROP POLICY IF EXISTS notif_member_read_sent_only ON outgoing_notifications;
CREATE POLICY notif_member_read_sent_only ON outgoing_notifications
  FOR SELECT USING (
    target_member_id = current_member_profile_id()
    AND status = 'sent'
  );


-- ---------------------------------------------------------------------
-- 5. v_contract_status view 재생성 (FK 변경에 따른 의존성 갱신)
--    컬럼/공식 그대로 — 단지 정의를 다시 등록.
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS v_contract_status;
CREATE OR REPLACE VIEW v_contract_status AS
SELECT
  c.id                              AS contract_id,
  c.member_id,
  c.trainer_id,
  c.total_sessions,
  COUNT(s.id) FILTER (WHERE s.status IN ('done', 'no_show', 'late_cancel'))
                                    AS used_sessions,
  c.total_sessions
    - COUNT(s.id) FILTER (WHERE s.status IN ('done', 'no_show', 'late_cancel'))
                                    AS remaining_sessions,
  c.start_date,
  c.end_date
FROM pt_contracts c
LEFT JOIN sessions s ON s.contract_id = c.id
WHERE c.deleted_at IS NULL
GROUP BY c.id;


COMMIT;

-- ---------------------------------------------------------------------
-- 검증 SQL (마이그레이션 적용 후 SQL Editor에서 돌려볼 것):
--
--   -- 1) member_profiles에 id PK가 잡혔는지
--   SELECT column_name, is_nullable, data_type
--   FROM information_schema.columns
--   WHERE table_name = 'member_profiles'
--     AND column_name IN ('id', 'user_id');
--   → id NO uuid / user_id YES uuid 두 행 기대.
--
--   -- 2) 헬퍼 함수 등록 확인
--   SELECT proname FROM pg_proc WHERE proname IN
--     ('current_member_profile_id', 'is_member_of_trainer', 'current_user_role');
--   → 3행 기대.
--
--   -- 3) 트레이너 본인이 빈 회원 추가 가능한지 (수동)
--   INSERT INTO member_profiles (center_id, name, phone, goal)
--   VALUES (NULL, '테스트 회원1', '010-0000-0000', '체중감량');
--   → 성공해야 함. user_id는 NULL.
-- ---------------------------------------------------------------------
