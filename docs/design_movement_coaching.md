# 동작 습관·체형 제약 코칭 설계 (Movement Coaching)

> 상태: **L1-a 구현·적용 완료 / L1-b~L3 미구현** · 작성일 2026-07-25 (최종 갱신 2026-07-25)
> 출처: 트레이너 피드백(2026-07-24, 2026-07-25 정정) — *"운동할 때의 습관(다리가 빠진다, 체중이 이상한 곳에 실린다)이나 체형의 한계에서 오는 문제(측만증으로 인한 운동 변경, 골반 전방경사로 신경써야 하는 부분)를 해결해줘야 한다."*
> 상위: `docs/develop_plan.md` Phase 4 (4.8). 4.5(자세 영상 분석 R&D)를 흡수·구체화한다. 결정 변경 시 develop_plan 먼저 갱신.
> 연계: `docs/design_body_analysis.md`(4.2 — 체형 수치가 L1 제약 등록의 근거로 합류), `docs/design_ghost_overlay.md`(4.7 — 큐 표시 지점 공유), `docs/design_class_videos.md`(0027 — L2가 그 위에 얹힘).
> **핵심 결정(제안): 앱은 판단하지 않는다. 트레이너의 판단을 구조화해서 나른다.**

---

## 0. 목적과 범위

### 0.1 무엇을 푸는가
회원이 혼자 운동할 때, **그 회원에게만 해당하는** 두 가지를 알려준다.
- **(가) 동작 습관** — 반복되는 폼 오류. "스쿼트에서 오른쪽 무릎이 안으로 말린다", "데드리프트에서 허리가 굽는다".
- **(나) 체형 제약** — 구조적 한계로 인한 운동 조정. "측만증이라 편측 부하 운동은 대칭 종목으로 대체", "골반 전방경사라 오버헤드 동작에서 허리 과신전 주의".

지금 이 정보는 **트레이너 머릿속에만 있다.** 수업 중엔 말로 전달되지만, 회원이 혼자 운동하는 순간 사라진다. **그 순간이 폼이 무너지는 순간이다.**

→ 본 기능은 트레이너의 판단을 **구조화해 저장하고, 회원이 그 동작을 하는 시점에 다시 꺼내준다.**

### 0.2 설계의 축 — 앱이 판단하지 않는다
"측만증을 앱이 찾아내서 알려준다"는 방향은 **불가능하고, 해서도 안 된다**(§2 정확도 표, §5 안전선). 대신:

| | 누가 판단하나 | 앱의 역할 |
|---|---|---|
| 체형 제약 (측만증·전방경사) | **의료기관** 또는 **트레이너 관찰** | 구조화 저장 + 해당 동작에서 큐 표시 |
| 동작 습관 (무릎 말림) | **트레이너의 눈** (L2) → 나중에 보조로 자동검출(L3) | 영상 시점에 마킹 + 회원 재생 시 재생 |
| 체형 수치 (좌우 기울기) | 온디바이스 계산(4.2) — **참고 수치** | 제약 등록의 *근거 자료*로 트레이너에게 제시 |

이 구조는 기존 제품 원칙("AI 결과는 트레이너 검수 후 노출")보다 **한 단계 더 보수적**이다 — AI가 초안조차 만들지 않고, 트레이너의 입력을 나르기만 한다.

### 0.3 비범위
- **의학적 진단·처방**: 절대 비범위(§5). 측만증 판정, 부상 진단, 재활 프로그램 처방.
- 자동 운동 프로그램 생성(운동 처방): 트레이너의 영역.
- 족저압·체중 분포 **측정**: 카메라로 불가(§2) — 자세 대리지표 추정만, 그것도 L3에서 단정 금지.
- 실시간(운동 중) 자동 폼 교정 피드백: L3 이후의 별트랙.

---

## 1. 3층 구조 — 무엇을 먼저 만드는가

