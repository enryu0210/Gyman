-- =====================================================================
-- 0015_trainer_favorite_exercises.sql
--
-- 트레이너별 즐겨찾기 운동 종목 (Phase 1.5).
--
-- 목적:
--   수업 기록 화면(M2)에서 "스쿼트/벤치프레스/데드리프트" 같은 자주 쓰는 종목을
--   1탭으로 추가할 수 있게 하여 1분 입력 UX 달성을 돕는다.
--
-- 왜 DB 인가:
--   - SharedPreferences/로컬 저장은 기기 변경 시 사라짐. 트레이너가 태블릿+폰
--     병용하는 시나리오에서 즐겨찾기를 다시 만들어야 하는 마찰 회피.
--   - RLS 본인 행만 접근 — 다른 트레이너 즐겨찾기는 자동 차단.
--
-- 정렬:
--   position 컬럼으로 사용자 정의 순서. UI 가 드래그/정렬을 지원해질 때 이 컬럼
--   업데이트. 현재는 추가 순서(=created_at)와 동일하게 둠.
--
-- 적용 전제: 베타 시작 시점이라 기존 데이터 0건 — 백필 고민 없음.
--
-- 참고: docs/develop_plan.md §4 Phase 1.5.
-- =====================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS trainer_favorite_exercises (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- 본인 트레이너 ID. DB default 가 auth.uid() 라 INSERT 시 자동 채워짐 (회원과 동일 패턴 0014).
  trainer_id  uuid NOT NULL REFERENCES trainer_profiles(user_id) ON DELETE CASCADE DEFAULT auth.uid(),
  -- 종목명. 자유 텍스트지만 (trainer_id, name) 으로 중복 방지.
  name        text NOT NULL,
  -- 정렬 순서. 같은 트레이너 안에서만 의미 — 작을수록 위에 표시.
  position    int  NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- 같은 트레이너 내 중복 종목명 방지 — "스쿼트" 두 번 등록 차단.
ALTER TABLE trainer_favorite_exercises
  DROP CONSTRAINT IF EXISTS trainer_favorite_exercises_unique_per_trainer;
ALTER TABLE trainer_favorite_exercises
  ADD CONSTRAINT trainer_favorite_exercises_unique_per_trainer
  UNIQUE (trainer_id, name);

-- 트레이너 본인 즐겨찾기 정렬 조회 패턴 가속.
CREATE INDEX IF NOT EXISTS idx_fav_trainer_position
  ON trainer_favorite_exercises(trainer_id, position, created_at);


-- =====================================================================
-- RLS — 본인만 read/write
-- =====================================================================
ALTER TABLE trainer_favorite_exercises ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS fav_owner_rw ON trainer_favorite_exercises;
CREATE POLICY fav_owner_rw ON trainer_favorite_exercises
  FOR ALL USING (trainer_id = auth.uid());


COMMIT;

-- ---------------------------------------------------------------------
-- 검증 SQL (마이그레이션 적용 후 SQL Editor):
--
--   -- 1) 테이블/정책 확인
--   SELECT polname, polcmd FROM pg_policy
--   WHERE polrelid = 'trainer_favorite_exercises'::regclass;
--   → fav_owner_rw 1행 기대.
--
--   -- 2) 트레이너 로그인 상태에서 INSERT/SELECT 라운드 트립:
--   INSERT INTO trainer_favorite_exercises (name) VALUES ('스쿼트');
--   SELECT * FROM trainer_favorite_exercises;
--   → 본인 행 1개 보이고, 같은 이름 한 번 더 INSERT 시 UNIQUE 위반 에러.
-- ---------------------------------------------------------------------
