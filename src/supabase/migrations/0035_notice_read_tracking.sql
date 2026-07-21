-- =====================================================================
-- 0035_notice_read_tracking.sql
-- 회원 "받은 안내" 읽음 처리 — read_at 컬럼 + 안읽음 카운트 인덱스 +
-- 회원이 본인 sent 안내를 읽음 처리하는 좁은 SECURITY DEFINER RPC.
--
-- 왜 RPC 인가: 회원에게 outgoing_notifications 직접 UPDATE 를 열면 read_at 외
-- content/status 까지 손댈 여지가 생긴다. 컬럼 단위 GRANT 로 좁히려 해도 트레이너도
-- 같은 'authenticated' 롤이라 트레이너 쓰기까지 막혀 못 쓴다 → read_at 만 건드리는
-- 좁은 RPC 로 우회(CLAUDE.md: 좁은 SECURITY DEFINER RPC + GRANT EXECUTE).
--
-- 멱등: ADD COLUMN IF NOT EXISTS / CREATE INDEX IF NOT EXISTS / CREATE OR REPLACE.
-- 참고: docs/develop_plan.md 회원 로드맵 ④, 0007(테이블)/0013(target_member_id→id, RLS).
-- =====================================================================

-- 읽음 시각. NULL = 안읽음.
ALTER TABLE outgoing_notifications
  ADD COLUMN IF NOT EXISTS read_at timestamptz;

-- 회원 홈 "받은 안내 N" 안읽음 배지 카운트용 부분 인덱스.
CREATE INDEX IF NOT EXISTS idx_notif_member_unread
  ON outgoing_notifications (target_member_id)
  WHERE status = 'sent' AND read_at IS NULL;

-- 회원이 본인이 받은(sent) 안내 1건을 읽음 처리. read_at 만 채운다.
--   - 본인 것(target_member_id = current_member_profile_id())만
--   - 발송된(sent) 것만 — draft/approved 는 애초에 회원에게 안 보임
--   - 이미 읽음이면 아무 행도 안 바뀜(멱등)
CREATE OR REPLACE FUNCTION mark_notice_read(p_notice_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE outgoing_notifications
  SET read_at = now()
  WHERE id = p_notice_id
    AND target_member_id = current_member_profile_id()
    AND status = 'sent'
    AND read_at IS NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION mark_notice_read(uuid) TO authenticated;