싸고 확실한 것부터. **L1·L2는 CV 없이 지금 만들 수 있고, 피드백의 대부분을 답한다.**

### L1 · 체형 제약 등록 → 동작 큐 (CV 0, 마이그레이션 1)
1. 트레이너가 회원의 제약을 **구조화 등록** — 코드(측만증/골반전방경사/라운드숄더/…) + **출처**(의료기관 진단 / 트레이너 관찰) + 메모.
2. 제약 × **동작 패턴**(§3.2) → **큐 규칙** 매핑. 센터 기본 시드 + 트레이너 커스텀.
3. 회원이 그 패턴의 운동을 만나는 **모든 지점**에서 큐가 뜬다:
   - 셀프 운동 기록(`/member/self-log`)에 "오버헤드 프레스" 입력 → *"갈비뼈 닫고 골반 중립. 허리가 젖혀지지 않게."*
   - 고스트 따라하기(4.7) 진입 시 상단에 그 회원의 큐
   - 트레이너 수업 기록(M2)에서 종목 추가 시 **주의 배너** — 트레이너 본인도 잊지 않게

> **예시:** 골반 전방경사 등록 → 회원이 셀프로 "밀리터리 프레스" 기록 → 앱이 `push_vertical` 패턴으로 인식 → *"트레이너 주의사항: 갈비뼈 닫고 골반 중립 유지. 허리 과신전 주의."* 표시.

### L2 · 영상 시점 지적 (CV 0, 마이그레이션 1, 정확도 100%)
- 트레이너가 회원 영상(0027)을 재생하며 **특정 시점에 마킹 + 코멘트**: `0:12 · 무릎 · "여기서 오른쪽 무릎이 안으로 말림"`.
- 회원이 그 영상을 재생하면 **해당 시점에 코멘트가 자동으로 뜬다.** 고스트 따라하기(4.7) 중에도 같은 시점에 뜬다.
- **이것이 "동작 습관 피드백"의 가장 확실한 답이다.** 트레이너의 눈은 이미 그걸 보고 있고, 정확도는 사람 수준이며, CV가 전혀 필요 없다.
- 부가 효과: 마킹이 쌓이면 L3의 **검증 데이터셋**이 된다 — "앱이 검출한 것 vs 트레이너가 마킹한 것"을 비교해 정확도를 실측할 수 있다.

### L3 · 자동 검출 (CV 필요, 불확실 — 후순위)
- 영상 관절 각도 시계열에서 **반복 패턴**을 잡아 트레이너에게 *후보*로 제시. 회원에게 직접 노출 금지 — **L2 마킹으로 승격되어야만** 회원에게 간다.
- 검출 대상은 §2 표에서 "가능"으로 판정된 항목만.

---

## 2. 무엇이 실제로 측정 가능한가 (정직하게)

피드백에 나온 항목을 그대로 놓고 판정한다. **이 표가 L3 범위를 결정한다.**

| 요구 항목 | 2D 단일 카메라로 | 판정 | 근거·대응 |
|---|---|---|---|
| **"다리가 빠진다"** (무릎 모임 — knee valgus) | 정면 영상에서 고관절–무릎–발목 정렬각(**FPPA**, Frontal Plane Projection Angle) | **부분 가능** | 스포츠과학에서 2D 비디오 FPPA 로 통용되는 지표. 단 **카메라가 정면·고정**이어야 하고, 스쿼트 하강 최저점 등 **특정 구간**에서만 유효 |
| **"체중이 이상한 곳에 실린다"** | 족저압/지면반력 — **카메라로 측정 불가** | **불가** | 압력분포는 force plate·압력 인솔의 영역. 몸통 기울기·발목 각도로 **간접 추정만** 가능하고 신뢰도 낮음 → L3에서도 **단정 금지**, "무게중심이 앞쪽으로 보임(참고)" 수준 |
| **측만증** | 척추 곡률 판정 = X-ray Cobb angle | **불가·금지** | 체표 keypoint 로 판정하면 **무면허 의료행위 소지**. 앱은 *등록된 진단을 나르기만* 한다(L1) |
| **골반 전방경사** | 측면 ASIS–PSIS 추정 | **screening만** | 옷·연부조직으로 신뢰도 낮음. 4.2에서 이미 "측면은 보조 표시·단정 금지"로 결정 — 그 결론 유지 |
| **좌우 어깨/골반 높이차** | 정면 keypoint 상대 비교 | **가능(참고 수치)** | 4.2의 베타 범위. 전역 오차가 상쇄되는 *상대* 지표라 가장 신뢰도 높음 |

