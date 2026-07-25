-- =====================================================================
-- 0037_condition_coaching_rules.sql
--
-- 체형 제약 × 동작 패턴 → 코칭 큐 규칙 — 동작 습관·체형 제약 코칭 L1-b.
-- (docs/design_movement_coaching.md §3.3, develop_plan §4 Phase 4.8)
--
-- 무엇을 하는가:
--   0036 에 등록된 회원 제약(예: 골반 전방경사)과, 지금 하려는 운동의 "동작 패턴"
--   (예: push_vertical)을 맞춰 큐 한 줄을 띄운다.
--   → "갈비뼈 닫고 골반 중립 유지. 허리가 젖혀지지 않게."
--
-- ⚠ 왜 "운동별"이 아니라 "동작 패턴별"인가:
--   종목명은 자유 텍스트다(session_records.exercises JSON, trainer_favorite_exercises).
--   "스쿼트"/"바벨 스쿼트"/"백스쿼트"를 각각 매핑하면 규칙이 폭발한다.
--   트레이너도 "오버헤드 동작은 조심"으로 사고하지 "밀리터리프레스만 조심"으로
--   생각하지 않는다. 종목명 → 패턴 매핑은 앱 도메인(domain/movement_pattern.dart)이
--   담당하고, DB 는 패턴 단위 규칙만 보관한다.
--
-- ⚠⚠ 의료·법적 안전선 (설계 §5) — 스키마에 강제해 둔 것:
--   action 에 'avoid'(금지)를 두지 않는다. "이 운동 하지 마세요"는 처방에 가깝다.
--   대체가 필요하면 'modify'(대체 권장)로 표현하고, 문구 주체는 항상 트레이너다.
--   → focus(집중) / caution(주의) / modify(대체 권장) 3종만.
--
-- center_id 의미:
--   NULL = 전 센터 공통 기본 시드(본 파일 하단에서 삽입).
--   값 있음 = 그 센터가 직접 만든 규칙. 같은 (제약, 패턴)이면 센터 규칙이 시드를
--   덮어쓴다 — 덮어쓰기 판단은 앱(domain/coaching_cue.dart)이 한다.
--
-- ⚠ 시드 문구는 잠정이다(설계 §8.2). 내용의 책임 소재상 **트레이너 검수 필수**.
--   검수 후에는 관리자 화면이나 UPDATE 로 문구만 교체하면 된다(구조 변경 불필요).
--
-- 멱등: CREATE TABLE IF NOT EXISTS / DROP POLICY IF EXISTS → CREATE /
--       시드는 WHERE NOT EXISTS 가드(재실행해도 중복 삽입 없음).
--
-- 참고: 0036(member_conditions), 0031(센터 범위 read 정책 선례), 0009/0013(헬퍼).
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1. 테이블
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS condition_coaching_rules (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- NULL = 전 센터 공통 기본 시드 / 값 = 해당 센터 전용 규칙.
  center_id        uuid REFERENCES centers(id) ON DELETE CASCADE,

  -- member_conditions.code 와 같은 코드 체계(앱 카탈로그가 표시명을 들고 있음).
  -- FK 를 걸지 않는 이유: code 는 앱 카탈로그 기준 자유 문자열이고, 마스터 테이블이
  -- 없다(0036 주석). 매칭 실패한 규칙은 앱이 그냥 무시한다.
  condition_code   text NOT NULL CHECK (length(trim(condition_code)) > 0),

  -- 동작 패턴 8종. 앱 도메인(MovementPattern)과 값이 1:1로 맞아야 한다.
  movement_pattern text NOT NULL CHECK (movement_pattern IN (
    'squat', 'hinge', 'lunge',
    'push_horizontal', 'push_vertical',
    'pull_horizontal', 'pull_vertical',
    'core_carry'
  )),

  -- ★ 'avoid'(금지) 없음 — 위 안전선 주석 참조.
  action           text NOT NULL CHECK (action IN ('focus', 'caution', 'modify')),

  -- 회원에게 보이는 한 줄. 짧고 실행 가능한 동작 지시여야 한다.
  cue              text NOT NULL CHECK (length(trim(cue)) > 0),

  -- 트레이너용 상세(왜 이 큐인지). 회원 노출 안 함 — 조회 select 에서 제외.
  detail           text,

  created_by       uuid REFERENCES trainer_profiles(user_id) ON DELETE SET NULL,
  created_at       timestamptz NOT NULL DEFAULT now()
);

