# Gyman — 개발 계획서 (Development Plan)

> 본 문서는 `assets/헬스장_앱_개발계획.md` 기획서를 기반으로,
> **실제 개발자가 코드를 작성할 때 참고할 실행 계획**을 정리한 문서입니다.
> 기획서가 "무엇을/왜"를 정의했다면, 본 문서는 "어떻게/언제/어떤 순서로"를 정의합니다.
>
> 작성일: 2026-05-24 (최종 갱신: 2026-07-25 — 마이그레이션 0001~0039 전부 적용 완료 반영)
> 대상 브랜치: `develop`

---

## 진행 현황 (2026-07-25 기준)

> **완료된 것의 목록·결과는 [`docs/shipped.md`](shipped.md) 로 옮겼다.**
> 여기엔 **아직 안 끝난 것만** 둔다 — 완료 서사가 계속 쌓이면 "지금 뭘 해야 하나"가 묻힌다.

### 기반 (전부 완료)
- 마이그레이션 `0001~0039` 전부 적용 완료. Edge Function 5종 배포 + 시크릿 설정 완료.
- 구현된 기능 전체 목록 → `shipped.md` §1, 지켜야 할 제약 → `shipped.md` §3.

### ⏳ 현재 최우선 병목 — 배포가 아니라 **동작 검증**
스키마·함수는 전부 올라갔지만 **실기기에서 실제로 도는지 확인한 항목이 아직 적다.**
체크리스트는 §8, 실행 대본은 `docs/e2e_verification_script.md`.

### ⬜ 앞으로
- **약관·개인정보 갭 16건 중 14건 처리 완료**(2026-08-10). 남은 2건은 **운영자 성명·연락처**로
  사용자만 채울 수 있다(`core/config/app_info.dart` 두 줄). 상세·검증 절차는
  [`docs/legal_docs_gap_check.md`](legal_docs_gap_check.md).
- **1.12** 베타 배포 — **⚠ 2026-07-30 전제 변경: iOS/TestFlight 우선.** 베타 테스터 트레이너가
  **전원 아이폰 유저**로 확인돼 "안드로이드 우선(Firebase App Distribution)" 계획은 폐기.
  현재 `src/app/ios/` 폴더 자체가 없고 Apple Developer Program($99/년) 등록이 크리티컬 패스다.
  블로커·실행 순서는 **[`docs/ios_beta_plan.md`](ios_beta_plan.md)**. 검증 백로그와 **병행** 진행.
- **Phase 3.2-B** 회원 인수인계 / **3.3** 회원 앱 정식 분리 / **3.4** 친구네 센터 파일럿.
- **Phase 4 (CV·코칭 트랙)** — 2026-07-24 트레이너 피드백으로 우선순위 상향. 4.8 L1·L2 와
  4.2 A단계는 완료, **다음은 PoC → 고스트 G1(`camera` 첫 도입)**.
  착수 순서는 §4 Phase 4 하단 "CV·개인화 트랙 실행 순서".

