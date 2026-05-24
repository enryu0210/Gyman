-- =====================================================================
-- 0005_init_contracts_sessions.sql
-- pt_contracts: PT 계약 (잔여 횟수의 원천)
-- sessions: 수업 1건 (예약·실행·차감 추적)
-- session_records: 수업 기록 본문 (sessions와 1:1)
-- 참고: docs/data_model.md §2.2
-- =====================================================================

-- PT 계약
-- 잔여 횟수는 sessions 테이블에서 동적으로 계산 (v_contract_status view 사용, 0011).
-- 캐시 컬럼을 두면 불일치 위험이 큼.
CREATE TABLE pt_contracts (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id       uuid NOT NULL REFERENCES member_profiles(user_id),
  trainer_id      uuid NOT NULL REFERENCES trainer_profiles(user_id),
  center_id       uuid REFERENCES centers(id),
  total_sessions  int  NOT NULL CHECK (total_sessions > 0),
  start_date      date NOT NULL,
  end_date        date,                  -- NULL 가능 (만료일 미정)
  price           int,                   -- 원 단위
  memo            text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz,
  CHECK (end_date IS NULL OR end_date >= start_date)
);

CREATE INDEX idx_contract_member ON pt_contracts(member_id);
CREATE INDEX idx_contract_trainer ON pt_contracts(trainer_id);


-- 수업 1건
-- 차감 여부는 status로 판단:
--   done, no_show, late_cancel → 차감 대상
--   scheduled, canceled        → 미차감
CREATE TABLE sessions (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contract_id            uuid NOT NULL REFERENCES pt_contracts(id) ON DELETE RESTRICT,
  scheduled_at           timestamptz NOT NULL,
  status                 session_status NOT NULL DEFAULT 'scheduled',
  recorded_at            timestamptz,           -- 기록 완료 시각
  recorded_by_trainer_id uuid REFERENCES trainer_profiles(user_id),
  -- 트레이너 메모(취소 사유 등). session_records와는 다른 영역.
  status_memo            text,
  created_at             timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_sessions_contract  ON sessions(contract_id);
CREATE INDEX idx_sessions_scheduled ON sessions(scheduled_at);
-- 트레이너 홈의 "오늘 수업" 빠른 조회용
CREATE INDEX idx_sessions_today ON sessions(scheduled_at, status);


-- 수업 기록 본문 (운동/컨디션/메모)
-- sessions와 1:1. 분리 이유: 예약만 있고 기록은 없는 케이스(노쇼 등) 처리.
CREATE TABLE session_records (
  session_id  uuid PRIMARY KEY REFERENCES sessions(id) ON DELETE CASCADE,
  -- 운동 종목/세트/무게/반복: 자유도 위해 JSON.
  -- 예: [{"name":"스쿼트", "sets":[{"weight":60,"reps":10},{"weight":70,"reps":8}]}]
  exercises   jsonb NOT NULL DEFAULT '[]'::jsonb,
  condition   text,            -- 회원 컨디션 ('good'/'normal'/'bad' 같은 코드 또는 자유 텍스트)
  pain        text,            -- 통증/특이사항
  next_memo   text,            -- 다음 수업 메모
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);


-- 이제 sessions 테이블이 존재하므로 member_notes.source_session_id에 FK 추가
ALTER TABLE member_notes
  ADD CONSTRAINT fk_notes_source_session
  FOREIGN KEY (source_session_id) REFERENCES sessions(id) ON DELETE SET NULL;