-- 같은 범위(센터 또는 공통) 안에서 (제약, 패턴) 조합은 1개.
-- COALESCE 로 NULL center_id 를 고정 UUID 로 접어 넣는다 — PG 의 UNIQUE 는 NULL 을
-- 서로 다른 값으로 취급해서(NULLS DISTINCT 기본), 그냥 두면 공통 시드가 중복 삽입된다.
CREATE UNIQUE INDEX IF NOT EXISTS idx_coaching_rule_unique
  ON condition_coaching_rules(
    COALESCE(center_id, '00000000-0000-0000-0000-000000000000'::uuid),
    condition_code,
    movement_pattern
  );

-- 조회 패턴 = "내가 볼 수 있는 규칙 전부" → 코드+패턴 인덱스로 매칭 가속.
CREATE INDEX IF NOT EXISTS idx_coaching_rule_lookup
  ON condition_coaching_rules(condition_code, movement_pattern);


-- ---------------------------------------------------------------------
-- 2. RLS
-- ---------------------------------------------------------------------
ALTER TABLE condition_coaching_rules ENABLE ROW LEVEL SECURITY;

-- 2-1) 읽기: 공통 시드 + 본인 센터 규칙. 역할 무관(회원도 자기 큐를 봐야 하므로).
--      규칙 문구 자체엔 PII 가 없다 — 민감한 건 "누가 어떤 제약을 갖는가"이고
--      그건 member_conditions RLS(0036)가 막는다.
DROP POLICY IF EXISTS coaching_rules_read ON condition_coaching_rules;
CREATE POLICY coaching_rules_read ON condition_coaching_rules
  FOR SELECT
  USING (
    center_id IS NULL
    OR center_id = (
      SELECT center_id FROM trainer_profiles WHERE user_id = auth.uid()
    )
    OR center_id = (
      SELECT center_id FROM member_profiles WHERE id = current_member_profile_id()
    )
    OR center_id = current_admin_center_id()
  );

-- 2-2) 쓰기: 트레이너/관리자가 **본인 센터 규칙만**.
--      WITH CHECK 가 center_id NOT NULL 을 요구하므로 공통 시드(NULL)는 앱에서
--      만들거나 고칠 수 없다 — 시드는 마이그레이션(SQL Editor)에서만 관리한다.
DROP POLICY IF EXISTS coaching_rules_center_write ON condition_coaching_rules;
CREATE POLICY coaching_rules_center_write ON condition_coaching_rules
  FOR ALL
  USING (
    center_id IS NOT NULL
    AND (
      center_id = (SELECT center_id FROM trainer_profiles WHERE user_id = auth.uid())
      OR center_id = current_admin_center_id()
    )
  )
  WITH CHECK (
    center_id IS NOT NULL
    AND (
      center_id = (SELECT center_id FROM trainer_profiles WHERE user_id = auth.uid())
      OR center_id = current_admin_center_id()
    )
  );


