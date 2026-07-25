-- =====================================================================
-- 0036_member_conditions.sql
--
-- 회원 체형 제약/특이사항 구조화 테이블 신설 — 동작 습관·체형 제약 코칭 L1-a.
-- (docs/design_movement_coaching.md §3.1, develop_plan §4 Phase 4.8)
--
-- 왜 필요한가:
--   "측만증이라 편측 부하는 대칭 종목으로", "골반 전방경사라 오버헤드에서 허리 주의"
--   같은 판단이 지금은 트레이너 머릿속에만 있다. 회원이 혼자 운동하는 순간 사라지고,
--   그 순간이 폼이 무너지는 순간이다. 이 테이블은 그 판단을 구조화해 저장한다.
--
-- ⚠ member_profiles.body_features / injury_history (0003, 자유 텍스트)와의 관계:
--   기존 컬럼은 그대로 둔다(파괴적 마이그레이션 회피). 자유 서술은 거기 남기고,
--   "동작 큐로 연결할 수 있는" 구조화된 항목만 이 테이블로 승격한다.
--
-- ⚠⚠ 의료·법적 안전선 (설계 §5) — 스키마에 강제해 둔 것:
--   1) source CHECK 로 '의료기관 진단'과 '트레이너 관찰'을 반드시 구분한다.
--      트레이너는 의료인이 아니라 진단 권한이 없다. 앱도 상태를 판정하지 않는다.
--      앱의 역할은 "등록된 판단을 나르는 것"이지 "판단하는 것"이 아니다.
--   2) severity(경중) 컬럼을 의도적으로 두지 않는다 — "중등도 측만증" 같은 표현은
--      의료 판단이다. 필요한 뉘앙스는 trainer_note 자유 텍스트로 남긴다.
--
-- code 를 enum 이 아니라 text 로 둔 이유:
--   제약 코드 목록은 트레이너와 함께 확정해야 하고(설계 §8.1), 이후에도 늘어난다.
--   enum 이면 코드 하나 추가할 때마다 마이그레이션이 필요하다. 표시명은 앱 도메인
--   (domain/models/member_condition.dart)이 들고 있고, 모르는 코드는 앱이 원문 표시로
--   흡수한다 — DB 는 문자열만 보관.
--
-- 식별자 정책(0013 이후): member_id 는 member_profiles.id(PK) 참조.
--   회원 측 RLS 는 current_member_profile_id() 헬퍼 경유(auth.uid() 직접 비교 금지).
--
-- 멱등: CREATE TABLE IF NOT EXISTS / DROP POLICY IF EXISTS → CREATE
--       (SQL Editor 부분 적용 후 재실행 대비).
--
-- 참고: docs/design_movement_coaching.md, 0009/0013(헬퍼), 0011(touch_updated_at),
--       0023(가장 유사한 트레이너 입력 테이블 패턴).
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1. 테이블
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS member_conditions (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- 대상 회원. 회원 hard delete 시 제약도 함께 정리.
  member_id     uuid NOT NULL
                  REFERENCES member_profiles(id) ON DELETE CASCADE,

  -- 제약 코드. 앱 도메인의 표시명 테이블과 매칭('scoliosis','anterior_pelvic_tilt',
  -- 'rounded_shoulder','forward_head','knee_valgus','flat_foot',
  -- 'shoulder_impingement','custom' 등). 모르는 코드는 앱이 label/원문으로 표시.
  code          text NOT NULL CHECK (length(trim(code)) > 0),

  -- code='custom' 일 때의 표시명. 그 외에는 앱 도메인 표시명을 쓰므로 NULL 가능.
  label         text,

  -- ★ 출처 — 진단인가 관찰인가. 법적 안전선이라 스키마에서 강제한다.
  --   'medical'             : 의료기관 진단 이력(회원이 제출한 것을 옮겨 적음)
  --   'trainer_observation' : 트레이너 관찰 소견 — 진단이 아님
  source        text NOT NULL
                  CHECK (source IN ('medical', 'trainer_observation')),

  -- 회원에게도 보이는 설명(예: "우측 어깨가 낮은 편").
  member_note   text,

  -- 트레이너 전용 상세. 회원 노출 금지 —
  --   ⚠ PG RLS 는 행 단위라 컬럼을 가릴 수 없다. 회원 측 조회(L1-b에서 구현)는
  --     이 컬럼을 SELECT 목록에서 제외하는 "컬럼 단위 방어"로 막는다
  --     (session_records.next_memo 와 동일한 기존 패턴 — CLAUDE.md).
  --   → 하드닝이 필요해지면 회원 전용 security_invoker view 로 승격 검토.
  trainer_note  text,

  -- 해제(과거 이력 보존용). 삭제 대신 active=false 로 내리면 이력이 남는다.
  active        boolean NOT NULL DEFAULT true,

  -- 등록한 트레이너(감사·표시용). 계정 삭제돼도 제약 이력은 보존 → SET NULL.
  recorded_by   uuid REFERENCES trainer_profiles(user_id) ON DELETE SET NULL,

  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

-- 주 조회 패턴 = "이 회원의 현재 유효한 제약" → 복합 인덱스.
CREATE INDEX IF NOT EXISTS idx_member_conditions_member
  ON member_conditions(member_id, active);

-- 같은 회원에 같은 코드가 중복 등록되는 것 방지(custom 은 label 로 갈리므로 제외).
-- 부분 유니크 인덱스 — 해제된(active=false) 이력은 중복 허용해 재등록 가능.
CREATE UNIQUE INDEX IF NOT EXISTS idx_member_conditions_unique_active
  ON member_conditions(member_id, code)
  WHERE active AND code <> 'custom';


-- updated_at 자동 갱신 — 0011 의 공용 트리거 함수 재사용.
DROP TRIGGER IF EXISTS trg_member_conditions_touch ON member_conditions;
CREATE TRIGGER trg_member_conditions_touch
  BEFORE UPDATE ON member_conditions
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();


-- ---------------------------------------------------------------------
-- 2. RLS
--    PG15+ 는 테이블 RLS 가 기본 비활성이므로 명시적으로 켠다.
-- ---------------------------------------------------------------------
ALTER TABLE member_conditions ENABLE ROW LEVEL SECURITY;

-- 2-1) 트레이너: 본인 담당 회원의 제약을 등록/조회/수정/해제.
--      is_member_of_trainer(member_id) = 현재 유효 계약 보유 여부(0013 재정의판,
--      인자는 member_profiles.id).
DROP POLICY IF EXISTS member_cond_trainer_rw ON member_conditions;
CREATE POLICY member_cond_trainer_rw ON member_conditions
  FOR ALL
  USING (
    current_user_role() = 'trainer'
    AND is_member_of_trainer(member_id)
  )
  WITH CHECK (
    current_user_role() = 'trainer'
    AND is_member_of_trainer(member_id)
  );