> **결론:** 피드백 4개 항목 중 자동 검출이 실제로 되는 건 **"다리가 빠진다" 하나**다. 나머지는 측정 불가이거나 의료 영역이다.
> → 그래서 **L1(등록·전달)과 L2(사람이 마킹)가 본체이고, L3는 보조**다. 이 순서를 뒤집으면 몇 주를 쓰고도 아무것도 못 준다.

---

## 3. 데이터 모델

### 3.1 `member_conditions` — 회원 체형 제약 (신규)
```sql
CREATE TABLE member_conditions (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id    uuid NOT NULL REFERENCES member_profiles(id) ON DELETE CASCADE,  -- 0013 이후 규칙: FK는 id
  code         text NOT NULL,      -- 'scoliosis'|'anterior_pelvic_tilt'|'rounded_shoulder'|'knee_valgus'|'custom'
  label        text,               -- code='custom' 일 때 표시명
  -- ★ 법적 안전선: 진단인가 관찰인가를 반드시 구분한다(§5)
  source       text NOT NULL CHECK (source IN ('medical','trainer_observation')),
  member_note  text,               -- 회원에게도 보이는 설명
  trainer_note text,               -- 트레이너 전용 상세 — 회원 조회 select 에서 제외(컬럼 단위 방어)
  active       boolean NOT NULL DEFAULT true,
  recorded_by  uuid REFERENCES trainer_profiles(user_id) ON DELETE SET NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_member_conditions ON member_conditions(member_id, active);
```
- **`severity`(경중) 컬럼을 두지 않는다** — "중등도 측만증" 같은 표현은 의료 판단이다. 필요한 뉘앙스는 `trainer_note` 자유 텍스트로.
- 기존 `member_profiles.body_features`/`injury_history`(자유 텍스트, 0003)는 **그대로 두고 병행** — 구조화가 필요한 것만 이 테이블로 승격. 마이그레이션 부담·기존 데이터 파괴 0.

### 3.2 동작 패턴 — 종목명이 아니라 **패턴**으로 묶는다
현재 종목은 **자유 텍스트**다(`session_records.exercises` JSON, `trainer_favorite_exercises.name`). "스쿼트"/"바벨 스쿼트"/"백스쿼트"를 각각 매핑하면 규칙이 폭발한다.

→ **8개 동작 패턴**으로 묶는다. 트레이너도 "오버헤드 동작은 조심"으로 사고하지 "밀리터리프레스만 조심"으로 생각하지 않는다.

| 패턴 | 예시 종목 |
|---|---|
| `squat` | 스쿼트, 레그프레스, 고블릿 |
| `hinge` | 데드리프트, RDL, 굿모닝 |
| `lunge` | 런지, 스플릿 스쿼트, 스텝업 (**편측 부하**) |
| `push_horizontal` | 벤치프레스, 푸시업, 체스트프레스 |
| `push_vertical` | 오버헤드프레스, 밀리터리프레스 |
| `pull_horizontal` | 바벨로우, 시티드로우 |
| `pull_vertical` | 랫풀다운, 풀업 |
| `core_carry` | 플랭크, 파머스워크, 데드버그 |