-- ---------------------------------------------------------------------
-- 3. 기본 시드 (center_id = NULL, 전 센터 공통)
--
-- ⚠ 잠정 문구 — 트레이너 검수 후 확정할 것(설계 §8.2).
-- 원칙:
--   - 사실 → 동작 지시 순서. 진단·처방 표현 금지.
--   - 'modify' 는 "트레이너가 안내한 대체 동작"으로 주체를 트레이너에 둔다.
--   - 통증 언급은 항상 트레이너/의료기관 확인으로 끝낸다.
-- 재실행 안전: 같은 (NULL 센터, 코드, 패턴)이 이미 있으면 건너뛴다.
-- ---------------------------------------------------------------------
INSERT INTO condition_coaching_rules (condition_code, movement_pattern, action, cue)
SELECT v.code, v.pattern, v.action, v.cue
FROM (VALUES
  -- 골반 전방경사 — 허리 과신전이 핵심 리스크
  ('anterior_pelvic_tilt', 'push_vertical', 'caution',
   '갈비뼈를 닫고 골반을 중립으로 두세요. 미는 동안 허리가 젖혀지지 않게 합니다.'),
  ('anterior_pelvic_tilt', 'hinge', 'caution',
   '허리를 젖히는 대신 고관절을 접는 느낌으로. 마무리에서 과도하게 펴지 마세요.'),
  ('anterior_pelvic_tilt', 'core_carry', 'focus',
   '복부에 힘을 주고 갈비뼈를 닫은 상태를 끝까지 유지하세요.'),

  -- 골반 후방경사 — 스쿼트 하단 말림(butt wink)
  ('posterior_pelvic_tilt', 'squat', 'caution',
   '하단에서 골반이 말리기 직전까지만 내려가세요. 깊이보다 자세가 우선입니다.'),
  ('posterior_pelvic_tilt', 'hinge', 'focus',
   '시작 자세에서 허리 중립을 먼저 만들고 출발하세요.'),

  -- 라운드 숄더 — 견갑 고정 + 당기기 보강
  ('rounded_shoulder', 'push_horizontal', 'caution',
   '어깨가 앞으로 말리지 않게 견갑을 뒤로 고정한 채 미세요.'),
  ('rounded_shoulder', 'push_vertical', 'caution',
   '어깨가 말린 상태로 밀지 마세요. 걸리는 느낌이 있으면 트레이너에게 알려주세요.'),
  ('rounded_shoulder', 'pull_horizontal', 'focus',
   '견갑을 모으는 데 집중하세요. 팔로만 당기지 않습니다.'),

  -- 거북목 — 경추 중립
  ('forward_head', 'pull_vertical', 'focus',
   '턱을 살짝 당겨 목을 중립으로 유지하세요. 목을 앞으로 빼며 당기지 않습니다.'),
  ('forward_head', 'push_horizontal', 'focus',
   '머리를 벤치에 붙인 채로. 목이 앞으로 나오지 않게 하세요.'),

  -- 척추측만 — 좌우 비대칭 부하 관리 (진단은 의료기관, 앱은 등록된 내용만 전달)
  ('scoliosis', 'lunge', 'modify',
   '한쪽씩 부하가 걸리는 동작입니다. 좌우 느낌 차이가 크면 트레이너가 안내한 대체 동작으로 진행하세요.'),
  ('scoliosis', 'hinge', 'caution',
   '좌우 균형에 유의하고, 무게보다 자세를 우선하세요.'),
  ('scoliosis', 'core_carry', 'modify',
   '한쪽으로만 드는 동작은 트레이너가 안내한 방식으로 진행하세요.'),

  -- 무릎 모임(knee valgus) — 스쿼트·런지 하강 구간
  ('knee_valgus', 'squat', 'focus',
   '무릎이 발끝 방향을 향하게 하세요. 안쪽으로 모이면 무게를 줄입니다.'),
  ('knee_valgus', 'lunge', 'focus',
   '무릎이 안쪽으로 무너지지 않게 엉덩이 옆쪽에 힘을 주세요.'),

  -- 평발 — 발바닥 체중 분산
  ('flat_foot', 'squat', 'focus',
   '엄지·새끼발가락·뒤꿈치 세 지점에 체중을 고르게 실으세요.'),
  ('flat_foot', 'lunge', 'focus',
   '앞발 아치가 무너지지 않게 발바닥 전체로 지면을 누르세요.'),

  -- 어깨 충돌증후군 — 통증 구간 회피는 트레이너 안내로
  ('shoulder_impingement', 'push_vertical', 'modify',
   '통증이 나는 구간이 있으면 트레이너가 안내한 각도·대체 동작으로 진행하세요.'),
  ('shoulder_impingement', 'pull_vertical', 'caution',
   '바를 목 뒤로 넘기지 마세요. 가슴 쪽으로 당깁니다.')
) AS v(code, pattern, action, cue)
WHERE NOT EXISTS (
  SELECT 1 FROM condition_coaching_rules r
  WHERE r.center_id IS NULL
    AND r.condition_code = v.code
    AND r.movement_pattern = v.pattern
);

COMMIT;


-- ---------------------------------------------------------------------
-- 검증 SQL (적용 후 SQL Editor):
--
--   -- 1) 시드 19건이 들어갔는지 (재실행해도 19건 유지 = 멱등)
--   SELECT count(*) FROM condition_coaching_rules WHERE center_id IS NULL;
--
--   -- 2) action 에 'avoid' 가 안 들어가는지(§5 안전선)
--   INSERT INTO condition_coaching_rules (center_id, condition_code, movement_pattern, action, cue)
--   VALUES (NULL, 'scoliosis', 'squat', 'avoid', 'x');
--   → check constraint 위반 기대.
--
--   -- 3) movement_pattern 오타 차단
--   INSERT INTO condition_coaching_rules (center_id, condition_code, movement_pattern, action, cue)
--   VALUES (NULL, 'scoliosis', 'squats', 'focus', 'x');
--   → check constraint 위반 기대.
--
--   -- 4) 회원 계정으로 로그인해 공통 시드가 읽히는지(큐 표시에 필요)
--   SELECT count(*) FROM condition_coaching_rules;  -- 19 이상 기대
--
--   -- 5) 앱에서 공통 시드를 못 고치는지(트레이너 계정으로)
--   UPDATE condition_coaching_rules SET cue = 'x' WHERE center_id IS NULL;
--   → 0 rows updated 기대(RLS 가 걸러 UPDATE 대상이 없음).
-- ---------------------------------------------------------------------
