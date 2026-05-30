-- =====================================================================
-- 0025_trainer_dnd_and_msg_policy_cleanup.sql
--
-- (1) 트레이너 "메시지 방해금지 시간(DND)" 설정 — 사생활 경계 보호(2.3 후반).
--     트레이너가 방해금지 시간대를 설정하면, 회원 채팅 화면에 "지금은 방해금지
--     시간(답장이 늦을 수 있어요)" 안내 배너가 뜬다. 전송은 막지 않는다(긴급 대비).
--     ※ FCM 도입 시, 이 시간대엔 푸시를 보류하는 데 그대로 재사용한다.
--
-- (2) 0010 의 messages 정책(msg_participant_rw) 정리.
--     0024 에서 are_chat_peers() 기반의 엄격한 정책(읽기/전송/읽음)을 추가했는데,
--     0010 의 msg_participant_rw(FOR ALL, sender OR receiver = me)가 함께 남아
--     OR 로 합쳐지면서 0024 의 "실제 트레이너-회원 관계만" 제약을 무력화한다
--     (관계 없는 임의 사용자에게도 전송 가능해짐 + 송신자 위조 여지). 옛 정책을
--     드롭해 0024 정책만 거버넌스를 갖게 한다.
--
-- 식별/권한:
--   - 트레이너 본인 수정: trainer_self_rw(0010, FOR ALL user_id=auth.uid()) 재사용 — 추가 불필요.
--   - 회원의 트레이너 DND 조회: trainer_read_by_member(0010/0013, 행 전체 노출) 재사용.
--
-- 멱등: ADD COLUMN IF NOT EXISTS / DROP POLICY IF EXISTS.
--
-- 참고: 0006/0010/0024(messages), 0013(trainer RLS), docs/develop_plan.md §4 2.3.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. 트레이너 DND 컬럼
--    시작/끝은 time(시각만). 22:00~08:00 처럼 자정을 넘기는 구간도 표현 가능
--    (활성 판정은 앱 도메인 DndSettings.isActiveAt 가 wrap-around 처리).
-- ---------------------------------------------------------------------
ALTER TABLE trainer_profiles
  ADD COLUMN IF NOT EXISTS dnd_enabled boolean NOT NULL DEFAULT false;
ALTER TABLE trainer_profiles
  ADD COLUMN IF NOT EXISTS dnd_start time;
ALTER TABLE trainer_profiles
  ADD COLUMN IF NOT EXISTS dnd_end time;

-- ---------------------------------------------------------------------
-- 2. 옛 messages 정책 제거 — 0024 정책(are_chat_peers 기반)만 남긴다.
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS msg_participant_rw ON messages;

-- ---------------------------------------------------------------------
-- 검증 SQL (적용 후):
--   -- 1) DND 컬럼
--   SELECT column_name, data_type FROM information_schema.columns
--   WHERE table_name='trainer_profiles' AND column_name LIKE 'dnd_%';
--
--   -- 2) messages 정책은 0024 의 3개만 남아야 함
--   SELECT polname, cmd FROM pg_policies WHERE tablename='messages';
--   → messages_read_own / messages_send / messages_mark_read (msg_participant_rw 없음)
-- ---------------------------------------------------------------------