### 🆕 원래 계획 대비 추가·변경된 사항
| 항목 | 내용 | 사유 |
|------|------|------|
| **LLM 공급자** | OpenAI/Anthropic → **Google Gemini**(`gemini-3.5-flash`) | 호스팅+키 방식이 Edge Function에 적합, 무료 티어 개발 |
| **1.8 구현 수단** | Edge Function+cron → **plpgsql + pg_cron** | 배포 파이프라인 부재 + SQL-Editor 워크플로 일치 |
| **Edge Function 파이프라인** | `supabase init` + `health` + `secrets` 워크플로 신설(`src/supabase/functions/`) | LLM 키를 서버에만 보관(클라 노출 금지) |
| **`ai_call_logs`(0017)** | LLM 호출 감사 로그 + 일일 한도 테이블 신설 | 비용 폭주 가드 |
| **view RLS(0018)** | `v_contract_status` security_invoker | 회원 측 잔여 조회 RLS 일관성 |
| **회원 연결(0019/0020)** | **초대 코드** + `claim_member_profile`/`verify_invite_code` RPC 신설 | 오프라인 등록 회원 ↔ 앱 계정 매핑(원 계획엔 흐름 미정) |
| **FCM 보류** | 1.7 재등록 알림은 in-app만 | 발송 채널·회원앱 준비 후 도입 |
| **예약 신청(⑤)** | 별도 테이블 대신 `sessions` 에 `requested` 상태 추가(0021/0022) | 잔여 계산 view·트레이너 예약 화면 등 기존 인프라 재사용. 회원 INSERT(requested)/철회 DELETE RLS만 신설, 승인은 기존 트레이너 RW 정책 |

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
| **채팅 사진 첨부 의존성** | `image_picker` 추가 (마이그레이션 0026) | 트레이너↔회원 채팅에 사진 전송. 비공개 버킷 `chat-images` + 서명 URL + Storage RLS(`are_chat_peers` 재사용). object key 첫 세그먼트 = 업로더 user_id 가 권한 키. 업로드 전 `imageQuality`/`maxWidth` 로 압축해 전송량 절감 |
| **PT 알림 의존성** | `flutter_local_notifications` + `timezone` + `shared_preferences`(직접 승격) 추가 (운톡 P1 후속) | "PT 시작 전 알림"(회원 요청). FCM 보류 상태라 **기기 로컬 예약 알림**으로 구현 — 회원 본인 다가올 `scheduled` 수업을 앱이 알아 기기에서 스케줄(서버/푸시 인프라 0). 리드타임은 사용자 설정(끄기/30분/1시간/2시간/하루 전, 기본 1시간), 기기 로컬(`shared_preferences`) 저장. **정시 대신 inexact 알람**(`inexactAllowWhileIdle`)이라 Android14 `SCHEDULE_EXACT_ALARM` 권한·Play 정책 회피(몇 분 오차 무방). 예약은 절대시각 대신 **"지금부터 N후" 상대 시각**(`TZDateTime.now(tz.local).add(delay)`)이라 기기 타임존 탐지 불필요 → `flutter_timezone` 의존성 제거(이 플러그인의 JVM 타깃 불일치로 빌드 깨짐). 발화 시각 계산은 순수 도메인 `computePtReminders`(단위테스트). 벽시계 컨벤션 유지(tz 변환 X). 재동기화 트리거 = 회원 홈 진입·새로고침·설정 변경(트레이너 승인분은 다음 홈 진입 때 반영 — 푸시 없으니 즉시성은 한계). 네이티브: AndroidManifest 권한/리시버 + core library desugaring |
| **소셜 로그인/계정 복구(P2-E)** | **신규 의존성 0** — `supabase_flutter` 내장 OAuth(`signInWithOAuth`) + PKCE + 딥링크 | 운톡 불만 #2. 카카오·구글은 Supabase 기본 공급자라 인앱 브라우저 OAuth로 SDK 없이 구현(카카오 네이티브 SDK는 후속 B). 회원 연결은 기존 `/member/claim` redirect 재사용. 비번 재설정은 `resetPasswordForEmail`→딥링크 `passwordRecovery`→`/reset-password`. 배선: `AuthFlowType.pkce` + Android intent-filter(`io.supabase.gyman://login-callback`). iOS는 플랫폼 미부트스트랩이라 생성 시 추가(+애플 로그인, 심사 4.8). 상세: `docs/social_login_plan.md` |
| **수업 영상 의존성** | `video_player` 추가 + `image_picker` 재사용 (마이그레이션 0027) | 트레이너가 짧은 클립(≤120초) 업로드 → 회원 본인 열람. 비공개 버킷 `class-videos` + 단기 서명 URL + Storage RLS. object key 첫 세그먼트 = **대상 회원 member_id**(채팅과 달리 업로더 폴더 아님) → 트레이너=`is_member_of_trainer`, 회원=`current_member_profile_id()`. 업로드는 보상 트랜잭션. `image_picker.pickVideo(maxDuration)` 로 선택, `video_player` 로 인라인 재생. 빌드 검증 완료(APK debug). 스케일 시 Cloudflare Stream 이전 |

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
| `messages` | 채팅 (S2) | id, sender_id, receiver_id, content, image_path(0026 사진 첨부), sent_at, read_at |
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
/trainer/members/:id/chat   → 회원과 1:1 채팅 (S2) ✅ (회원 상세에서 진입)
/trainer/chat               → 회원 채팅 대화 목록 (S2) ✅ (마지막 메시지·안읽음 배지)
```

### 3.2 회원 앱 (Phase 2~3)

```
/member/home                → 다음 수업 + 잔여 횟수
/member/records             → 내 운동 기록
/member/records/progress    → 변화 추이 그래프 (S1, 중량+인바디) ✅
/member/booking             → 예약 신청
/member/chat                → 트레이너와 채팅 (S2) ✅
/member/faq                 → 자주 묻는 질문 (S3, 운동 상식 정적) ✅
/member/self-log            → 셀프 운동 기록 (S4, 회원 작성·트레이너 읽기) ✅
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
| 1.1 | ✅ 로그인 + 역할 분기 (Supabase Auth) | High | 트레이너만 로그인 가능 |
| 1.2 | ✅ 회원 카드 CRUD (M4) + 오프라인 등록 | High | 트레이너 전용 메모 회원에게 안 보임 (RLS) |
| 1.3 | ✅ PT 계약 등록 + 잔여 횟수 자동 계산 (M1) | **Critical** | 단위 테스트 + `v_contract_status` view |
| 1.4 | ✅ 수업 기록 화면 (M2) — 1분 입력 UX | **Critical** | 입력 시간 1분 이내 (베타 측정 지표) |
| 1.5 | ✅ 이전 기록 복사, 자주 쓰는 종목 즐겨찾기 | High | 입력 속도 개선 |
| 1.6 | ✅ 예약 + 노쇼/취소 기록 (M3) | High | 차감 규정 자동 표시 (chip 필터, 캘린더 위젯은 보류) |
| 1.7 | ✅ 재등록 알림 자동화 ("5회 남음" 등) (M1) | High | **in-app 구현. FCM 푸시는 보류**(채널 준비 후) |
| 1.8 | 수업 전날 회원 안내 메시지 자동 발송 (M1) | High | ✅ 백엔드 적재 구현(0016). **결정 변경:** Edge Function 대신 plpgsql 함수 + pg_cron (배포 파이프라인 부재 + SQL-Editor 워크플로 일치). FCM/회원앱 부재로 범위는 "발송"이 아닌 **draft 자동 적재**까지 — 검수/발송 UI는 1.9 AI 검수 허브에서 통합. 기본 템플릿(비-AI). |
| **1.9** | **AI-B. 회원 안내 메시지 초안 LLM 생성** | High | ✅ **검수 게이트 + LLM 생성 연동 완료** — AI 검수 허브(`/trainer/ai-review`) + 승인/수정/취소/일괄승인 + 홈 배지. 회원 상세 "AI 초안 생성"(트리거/톤 선택) → `generate-message-draft` Edge Function(Gemini) 호출 → draft 적재 → 검수 큐. 실패 시 code별 폴백 UX(consent/rate_limit/llm_failed). 실발송(sent 전이)은 FCM/회원앱 준비 후. 안전장치: 도메인 `NotificationStatus.isVisibleToMember`(sent만) 단위테스트 + 서버 동의/마스킹/한도. |
| **1.10** | **AI-C. 트레이너 메모 자동 초안 (수업 기록 기반)** | High | ✅ 구현 — `generate-memo-draft` Edge Function(최근 done 수업 기록 기반, 동의/마스킹/한도/폴백 가드) → `member_notes` source='ai_draft' 적재. 회원 상세 "트레이너 전용 메모" 카드에서 확정(ai_confirmed)/수정/삭제 + 직접 추가. RLS `notes_member_deny` + visibility=trainer_only 로 회원 차단. (현재는 트레이너 수동 트리거 — 저장 시 자동 트리거는 비용/동의 고려해 보류) |
| **1.11** | **LLM API 연동 + 비용/장애 가드** | High | ⏳ **서버 코어 구현** — 배포 파이프라인(`supabase init`/health) + `generate-message-draft` Edge Function(Gemini 호출 + 동의 확인 + **PII 마스킹**[실명→{{NAME}}] + 일일 호출 한도[`ai_call_logs` 0017] + 장애 시 구조화 에러로 수동 폴백 유도). 키는 `supabase secrets`(서버)에만. **남은 작업:** 사용자 `deploy` + `LLM_API_KEY` 설정 후 동작 검증, 그다음 Flutter "초안 생성" 버튼 연동. |
| 1.12 | **TestFlight 베타 배포 (iOS 우선)** | High | 친구 디바이스에서 설치 성공. **전제 변경(2026-07-30):** 테스터 전원 아이폰 → iOS 가 크리티컬 패스. Windows 에서 `.ipa` 빌드 불가(클라우드 macOS CI 필요) + Apple Developer Program 등록 대기가 최장 리드타임. 상세 → `docs/ios_beta_plan.md` |

