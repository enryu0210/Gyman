# 실기기 E2E 검증 대본 (Phase 1.12 베타 배포 전)

> 대상: `docs/develop_plan.md` §8 "검증" 체크리스트 잔여 10항목.
> 목적: 마이그레이션·Edge Function은 전부 배포됐으나 **실제로 도는지 확인한 항목이 0건**이라,
>       한 번의 실기기 세션으로 전 항목을 소진한다.
> 최초 작성: 2026-07-20

## 이 문서를 쓰는 법

- 위에서부터 순서대로 진행한다. **순서에 의존성이 있다** — 특히 라운드 6(탈퇴)은 계정을 파괴하므로 반드시 마지막.
- 각 항목의 `기대`가 실제와 다르면 그 자리에서 멈추고 `의심 지점`을 확인한다.
- 통과한 항목은 `develop_plan.md` §8 체크박스에 `[x]` + 날짜를 남긴다.
- 소요 예상: 준비 30분 + 검증 90분.

---

## 라운드 0 — 준비

### 0.1 계정 3종

| 역할 | 만드는 법 | 비고 |
|------|-----------|------|
| 트레이너 | 앱에서 가입 후 SQL로 `trainer_profiles` INSERT | 이미 있으면 재사용 |
| 회원 | **라운드 1에서 앱으로 신규 가입** (초대 코드 필요) | 미리 만들지 말 것 — 가입 자체가 검증 대상 |
| 관리자 | SQL로 `admin_profiles` INSERT (앱 가입 UI 없음) | 트레이너 계정에 겸직시키면 라운드 4가 편함 |

```sql
-- 관리자 등록 (0029 주석의 방식). 트레이너 겸직 = 같은 user_id 사용.
INSERT INTO admin_profiles (user_id, center_id, name)
SELECT t.user_id, t.center_id, t.name || '(관리자)'
FROM trainer_profiles t
WHERE t.user_id = '<트레이너 user_id>'
ON CONFLICT DO NOTHING;

-- 확인: 'admin' 또는 겸직 시 'trainer' 가 나와야 함(역할 우선순위상 트레이너가 이김)
SELECT current_user_role();
```

> 겸직이면 홈이 트레이너 홈이고, 격자 맨 앞에 **"관리자 대시보드"** 타일이 추가로 뜬다
> (`trainer_home_screen.dart:219`). 이 타일이 안 보이면 `admin_profiles` INSERT가 안 된 것.

### 0.2 AI 사용 동의

`ai_consent`는 기본 `false`이고, 이게 `true`여야만 라운드 3의 AI 3종이 동작한다.
**앱에서 켠다** — 트레이너 → 회원 목록 → 회원 상세 → **수정** → 맨 아래 `AI 사용 동의` 스위치.

> 이 토글 자체가 검증 대상이다. 켠 뒤 아래로 DB에 반영됐는지 확인할 것.

```sql
SELECT name, ai_consent FROM member_profiles WHERE invite_code = '<대상 회원 코드>';
```

- **기대**: 스위치를 켜고 저장하면 `ai_consent = true`
- **의심 지점**: 스위치는 켜지는데 DB가 `false`면 → `updateMember` payload에서 `ai_consent` 누락

### 0.3 타 센터 더미 데이터 (라운드 4 격리 검증용)

관리자가 **본인 센터만** 보는지 증명하려면 비교 대상이 있어야 한다. 검증 후 0.4로 반드시 삭제.

```sql
-- 타 센터 + 회원 1명 + 계약 1건
INSERT INTO centers (id, name) VALUES ('00000000-0000-0000-0000-0000000000ff', 'E2E-타센터');

INSERT INTO member_profiles (center_id, name, phone)
VALUES ('00000000-0000-0000-0000-0000000000ff', 'E2E타센터회원', '010-0000-0000');

INSERT INTO pt_contracts (member_id, total_sessions, price, started_at)
SELECT id, 10, 990000, now()
FROM member_profiles WHERE name = 'E2E타센터회원';
```

> `pt_contracts` 컬럼명은 실제 스키마(`0004`~)에 맞춰 조정할 것. 핵심은
> **"내 센터가 아닌 회원 1명 + 매출 990,000원"** 이 DB에 존재하게 만드는 것.

### 0.4 정리 SQL (검증 끝나고 반드시 실행)

```sql
DELETE FROM pt_contracts WHERE member_id IN
  (SELECT id FROM member_profiles WHERE name = 'E2E타센터회원');
DELETE FROM member_profiles WHERE name = 'E2E타센터회원';
DELETE FROM centers WHERE id = '00000000-0000-0000-0000-0000000000ff';
```

