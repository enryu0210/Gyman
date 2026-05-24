-- =====================================================================
-- 0010_rls_policies.sql
-- 모든 테이블 RLS 활성화 + 정책 정의
-- 핵심 원칙:
--   1. 트레이너 전용 메모(member_notes)는 회원 SELECT 차단 (이중 안전장치)
--   2. AI 결과(body_assessments)는 trainer_comment 채워진 것만 회원 노출
--   3. AI 안내 메시지(outgoing_notifications)는 status='sent'만 회원 노출
-- 참고: docs/data_model.md §3.2
-- =====================================================================

-- ---------- centers ----------
ALTER TABLE centers ENABLE ROW LEVEL SECURITY;

-- 인증된 사용자는 자기가 소속된 센터를 읽을 수 있다.
-- (관리자 전용 정책은 Phase 3에서 추가)
CREATE POLICY centers_authenticated_read ON centers
  FOR SELECT TO authenticated USING (true);


-- ---------- trainer_profiles ----------
ALTER TABLE trainer_profiles ENABLE ROW LEVEL SECURITY;

-- 본인 조회/수정
CREATE POLICY trainer_self_rw ON trainer_profiles
  FOR ALL USING (user_id = auth.uid());

-- 회원이 자기 담당 트레이너 프로필 조회 가능 (이름/연락처만 필요)
CREATE POLICY trainer_read_by_member ON trainer_profiles
  FOR SELECT USING (
    current_user_role() = 'member'
    AND EXISTS (
      SELECT 1 FROM pt_contracts
      WHERE pt_contracts.trainer_id = trainer_profiles.user_id
        AND pt_contracts.member_id  = auth.uid()
        AND pt_contracts.deleted_at IS NULL
    )
  );


-- ---------- member_profiles ----------
ALTER TABLE member_profiles ENABLE ROW LEVEL SECURITY;

-- 본인 조회/수정
CREATE POLICY member_self_rw ON member_profiles
  FOR ALL USING (user_id = auth.uid());

-- 담당 트레이너 조회/수정
CREATE POLICY member_by_trainer ON member_profiles
  FOR ALL USING (
    current_user_role() = 'trainer'
    AND is_member_of_trainer(user_id)
  );


-- ---------- member_notes ----------
ALTER TABLE member_notes ENABLE ROW LEVEL SECURITY;

-- 본인이 작성한 메모만 트레이너가 read/write
CREATE POLICY notes_owner_rw ON member_notes
  FOR ALL USING (
    current_user_role() = 'trainer'
    AND trainer_id = auth.uid()
  );

-- 이중 안전장치: member 역할 명시적 거부
-- (notes_owner_rw가 trainer 조건이라 member는 자동 차단되지만,
--  향후 정책 추가 시 실수로 회원에게 열어주는 사고 방지)
CREATE POLICY notes_member_deny ON member_notes
  FOR SELECT TO authenticated
  USING (current_user_role() <> 'member');


-- ---------- pt_contracts ----------
ALTER TABLE pt_contracts ENABLE ROW LEVEL SECURITY;

CREATE POLICY contract_member_read ON pt_contracts
  FOR SELECT USING (member_id = auth.uid());

CREATE POLICY contract_trainer_rw ON pt_contracts
  FOR ALL USING (trainer_id = auth.uid());


-- ---------- sessions ----------
ALTER TABLE sessions ENABLE ROW LEVEL SECURITY;

-- 회원: 본인 계약에 속한 수업 조회만 가능 (UPDATE 불가)
CREATE POLICY sessions_member_read ON sessions
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM pt_contracts c
      WHERE c.id = sessions.contract_id AND c.member_id = auth.uid()
    )
  );

-- 트레이너: 본인이 담당하는 계약의 수업 전체 권한
CREATE POLICY sessions_trainer_rw ON sessions
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM pt_contracts c
      WHERE c.id = sessions.contract_id AND c.trainer_id = auth.uid()
    )
  );


-- ---------- session_records ----------
ALTER TABLE session_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY records_member_read ON session_records
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM sessions s
      JOIN pt_contracts c ON c.id = s.contract_id
      WHERE s.id = session_records.session_id AND c.member_id = auth.uid()
    )
  );

CREATE POLICY records_trainer_rw ON session_records
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM sessions s
      JOIN pt_contracts c ON c.id = s.contract_id
      WHERE s.id = session_records.session_id AND c.trainer_id = auth.uid()
    )
  );


-- ---------- messages (Phase 2, RLS만 미리) ----------
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- 송수신 당사자만 접근
CREATE POLICY msg_participant_rw ON messages
  FOR ALL USING (sender_id = auth.uid() OR receiver_id = auth.uid());


-- ---------- outgoing_notifications (AI-B 검수 게이트) ----------
ALTER TABLE outgoing_notifications ENABLE ROW LEVEL SECURITY;

-- 트레이너: 본인이 보낼 알림 전체 read/write
CREATE POLICY notif_trainer_rw ON outgoing_notifications
  FOR ALL USING (trainer_id = auth.uid());

-- 회원: '본인 앞' + '발송 완료'만 조회.
-- draft/approved/canceled 상태는 절대 노출되지 않음.
-- → AI 미검수 초안 노출 방지를 RLS로 강제.
CREATE POLICY notif_member_read_sent_only ON outgoing_notifications
  FOR SELECT USING (
    target_member_id = auth.uid()
    AND status = 'sent'
  );


-- ---------- body_assessments (AI 검수 게이트, Phase 4) ----------
ALTER TABLE body_assessments ENABLE ROW LEVEL SECURITY;

-- 트레이너: 담당 회원 분석 전체 권한
CREATE POLICY assess_trainer_rw ON body_assessments
  FOR ALL USING (
    current_user_role() = 'trainer'
    AND is_member_of_trainer(member_id)
  );

-- 회원: 본인 분석이되, '트레이너 코멘트가 채워진 것만' 조회.
-- AI가 단독으로 회원에게 결과를 전달하지 못하게 하는 안전 게이트.
CREATE POLICY assess_member_read_after_review ON body_assessments
  FOR SELECT USING (
    member_id = auth.uid()
    AND trainer_comment IS NOT NULL
    AND length(trim(trainer_comment)) > 0
  );