- **매핑은 앱 도메인 상수로**(`domain/movement_pattern.dart` — 키워드 → 패턴, **순수 함수 + 단위테스트**). 테이블 신설 0. 트레이너 보정이 필요해지면 그때 DB 승격(YAGNI).
- 매칭 실패 시 `null` → 큐 미표시. **조용히 넘어가되 틀린 큐는 절대 안 띄운다.**

### 3.3 `condition_coaching_rules` — 제약 × 패턴 → 큐 (신규)
```sql
CREATE TABLE condition_coaching_rules (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  center_id        uuid REFERENCES centers(id) ON DELETE CASCADE,  -- NULL = 기본 시드(전 센터 공통)
  condition_code   text NOT NULL,
  movement_pattern text NOT NULL,
  action           text NOT NULL CHECK (action IN ('focus','caution','modify')),
  cue              text NOT NULL,     -- 회원에게 보이는 한 줄
  detail           text,              -- 트레이너용 상세
  created_by       uuid REFERENCES trainer_profiles(user_id) ON DELETE SET NULL,
  created_at       timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX idx_rule_unique
  ON condition_coaching_rules(COALESCE(center_id,'00000000-0000-0000-0000-000000000000'::uuid), condition_code, movement_pattern);
```
- `action` 에 **`avoid`(금지)를 두지 않는다** — "이 운동 하지 마세요"는 처방에 가깝다. 대신 `modify`(대체 권장)로 표현하고, 문구 주체는 항상 트레이너.
- 기본 시드 예: `anterior_pelvic_tilt` × `push_vertical` → `caution` / *"갈비뼈 닫고 골반 중립 유지. 허리가 젖혀지지 않게."*

### 3.4 `class_video_marks` — 영상 시점 지적 (L2, 신규)
```sql
CREATE TABLE class_video_marks (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  video_id   uuid NOT NULL REFERENCES class_videos(id) ON DELETE CASCADE,
  t_ms       int  NOT NULL CHECK (t_ms >= 0),   -- 영상 내 시점
  body_part  text,                              -- 'knee'|'hip'|'lumbar'|'shoulder'|null (태그)
  comment    text NOT NULL,
  created_by uuid REFERENCES trainer_profiles(user_id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_marks_video ON class_video_marks(video_id, t_ms);
```
- `ON DELETE CASCADE` — 영상이 지워지면 마킹도 함께(고아 방지).

---

## 4. RLS

| 테이블 | 트레이너 | 회원 |
|---|---|---|
| `member_conditions` | ALL — `is_member_of_trainer(member_id)` | SELECT — `member_id = current_member_profile_id()`. **`trainer_note` 는 조회 select 에서 제외**(컬럼 단위 방어, `next_memo` 선례) |
| `condition_coaching_rules` | 본인 센터 + 기본 시드(`center_id IS NULL`) read / 본인 센터 write | 직접 조회 불필요 — 큐는 앱이 조합해 표시 |
| `class_video_marks` | ALL — 해당 영상이 담당 회원 것일 때 | SELECT — 본인 영상의 마킹 |

- **회원이 자기 제약을 보는 건 정상**이다(본인 건강 정보). 숨기는 게 오히려 이상하다. 다만 트레이너 전용 상세(`trainer_note`)는 분리.
- L2 마킹에 **검수 게이트는 두지 않는다** — 트레이너가 의도적으로 다는 코멘트라 영상 시스템과 같은 논리(`design_class_video_tracking.md` §0).
- 회원 FK는 전부 `member_profiles.id`, 회원 RLS는 `current_member_profile_id()` 경유 (CLAUDE.md 0013 규칙).

---

## 5. 의료·법적 안전선 (이 기능의 최대 리스크)

측만증·골반전방경사는 **의학적 상태명**이다. 다루는 방식을 틀리면 제품이 아니라 법적 문제가 된다.

- **앱은 상태를 판정하지 않는다.** `source` 필드로 출처를 강제 구분하고, UI에도 다르게 표기한다:
  - `medical` → *"의료기관 진단 이력 (회원 제출)"*
  - `trainer_observation` → *"트레이너 관찰 소견"* — **진단이 아님을 명시**