> **Phase 1 완료 정의(DoD):**
> 1) 친구가 본인 회원 3~5명 데이터를 넣고 **1주일간 매일 사용**할 수 있다.
> 2) **AI 안내 메시지/메모 초안이 발송·확정 전에 트레이너 검수 화면을 반드시 거친다는 RLS·UX 흐름이 통합 테스트로 검증되어 있다.**
> 3) LLM API 장애 시에도 앱이 멈추지 않고 수동 입력으로 정상 동작한다.

### Phase 2 — 친구 실사용 + 정착 강화 (3~4주)

> **회원 앱 로드맵 (베타에서 친구의 회원도 사용 — 일부 당겨옴):**
> 베타에 회원 셀프 사용이 필요해져 회원용 화면을 Phase 1 말미~Phase 2 초입으로 당김.
> 1. ✅ **회원 계정 연결** — 초대 코드(0019/0020), 가입 시 코드 필수.
> 2. ✅ **회원 홈** — 다음 수업 + 잔여 횟수 (읽기 전용). `features/member/home/` —
>    본인 시점 repository(RLS `current_member_profile_id()` 위임, member_id 필터 불필요)
>    + v_contract_status 합산 + 다음 scheduled 수업. 잔여 합산/음수 클램프 단위테스트.
> 3. ✅ **내 수업 기록 열람** — `features/member/records/`. 본인 done 수업+기록을
>    최신순 카드 + 탭 시 세트별 상세 바텀시트. **가시성 분리:** 트레이너용 메모
>    (`next_memo`)는 쿼리에서 아예 select 제외(컬럼 단위 방어) — 운동/컨디션/통증만 노출.
>    날짜 포맷은 `core/util/date_format_ko.dart` 공용 헬퍼로 추출(홈과 공유).
> 3. ⬜ **내 수업 기록 열람** — 본인 운동 기록.
> 4. ✅ **받은 안내** — 트레이너가 발송(sent)한 메시지 수신. **FCM 없이 in-app 전달:**
>    트레이너 AI 검수 허브에 `markSent`(approved→sent, send_channel='in_app') 추가 —
>    검수 다이얼로그 주 버튼이 상태별로 "발송 승인→발송하기"로 전이. 회원은
>    `features/member/notices/`에서 sent 만 조회(RLS `notif_member_read_sent_only`).
>    안전 게이트(draft→approved→sent) 유지. 수정 시 draft 로 되돌려 재검수 강제.
> 5. ✅ **예약 신청** — 회원 신청 → 트레이너 승인. **별도 테이블 없이 `sessions` 에
>    `requested` 상태 추가**(0021) — 잔여 계산 view(차감 X)·트레이너 예약 화면 등 기존
>    인프라 재사용. 회원은 `features/member/booking/`에서 본인 계약에 신청(INSERT
>    requested)·철회(DELETE) — RLS `sessions_member_request_insert`/`_cancel_request`
>    (0022). 트레이너는 예약 화면 상단 "승인 대기" 섹션 + 홈 배지에서 승인(→scheduled)
>    /거절(행 삭제). 승인/거절은 기존 `sessions_trainer_rw`(FOR ALL) 재사용.
> 6. ✅ **변화 추이 그래프(S1)** — 중량 + 인바디. **인바디 수치 테이블 신설(0023
>    `body_measurements`)** — 사진 기반 `body_assessments`(Phase 4)와 별도. 트레이너가
>    회원 상세에서 체중/체지방률/골격근량 입력(`features/trainer/member_card/`),
>    회원은 `/member/records/progress`에서 종목별 최고중량·인바디 지표를 라인차트로 봄.
>    차트는 **의존성 없이 CustomPainter 자체 구현**(`features/member/progress/`). 중량 추이는
>    `WeightTrendCalculator`(도메인, 단위테스트)로 exercises JSON → 종목별 시계열 도출.
> 7. ✅ **회원 채팅(S2)** — 트레이너↔회원 1:1 실시간 채팅. `messages`(0006)에
>    RLS+실시간 publication 신설(0024, `are_chat_peers` 계약기반 검증). 역할 공용
>    `features/chat/`(repository는 Supabase `.stream()` + 클라 peer 필터, sender_id 는
>    RLS가 auth.uid()로 강제). 회원은 `/member/chat`(계약→트레이너 해석), 트레이너는
>    회원 상세 AppBar에서 진입(`/trainer/members/:id/chat`) + 트레이너 대화 목록
>    `/trainer/chat`(마지막 메시지·안읽음 배지, 홈 진입). 양 역할 홈에 안읽음 배지.
>    **방해금지 시간**: 트레이너가 설정(trainer_profiles dnd 컬럼, 0025) → 회원 채팅에
>    안내 배너(전송은 허용). FCM 푸시는 보류 — 도입 시 이 시간대에 푸시 억제로 재사용.
> 8. ✅ **FAQ(S3)** — 운동 상식 정적 목록(`features/faq/`, `/member/faq`). 센터별 PT 규정은 Phase 3 관리자로.
>    ✅ **셀프 기록(S4)** — 회원 자율 운동 일지(`self_workout_logs` 0028). 회원 작성, 트레이너 읽기(`/member/self-log`).