---

## 라운드 1 — 회원 온보딩 (§8: 초대코드 가입 / 동의 2종)

**모든 회원 검증의 전제**라 가장 먼저 한다.

### 1.1 초대 코드 발급 — 트레이너 기기

1. 트레이너 로그인 → 홈 → **회원 목록**(`/trainer/members`)
2. `+` 로 회원 추가 (이름만 필수)
3. 방금 만든 회원 상세 진입 → **초대 코드 칩** 확인 (8자리 대문자)

- **기대**: 앱 미연결 회원이라 코드 칩이 보인다 (`member_detail_screen.dart:201`)
- **의심 지점**: 칩이 안 보이면 → 이미 `user_id`가 붙은 회원이거나, `0019` 마이그레이션의 `invite_code` DEFAULT 미적용

```sql
-- 코드 직접 확인
SELECT id, name, invite_code, user_id FROM member_profiles ORDER BY created_at DESC LIMIT 5;
```

### 1.2 회원 가입 + 필수 동의 2종 — 회원 기기

1. 로그아웃 → `/login` → 회원가입 전환
2. **동의 2종 체크 없이** 가입 시도
   - **기대**: 가입 차단. `[필수] 이용약관 동의` / `[필수] 개인정보 처리방침 동의` 둘 다 체크해야 진행
3. `보기` 링크 → `/legal/terms`, `/legal/privacy` 열리는지
4. 잘못된 초대 코드(`WRONG`) 입력
   - **기대**: `초대 코드가 올바르지 않거나 이미 사용되었습니다.` — **계정 생성 자체가 막혀야** 함
     (`auth_providers.dart:169` — `verify_invite_code` 사전 검증)
5. 올바른 코드로 가입 완료

- **기대**: `/member/home` 진입, 상단에 회원 이름
- **의심 지점**: 초대코드 화면으로 튕기면 → 콜드스타트 레이스(`009c5e6`에서 수정됨, 재발 여부 확인)

```sql
-- 동의 기록 + 회원 연결 확인
SELECT * FROM user_consents WHERE user_id = '<신규 회원 user_id>';
SELECT id, name, user_id, invite_code FROM member_profiles WHERE invite_code = '<사용한 코드>';
-- user_id 가 채워져 있어야 연결 성공
```

---

## 라운드 2 — 회원 일상 기능

### 2.1 셀프 운동 기록 작성 (§8: `self_workout_logs`)

회원 홈 → **셀프 운동 기록**(`/member/self-log`) → 기록 추가 (종목·중량·횟수 + 컨디션 점수 1~10)

- **기대**: 저장 성공, 목록에 즉시 반영
- **의심 지점**: 저장은 되는데 컨디션 점수만 비면 → `_columns` SELECT 문자열에 `condition_score` 누락
  (CLAUDE.md에 기록된 기존 버그 유형 — 분석/런타임 에러 없이 조용히 null)

### 2.2 출석 달력 반영

회원 홈 → **출석 달력**(`/member/attendance`)

- **기대**: 방금 쓴 셀프 기록 날짜에 **주황 마커**. 홈에 `이번 달 N일 운동했어요` 배지
- **의심 지점**: 날짜가 하루 밀리면 → `.toLocal()` 호출(벽시계 컨벤션 위반, `member_attendance` 기존 버그)

### 2.3 예약 신청 (§8: `requested` → `scheduled`)

회원 홈 → **예약 신청**(`/member/booking`) → 날짜·시간 선택 후 신청

- **기대**: 목록에 "승인 대기" 상태로 표시. 철회 가능
- 여기서 멈추고 라운드 3.1로 (트레이너 승인)

---

## 라운드 3 — 트레이너

### 3.1 예약 승인/거절 (§8: 예약 end-to-end)

1. 트레이너 홈 → **승인 대기 N건** 배지 확인
2. **예약**(`/trainer/booking`) → 승인 대기 섹션 → 승인

- **기대**: 회원 앱 새로고침 시 "승인 대기" → **다음 수업**으로 이동, 상태 `scheduled`
- **거절도 1건 테스트** (2.3을 한 번 더 하고 거절)
- **의심 지점**: 승인이 반영 안 되면 → 회원 INSERT(`requested`) RLS는 되는데 트레이너 UPDATE 정책 누락(`0021/0022`)

### 3.2 셀프 기록 트레이너 열람 (§8: 가시성 대칭)

트레이너 → 회원 목록 → 해당 회원 상세 → **셀프 운동 기록 카드**

