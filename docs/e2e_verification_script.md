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

### 0.0 ★ 기기 앱이 최신 빌드인지 먼저 확인 (2026-07-29 추가)

**이걸 안 하면 검증이 통째로 무의미해진다.** 2026-07-29 세션에서 기기 앱이
**2026-07-21 빌드**였고, 그 뒤 07-25 에 들어간 0036~0039 기능(체형 특이사항·동작 큐·
영상 마킹·체형분석 A)이 **화면에 하나도 없었다.** "카드가 안 보인다" 를 RLS 나 데이터
문제로 오진하기 딱 좋은 상황이라, 진단에 시간을 썼다.

```bash
# 1) 기기 앱 설치 시각
adb shell "dumpsys package com.gyman.gyman | grep lastUpdateTime"

# 2) 검증 대상 기능의 커밋 시각과 비교 (예: 체형 특이사항 카드)
git -C C:/dev/Gyman log -1 --format="%ad" --date=iso 02825c0

# 3) 앱이 더 오래됐으면 재빌드·재설치 (데이터 유지)
cd src/app && flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

- **기대**: 1) 이 2) 보다 나중. 아니면 재설치.
- `install -r` 은 **로그인 세션과 앱 데이터를 유지**한다(2026-07-29 확인). 실패하면
  서명 불일치이므로 삭제 후 재설치해야 하고, 그때는 다시 로그인해야 한다.
- **`-Ppoc=true` 를 붙이지 말 것** — 그건 PoC 앱(`com.gyman.poc`)이다(CLAUDE.md).

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

### 4.0 사전 점검 — center_id 체인 (라운드 4 전체의 전제)

라운드 4는 세 화면 모두 **`trainer_profiles.center_id` 가 채워져 있어야** 동작한다(0032 "전제").
이 값이 NULL 이면 연쇄로: 회원 등록 시 `center_id` 가 NULL → FAQ 안 보임(4.2) + 대시보드
텅 빔(4.1) + `current_admin_center_id()` NULL.

> **중요**: 텅 빈 대시보드는 **유출이 아니다**. admin RLS 는 `center_id = current_admin_center_id()`
> 인데 우변이 NULL 이면 조건이 거짓이 되어 **한 행도 안 보인다(fail-closed)**. 즉 "텅 빔"은 이
> 사전점검을 안 한 것이지 격리 실패가 아니므로, 4.1 을 "격리 실패, 베타 중단"으로 **오판하지 말 것**.
> (0031 이 겸직자를 위해 `current_user_role()='admin'` 게이트를 빼고 center_id 매칭만 남겼기에,
> NULL 은 유출이 아니라 차단으로 작동한다.)

아래를 순서대로 확인·보정한 뒤 4.1 로 내려간다.

```sql
-- 1) 센터 존재 + 내 center_id 확보 (이후 <내 center_id> 에 사용)
SELECT id, name FROM centers;

-- 2) 트레이너 center_id (NULL 이면 먼저 세팅 — 회원/대시보드/FAQ 체인의 뿌리)
SELECT user_id, name, center_id FROM trainer_profiles WHERE user_id = auth.uid();
--   NULL 이면 세팅 후 0032 백필 재실행:
--   UPDATE trainer_profiles SET center_id = '<내 center_id>' WHERE user_id = auth.uid();
--   UPDATE member_profiles m SET center_id = t.center_id FROM trainer_profiles t
--   WHERE m.center_id IS NULL AND m.created_by_trainer_id = t.user_id AND t.center_id IS NOT NULL;

-- 3) 관리자 center_id = 트레이너 center_id 여야 함(0.1 겸직 INSERT 가 t.center_id 를 복사)
SELECT current_admin_center_id();  -- NULL 이면 안 됨. 2)와 같은 값이어야 함