| # | 작업 | 메모 |
|---|------|------|
| 2.1 | 매주 피드백 수집 → 입력 마찰 지점 우선 개선 | "어디서 막혔는지" 기록 요청 |
| 2.2 | ✅ 변화 추이 그래프 (S1) — 중량/인바디 추이 | 재등록 세일즈 직결. 0023 `body_measurements` 신설 + CustomPainter 차트(의존성 0) |
| 2.3 | ✅ 회원 채팅 (S2) + ✅ 방해금지 시간 | 채팅: `messages`(0006)에 RLS+실시간(0024) + 공용 `features/chat/`. 안읽음 배지(양 역할). 방해금지: trainer_profiles에 dnd 컬럼(0025), 회원 채팅에 안내 배너(전송 허용). FCM 푸시 보류는 동일 |
| 2.4 | ✅ FAQ 자동 응답 (S3) — 운동 상식(정적) | **결정: 정적 FAQ 목록**(AI 자동응답 X — "AI는 트레이너 검수 후 노출" 원칙과 충돌 회피). 운동 상식만 앱 내장 시드(`features/faq/` + 도메인 `FaqItem`/`FaqCategory`, 의존성·마이그레이션 0). 검수 게이트 없는 콘텐츠라 답변은 비-의학단정 톤 + 통증은 트레이너 상담 유도. 센터별 PT 규정 FAQ는 `FaqCategory.ptPolicy` 자리만 열고 "준비 중" 안내 → Phase 3 관리자 입력으로. 회원 홈 메뉴 진입(`/member/faq`) |
| 2.5 | ✅ 회원 셀프 운동 기록 간단 입력 (S4) | 초간단 필드(날짜+운동 한 줄+**컨디션 점수 1~10 슬라이더**(높을수록 좋음)+선택 메모). 컨디션은 자유 텍스트 대신 점수로 받아 입력 마찰 축소. `self_workout_logs`(0028, `condition_score` smallint 1~10) — member_id `DEFAULT current_member_profile_id()` 로 회원이 id 안 넘겨도 INSERT, 위변조는 RLS WITH CHECK 차단. **가시성:** 회원 rw(`self_log_member_rw`) / **트레이너 read-only**(`self_log_trainer_read`, 통증 내역 보고 수업 반영). 공용 `features/self_log/`(repo·providers) + 회원 작성 화면(`features/member/self_log/`, `/member/self-log`) + 트레이너 읽기 카드(회원 상세). |
| 2.7 | 수업 영상 보관·열람 (친구 요청) — ✅ **MVP(A단계) 구현** | 트레이너 업로드(촬영/갤러리·120초·250MB 상한·보상 트랜잭션) → 회원 본인 열람·재생. 0027(`class_videos` + 비공개 버킷 `class-videos` + RLS). 비공개 버킷+서명URL+폴더=member_id 권한키. 동의는 MVP=트레이너 확인 체크박스(약관 확정 시 서버 플래그 승격, 설계 §9.6). ✅ **B-1 수업 연결**(업로드 시 수업 선택→`session_id`, 타일에 연결 수업 표시) + ✅ **B-2 보관 개수 상한**(회원당 20개, 차단 방식·자동삭제 X; 카드에 N/상한 표시) 완료 — 둘 다 의존성·마이그레이션 추가 0. 기간 자동삭제는 Storage 고아 리스크로 정리 잡과 별트랙 보류. **남은 단계:** B(기기 압축·썸네일) / C(Cloudflare Stream 이전). 상세: `docs/design_class_videos.md` |
| 2.6 | 회원용 화면 최소 분리 (홈/기록 열람) | 단일 앱 내 역할 분기 유지. ⏳ **회원 온보딩(초대 코드 연결) 완료** — 0019(invite_code + `claim_member_profile` RPC), 회원 셀프 가입(login 토글), `/member/claim` 코드 입력 화면, 트레이너 회원 상세에 코드 노출. 연결 후 `/member/home`(현재 placeholder). **남은 회원 기능:** 홈(다음수업/잔여), 내 기록 열람, 받은 안내+발송, 예약 신청 |

### Phase 3 — 관리자 + B2B 파일럿 (4~6주)

| # | 작업 |
|---|------|
| 3.1-A | ✅ **관리자 인프라** — `admin_profiles`(0029) + `current_user_role()` admin 분기 + `current_admin_center_id()` 헬퍼 + 센터 범위 read RLS(member/trainer/contracts/sessions). **계정은 수동 SQL 등록**(베타 관리자 1명). 역할 우선순위 trainer>admin>member. `role_repository` admin 분기. |
| 3.1-B | ✅ **관리자 대시보드 (C1)** — `v_admin_contract_overview`(0030, security_invoker) + `features/admin/dashboard/`. 센터 요약(활성 회원·계약·매출·노쇼율) + 트레이너별 성과(매출순) + 만료 임박 회원(잔여≤3 또는 14일 이내). 집계는 순수 함수 `aggregate`로 분리·단위테스트 9종. ✅ 0030 적용 완료. ⏳ **남은 일: 관리자 계정으로 end-to-end RLS 검증(타 센터 유출 0).** |
| 3.2-A | ✅ **센터 규정·멘트 관리 (C2 전반)** — `0031`(admin RLS 겸직 수정 + centers UPDATE + `center_faqs`). `features/admin/center/`: 관리자가 센터 규정(`centers.rules`: 취소·노쇼·지각) + PT 규정 FAQ CRUD. 회원 FAQ 화면의 "준비 중"(2.4) → DB 연동. **0031에서 0029 admin RLS 게이트를 `current_admin_center_id()` 기준으로 교체** — 트레이너 겸 관리자가 센터 전체를 보게(이전엔 본인 담당만). ✅ 0031 적용 완료. ⏳ **남은 일: 규정 저장/FAQ 노출 end-to-end 검증.** |
| 3.2-B | ⬜ 회원 인수인계 (C2 후반) — 트레이너 변경 시 담당 재배정 + 히스토리 정리. 트레이너 다수(3.4) 전제라 그 단계에서. |
| 3.3 | 회원 앱 정식 분리 (별도 빌드 또는 별도 진입점) |
| 3.4 | 친구네 센터 파일럿 — 트레이너 3~5명 |
| 3.5 | ⏳ **개인정보처리방침 / 이용약관 / 동의 + 탈퇴·문의** (운톡 P0 묶음, 2026-06-16) — `0033`(support_inquiries) + `0034`(account_deletion_logs·user_consents) + Edge Function `delete-account`(익명화 탈퇴). `features/settings/`(설정·문의·탈퇴), `features/legal/`(약관·정책 **임시 초안** — 정식 배포 전 법무 검토 필요), `features/admin/support/`(운영자 문의함 + 미처리 배지). 가입 시 필수 동의 2종 + 기록, 전 역할 설정 진입점(미연결 사용자 포함). 상세·근거: `docs/untok_improvement_plan.md`. ✅ 0033/0034 적용 완료. **남은 일: `delete-account` 배포 후 end-to-end 검증.** |

