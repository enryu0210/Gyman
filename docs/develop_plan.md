# Gyman — 개발 계획서 (Development Plan)

> 본 문서는 `assets/헬스장_앱_개발계획.md` 기획서를 기반으로,
> **실제 개발자가 코드를 작성할 때 참고할 실행 계획**을 정리한 문서입니다.
> 기획서가 "무엇을/왜"를 정의했다면, 본 문서는 "어떻게/언제/어떤 순서로"를 정의합니다.
>
> 작성일: 2026-05-24
> 대상 브랜치: `develop`

---

## 0. 의사결정 요약 (Executive Summary)

| 항목 | 결정 | 근거 |
|------|------|------|
| **프레임워크** | Flutter (Dart) | 카메라 그리드/수평 가이드 UI(체형 분석) 커스텀 그리기 강점, Android/iOS 단일 코드베이스 |
| **백엔드** | Supabase (1순위) / Firebase (대안) | Postgres 기반 RLS(행 단위 권한)이 "트레이너 전용 메모 비노출" 요구에 직결, SQL로 매출 대시보드(Phase 3) 구현 용이 |
| **상태관리** | Riverpod | Provider 진화형, 테스트 용이, 단위 테스트 필수 영역(잔여 횟수/재등록 계산)과 궁합 좋음 |
| **푸시 알림** | FCM + (검토)카카오 알림톡 | "수업 전날 안내" "재등록 시점" 자동 발송에 필수 |
| **앱 분리 전략** | 단일 코드베이스 + 역할 기반 라우팅 | 트레이너/회원/관리자 3종, 초기엔 한 앱 안에서 로그인 후 분기. Phase 3에 회원앱 분리 검토 |
| **첫 개발 타겟** | 트레이너 앱 — 수업 기록 화면 | 친구가 혼자 써볼 수 있어야 정착 검증 가능 |
| **데모 단계 AI 기능 포함** | ✅ B(회원 안내 메시지 초안) + C(트레이너 메모 자동 초안) | 친구 베타 사용 경험 향상 + 정착 강화. **둘 다 "트레이너 검수 후 노출/발송" 원칙 유지** |
| **AI 모델** | **Google Gemini API** (`gemini-3.5-flash`, env `LLM_MODEL` 로 교체 가능) | 호스팅+키 방식이라 Edge Function 구조에 적합. 무료 티어로 개발(저토큰 작업), 단 무료 티어는 데이터가 학습에 쓰일 수 있어 **PII 마스킹 필수**·실데이터 베타 전 Tier 1 검토. 자체 모델 학습 비용/시간 회피, 데모 규모 월 $5 미만 |
| **회원 오프라인 등록** | `member_profiles.user_id` nullable + `id` PK 분리 (마이그레이션 0013) | 베타에서 회원이 앱 안 깔아도 트레이너가 정보·계약 관리 가능 — 본 제품의 진입 장벽을 결정짓는 차별점. 회원 가입 시점에 `UPDATE ... SET user_id = ?` 로 매핑 |

> **리스크 알림:** Flutter가 익숙하지 않다면 데모 속도가 최우선이므로 본인 익숙한 스택으로 변경할 것.
> 본 계획서는 Flutter + Supabase 기준으로 작성하되, 스택 변경 시 §4 데이터모델, §5 마일스톤은 그대로 유효합니다.

---

## 1. 프로젝트 폴더 구조 (제안)