- **기대**: 2.1에서 회원이 쓴 기록이 **읽기 전용**으로 보인다 (수정·삭제 버튼 없음)
- **의심 지점**: 안 보이면 → `0028`의 트레이너 read 정책 누락. 수정이 되면 → **RLS 과다 허용, 즉시 중단 사유**

### 3.3 AI-C 메모 초안 (§8: AI-C end-to-end)

> 선행: 0.2의 `ai_consent = true` + 해당 회원의 **완료된 수업 기록 1건 이상**

회원 상세 → **트레이너 전용 메모** 카드 → `AI 초안 생성`

- **기대**: `AI 메모 초안이 생성되었습니다. 검수 후 확정하세요.` → 카드에 `AI 초안 — 검수 필요` 배지
- 확정(ai_confirmed) / 수정 / 삭제 각각 동작
- **회원 기기에서 이 메모가 절대 안 보여야 함** (`visibility=trainer_only` + `notes_member_deny`) ← **유출 시 즉시 중단**
- **의심 지점**
  - `consent_required` → 0.2 SQL 미실행
  - `Failed to fetch` → 함수 미배포
  - 본문에 추론 과정이 섞여 나옴 → `thinkingBudget=0` 파싱 문제

### 3.4 AI-B 메시지 초안 (§8: AI-B end-to-end)

회원 상세 → AI 메시지 카드 → 생성 → `/trainer/ai-review` 검수함

- **기대**: `검수 대기` 목록에 적재 → 내용 수정 → 승인 → `승인됨 — 탭하여 발송` → 발송
- 회원 기기 → **받은 안내**(`/member/notices`)에 도착
- **핵심 불변식**: 승인 전(`draft`) 상태가 회원에게 **절대 안 보여야** 함 (`isVisibleToMember` = `sent`만)

### 3.5 재등록 유도 AI 멘트 (§8: `generate-renewal-pitch`)

> 선행: 재등록 알림이 뜬 회원(잔여 5회 이하) + 진척 근거(종목별 중량 변화 **또는** 인바디 기록)가 있어야 함

트레이너 홈 → **재등록 알림** 카드 → 해당 행의 `AI 재등록 멘트` 아이콘

- **기대**: 진척 분석 → 멘트 생성 → 검수(수정 가능) → `[승인하고 발송]` / `[검수함 보관]` 2단계
- **의심 지점**
  - `no_progress_data` → **정상 동작**. 성장 근거가 없으면 지어내지 않고 차단하는 설계
  - `Failed to fetch` → 2026-07-20 배포분 반영 확인

---

## 라운드 4 — 관리자 (⚠️ 유출 시 베타 중단)

### 4.1 센터 격리 RLS (§8: 타 센터 유출 0)

관리자(겸직 시 트레이너 홈 → **관리자 대시보드**) → `/admin/dashboard`

먼저 SQL로 **정답**을 구한다:

```sql
-- 내 센터의 진짜 숫자
SELECT
  (SELECT count(*) FROM member_profiles WHERE center_id = '<내 center_id>') AS 활성회원,
  (SELECT count(*) FROM pt_contracts c JOIN member_profiles m ON m.id = c.member_id
    WHERE m.center_id = '<내 center_id>') AS 계약수;
```

- **기대**: 대시보드의 `활성 회원` / `진행 중 계약` / `누적 매출`이 위 숫자와 **일치**하고,
  0.3에서 심은 `E2E타센터회원`(+990,000원)이 **어디에도 안 잡힘**
- **판정**: 누적 매출에 990,000원이 섞여 있으면 → **격리 실패, 즉시 베타 중단**
- **의심 지점**: `current_admin_center_id()`가 NULL 반환(= `admin_profiles.center_id` 미설정)이면
  정책이 통째로 무력화될 수 있으니 아래를 반드시 확인

```sql
SELECT current_admin_center_id();  -- NULL 이면 안 됨
```

### 4.2 센터 규정 + PT FAQ (§8: 3.2-A)

1. `/admin/center` → 규정 수정 → **규정 저장**
2. PT FAQ 항목 **추가**
3. 회원 기기 → **자주 묻는 질문**(`/member/faq`)

- **기대**: 방금 추가한 FAQ가 회원 화면에 노출. 규정도 반영
- **의심 지점**: 회원에게 안 보이면 → `0031/0032`의 회원 read 정책 또는 `center_id` 기본값 누락

### 4.3 인앱 문의 (§8: 3.5)

1. 회원 기기 → **설정** → **문의하기** → 내용 작성 → 보내기
   - **기대**: `문의가 접수되었습니다. 확인 후 처리하겠습니다.`
2. 관리자 → `/admin/support` **문의함**
   - **기대**: 문의 도착 + **미처리 배지 증가** → `처리완료` 누르면 배지 감소