### Phase 4 — 고급 AI 기능 (6~8주, 일부 병렬)

> 참고: 기본 LLM 기반 AI 기능(메시지 초안, 메모 초안)은 **Phase 1 데모로 당겨졌습니다.**
> Phase 4는 카메라/이미지 기반의 무거운 AI 기능에 집중합니다.

| # | 작업 | 비고 |
|---|------|------|
| 4.1 | 카메라 촬영 가이드 UI (그리드/수평/발 위치/거리) | Flutter 강점 영역. 상세: `docs/design_body_analysis.md` |
| 4.2 | 체형 분석 (C3) — ⏳ **A단계 구현 완료(2026-07-25, 0039)** | **결정 고정: 100% 온디바이스**(ML Kit Pose, 사진 외부전송 0, LLM·비용 0). 좌우 어깨/골반 비대칭 우선. 첫 등록 + 4·8·12주 비교. ~~⚠ 0008 스키마 빚 정리 필요~~ → **0013 에서 이미 해결돼 있었음**(2026-07-25 확인). 0039 는 `recorded_by`·FK CASCADE·인덱스·`body-photos` 버킷·`body_photo_consent` 만 보강. **CV 트랙의 관문** — 4.6·4.7이 ML Kit/`camera` 를 공유하므로 여기를 세우면 나머지 한계비용이 급감. 상세: `docs/design_body_analysis.md` |
| 4.3 | **트레이너 검수 플로우** — AI/수치 결과 → 트레이너 코멘트 → 회원 노출 | **반드시** 순서 강제 (Phase 1의 B/C와 동일 원칙 재사용). RLS `trainer_comment IS NOT NULL` 게이트가 2D 키포인트 정확도 한계의 안전장치 |
| 4.4 | 식단 분석 (C4) — 멀티모달 LLM API | 칼로리/단백질 대략 피드백 |
| 4.5 | 자세 영상 분석 (별도 R&D 트랙) | **→ 4.8 L3 로 흡수**(2026-07-25). 자동 검출은 4.8의 3층 중 최하위 우선순위로 재배치 — 실제 검출 가능 범위가 좁아(`design_movement_coaching.md` §2) 단독 트랙으로 세울 근거가 약함. 정확도 검증은 L2 트레이너 마킹을 정답지로 실측 |
| 4.6 | 수업 영상 객체 트래킹·자동 프레이밍 — ⬜ **설계만 완료** | **결정 제안: 온디바이스 ML Kit + 비파괴(재생시점 팬/줌)**. 인물 위치만 뽑아 "크롭 경로(JSON)"로 저장 → 재생 시 플레이어가 팬/줌 → 손떨림 완화+자동 프레이밍. **재인코딩·서버 파이프라인 미도입**(Edge Function은 FFmpeg 불가·서버 처리는 새 인프라+비용). 원본 불변. 체형분석(4.2)과 ML Kit·CV 트랙 공유 → 함께 착수 권장. ⚠ 프레임추출 실현성 PoC 선행. 상세: `docs/design_class_video_tracking.md` |
| **4.7** | **고스트 오버레이(따라하기)** — ⬜ **설계만 완료**(신규, 2026-07-24 피드백) | 회원 본인의 PT 영상을 **카메라 프리뷰 위에 반투명으로 겹쳐** 보며 따라하기. **DB·스토리지·동의 추가 0**(기존 `class_videos` 0027 재생 방식만 변형, 촬영물 저장 없음). 신규 의존성은 `camera` 1개 — **4.1 촬영 가이드와 공유**. 난이도의 본체는 합성이 아니라 **정렬·템포·좌우반전 통제**(카메라 위치·체형이 달라 그냥 겹치면 안 맞음). ⚠ 카메라+영상 동시 렌더 PoC 선행. 상세: `docs/design_ghost_overlay.md` |
| **4.8** | **동작 습관·체형 제약 코칭** — ⏳ **L1·L2 구현 완료**(2026-07-25, 0036~0038) | **4.5(자세 영상 분석 R&D)를 흡수·구체화.** 요구 = "다리가 빠진다" 같은 **동작 습관** + "측만증으로 인한 운동 변경" 같은 **체형 제약**. **결정: 앱은 판단하지 않고 트레이너의 판단을 구조화해 나른다.** 3층 — L1 제약 등록(출처 `medical`/`trainer_observation` 강제 구분) → 동작 패턴 8종별 큐 표시 / L2 트레이너가 영상 시점에 마킹 → 회원 재생 시 재생 / L3 자동 검출(후순위·보조). **L1·L2는 CV 0·신규 의존성 0.** ⚠ 자동 검출 가능 범위는 설계 §2 표로 고정(무릎 모임=부분가능 / 체중분포=측정불가 / 측만증=의료영역). 상세: `docs/design_movement_coaching.md` |

