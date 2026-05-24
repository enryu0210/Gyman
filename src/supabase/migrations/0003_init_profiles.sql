-- =====================================================================
-- 0003_init_profiles.sql
-- trainer_profiles, member_profiles
-- Supabase Auth(auth.users)와 1:1 매핑 + 역할별 추가 속성
-- 참고: docs/data_model.md §2.2
-- =====================================================================

-- 트레이너 프로필
CREATE TABLE trainer_profiles (
  user_id    uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  center_id  uuid REFERENCES centers(id),
  name       text NOT NULL,
  phone      text,
  bio        text,
  created_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);

CREATE INDEX idx_trainer_center ON trainer_profiles(center_id);


-- 회원 프로필
-- 회원 본인 + 담당 트레이너가 모두 볼 수 있는 정보만 여기에 저장.
-- 트레이너 전용 메모(성향, 재등록 가능성 등)는 member_notes 테이블에 분리(0004).
CREATE TABLE member_profiles (
  user_id          uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  center_id        uuid REFERENCES centers(id),
  name             text NOT NULL,
  phone            text,
  birth_date       date,
  goal             text,                 -- 운동 목적 (예: "체중감량")
  experience       text,                 -- 운동 경험
  injury_history   text,                 -- 부상 이력
  body_features    text,                 -- 체형 특징
  lifestyle        text,                 -- 생활 패턴
  available_times  jsonb,                -- [{day:'mon', from:'19:00', to:'21:00'}, ...]
  -- AI 기능 사용 동의 (회원별 토글)
  -- false면 이 회원에 대한 AI 안내 메시지/메모 초안 생성 자체를 막아야 함 (앱 단에서 체크)
  ai_consent       boolean NOT NULL DEFAULT false,
  created_at       timestamptz NOT NULL DEFAULT now(),
  deleted_at       timestamptz
);

CREATE INDEX idx_member_center ON member_profiles(center_id);
