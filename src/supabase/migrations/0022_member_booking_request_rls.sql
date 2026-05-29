-- =====================================================================
-- 0022_member_booking_request_rls.sql
--
-- 회원이 본인 계약에 한해 예약을 "신청"(requested)하고, 아직 미승인 상태인
-- 신청을 스스로 철회(DELETE)할 수 있도록 sessions RLS 를 보강한다.
--
-- 기존 정책과의 관계:
--   - 조회: sessions_member_read (0013) 가 본인 계약의 모든 수업을 노출 →
--           requested 상태도 그대로 회원이 본다(신청 현황 확인용). 추가 불필요.
--   - 트레이너 승인/거절: sessions_trainer_rw (0010, FOR ALL) 가 본인 계약 수업의
--           UPDATE(requested→scheduled)·DELETE(거절)를 이미 허용. 추가 불필요.
--
-- 본 파일이 새로 여는 권한(회원):
--   1) INSERT — status='requested' 인 본인 계약 수업만. (확정 예약 직접 생성 차단)
--   2) DELETE — 본인 계약의 'requested' 신청만. (확정/완료 수업은 못 지움)
--
-- 회원 식별은 current_member_profile_id() 경유(CLAUDE.md 지침 — auth.uid() 직접비교 금지).
--
-- ⚠ 선행 조건: 0021(session_status 에 'requested' 추가)이 **먼저 커밋**되어 있어야 한다.
--   아니면 정책의 status = 'requested' 리터럴에서 ENUM 캐스팅 에러가 난다.
--
-- 멱등: DROP POLICY IF EXISTS → CREATE (부분 적용 후 재실행 대비).
--
-- 참고: docs/develop_plan.md §4 회원 로드맵 ⑤, 0010/0013 RLS.
-- =====================================================================

-- 1) 회원: 본인 계약에 'requested' 신청 INSERT 만 허용.
DROP POLICY IF EXISTS sessions_member_request_insert ON sessions;
CREATE POLICY sessions_member_request_insert ON sessions
  FOR INSERT TO authenticated
  WITH CHECK (
    status = 'requested'
    AND EXISTS (
      SELECT 1 FROM pt_contracts c
      WHERE c.id = sessions.contract_id
        AND c.member_id = current_member_profile_id()
    )
  );

-- 2) 회원: 본인이 신청한 'requested' 만 철회 DELETE.
--    승인되어 scheduled 가 되었거나 진행/취소된 수업은 회원이 못 지운다
--    (status 조건으로 차단 — 트레이너 영역 보호).
DROP POLICY IF EXISTS sessions_member_cancel_request ON sessions;
CREATE POLICY sessions_member_cancel_request ON sessions
  FOR DELETE TO authenticated
  USING (
    status = 'requested'
    AND EXISTS (
      SELECT 1 FROM pt_contracts c
      WHERE c.id = sessions.contract_id
        AND c.member_id = current_member_profile_id()
    )
  );

-- ---------------------------------------------------------------------
-- 검증 SQL (적용 후):
--   SELECT polname, cmd FROM pg_policies
--   WHERE tablename = 'sessions' AND polname LIKE 'sessions_member_%';
--   → request_insert(INSERT) / cancel_request(DELETE) / read(SELECT) 기대.
-- ---------------------------------------------------------------------