#### CV·개인화 트랙 실행 순서 (2026-07-24 피드백 반영)

> **피드백 ①** "운동영상을 본다고 해도 따라한다고 되는 게 아니다 — 카트라이더 고스트처럼 PT 영상을 투명도 낮춰 보는 느낌" → **4.7 고스트 오버레이**
> **피드백 ②** "개인화된 신체·습관 피드백" — **운동할 때의 습관**(다리가 빠진다, 체중이 이상한 곳에 실린다)과 **체형의 한계에서 오는 문제**(측만증으로 인한 운동 변경, 골반 전방경사로 신경써야 할 부분) → **4.8 동작 습관·체형 제약 코칭**
> ⚠ 2026-07-25 정정: ②를 처음에 "출석·컨디션 집계 리포트"로 해석했으나 **동작 품질 코칭**이 요구였음. 집계 방향 설계는 폐기(`design_personal_insight.md` 삭제, git 이력에 보존).
>
> **결론:** 체형분석(4.2)을 앞당긴다. 근거 둘 — ⑴ 4.2가 **CV 트랙의 관문**(4.2·4.6·4.7이 `google_mlkit_pose_detection`·`camera` 공유), ⑵ 4.2의 체형 수치가 **4.8 L1 제약 등록의 근거 자료**가 된다.
>
> ⚠ **2026-07-29 정정:** 위 근거 ⑵는 **PoC 2 재현성 실패로 성립하지 않는다.** 자동 수치가 촬영마다 2도 흔들려 L1 제약의 근거 자료로 쓸 수 없다. 근거 ⑴(관문)은 유효하되, **관문 자체가 "ML Kit 을 넣을 것인가" 에서 "각도 대신 무엇을 쓸 것인가" 로 바뀌었다.** 5단계는 수치 없이 재설계했다(아래 표).

**순서 원칙 두 가지.**
1. **의존성 추가가 늦을수록 좋다.** 네이티브 플러그인은 빌드·기기 호환 리스크라, 검증 안 된 앱에 먼저 얹으면 장애 원인 분리가 안 된다 → 의존성 0 → `camera` → ML Kit 순.
2. **CV 정확도에 의존하지 않는 것부터.** 피드백 ②의 4개 항목 중 자동 검출이 실제로 되는 건 "다리가 빠진다" 하나뿐이다(`design_movement_coaching.md` §2 — 체중분포는 족저압이라 카메라로 측정 불가, 측만증은 의료 영역). **CV로 시작하면 몇 주를 쓰고도 아무것도 못 준다.**

| 단계 | 내용 | 신규 의존성 | 마이그레이션 | 회수하는 피드백 |
|---|---|---|---|---|
| **0. PoC 3종** | ① 카메라+영상 동시 렌더(4.7) ② ML Kit Pose 정지사진 + **APK 크기·빌드시간 측정**(4.2) ③ 영상 프레임 추출(4.6/L3 관문) | 임시 | 0 | — (리스크 제거) |
| **1. 4.8 L1 제약 등록 + 큐** | ✅ **구현 완료(2026-07-25)** — `member_conditions`(0036) + 트레이너 등록 카드 / 동작패턴 8종 도메인 + `condition_coaching_rules`(0037, 시드 19건) → 회원 셀프기록·트레이너 수업기록에 큐 표시 | **0** | 2 (0036·0037 ✅ 적용 완료) | **② 체형 제약 전부** |
| **2. 4.8 L2 영상 시점 지적** | ✅ **구현 완료(2026-07-25)** — `class_video_marks`(0038) + 재생기 확장(진행바 눈금·시점 오버레이·목록 탭 이동) + 트레이너 마킹/삭제 | **0** | 1 (0038 ✅ 적용 완료) | **② 동작 습관 전부**(정확도 100%) |
| **3. 체형분석 A** | ✅ **구현 완료(2026-07-25)** — 0039(감사 컬럼·FK CASCADE·인덱스·`body-photos` 버킷·Storage RLS·`body_photo_consent`) + `posture_metrics`(ML Kit 비의존 순수 Dart) + `BodyAssessment` 모델(RLS 미러 게이트) | **0** | 1 (0039 ✅ 적용 완료) | (관문 정리) |
| **4. 고스트 G1 + L1/L2 결합** | 반투명 합성 + 정렬·템포·반전 통제. **따라하기 화면에 L1 큐·L2 마킹 표시** — 두 피드백이 여기서 합쳐짐 | `camera` | **0** | **① 전부** |
| **5. 체형분석 B·C** | ⚠ **재설계(2026-07-29)** — **수치 없이** 사진 + 촬영 가이드(4.1) → 검수(4.3) → 회원 열람. **ML Kit 자동 수치·4/8/12주 비교는 뺀다** | **0** | 0 | ② 신체 축 근거 자료(트레이너 소견) |
| **6. 확장 + ML Kit 재판단** | 4.8 L3 자동 검출 + 고스트 G2/G3 + 영상 트래킹 4.6. **여기서 ML Kit 도입 여부를 용도별로 판단** | `google_mlkit_pose_detection`(도입 시) | 0~1 | 엔진 공유 회수 |