```
Gyman/
├─ assets/                        # 기획서 등 원본 자료
├─ docs/                          # 개발 문서 (본 문서 포함)
│  ├─ develop_plan.md
│  ├─ data_model.md              # (Phase 0 산출물)
│  ├─ wireframes/                # (Phase 0 산출물, 이미지)
│  └─ api_spec.md                # (Phase 1 산출물)
└─ src/
   ├─ app/                        # Flutter 앱
   │  ├─ lib/
   │  │  ├─ core/                 # 공통 (테마, 라우터, 에러, 유틸)
   │  │  ├─ data/                 # Supabase 호출, repository, model
   │  │  ├─ domain/               # 비즈니스 로직 (재등록 계산, 잔여 횟수)
   │  │  ├─ features/             # 화면 단위
   │  │  │  ├─ auth/              # 로그인/역할 분기
   │  │  │  ├─ trainer/           # 트레이너 화면
   │  │  │  │  ├─ session_log/    # M2 수업 기록
   │  │  │  │  ├─ member_card/    # M4 회원 카드
   │  │  │  │  ├─ booking/        # M3 예약/노쇼
   │  │  │  │  └─ renewal/        # M1 재등록 알림
   │  │  │  ├─ member/            # 회원 화면 (Phase 2~3)
   │  │  │  └─ admin/             # 관리자 대시보드 (Phase 3)
   │  │  └─ main.dart
   │  ├─ test/                    # 단위/위젯 테스트
   │  └─ pubspec.yaml
   └─ supabase/                   # 마이그레이션, RLS 정책, edge function
      ├─ migrations/
      └─ functions/
```

**원칙 (사용자 코딩 표준 반영)**
- 한 파일이 길어지면 기능별로 분리 — `features/` 디렉토리 단위로 격리
- 도메인 로직(`domain/`)은 UI/네트워크와 분리 → 단위 테스트 용이
- 변수명/함수명은 의도가 드러나게 (예: `calculateRemainingSessions`)

---

## 2. 데이터 모델 (ERD 초안)

> **핵심 설계 원칙:** 필드 단위 가시성 — 트레이너 전용 메모는 회원이 절대 못 보게 한다. (기획서 답변 9)

### 2.1 주요 엔티티

| 엔티티 | 설명 | 핵심 필드 |
|--------|------|----------|
| `users` | 통합 사용자 (Supabase Auth 연동) | id, email, role(trainer/member/admin), created_at |
| `trainer_profiles` | 트레이너 추가 정보 | user_id, name, center_id |
| `member_profiles` | 회원 추가 정보 | user_id, name, phone, goal, experience, injury_history, body_features, lifestyle, available_times |
| `centers` | 헬스장(센터) | id, name, address, rules (PT 규정 JSON) |
| `pt_contracts` | PT 계약 (잔여 횟수의 원천) | id, member_id, trainer_id, total_sessions, used_sessions, start_date, end_date, price |
| `sessions` | 수업 1건 | id, contract_id, scheduled_at, status(done/no-show/canceled/late), recorded_at |
| `session_records` | 수업 기록 (M2) | session_id, exercises(JSON), condition, pain, next_memo |
| `member_notes` | **트레이너 전용** 회원 메모 (M4 분리) | member_id, trainer_id, content, visibility='trainer_only' |
| `messages` | 채팅 (S2) | id, sender_id, receiver_id, content, sent_at, read_at |
| `body_assessments` | 체형 분석 (C3) | member_id, photos(JSON), ai_result, trainer_comment, created_at |

### 2.2 권한(RLS) 설계 — Supabase 행 단위 보안

| 테이블 | trainer 권한 | member 권한 | admin 권한 |
|--------|-------------|------------|-----------|
| `member_profiles` | 자신이 담당한 회원만 read/write | 본인만 read/write | 센터 전체 read |
| `member_notes` | 자신이 작성한 것만 read/write | **read 불가** | 센터장만 read |
| `pt_contracts` | 담당 계약만 read/write | 본인 계약만 read | 센터 전체 read |
| `session_records` | 담당 계약의 기록만 read/write | 본인 기록 read | 센터 전체 read |
| `body_assessments` | 담당 회원만 read, trainer_comment write | 본인 것만 read (trainer_comment가 있는 것만) | - |

> **`body_assessments` 노출 조건 핵심:** AI 결과는 트레이너가 코멘트를 단 다음에만 회원에게 보인다.
> (기획서 답변 14 — AI가 단정적으로 "라운드숄더입니다"라고 직접 말하지 않게)

### 2.3 핵심 계산 로직 (반드시 단위 테스트)

```dart
// domain/renewal_calculator.dart
// 재등록 타이밍 계산 — 매출과 분쟁 직결. 버그 시 치명적.
class RenewalCalculator {
  // 남은 횟수 + 평균 주당 수업 빈도로 예상 만료일 계산
  DateTime estimateExpiryDate(PtContract contract, List<Session> recentSessions);

  // 알림 트리거: "세션 반 소진" / "5회 남음" / "곧 만료"
  RenewalAlertLevel getAlertLevel(PtContract contract);
}
```

