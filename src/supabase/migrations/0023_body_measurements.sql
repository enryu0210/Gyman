-- =====================================================================
-- 0023_body_measurements.sql
--
-- 인바디(체성분) "수치" 측정 기록 테이블 신설 — 변화 추이 그래프(S1, develop_plan §4 2.2).
--
-- ⚠ body_assessments(0008)와의 구분:
--   - body_assessments : 사진 + AI 포즈 분석 (Phase 4 / C3). 트레이너 검수 게이트 필요.
--   - body_measurements : 인바디 기기로 측정한 "객관적 수치"(체중/체지방률/골격근량).
--     검수 게이트 없이 회원에게 바로 노출한다 — 측정값은 트레이너의 주관/AI 추론이
--     아니라 사실이므로 회원이 자기 추이를 즉시 보는 편이 동기부여에 낫다.
--
-- 식별자 정책(0013 이후): member_id 는 member_profiles.id(PK)를 참조.
--   회원 측 RLS 는 current_member_profile_id() 헬퍼 경유(auth.uid() 직접 비교 금지).
--
-- 멱등: CREATE TABLE IF NOT EXISTS / ADD COLUMN IF NOT EXISTS /
--       DROP POLICY IF EXISTS → CREATE (SQL Editor 부분 적용 후 재실행 대비).
--
-- 참고: docs/develop_plan.md §4 Phase 2 2.2, 0009/0013(헬퍼·RLS), 0010(트레이너 RLS).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. 테이블
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS body_measurements (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- 측정 대상 회원. 회원 삭제(hard)되면 측정 기록도 함께 정리.
  member_id           uuid NOT NULL
                        REFERENCES member_profiles(id) ON DELETE CASCADE,

  -- 인바디 핵심 3지표. 측정 항목이 일부만 있을 수 있어 모두 nullable.
  -- numeric 으로 소수 첫째자리까지(예: 72.5kg, 18.3%). 음수/이상치는 앱이 검증.
  weight_kg           numeric(5,1),   -- 체중 (kg)
  body_fat_pct        numeric(4,1),   -- 체지방률 (%)
  skeletal_muscle_kg  numeric(5,1),   -- 골격근량 (kg)

  -- 측정일. 인바디는 날짜 단위로 충분(시각 불필요) → date.
  measured_at         date NOT NULL,

  -- 기록한 트레이너(감사/표시용). 트레이너 user_id 참조.
  -- 트레이너 계정 삭제 시에도 측정 이력은 보존 → SET NULL.
  recorded_by         uuid REFERENCES trainer_profiles(user_id) ON DELETE SET NULL,

  created_at          timestamptz NOT NULL DEFAULT now()
);

-- 회원별 + 측정일순 조회가 주 패턴(추이 그래프) → 복합 인덱스.
CREATE INDEX IF NOT EXISTS idx_body_meas_member_date
  ON body_measurements(member_id, measured_at);


-- ---------------------------------------------------------------------
-- 2. RLS
--    PG15+ 는 테이블 RLS 가 기본 비활성이므로 명시적으로 켠다.
-- ---------------------------------------------------------------------
ALTER TABLE body_measurements ENABLE ROW LEVEL SECURITY;

-- 2-1) 트레이너: 본인 담당 회원의 측정값을 모두 다룰 수 있음(조회/입력/수정/삭제).
--      is_member_of_trainer(member_id) = 현재 유효 계약 보유 여부(0009/0013).
DROP POLICY IF EXISTS body_meas_trainer_rw ON body_measurements;
CREATE POLICY body_meas_trainer_rw ON body_measurements
  FOR ALL
  USING (
    current_user_role() = 'trainer'
    AND is_member_of_trainer(member_id)
  )
  WITH CHECK (
    current_user_role() = 'trainer'
    AND is_member_of_trainer(member_id)
  );

-- 2-2) 회원: 본인 측정값만 조회(읽기 전용). 검수 게이트 없음 — 수치는 사실이므로 즉시 노출.
DROP POLICY IF EXISTS body_meas_member_read ON body_measurements;
CREATE POLICY body_meas_member_read ON body_measurements
  FOR SELECT
  USING (member_id = current_member_profile_id());


-- ---------------------------------------------------------------------
-- 검증 SQL (적용 후 SQL Editor):
--   -- 1) 테이블/컬럼
--   SELECT column_name, data_type, is_nullable
--   FROM information_schema.columns WHERE table_name = 'body_measurements';
--
--   -- 2) RLS 정책 2개(rw=ALL / read=SELECT)
--   SELECT polname, cmd FROM pg_policies WHERE tablename = 'body_measurements';
--   → body_meas_trainer_rw(ALL) / body_meas_member_read(SELECT) 기대.
-- ---------------------------------------------------------------------
