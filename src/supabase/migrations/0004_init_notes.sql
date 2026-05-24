-- =====================================================================
-- 0004_init_notes.sql
-- member_notes: 트레이너 전용 메모 (회원 노출 절대 X)
-- source 컬럼으로 manual / AI 초안 / AI 확정 추적 (AI-C 기반)
-- 참고: docs/data_model.md §2.2
-- =====================================================================

CREATE TABLE member_notes (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id         uuid NOT NULL REFERENCES member_profiles(user_id) ON DELETE CASCADE,
  trainer_id        uuid NOT NULL REFERENCES trainer_profiles(user_id),
  content           text NOT NULL,
  visibility        note_visibility NOT NULL DEFAULT 'trainer_only',
  -- AI-C: 메모의 출처 추적
  source            note_source NOT NULL DEFAULT 'manual',
  -- ai_draft인 경우 어떤 수업 기록에서 파생됐는지 (audit + 화면 표시 "출처: 5/24 수업")
  -- FK는 sessions 테이블 생성 후(0005)이므로 여기서 제약 없이 컬럼만 두고,
  -- 무결성이 강하게 필요하면 별도 마이그레이션에서 ALTER로 FK 추가 가능.
  source_session_id uuid,
  -- ai_draft → ai_confirmed로 바뀐 시각
  confirmed_at      timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_notes_member ON member_notes(member_id);
CREATE INDEX idx_notes_trainer ON member_notes(trainer_id);

-- "확인 안 한 AI 초안"을 트레이너 홈에서 빠르게 조회하기 위한 부분 인덱스
CREATE INDEX idx_notes_unconfirmed_drafts ON member_notes(trainer_id)
  WHERE source = 'ai_draft' AND confirmed_at IS NULL;