---

## 3. 화면 구조 (라우트 맵)

### 3.1 트레이너 앱 (Phase 1 우선 개발)

```
/login                       → 로그인 (역할 자동 분기)
/trainer/home               → 오늘 수업 + 재등록 알림 (M1)
/trainer/members            → 회원 리스트
/trainer/members/:id        → 회원 카드 (M4)
/trainer/members/:id/notes  → 트레이너 전용 메모
/trainer/session/new        → 수업 기록 (M2) — 1분 입력 목표
/trainer/session/:id        → 수업 기록 상세/수정
/trainer/booking            → 예약 캘린더 (M3)
/trainer/booking/:id        → 예약 상세 (노쇼/취소 처리)
/trainer/chat               → 회원 채팅 리스트 (S2, Phase 2)
```

### 3.2 회원 앱 (Phase 2~3)

```
/member/home                → 다음 수업 + 잔여 횟수
/member/records             → 내 운동 기록 + 변화 추이 (S1)
/member/booking             → 예약 신청
/member/chat                → 트레이너와 채팅
/member/body                → 체형 분석 결과 (C3, 트레이너 코멘트 있는 것만)
```

### 3.3 관리자 앱 (Phase 3)

```
/admin/dashboard            → 재등록률/전환률/매출/노쇼율 (C1)
/admin/trainers             → 트레이너 성과 + 온보딩 (C2)
/admin/members/expiring     → 만료 임박/이탈 위험 회원 (C1)
```

---

## 4. Phase별 마일스톤 (실행 단위)

> 기획서 §3의 Phase를 실제 개발 task 단위로 분해했습니다.

### Phase 0 — 환경 셋업 + 설계 (1~2주)

| # | 작업 | 산출물 |
|---|------|--------|
| 0.1 | Flutter 개발 환경 셋업 (Android Studio + Xcode) | `flutter doctor` 통과 |
| 0.2 | Supabase 프로젝트 생성, 양 플랫폼 빈 앱 빌드 확인 | "Hello Supabase" 화면 |
| 0.3 | 데이터 모델 SQL 마이그레이션 작성 + RLS 정책 적용 | `supabase/migrations/0001_init.sql` |
| 0.4 | 트레이너 앱 와이어프레임 (9개 화면 1차 초안) | `docs/wireframes/` ✅ v0.1 작성 완료. **각 화면 구현 시점에 와이어를 한 화면씩 갱신하지 않고, Phase 1.4~1.7 마친 뒤 실제 화면을 기준으로 일괄 재정비** — 구현 중에 UX가 계속 바뀌어 부분 갱신이 의미 없음. |
| 0.5 | 친구 1차 와이어프레임 리뷰 (README §5 질문 답변) | 피드백 메모 |
| 0.6 | 라우터/테마/상태관리 골격 코드 | `lib/core/` 완성 |

### Phase 1 — MVP 트레이너 앱 + 기본 AI 기능 (5~7.5주)