- **PoC(0단계)에서 막히는 항목이 있으면 그 트랙만 보류**하고 나머지는 진행한다 — 세 PoC는 서로 독립적이다. 가장 싼 값에 가장 큰 불확실성을 제거하는 순서.
- **1·2·3단계는 의존성 0이라 §8 검증 백로그·1.12 베타 배포와 병행 가능.** 4단계 이후(네이티브 플러그인 도입)는 **베타 배포를 1회 내보낸 뒤** 착수를 권장 — 안 그러면 "베타에서 앱이 깨졌다"의 원인이 기능인지 플러그인인지 가려지지 않는다.
- ⚠ **ML Kit 도입은 5단계에서 6단계로 미뤘다 (2026-07-29, PoC 2 결과).** 정지사진 재현성 측정에서 **자세를 전혀 바꾸지 않았는데 어깨 각도가 1.97도 흔들렸다**(기준 0.5도). 오차가 변형 크기에 비례하지 않아(3px 이동이 14px 이동보다 큰 오차) **촬영 가이드로 막을 수 없다.** 계산식(`posture_metrics.dart`)은 결백하고 오차는 ML Kit 랜드마크 단계에서 들어온다 — 근거·요인 분해는 `poc_cv_track_results.md` §4·§8.
  - **버리는 게 아니라 미루는 것이다.** bbox(4.6)·시각화(G2) 용도는 이 실패의 영향을 거의 안 받는다. 무너진 건 **각도를 숫자로 내보내는 두 기능(4.2 B·L3)** 이다.
  - 지금 미루는 실질적 이유: ML Kit 을 쓰는 네 기능이 **전부 미완**이고 그중 4.6 은 PoC 3 에서 속도 4.5배 초과로 막혔다. 가치 0 에 **APK +22MB**(arm64 25.2 → 47.3MB)를 얹을 이유가 없다.
  - 도입 시 **APK 크기·빌드시간 측정 후 §0 의존성 표 갱신**은 여전히 선행 조건(3개 설계 문서 공통 경고).
- **4.8은 의료 인접 영역** — 진단·처방 금지선(`design_movement_coaching.md` §5)을 착수 전 반드시 읽을 것. `source` 출처 구분(`medical`/`trainer_observation`)은 스키마 레벨 CHECK 로 강제한다.

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

> **iOS 최소 지원 버전은 의존성이 결정한다(2026-07-30 실측):** `google_mlkit_pose_detection` 0.15.0 이
> **iOS 15.5** 를 강제하고, 나머지(`camera`/`image_picker`/`video_player`)는 13.0 이다.
> ML Kit 은 현재 `lib/poc/` 전용이라 **베타 빌드에서 빼면 13.0 으로 내려가 지원 기기가 넓어진다.**
> 결정·근거는 `ios_beta_plan.md` §1.1·§5.
>
> **iOS 는 권한 문구(Info.plist)가 없으면 경고가 아니라 즉시 크래시**한다 — Android 와 다르다.
> 아래 §6 의 "iOS Health/Camera 권한 사용 목적 명시" 는 심사 항목이기 전에 **동작 요건**이다.

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
| iOS Health/Camera 권한 사용 목적 명시 | Phase 1 빌드 시 | 미기재 시 심사 반려 — **그 전에 런타임 즉시 크래시**(iOS 는 문구 없으면 접근 자체가 중단됨) |
| **App Store Connect: 지원 URL + 개인정보 처리방침 URL** | **iOS 베타 등록 시(필수 입력)** | 웹에 접근 가능한 URL 이어야 함 — 앱 내 문의하기로 대체 불가. **현재 미준비** (`ios_beta_plan.md` §4-5) |
| **App Privacy 설문에 "제3자 공유"(외부 LLM) 신고** | **iOS 베타 등록 시** | 회원 데이터 일부가 Gemini API 로 전송됨 — 누락 시 반려/제재. 위 AI 동의 항목과 짝을 맞출 것 |
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

> Phase 0 및 Phase 1.0~1.11은 완료(상단 "진행 현황" 참조). 아래는 현재 시점 액션.

### 검증 (배포·설정 후 동작 확인)
> ✅ 마이그레이션 `0001~0039` 전부 적용 완료(0035~0039는 2026-07-25). 아래는 **적용된 스키마 위에서 기능이 실제로 도는지** 확인하는 잔여.
- [ ] **`0039` 동작 확인**(4.2 A단계) — 적용 완료. 남은 건 하단 검증 SQL 5종. 특히 ⑵ FK 가 CASCADE 인지, ⑶ `body-photos` 가 **비공개**인지, ⑸ **코멘트 없는 분석이 회원 계정에서 0건**인지(AI 단독 노출 차단 — 가장 중요).
- [~] **`0036` 동작 확인**(4.8 L1-a) — **앱 라운드트립 등록·해제·재적용 통과(2026-07-29, 실기기)**, 삭제만 남음. 검증 SQL 은 미실행: ⑶ `source` CHECK 가 잘못된 값을 막는지, ⑷ 같은 회원+코드 활성 중복이 차단되는지, ⑸ 회원 계정에서 타인 제약이 안 보이는지. 진행 상태·중단 지점은 `e2e_verification_script.md` "진행 상태".
- [ ] **`0037` 동작 확인**(L1-b) — 시드 19건 삽입 / `action='avoid'`·잘못된 패턴 차단 / 회원 계정에서 공통 시드가 읽히는지 / 앱에서 공통 시드를 못 고치는지. + 셀프기록에 "스쿼트" 입력 시 큐가 뜨는지.
- [ ] **`0038` 동작 확인**(L2) — 빈 코멘트·음수 시점 차단 / 회원 계정에서 타인 영상 마킹 비노출 / 영상 삭제 시 마킹 CASCADE. + 트레이너가 남긴 코멘트가 회원 재생 시 같은 지점에 뜨는지.
- [ ] 관리자 계정으로 `/admin/dashboard` 진입 → **본인 센터 데이터만** 보이는지(타 센터 유출 0) end-to-end RLS 검증 (3.1-A/B, 3.2-A)
- [ ] `/admin/center`에서 규정 저장 + PT FAQ 추가 → 회원 FAQ 화면(`/member/faq`)에 노출되는지, 트레이너 겸 관리자가 **센터 전체** 대시보드를 보는지 확인 (3.2-A)
- [x] `npx supabase functions deploy delete-account` 배포 (3.5) — service_role 자동 주입 확인 ✅ (2026-07-18)
- [ ] 회원 계정: 설정 > 문의하기 → 운영자(관리자) 문의함에 보이고 미처리 배지 증가 → 처리완료 동작 (3.5)
- [ ] 회원 계정: 설정 > 회원 탈퇴 → 익명화('(탈퇴한 회원)') + 재로그인 차단 + 트레이너 화면에서 PII 비노출, 수업기록/계약은 보존 (3.5)
- [ ] 신규 회원 가입 시 필수 동의 2종 체크 강제 + `user_consents` 기록 / 동일 이메일 탈퇴 후 재가입 가능 (3.5, U5)
- [ ] **`0041` 동작 확인**(약관 갭 C·D-4) — ✅ 적용 완료(2026-08-10). ⚠ **앱 재빌드·재설치 선행 필수** — 구버전 앱은 동의 확인 컬럼을 안 보내 트리거에 걸리므로 [회원 추가]가 실패한다. 8항목 체크리스트는 `legal_docs_gap_check.md` "검증 절차". 특히 ③ SQL 직접 INSERT 우회 차단이 핵심(앱 없이 지금 확인 가능).
- [~] 회원 셀프 기록 작성/트레이너 읽기 end-to-end (2.5, `self_workout_logs`) — **트레이너 읽기 통과(2026-07-29, 실기기)**: 회원 기록 4건이 **읽기 전용**으로 보이고 수정·삭제 버튼 없음(RLS 과다 허용 아님). 회원 측 **작성** 동작은 로그아웃이 필요해 미확인.
- [ ] `pg_cron` 활성화 확인 + 수업 전날 안내 자동 적재 동작(1.8)
- [ ] 회원 예약 신청 → 트레이너 승인/거절 end-to-end (회원 `requested` → `scheduled`)
- [x] Edge Function 3종(`generate-message-draft`/`generate-memo-draft`/`delete-account`) 배포 + `LLM_API_KEY` 시크릿 설정 ✅ (2026-07-18)
- [ ] AI-B/AI-C 생성 → 검수 → 승인/확정 end-to-end (회원 `ai_consent=true`)
- [ ] **AI 재등록 유도 멘트**(`generate-renewal-pitch`) 배포 + 재등록 알림 → 진척 분석 → 승인·발송 end-to-end
- [ ] 회원 가입(초대 코드) → 연결 → 회원 홈 진입