-- 4) 회원 center_id 가 다 채워졌는지 (0행이어야 정상)
SELECT id, name FROM member_profiles WHERE center_id IS NULL AND deleted_at IS NULL;
```

- **기대**: 2)·3) 이 같은 non-NULL 값, 4) 0행 → 여기까지 맞춰야 4.1~4.3 이 의미 있는 숫자를 보인다

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

## 진행 상태 (2026-07-29 세션 2 — 중단 지점)

**환경**: Galaxy Z Flip 3 · 앱 재빌드·재설치(2026-07-29 13:2x, 아래 크래시 수정 포함) ·
트레이너 겸 관리자 로그인 중. 조작은 `adb shell input tap/swipe` + `screencap` 으로 자동화.

> ⚠ 세션 시작 시 **앱이 로그아웃 상태**였다. 자격증명이 없어 Claude 는 로그인할 수 없으므로
> 사용자가 직접 로그인해야 한다 — 실기기 세션을 여는 첫 단계로 미리 확인할 것.

### 세션 1(오전)에서 통과한 것
| 항목 | 결과 |
|---|---|
| 0.0 앱 최신화 | ✅ 구버전(07-21) 발견 → 재설치. 로그인·데이터 유지됨 |
| 0.1 계정 | ✅ 트레이너 겸 관리자(대시보드 타일 확인), 회원 "테스트" 앱 가입 완료 |
| 0.2 `ai_consent` | ✅ 이미 `true`(회원 목록 AI 칩 + 상세 배지) |
| 3.2 셀프 기록 트레이너 열람 | ✅ 4건이 **읽기 전용**. RLS 과다 허용 아님 |
| L1-a 등록 / 해제 / 재적용 | ✅ |

### 세션 2(오후)에서 통과한 것
| 항목 | 결과 |
|---|---|
| L1-a **중복 가드** | ✅ 활성 중인 같은 항목 재등록 → `이미 등록된 항목입니다…` (raw PG 에러 미노출, 다이얼로그 유지) |
| L1-a **삭제** | ✅ 라운드트립 완료. 확인 다이얼로그가 항목명을 인용하고 `[해제]` 대안을 안내, **취소 시 보존**·삭제 시 `삭제했습니다.` |
| L1-a **의료기관 진단 경로** | ✅ 출처 전환 시 §5 안전선 문구가 바뀌고, 목록 배지도 테두리로 구분됨 |
| 3.3 **AI-C 메모 초안** | ✅ 생성(`AI 초안 — 검수 필요` 배지) → **수정** → **확정**(`AI 확정 · 날짜`). 추론 과정 혼입 없음(`thinkingBudget=0` 정상) |
| 3.4 **AI-B 메시지 초안** (트레이너 측) | ✅ 생성 → 검수함 적재 → 본문 수정 → 재검수 → `승인하고 발송` → `회원에게 발송되었습니다.` (검수 대기 2→1) |
| 4.0 center_id 체인 | ✅ 대시보드가 **텅 비지 않고 실제 값** 표시 = 트레이너·관리자·회원 `center_id` 전부 채워짐(NULL 이면 fail-closed 로 0) |
| 4.2 센터 규정 + FAQ (관리자 측) | ✅ FAQ 추가 반영, `센터 규정을 저장했습니다.` |

**설계 확인 (버그 아님)**
- 검수함에서 **본문을 고치면 즉시 발송되지 않고** `내용을 저장했습니다. 다시 검수 후 발송해 주세요.`
  로 되돌아간다 — 수정본을 한 번 더 보게 하는 의도된 안전장치.
- 목록 카드의 `수동 작성` 은 **작성자가 아니라 `trigger_type='manual'`**(= 크론이 아닌 수동 트리거).
  작성 주체는 별도 `AI` 칩. 검수 다이얼로그에선 `트리거 / 생성` 으로 나뉘어 모호함이 없다.

### 세션 2에서 발견·수정한 크래시 (수정 완료)
**메모 수정 저장 시 붉은 화면** — `'_dependents.isEmpty': is not true` (framework.dart:6268).
- 원인: `showNoteEditDialog` 가 `showDialog` 를 `try/finally` 로 감싸 `await` 직후
  `TextEditingController.dispose()` 를 호출했다. `showDialog` 의 Future 는 `Navigator.pop`
  시점에 완료되지만 **퇴장 애니메이션 동안 `TextField` 는 아직 트리에 살아 있어**,
  라우트가 걷힐 때 `InheritedElement.debugDeactivated()` assertion 이 터졌다.
- 영향 범위: `member_notes_card.dart` 의 메모 **수정·직접 추가** 경로 전부(AI-C 검수의 핵심 동선).
  DB 쓰기 자체는 성공했으므로 **UI 전용 크래시**였다.
- 조치: 컨트롤러를 `_NoteEditDialog`(StatefulWidget)가 소유하고 `State.dispose()` 에서 정리.
  이 저장소의 다른 다이얼로그 30여 개는 원래 이 패턴이라 영향 없음(함수 지역 컨트롤러는 이 한 곳뿐).
- 재검증: 재빌드·재설치 후 수정 저장이 크래시 없이 반영됨.

### 남은 품질 이슈 (기능은 동작, 수정 대상)
- **AI-C 초안 본문에 영문 enum 노출** — "컨디션은 `normal` 상태로 확인됨."
  회원 컨디션 값을 한국어로 옮기지 않고 그대로 프롬프트/출력에 태우고 있다. 트레이너 전용
  메모라 유출 문제는 아니지만 실사용 문구로는 부적절.

### 세션 3(회원 시점 + 트레이너 마무리)에서 통과한 것 — 2026-07-29
회원 계정 로그인은 사용자가 직접 수행. 앱 에러 0.

**가시성 대조군 5종 — 전부 기대대로 (§8 가시성 분리의 실증)**

| 데이터 | 기대 | 결과 |
|---|---|---|
| 발송 안내 `[E2E-APPROVED]` | 보여야 | ✅ 안읽음으로 도착(발송 시각 일치) |
| 검수함 `draft`(발송 예정 07-21 03:50) | **안 보여야** | ✅ 목록에 없음. 홈 배지도 `1`(발송분만) |
| 트레이너 전용 메모(AI 확정) | **안 보여야** | ✅ 수업 상세 어디에도 없음 |
| 특이사항 `E2E-TRAINER-ONLY` | **안 보여야** | ✅ 큐 카드에 없음(`MyConditionRepository` 가 `trainer_note` 를 SELECT 에서 제외) |
| FAQ `E2E-FAQ-Q` | 보여야 | ✅ "PT 규정" 섹션에 답변까지 노출 |

**기능 항목**

| 항목 | 결과 |
|---|---|
| 2.1 셀프 운동 기록 | ✅ 저장·즉시 반영. **컨디션 7/10 정상**(조용히 null 되는 `_columns` 버그 없음) |
| 2.2 출석 달력 | ✅ 오늘(29일)에 주황 마커 정확 — 날짜 밀림 없음(`.toLocal()` 위반 없음) |
| 2.3 예약 신청 | ✅ `승인대기` 로 적재, 철회 가능. "신청만으로는 잔여 차감 안 됨" 고지 있음 |
| L1-b 동작 큐 | ✅ `deadlift` → `척추측만`·`주의` 칩 + hinge 큐. `squat` → **큐 없음**(척추측만 시드에 squat 규칙 없음 = "틀린 큐를 띄우느니 안 띄운다" 설계대로) |
| 3.1 예약 승인/거절 | ✅ 회원 신청이 트레이너 홈 배지에 즉시 반영(처리 대기 3 / 예약 승인 2) → 1건 승인(내일 15:00 `예약` 확정) + 1건 거절(비가역 경고 다이얼로그 후 삭제) |
| 4.3 인앱 문의 | ✅ 회원 전송 → 관리자 문의함에 `미처리` 로 도착(역할·시각·앱버전 메타 포함) → `처리완료` 전환 |
| 라운드 5 선행 조건 | ✅ **내일(7/30 15:00) `scheduled` 수업 1건 확보** — cron 수동 실행 준비 완료 |

### 세션 3에서 발견한 것

**1. "회원에게 보일 설명"(`member_note`)이 회원 앱 어디에도 표시되지 않는다.**
- 약속은 여러 곳에 있다: 입력 라벨 `회원에게 보일 설명 (선택)`, 트레이너 카드 툴팁
  `회원도 볼 수 있습니다 (트레이너 전용 메모 제외)`, 도메인 주석 `memberNote는 회원에게 보이지만`.
- 회원용 `MyConditionRepository._columns` 는 `member_note` 를 **SELECT 까지 한다.**
  그런데 회원이 보는 유일한 화면인 `CoachingCueView` 는 `cue`·`conditionLabel`·`action`
  만 그리고 `memberNote` 는 렌더링하지 않는다(`memberNote` 참조는 트레이너 카드 한 곳뿐).
- 즉 **데이터는 받아오는데 안 그린다.** 이미 해소된 `ai_consent` dead-end 와 같은 유형(U4).
  보안 문제는 아니다 — 과소 노출이라 안전한 쪽. 다만 트레이너가 전달된다고 믿고 쓴 내용이
  전달되지 않는다. 고치려면 **어디에 붙일지**(큐 카드 하단 / 별도 "내 체형 기록" 화면)를
  먼저 정해야 하므로 설계 판단이 필요하다.

**2. 같은 시각 예약 중복 신청이 허용된다.**
- 7/30 15:00 으로 두 번 신청했더니 둘 다 그대로 적재됐다. 특이사항엔 부분 유니크 인덱스가
  있는데 예약엔 없다. 트레이너 승인 구조라 자동 확정되진 않지만, 둘 다 승인하면 같은 시간에
  수업 2건이 된다.

**3. `받은 안내` 목록을 열어도 홈의 안읽음 배지가 줄지 않는다.**
- 목록 진입만으로는 읽음 처리가 안 되고 개별 항목을 열어야 하는 것으로 보인다. 사소하지만
  "확인했는데 배지가 남아 있다"는 인상을 준다. 의도된 동작인지 확인 필요.

### 남겨둔 데이터 (일부러 지우지 않음 — 회원 시점 검증의 대조군)
| 데이터 | 기대 |
|---|---|
| 특이사항 1건: 설명 `E2E-MEMBER-VISIBLE` / 트레이너 메모 `E2E-TRAINER-ONLY` | 앞은 **보이고** 뒤는 **안 보여야** 함 |
| 트레이너 전용 메모(AI 확정, `…E2E-EDITED-AGAIN`) | 회원에게 **절대 안 보여야** 함 |
| 검수함에 남은 `draft` 1건(07-21) | 승인 전이므로 회원 `받은 안내`에 **안 보여야** 함 |
| 방금 발송한 안내(`…[E2E-APPROVED]…`) | 회원 `받은 안내`에 **보여야** 함 |
| FAQ `E2E-FAQ-Q` / `E2E-FAQ-A-MEMBER-SHOULD-SEE-THIS` | 회원 `자주 묻는 질문`에 **보여야** 함 |

**다음 세션에서 이어갈 것** (2026-07-29 세션 3 종료 시점 기준)

앱 UI 로 할 수 있는 검증은 아래 3개를 빼고 **전부 소진**했다. 남은 것은 전부
"조건을 만들어야" 하거나 "SQL 이 필요"하다.

1. **라운드 5 cron** — 선행 조건(내일 `scheduled` 1건)은 **이미 갖춰졌다.**
   `SELECT enqueue_pre_session_notices();` 를 두 번 돌려 1회차 ≥1 / 2회차 **0**(멱등) 확인.
   → SQL 접근만 있으면 바로 가능
2. **3.5 재등록 유도 AI 멘트** — 조건 미충족(잔여 19회 > 알림 기준 5회, 인바디 0건).
   **SQL 없이도 앱에서 뚫을 수 있다**: ① `계약 추가` 로 총 5회짜리 계약 생성 → 재등록 알림
   발생, ② `인바디 측정 → 측정 입력` 2건 → 진척 근거 확보. 검증용 데이터가 실계약에
   섞이는 걸 감수할지 결정 필요
3. **4.1 센터 격리** — **부분 통과 상태.** 대시보드 숫자는 내 센터 실제 값과 정확히 일치하고
   초과분이 없다(소극적 증거). 다만 0.3 의 타 센터 더미를 심지 못해 **대조군이 없다** —
   앱에 센터 생성 UI 가 없어 우회로도 없다. "유출 0" 을 적극 증명하려면 SQL 필요.
   ⚠ 이 항목은 문서상 "유출 시 베타 중단" 이므로 베타 전 반드시 닫을 것
4. **라운드 6 탈퇴** — 계정을 파괴하므로 **맨 마지막에, 사용자 판단으로**. 위 항목들이
   이 계정을 계속 쓰므로 먼저 끝낼 것
5. SQL 검증 — `develop_plan.md:430-433`(0036~0039 검증 SQL).
   **Supabase 자격증명이 없어 Claude 가 실행할 수 없다**(`.env` 열람 금지)

> 라운드 1(초대코드 가입·동의 2종)은 회원 계정이 이미 가입 완료 상태라 **재현 불가**.
> 검증하려면 신규 회원을 하나 더 만들어야 한다(6.2 재가입과 함께 묶는 편이 효율적).

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