---

## 라운드 5 — cron (§8: 1.8 수업 전날 안내)

SQL Editor에서:

```sql
-- 1) 잡 등록 확인 — 행이 없으면 pg_cron 미활성
SELECT jobname, schedule, command FROM cron.job
WHERE jobname = 'enqueue-pre-session-notices';

-- 2) 수동 실행 (반환값 = 신규 적재 건수)
SELECT enqueue_pre_session_notices();

-- 3) 멱등 확인 — 반드시 0
SELECT enqueue_pre_session_notices();

-- 4) 적재 결과
SELECT target_member_id, trigger_type, status, scheduled_for, left(content, 40)
FROM outgoing_notifications WHERE trigger_type = 'pre_session'
ORDER BY created_at DESC;
```

- **선행**: **내일** 날짜의 `scheduled` 수업이 최소 1건 있어야 2)가 0이 아니다 (라운드 3.1 승인분 활용)
- **기대**: 1) 잡 1행 / 2) ≥1 / 3) **0** / 4) `draft` 상태로 적재
- **3)이 0이 아니면**: 멱등 깨짐 = 매일 중복 발송 → 수정 필요
- **1)이 비면**: 대시보드 > Database > Extensions에서 `pg_cron` 활성화 후 `0016` 재실행

---

## 라운드 6 — 탈퇴 (⚠️ 계정 파괴, 반드시 마지막)

### 6.1 익명화 탈퇴 (§8: 3.5)

> 탈퇴 전 그 회원의 `member_profiles.id`와 수업 기록 건수를 메모해 둘 것.

회원 기기 → **설정** → **회원 탈퇴** → 사유 선택 → **탈퇴하기**

- **기대**: `탈퇴가 완료되었습니다.` → 로그아웃
- 같은 계정으로 **재로그인 차단**
- 트레이너 화면 → 해당 회원이 `(탈퇴한 회원)`으로 표시, **이름·연락처 비노출**
- **수업 기록·계약은 보존** (매출 통계 유지)

```sql
SELECT name, phone, user_id, ai_consent FROM member_profiles WHERE id = '<메모한 id>';
-- name='(탈퇴한 회원)', phone=NULL, ai_consent=false 여야 함
SELECT count(*) FROM sessions WHERE ...;  -- 탈퇴 전 건수와 동일해야 함
```

- **의심 지점**: `Failed to fetch` → `delete-account` 미배포. PII가 남아 있으면 → **개인정보 이슈, 중단 사유**

### 6.2 동일 이메일 재가입 (§8: U5)

탈퇴한 이메일로 새 초대 코드를 받아 다시 가입

- **기대**: 정상 가입. 이전 기록과 **연결되지 않은 새 회원**으로 시작
- **의심 지점**: `이미 등록된 이메일` 오류 → `auth.users` 정리가 안 된 것

---

## 검증 중 발견한 선결 과제

### ✅ `ai_consent` 토글 UI 부재 — 해소 (2026-07-20, `9ac2c44`)

- **현상이었던 것**: `ai_consent`는 DB 기본값 `false`인데 이를 켜는 UI가 앱 어디에도 없어
  (Flutter 코드 전체에서 참조 0건) AI 3종이 실사용에서 전부 `consent_required`로 차단
- **U4 위반이기도 했음**: 폴백 안내는 `회원 상세 → 수정에서 AI 사용 동의를 받은 뒤`라고
  하는데(`generate_draft_dialog.dart:199`, `renewal_pitch_dialog.dart:337`) 그 화면에
  토글이 없었음 = dead-end. 이제 안내대로 따라가면 실제로 켤 수 있다
- **조치**: `Member.aiConsent` + 수정 다이얼로그 동의 카드 + update payload.
  `UpdateMemberInput.aiConsent`는 `required` — 값을 안 넘긴 호출부가 기존 동의를
  조용히 꺼뜨리는 걸 컴파일 단계에서 막는다

### ✅ 동의 상태의 가시성 — 해소 (2026-07-21, `fe04b92`)

- **현상이었던 것**: 회원 목록·상세에서 누가 AI 동의를 했는지 한눈에 안 보여, 수정
  다이얼로그를 열어야만 확인 가능했다("왜 이 회원만 AI가 안 되지"를 매번 확인).
- **조치**: 회원 상세 헤더에 동의/미동의 둘 다 명시하는 배지 +
  회원 목록엔 동의(옵트인)한 회원만 강조 칩(미동의가 기본이라 다 칠하면 노이즈 →
  "AI 켜진 회원이 누구냐"에 집중). `smart_toy_outlined` 라인 아이콘, primary 색.
