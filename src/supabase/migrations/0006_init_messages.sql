-- =====================================================================
-- 0006_init_messages.sql
-- messages: 트레이너 ↔ 회원 1:1 채팅 (Phase 2 / S2)
-- Phase 1 데모에서는 비활성이지만 데이터 모델 일관성을 위해 미리 생성
-- 참고: docs/data_model.md §2.2
-- =====================================================================

CREATE TABLE messages (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id   uuid NOT NULL REFERENCES auth.users(id),
  receiver_id uuid NOT NULL REFERENCES auth.users(id),
  content     text NOT NULL,
  sent_at     timestamptz NOT NULL DEFAULT now(),
  read_at     timestamptz,
  CHECK (sender_id <> receiver_id)
);

-- 안 읽은 메시지 빠른 카운트 (회원/트레이너 양쪽 푸시 배지)
CREATE INDEX idx_msg_receiver_unread ON messages(receiver_id) WHERE read_at IS NULL;
-- 1:1 대화 페이징 조회용
CREATE INDEX idx_msg_pair ON messages(sender_id, receiver_id, sent_at DESC);