| # | 작업 | 우선순위 | 핵심 검증 |
|---|------|---------|----------|
| 1.1 | 로그인 + 역할 분기 (Supabase Auth) | High | 트레이너만 로그인 가능 |
| 1.2 | 회원 카드 CRUD (M4) | High | 트레이너 전용 메모 회원에게 안 보임 (RLS 테스트) |
| 1.3 | PT 계약 등록 + 잔여 횟수 자동 계산 (M1) | **Critical** | 단위 테스트 100% — 매출 직결 |
| 1.4 | 수업 기록 화면 (M2) — 1분 입력 UX | **Critical** | 입력 시간 1분 이내 (베타 측정 지표) |
| 1.5 | 이전 기록 복사, 자주 쓰는 종목 즐겨찾기 | High | 입력 속도 개선 |
| 1.6 | 예약 캘린더 + 노쇼/취소 기록 (M3) | High | 차감 규정 자동 표시 |
| 1.7 | 재등록 알림 자동화 ("5회 남음" 등) (M1) | High | FCM 푸시 정상 도달 |
| 1.8 | 수업 전날 회원 안내 메시지 자동 발송 (M1) | High | ✅ 백엔드 적재 구현(0016). **결정 변경:** Edge Function 대신 plpgsql 함수 + pg_cron (배포 파이프라인 부재 + SQL-Editor 워크플로 일치). FCM/회원앱 부재로 범위는 "발송"이 아닌 **draft 자동 적재**까지 — 검수/발송 UI는 1.9 AI 검수 허브에서 통합. 기본 템플릿(비-AI). |
| **1.9** | **AI-B. 회원 안내 메시지 초안 LLM 생성** | High | ⏳ **검수 게이트 부분 완료** — AI 검수 허브(`/trainer/ai-review`) + 메시지 승인/수정/취소/일괄승인 + 홈 검수 배지 구현. draft 큐(0016 cron 또는 LLM)를 동일하게 검수. **LLM 생성 자체는 Edge Function 배포 파이프라인 선행 필요로 보류**(키 클라이언트 노출 금지). 실발송(sent 전이)은 FCM/회원앱 준비 후. 도메인 `NotificationStatus.isVisibleToMember`(sent만) 단위테스트로 안전장치 검증. |
| **1.10** | **AI-C. 트레이너 메모 자동 초안 (수업 기록 기반)** | High | 수업 기록 저장 시 `member_notes`에 ai_draft로 자동 저장. RLS로 회원 차단 |
| **1.11** | **LLM API 연동 + 비용/장애 가드** | High | ⏳ **서버 코어 구현** — 배포 파이프라인(`supabase init`/health) + `generate-message-draft` Edge Function(Gemini 호출 + 동의 확인 + **PII 마스킹**[실명→{{NAME}}] + 일일 호출 한도[`ai_call_logs` 0017] + 장애 시 구조화 에러로 수동 폴백 유도). 키는 `supabase secrets`(서버)에만. **남은 작업:** 사용자 `deploy` + `LLM_API_KEY` 설정 후 동작 검증, 그다음 Flutter "초안 생성" 버튼 연동. |
| 1.12 | Firebase App Distribution / TestFlight 베타 배포 | High | 친구 디바이스에서 설치 성공 |

> **Phase 1 완료 정의(DoD):**
> 1) 친구가 본인 회원 3~5명 데이터를 넣고 **1주일간 매일 사용**할 수 있다.
> 2) **AI 안내 메시지/메모 초안이 발송·확정 전에 트레이너 검수 화면을 반드시 거친다는 RLS·UX 흐름이 통합 테스트로 검증되어 있다.**
> 3) LLM API 장애 시에도 앱이 멈추지 않고 수동 입력으로 정상 동작한다.

### Phase 2 — 친구 실사용 + 정착 강화 (3~4주)

| # | 작업 | 메모 |
|---|------|------|
| 2.1 | 매주 피드백 수집 → 입력 마찰 지점 우선 개선 | "어디서 막혔는지" 기록 요청 |
| 2.2 | 변화 추이 그래프 (S1) — 중량/인바디 추이 | 재등록 세일즈 직결 |
| 2.3 | 회원 채팅 (S2) + 알림 시간대 설정 | 사생활 경계 보호 |
| 2.4 | FAQ 자동 응답 (S3) — 운동 상식 / PT 규정 분리 | |
| 2.5 | 회원 셀프 운동 기록 간단 입력 (S4) | 초간단 — "어디 아팠고 어떻게 나아졌다" |
| 2.6 | 회원용 화면 최소 분리 (홈/기록 열람) | 단일 앱 내 역할 분기 유지 |

### Phase 3 — 관리자 + B2B 파일럿 (4~6주)

| # | 작업 |
|---|------|
| 3.1 | 관리자 대시보드 (C1) — SQL view 활용 |
| 3.2 | 트레이너 온보딩 + 회원 인수인계 (C2) |
| 3.3 | 회원 앱 정식 분리 (별도 빌드 또는 별도 진입점) |
| 3.4 | 친구네 센터 파일럿 — 트레이너 3~5명 |
| 3.5 | 개인정보처리방침 / 이용약관 / 동의 플로우 정식화 |

### Phase 4 — 고급 AI 기능 (6~8주, 일부 병렬)