-- 2-2) 회원: 본인 제약만 조회(읽기 전용).
--      본인 건강 관련 정보라 열람은 정상 — 숨기는 편이 오히려 부자연스럽다.
--      단 trainer_note 는 앱 조회 select 에서 제외(위 컬럼 주석 참조).
DROP POLICY IF EXISTS member_cond_member_read ON member_conditions;
CREATE POLICY member_cond_member_read ON member_conditions
  FOR SELECT
  USING (member_id = current_member_profile_id());

COMMIT;


-- ---------------------------------------------------------------------
-- 검증 SQL (적용 후 SQL Editor):
--
--   -- 1) 테이블/컬럼 — severity 컬럼이 "없어야" 정상(§5 안전선).
--   SELECT column_name, data_type, is_nullable
--   FROM information_schema.columns WHERE table_name = 'member_conditions';
--
--   -- 2) RLS 정책 2개
--   SELECT policyname, cmd FROM pg_policies WHERE tablename = 'member_conditions';
--   → member_cond_trainer_rw(ALL) / member_cond_member_read(SELECT) 기대.
--
--   -- 3) source CHECK 가 실제로 막는지(잘못된 값 INSERT 시도 → 에러 기대)
--   INSERT INTO member_conditions (member_id, code, source)
--   VALUES ('<담당 회원 id>', 'scoliosis', 'self_diagnosed');
--   → new row violates check constraint 기대. 'medical' 로는 성공해야 함.
--
--   -- 4) 활성 중복 차단(같은 회원+코드 두 번 → 두 번째 UNIQUE 위반 기대)
--   INSERT INTO member_conditions (member_id, code, source)
--   VALUES ('<같은 회원 id>', 'scoliosis', 'medical');
--
--   -- 5) 회원 계정으로 로그인해 타인 제약이 안 보이는지
--   SELECT count(*) FROM member_conditions;  -- 본인 것만 기대
-- ---------------------------------------------------------------------