- **트레이너도 진단하지 않는다.** 트레이너는 의료인이 아니므로 등록 UI 문구를 "진단"이 아니라 "관찰/기록"으로 쓴다.
- **금지 표현:** "측만증입니다" ✗ / "이 운동을 하지 마세요" ✗ / "교정해 드립니다" ✗
  **허용 표현:** "측만증 진단 이력이 등록되어 있습니다(출처: 의료기관)" ○ / "트레이너가 대체 동작을 권장했습니다" ○
- **통증·악화 시 항상 의료기관 안내로 끝낸다** (FAQ 2.4에서 정한 톤과 동일).
- L3 자동 검출 결과는 **회원에게 직접 노출 금지** — 트레이너가 L2 마킹으로 승격시킨 것만 회원에게 간다.
- 신체 정보 민감도: 체형분석(4.2 §3.4)의 `body_photo_consent` 와 별개로, **제약 등록 자체에 대한 회원 고지**가 필요한지 Phase 3.5 약관과 함께 확정(§7).

---

## 6. 앱 구조

- `domain/movement_pattern.dart` — 종목명 → 동작 패턴 매핑(**순수 함수 + 단위테스트**, §3.2).
- `domain/coaching_cue.dart` — (제약 목록 × 패턴 × 규칙) → 표시할 큐 선별·정렬(**순수 함수 + 단위테스트**). 최대 표시 개수 제한도 여기서.
- `features/trainer/member_card/member_condition_{repository,providers,card}.dart` + `add_member_condition_dialog.dart` — L1 등록(기존 카드 패턴 co-locate).
- `features/videos/video_mark_*.dart` — L2 마킹 UI(트레이너) + 재생 중 표시(공용 재생기·고스트 화면 양쪽에서 재사용).
- `features/admin/center/coaching_rules_*.dart` — 센터 큐 규칙 관리(3.2-A 센터 규정 화면 옆에 co-locate).
- 큐 표시 지점(읽기 전용 소비자): 회원 셀프 기록, 고스트 화면(4.7), 트레이너 수업 기록(M2).
- **신규 의존성 0.**

---

## 7. 단계적 구현 계획

- **L1-a. 제약 등록 — ✅ 구현 완료(2026-07-25).** `0036_member_conditions.sql`(테이블 + RLS 2종 + `touch_updated_at` 트리거 + 활성 중복 차단 부분 유니크 인덱스) + 도메인 모델(`domain/models/member_condition.dart` — 출처 enum·코드 카탈로그·payload 정규화, 단위테스트 22종) + 트레이너 UI(`features/trainer/member_card/member_condition_{repository,providers}.dart`, `member_conditions_card.dart`, `add_member_condition_dialog.dart`). 회원 상세의 프로필 카드 바로 아래 배치.
  - 등록/해제(active 토글, 이력 보존)/삭제. 중복 등록은 DB 유니크 인덱스 → repository 가 사람이 읽을 메시지로 변환.
  - 안전선 구현분: `source` CHECK 강제, `severity` 미도입, 다이얼로그에 출처별 안내 문구("관찰은 진단이 아님"), 기본 출처를 보수적인 `trainer_observation` 으로.
  - ✅ **0036 SQL Editor 적용 완료(2026-07-25).** 남은 건 스키마가 아니라 동작 확인 — 파일 하단 검증 SQL(특히 `source` CHECK·활성 중복 차단·타 회원 비노출) + 앱에서 등록/해제/삭제 라운드트립.