> 참고: 기본 LLM 기반 AI 기능(메시지 초안, 메모 초안)은 **Phase 1 데모로 당겨졌습니다.**
> Phase 4는 카메라/이미지 기반의 무거운 AI 기능에 집중합니다.

| # | 작업 | 비고 |
|---|------|------|
| 4.1 | 카메라 촬영 가이드 UI (그리드/수평/발 위치/거리) | Flutter 강점 영역 |
| 4.2 | 체형 분석 (C3) — MediaPipe Pose 키포인트 추출 | 첫 등록 + 4·8·12주 비교 |
| 4.3 | **트레이너 검수 플로우** — AI 결과 → 트레이너 코멘트 → 회원 노출 | **반드시** 순서 강제 (Phase 1의 B/C와 동일 원칙 재사용) |
| 4.4 | 식단 분석 (C4) — 멀티모달 LLM API | 칼로리/단백질 대략 피드백 |
| 4.5 | 자세 영상 분석 (별도 R&D 트랙) | 정확도 검증 후 결정 |

---

## 5. 테스트 전략 (실행 가능 수준)

### 5.1 단위 테스트 — 필수 (매출/분쟁 직결 로직)

```
test/domain/
├─ renewal_calculator_test.dart       # 재등록 시점 계산
├─ remaining_sessions_test.dart       # 잔여 횟수 계산 (노쇼/취소 케이스 전부)
├─ deduction_rule_test.dart           # 차감 규정 (당일취소/지각)
└─ visibility_test.dart               # 메모 가시성 (트레이너 전용 노출 안 됨)
```

> 위 4개 파일은 **Phase 1 시작 전에 테스트부터 작성(TDD)** 권장. 버그 시 손해 큼.

### 5.2 위젯/통합 테스트

- 수업 기록 입력 플로우 회귀 테스트 (1분 이내 입력 가능한지)
- RLS 통합 테스트 — Supabase 로컬 인스턴스에 테스트 데이터 넣고 "회원 계정으로 트레이너 메모 조회 시 0건" 검증

### 5.3 디바이스 매트릭스

| 플랫폼 | 디바이스 | 검증 포인트 |
|--------|---------|----------|
| Android | 보급형 (예: Galaxy A 시리즈) | 카메라/그리드 끊김 |
| Android | 중급기 (예: Galaxy S 시리즈) | 전반적 성능 |
| iOS | 구형 (iPhone 11 이전) | 메모리/렌더링 |
| iOS | 최신 (iPhone 15 이상) | 카메라 |

### 5.4 베타 측정 지표 (친구 사용 시 자동 수집)

```dart
// 예: 수업 기록 화면 진입~저장까지 시간 측정
Analytics.track('session_record_duration', durationMs);
Analytics.track('app_open_initiator', 'self' | 'notification');
```

| 지표 | 목표 | 의미 |
|------|------|------|
| 수업 1건 기록 소요 시간 | 1분 이내 | 정착의 핵심 |
| 자발적 앱 열기 비율 | 50% 이상 | "회원관리 앱"으로 인식됨 |
| 회원의 셀프 기록/채팅 사용률 | 30% 이상 | 양방향 정착 |

---

## 6. 보안 & 컴플라이언스 체크리스트

| 항목 | 시점 | 비고 |
|------|------|------|
| Supabase RLS 정책 전체 테이블 적용 확인 | Phase 0 종료 시 | 정책 누락 = 정보 유출 |
| 신체 사진 암호화 저장 (Supabase Storage + bucket 정책) | C3 착수 전 | 민감정보 |
| 개인정보 수집·이용 동의 화면 | Phase 1 종료 전 | 베타도 동의 필요 |
| **AI(외부 LLM) 데이터 전송 동의 별도 항목** | **Phase 1 베타 배포 전 (필수)** | 회원 이름·컨디션·메모 일부가 외부 API로 전송됨. 동의 못 받으면 해당 회원은 AI 기능 비활성화 |
| **LLM 호출 시 개인 식별 정보(PII) 마스킹** | **Phase 1 1.11 작업과 함께** | 회원 실명 → "회원A" 등 토큰화 후 전송. 응답 받아서 다시 치환 |
| 개인정보처리방침 페이지 | Phase 2 종료 전 | 스토어 심사 필수 |
| iOS Health/Camera 권한 사용 목적 명시 | Phase 1 빌드 시 | 미기재 시 심사 반려 |
| AI 분석 결과 보관 기간 정책 | C3 착수 전 | 명시·동의 |
| **AI 생성 콘텐츠 audit log** | Phase 1 종료 전 | `ai_drafted=true` 플래그 + 어떤 prompt로 생성됐는지 추적 가능해야 사후 분쟁 대응 |