### 다음 구현
1. ✅ **회원 홈** — 다음 수업 + 잔여 횟수 (회원 로드맵 ②) — `features/member/home/`
2. ✅ **내 수업 기록 열람** (③) — `features/member/records/`
3. ✅ **받은 안내 + 트레이너 발송(sent)** (④) — `features/member/notices/` + 트레이너 `markSent`
4. ✅ **예약 신청** (⑤) — `features/member/booking/` + 트레이너 승인/거절(예약 화면 승인 대기 섹션·홈 배지)
5. ✅ **변화 추이 그래프** (S1 / 2.2) — 중량 + 인바디. `features/member/progress/`(CustomPainter 차트)
   + 트레이너 인바디 입력(`features/trainer/member_card/body_measurement*`) + 0023 마이그레이션.
6. ✅ **회원 채팅** (S2 / 2.3) — 트레이너↔회원 1:1 실시간. 공용 `features/chat/` + 0024(RLS·실시간).
   알림 시간대 설정은 FCM 도입 시로 보류.
7. ✅ **출석 달력 + 스트릭** (운톡 P1, 2026-06-16) — `features/member/attendance/`. PT 완료+셀프 기록을
   날짜 집합으로 모아 커스텀 월 그리드(PT 파랑/셀프 주황, 전체기간 이동). 홈에 "이번 달 N일·연속" 배지.
   순수 도메인 `AttendanceStreakCalculator`(+단위테스트 9종). 상세: `docs/untok_improvement_plan.md` §5 C·D.
8. **1.12 베타 배포** — **iOS/TestFlight** ← 다음. 실행 순서·블로커는 `docs/ios_beta_plan.md` §6.
   가장 급한 것은 **Apple Developer Program 등록**(승인 며칠~2주, 우리가 단축 불가) —
   나머지 코드 배선(ios 폴더 생성·Info.plist 권한 문구·URL scheme·아이콘)은 그 사이에 병행.

### Phase 1 DoD 잔여
- [~] AI 검수 흐름 통합 테스트(RLS·UX) — DoD 2) : **클라 게이트 불변식 단위 테스트 완료**(2026-07-18) —
  상태 전이 payload(수정 시 approved_at=null 재검수 강제·발송은 in_app·승인 시점 보존)와
  회원 노출 규칙(`isVisibleToMember`=sent 만)을 `ai_review_gate_test`/`notification_status_test`로 고정.
  AI-B·재등록 유도 멘트가 공유하는 게이트를 회귀 방지. RLS/CHECK **자체**의 DB 강제는 0007 검증 SQL 로 별도 확인(오프라인 하네스 범위 밖).
- [ ] 친구 1주일 실사용 (DoD 1)

---

## 9. 문서 연계

> 전체 문서 지도(활성/아카이브 구분 포함)는 **[`docs/shipped.md`](shipped.md) §5** 에 있다.

| 문서 | 역할 |
|------|------|
| `develop_plan.md` (본 문서) | **설계 정본** — 앞으로 할 일·의사결정. 결정 바꿀 땐 여기부터 |
| `shipped.md` | 구현 완료 현황 + **지켜야 할 제약** |
| `src/supabase/migrations/README.md` | **스키마 정본** (⚠ `data_model.md` 아님 — 그건 낡은 초안) |
| `design_*.md` 5종 | 기능별 상세 설계 (체형분석·고스트·영상트래킹·동작코칭·영상시스템) |
| `e2e_verification_script.md` / `qa_regression_checklist.md` | 검증 대본 / 회귀 점검 |
| `social_login_console_setup.md` | 콘솔 설정 절차 (리포 밖 작업) |
| `ios_beta_plan.md` | **iOS/TestFlight 베타 배포 정본** (1.12) — 블로커·계정 작업·결정 사항·iOS 재검증 항목 |