- **L1-b. 동작 패턴 + 큐** — `movement_pattern`/`coaching_cue` 도메인 + 단위테스트 → `condition_coaching_rules` + 기본 시드 → 셀프 기록·수업 기록에 큐 표시. **← 피드백 (나) 회수 지점.**
- **L2. 영상 시점 지적** — `class_video_marks` + 트레이너 마킹 UI + 회원 재생 시 표시. **← 피드백 (가) 회수 지점.**
- **L2+. 고스트 결합** — 4.7 따라하기 화면에 L1 큐 + L2 마킹 표시(같은 시점에). 두 기능이 여기서 합쳐진다.
- **L3. 자동 검출(R&D)** — §2에서 "가능" 판정된 FPPA(무릎 모임)부터. 체형분석 B(ML Kit)·4.6 프레임추출 인프라 위에서. 결과는 **트레이너 후보 제시까지만.**

각 단계 끝: analyze/test/build 통과 + develop_plan 갱신.

---

## 8. 미해결 결정 (구현 전 확정 필요)

1. **제약 코드 목록**: 기본 세트를 무엇으로 할지(측만증/골반전방경사/라운드숄더/거북목/평발/무릎모임/어깨충돌…). 트레이너와 함께 확정 — **실제로 쓰는 것만** 넣어야 한다.
2. **기본 큐 시드 작성 주체**: 내가 초안 → 트레이너 검수 vs 트레이너가 직접 작성. **트레이너 검수 필수**(내용의 책임 소재).
3. **회원에게 제약을 어디까지 보여줄지**: 전부 vs `member_note` 만. 투명성 ↔ 불안 유발 트레이드오프.
4. **큐 표시 개수/빈도**: 매번 보이면 무시하게 된다("잔소리 앱"). 최대 2개 + 접기 제안.
5. **L2 마킹 진입 경로**: 영상 재생 중 롱프레스 vs 별도 "코멘트 달기" 모드.
6. **제약 등록 고지·동의**: 건강 관련 정보라 별도 고지가 필요한지 (Phase 3.5 약관 연계).
7. **`session_records.pain` 연계**: 통증 기록이 반복되면 "제약으로 등록하시겠어요?" 제안할지.

---

## 9. 리스크 요약

| 리스크 | 영향 | 대응 |
|---|---|---|
| **의료 영역 침범**(진단·처방으로 읽힘) | 법적·신뢰 | `source` 구분 강제 · 금지 표현 목록(§5) · `severity`/`avoid` 미도입 · 통증은 의료기관 안내 |
| **자동 검출 정확도 과신** | 잘못된 코칭 | §2 표로 범위 고정 · L3는 트레이너 후보 제시까지 · 회원 직접 노출 금지 |
| "체중 분포"는 측정 불가인데 기대됨 | 요구 미충족 | **불가능함을 먼저 합의**(§2) · L2(트레이너 눈)로 대체 |
| 종목명 자유 텍스트 → 패턴 오매칭 | 엉뚱한 큐 | 매칭 실패 시 **큐 미표시**(틀린 큐보다 없는 큐) · 단위테스트 · 트레이너 보정 경로 |
| 큐 과잉 → 무시·이탈 | 기능 무용 | 표시 개수 상한 · `focus` 우선 · 접기 |
| 제약 정보 유출 | 민감정보 | RLS 본인+담당 트레이너 한정 · `trainer_note` 컬럼 단위 방어 |
| 트레이너 입력 부담 | 데이터 안 쌓임 | 등록은 회원당 1~2회 · 큐는 센터 시드 재사용 · L2는 영상 보며 1탭 |

---

## 10. 요약

- **한 문장**: 측만증·골반전방경사 같은 제약은 **트레이너가 등록**하고, 무릎 말림 같은 습관은 **트레이너가 영상에 마킹**하며, 앱은 회원이 해당 동작을 하는 **바로 그 순간에 그걸 다시 꺼내준다** — 앱은 판단하지 않는다.
- **왜 이 순서인가**: 피드백 4개 항목 중 자동 검출이 실제로 가능한 건 "다리가 빠진다" 하나뿐이다(§2). CV로 시작하면 몇 주를 쓰고도 아무것도 못 준다. **L1·L2는 CV 없이, 신규 의존성 0으로, 정확도 100%로 요구의 대부분을 답한다.**