---

## 7. 리스크 대응 (개발 관점)

| 리스크 | 발생 시 대응 |
|--------|-------------|
| 친구가 입력 귀찮다고 함 | 즉시 마찰 지점 인터뷰 → Phase 2의 S 작업 보류하고 입력 UX 개선 우선 |
| Flutter 학습 속도 부족 | 본인 익숙한 스택(예: React Native, Kotlin/Swift 네이티브)으로 전환. 데이터모델·로드맵은 그대로 |
| Supabase RLS 정책 오류로 데이터 노출 | 즉시 베타 중단 → SQL view + RLS 재점검 → 통합 테스트 추가 후 재배포 |
| FCM 전달률 낮음 (특히 안드로이드 절전 모드) | 카카오 알림톡 보조 채널 도입 검토 |
| Phase 1이 7.5주 초과 | AI 작업(1.9~1.11) 중 1.11 비용/장애 가드만 남기고 1.9·1.10은 Phase 2로 이동. Must(M1~M4)는 절대 양보 X |
| **LLM API 장애로 앱 멈춤** | 호출 실패 시 즉시 수동 입력 폼으로 폴백. 모든 AI 기능은 "선택사항"으로 표기 |
| **LLM 비용 폭주** (예: 무한 루프 호출) | 일일/계정별 호출 한도 + Supabase Edge Function 레이트리밋. 한도 초과 시 알림 |
| **LLM이 부적절한 회원 메시지 초안 생성** | 트레이너 검수 화면 필수 통과. 한 번도 수정 안 하고 발송한 비율을 추적해서 prompt 개선 |
| **회원이 AI 사용 동의 거부** | 해당 회원은 AI 기능 비활성화하고 기본 템플릿/수동 입력으로 동작. 거부했다고 서비스 자체 차단은 X |

---

## 8. 당장 할 일 (Next Actions)

### 이번 주
1. **기술 스택 확정** — Flutter로 갈지, 본인 익숙한 것으로 갈지 본인 의지 확인
2. **친구와 본 문서 공유 + MVP 3대 기능(M1~M3) 우선순위 재확인**
3. **Supabase 계정/프로젝트 생성**

### 다음 주
4. 데이터 모델 SQL 마이그레이션 작성 (§2 기준)
5. 트레이너 앱 와이어프레임 — 수업 기록 화면부터
6. 빈 Flutter 앱 양 플랫폼 빌드 확인

### Phase 0 종료 조건
- [ ] `flutter doctor` 통과 + 양 플랫폼 빈 앱 실행
- [ ] Supabase 마이그레이션 적용 + RLS 정책 통합 테스트 통과
- [ ] 와이어프레임 친구 1차 리뷰 완료
- [ ] `docs/data_model.md` 확정

---

## 9. 문서 연계

| 문서 | 위치 | 상태 |
|------|------|------|
| 기획서 (원본) | `assets/헬스장_앱_개발계획.md` | 완료 |
| 개발계획 (본 문서) | `docs/develop_plan.md` | 완료 |
| 데이터 모델 상세 | `docs/data_model.md` | Phase 0에서 작성 예정 |
| 와이어프레임 | `docs/wireframes/` | Phase 0에서 작성 예정 |
| API 명세 | `docs/api_spec.md` | Phase 1에서 작성 예정 |

---

> **다음 단계 제안:**
> 1) 본 계획서를 검토하고 수정 의견 주시면 반영하겠습니다.
> 2) 합의되면 `docs/data_model.md` (SQL 스키마 + RLS 정책 초안)부터 작성하는 것을 추천합니다.
> 3) 또는 와이어프레임을 먼저 그리고 싶으시면 수업 기록 화면 시안부터 시작할 수 있습니다.
