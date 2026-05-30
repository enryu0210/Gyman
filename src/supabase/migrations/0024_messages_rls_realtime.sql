-- =====================================================================
-- 0024_messages_rls_realtime.sql
--
-- 트레이너 ↔ 회원 1:1 채팅(S2 / develop_plan §4 2.3) 활성화.
-- messages 테이블(0006)에 RLS + 실시간 publication 을 붙인다.
--
-- 모델: messages.sender_id / receiver_id 는 auth.users(id)(= 트레이너 user_id 또는
--   회원 user_id). 회원은 앱 연결(user_id != NULL)된 경우에만 채팅 가능.
--
-- 보안 핵심:
--   - 누구에게나 메시지를 못 보내게 — sender/receiver 가 "실제 트레이너-회원
--     관계(유효 계약)"여야 한다. are_chat_peers() 로 검증.
--   - 송신자 위조 차단 — INSERT WITH CHECK 으로 sender_id = auth.uid() 강제.
--   - 읽음 처리(read_at)는 받은 사람만.
--
-- 멱등: CREATE OR REPLACE FUNCTION / DROP POLICY IF EXISTS → CREATE /
--       publication 추가는 존재 검사 후 (부분 적용 후 재실행 대비).
--
-- 참고: 0006(messages), 0009/0013(헬퍼·RLS), docs/develop_plan.md §4 2.3.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. 헬퍼: 두 user_id 가 트레이너-회원(유효 계약) 관계인가?
--    방향 무관(누가 트레이너든) — 계약이 하나라도 살아 있으면 true.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION are_chat_peers(p_user_a uuid, p_user_b uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT EXISTS (
    SELECT 1
    FROM pt_contracts c
    JOIN member_profiles m ON m.id = c.member_id
    WHERE c.deleted_at IS NULL
      AND (
        (c.trainer_id = p_user_a AND m.user_id = p_user_b) OR
        (c.trainer_id = p_user_b AND m.user_id = p_user_a)
      )
  )
$$;

-- ---------------------------------------------------------------------
-- 2. RLS
-- ---------------------------------------------------------------------
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- 2-1) 조회: 내가 보낸/받은 메시지만. (관계 검증은 INSERT 에서 이미 걸리지만,
--      혹시 모를 잘못된 행이 새지 않게 peer 검증도 함께 — 2차 방어.)
DROP POLICY IF EXISTS messages_read_own ON messages;
CREATE POLICY messages_read_own ON messages
  FOR SELECT TO authenticated
  USING (
    (auth.uid() = sender_id OR auth.uid() = receiver_id)
    AND are_chat_peers(sender_id, receiver_id)
  );

-- 2-2) 전송: 내가 보낸 것(sender 위조 차단) + 실제 트레이너-회원 관계만.
DROP POLICY IF EXISTS messages_send ON messages;
CREATE POLICY messages_send ON messages
  FOR INSERT TO authenticated
  WITH CHECK (
    sender_id = auth.uid()
    AND sender_id <> receiver_id
    AND are_chat_peers(sender_id, receiver_id)
  );

-- 2-3) 읽음 처리: 받은 사람이 본인이 받은 메시지의 read_at 을 채운다.
--      USING/CHECK 둘 다 receiver=본인 — 남의 메시지 상태 변경 차단.
DROP POLICY IF EXISTS messages_mark_read ON messages;
CREATE POLICY messages_mark_read ON messages
  FOR UPDATE TO authenticated
  USING (auth.uid() = receiver_id)
  WITH CHECK (auth.uid() = receiver_id);

-- ---------------------------------------------------------------------
-- 3. 실시간(Realtime) — supabase_realtime publication 에 messages 추가.
--    이미 들어 있으면 건너뜀(멱등). RLS 가 적용되므로 본인 메시지만 수신.
-- ---------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE messages;
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- 검증 SQL (적용 후):
--   -- 1) 정책 3개
--   SELECT polname, cmd FROM pg_policies WHERE tablename = 'messages';
--   → messages_read_own(SELECT) / messages_send(INSERT) / messages_mark_read(UPDATE)
--
--   -- 2) 실시간 등록
--   SELECT tablename FROM pg_publication_tables
--   WHERE pubname = 'supabase_realtime' AND tablename = 'messages';
--   → 1행 기대.
-- ---------------------------------------------------------------------
