# 구현 완료 현황 (Shipped) — 결과만

> **이 문서의 용도:** "지금 앱에 무엇이 있고, 앞으로 코드를 만질 때 무엇을 지켜야 하는가"만 모은다.
> **왜 그렇게 됐는지(과정·대안 비교)는 여기 없다** — git 이력과 각 원본 설계 문서에 있다(§5).
> 앞으로 할 일은 여기 없다 → `docs/develop_plan.md`.
>
> 최종 갱신: 2026-08-10 (UI 1차 개편 — 트레이너 앱 셸 + 홈 재구성 적용)

---

## 1. 지금 앱에 있는 것

### 트레이너
| 기능 | 위치 |
|---|---|
| 로그인·역할 분기 (트레이너/회원/관리자) | `features/auth/` |
| 회원 CRUD + **앱 미가입 회원 등록** + 초대 코드 발급 | `features/trainer/member/` |
| PT 계약 + 잔여 횟수 | `features/trainer/contract/` |
| 수업 기록 (1분 입력·이전기록 복사·즐겨찾기 종목) | `features/trainer/session_log/` |
| 예약 승인/거절·노쇼·취소 | `features/trainer/booking/` |
| 재등록 알림 (in-app) | `features/trainer/renewal/` |
| AI 검수 허브 (초안→승인→발송 게이트) | `features/trainer/ai_review/` |
| 회원 카드 — 전용 메모·인바디·영상·셀프기록·**체형 특이사항** | `features/trainer/member_card/` |
| 회원 1:1 채팅 + 대화 목록 + 방해금지 시간 | `features/chat/`, `features/trainer/chat/` |
| **고정 하단 탭 셸** (홈·회원·기록하기·일정·채팅) | `features/trainer/shell/`, `core/widgets/app_shell_scaffold.dart` |
| **홈 — 다음 수업 카드 + 오늘 타임라인 + 처리할 일** | `features/trainer/home/`, `domain/today_schedule.dart` |

### 회원
| 기능 | 위치 |
|---|---|
| 홈 (다음 수업·잔여 횟수·안읽음 배지) | `features/member/home/` |
| 내 수업 기록 열람 (트레이너 메모 제외) | `features/member/records/` |
| 변화 추이 그래프 (중량 + 인바디, CustomPainter 자체 구현) | `features/member/progress/` |
| 받은 안내 (+ 읽음 처리) | `features/member/notices/` |
| 예약 신청·철회 | `features/member/booking/` |
| 셀프 운동 기록 (컨디션 1~10) **+ 체형 특이사항 큐** | `features/member/self_log/` |
| 출석 달력 + 스트릭 | `features/member/attendance/` |
| 내 수업 영상 **+ 트레이너 시점 지적 표시** | `features/member/videos/` |
| PT 시작 전 로컬 알림 | `features/member/notifications/` |
| **고정 하단 탭 셸** (홈·일정·기록·채팅·내 정보) | `features/member/shell/`, `features/member/profile/` |
| FAQ (운동 상식 + 센터 PT 규정) | `features/faq/` |

### 관리자
| 기능 | 위치 |
|---|---|
| 대시보드 (매출·재등록·노쇼율·만료 임박) | `features/admin/dashboard/` |
| 센터 규정 + PT FAQ 관리 | `features/admin/center/` |
| 인앱 문의함 | `features/admin/support/` |

### 전 역할
설정·약관/동의·익명화 탈퇴(`features/settings/`, `features/legal/`), 소셜 로그인(카카오·구글)·비밀번호 재설정.

---

## 2. 백엔드 자산

- **마이그레이션 `0001~0041`** — 전부 적용 완료. 목록·역할은 `src/supabase/migrations/README.md`(정본).
- **Edge Function 5종** — `generate-message-draft` / `generate-memo-draft` / `generate-renewal-pitch` / `delete-account` / `health`. 배포·시크릿 설정 완료.
- **Storage 버킷 3종** (전부 비공개 + 단기 서명 URL):
  | 버킷 | 용도 | object key 첫 세그먼트(=권한 키) |
  |---|---|---|
  | `chat-images` | 채팅 사진 | 업로더 `user_id` |
  | `class-videos` | 수업 영상 | 대상 회원 `member_id` |
  | `body-photos` | 체형 사진 | 대상 회원 `member_id` |
- **LLM**: Google Gemini (`gemini-3.5-flash`), 키는 서버 시크릿에만.

---

## 3. 살아 있는 제약 ★

완료된 작업이 남긴 규칙들. **앞으로 코드를 만질 때 여기에 어긋나면 그건 버그다.**

### 3.1 가시성 — 이 제품의 핵심 요구사항
- **트레이너 전용 메모는 회원이 절대 못 본다.** RLS `notes_member_deny` + `visibility='trainer_only'` 이중.
- **AI 안내 메시지는 `status='sent'` 만 회원 노출.** `draft → approved → sent` 게이트. 수정하면 `approved_at=null` 로 되돌아가 재검수를 강제한다.
- **AI 체형분석은 `trainer_comment` 가 채워져야만 회원 노출.** RLS + 앱 `BodyAssessment.isVisibleToMember` 이중.
- **PG RLS 는 행 단위라 컬럼을 못 가린다** → 회원에게 숨길 컬럼은 **SELECT 목록에서 빼는 것**이 유일한 수단.
  현재 그렇게 방어 중인 컬럼: `session_records.next_memo`, `member_conditions.trainer_note`, `condition_coaching_rules.detail`.
- 회원 측 RLS 는 **항상 `current_member_profile_id()` 경유** — `auth.uid()` 직접 비교 금지.

### 3.2 식별자
- `member_profiles.id` 가 PK, `user_id` 는 nullable UNIQUE FK(앱 미가입 회원 지원).
- **회원 참조 FK 는 전부 `id`.** 신규 테이블도 예외 없음.

### 3.3 의료·법적 안전선 (4.8)
- 체형 제약은 **출처를 반드시 구분**한다 — `medical`(의료기관 진단) / `trainer_observation`(관찰, **진단 아님**). DB CHECK 로 강제.
- **`severity`(경중) 컬럼을 두지 않는다** — "중등도 측만증"은 의료 판단.
- **`action` 에 `avoid`(금지)를 두지 않는다** — "이 운동 하지 마세요"는 처방. `modify`(대체 권장)로만, 주체는 트레이너.
- 모르는 값은 **약한 쪽으로 흡수**한다(출처 불명 → 관찰, action 불명 → focus, flag 불명 → 측정 불가). 모호할 때 강한 주장으로 승격하면 근거 없는 권위/과잉 경고가 된다.

### 3.4 AI 원칙
- 이미지·영상은 **온디바이스**, 텍스트는 **서버(Edge Function)**. 신체 사진·영상은 분석 목적으로 외부 전송 0.
- LLM 호출 전 **PII 마스킹**(실명→`{{NAME}}`) + 회원 `ai_consent` 확인 + 일일 한도(`ai_call_logs`).
- LLM 이 죽어도 앱은 돌아야 한다 — 전부 수동 입력 폴백.
- **수치·판정은 규칙기반, LLM 은 문장만.** 코칭 큐도 체형 수치도 LLM 이 계산하지 않는다.

### 3.5 데이터 무결성
- **Supabase Dart SDK 는 멀티테이블 트랜잭션 미지원** → 2단계 쓰기는 보상 트랜잭션(1단계 성공 + 2단계 실패 → 1단계 hard delete). 선례: `SessionRepository.createDoneSession`, 영상 업로드, 체형 사진 업로드(예정).
- 잔여 횟수 표시의 정본은 DB view `v_contract_status`. 도메인 `RemainingSessionsCalculator` 는 audit/테스트용. **둘이 어긋나면 베타 중단 사유.**
- 수업 시각은 **"벽시계 그대로"** 컨벤션 — 읽을 때 `.toLocal()` 금지(부르면 +9h 밀림).

### 3.6 표시 원칙
- **틀린 정보를 띄우느니 아무것도 안 띄운다.** 종목 매칭 실패 → 큐 미표시. 키포인트 신뢰도 부족 → 수치 미표시(0 으로 채우지 않음).
- 못 잰 값은 **`null`, 0 이 아니다.** 0 은 "완벽히 수평" 같은 실제 의미를 갖는다.
- 회원에게 가는 판단에는 **근거를 함께** 표시한다(큐 옆 제약명 칩).

### 3.7 동의 근거 (0040·0041)
- **AI 전송 허용 판정은 `ai_consent_effective` 하나만 본다** — `ai_consent`(트레이너 기록) AND NOT `ai_consent_member_optout`(회원 거부). 두 값을 읽는 쪽마다 `AND` 를 직접 쓰면 언젠가 한 군데가 빠지고, **그 한 군데가 "동의 없이 전송"이 된다.**
- **회원 거부는 트레이너가 못 뒤집는다** — RLS 는 행 단위라 컬럼을 못 막고, 회원·트레이너가 같은 `authenticated` role 이라 컬럼 GRANT 도 못 쓴다 → `BEFORE UPDATE` 트리거로 강제.
- **신규 회원 등록에는 동의 확인이 필수다** — 앱 미가입 회원은 약관을 볼 수도, `user_consents` 에 행이 생길 수도 없어(PK 가 `auth.users.id`) 트레이너의 확인이 유일한 동의 근거다. `BEFORE INSERT` 트리거가 UI 우회까지 막는다. `0041` 이전 회원만 NULL 허용(소급 확인 불가) — 수정 화면에서 뒤늦게 채울 수 있다.
- **민감정보(건강정보) 동의는 별도 항목이고 선택이다.** 필수로 만들면 "선택"이라 써놓고 강제하는 셈. 단 **미동의 시 기능 자동 제한은 아직 없고, 문안도 그렇게 쓰지 않았다**(`legal_docs_gap_check.md` F-1).
- 동의 시각은 **UTC 로 기록한다** — 수업 시각의 "벽시계 그대로" 컨벤션을 여기 적용하면 KST 기준 9시간 미래로 적재돼 트리거의 미래시각 검사에 걸린다.
- **문안이 주장하는 것과 코드가 하는 것을 어긋나게 두지 말 것.** 대조 결과는 `legal_docs_gap_check.md` — 문안을 고치면 그 문서도 같이 갱신한다.

### 3.8 네비게이션 구조 (UI 1차 개편)
- **트레이너 경로는 셸 안(탭 루트)과 셸 밖(드릴인)으로 갈린다.** 탭 루트는 4개뿐 —
  `/trainer/home` · `/trainer/members` · `/trainer/booking` · `/trainer/chat`.
  회원 상세·수업 기록·1:1 채팅·AI 검수·설정은 **셸 밖 최상위 라우트**다.
- **드릴인 라우트를 브랜치 안으로 옮기지 말 것.** 브랜치에 속한 경로를 다른 탭에서
  `push` 하면 셸이 그 브랜치로 따라 옮겨가, 뒤로 나왔을 때 누르지도 않은 탭이 선택돼 있다.
  경로 문자열(`/trainer/members/:id`)은 계층처럼 생겼지만 라우트 계층상 **형제**다.
- **탭 루트로 이동은 `context.go`, 드릴인은 `context.push`.** 탭 루트를 push 하면
  같은 화면이 두 겹으로 쌓인다(회원 목록 사례).
- **AI 검수는 하단 탭에 두지 않는다** — 항상 처리해야 하는 핵심 업무처럼 보이면 안 되는
  기능이라 홈에서만 진입한다. 탭에 추가하려면 이 결정부터 뒤집을 것.
- **오늘 일정은 새 쿼리를 만들지 않는다** — 홈 타임라인은 예약 화면과 같은
  `trainerBookingsProvider(TrainerBookingRange.today)` 를 재사용한다. 그래야 수업
  저장·취소·승인 시 도는 기존 invalidate 경로에 홈이 자동으로 얹힌다. 별도 조회를
  파면 홈만 조용히 낡는다.
- **시각 의존 표시는 도메인 순수 함수로.** 예정→진행 중→기록 대기 판정은
  `domain/today_schedule.dart` 가 `now` 를 인자로 받아 계산하고 단위 테스트로 고정돼 있다.
  위젯 안에서 `DateTime.now()` 로 분기하면 경계에서 조용히 틀어진다.
- **"기록하기"를 회원 탭으로 넘기지 말 것.** 넘기는 순간 두 버튼이 같은 곳으로 가서
  가운데 강조 버튼이 존재 이유를 잃는다(실제로 그렇게 만들었다가 되돌림). 시트의
  모든 줄은 **기록 화면으로 직행**한다 — 회원 탭은 회원 카드로, 기록하기는 기록 입력으로.
- **회원 탭 루트도 5개뿐** — `/member/home` · `/member/attendance`(일정) · `/member/records`(기록)
  · `/member/chat` · `/member/profile`(내 정보). 나머지(예약 신청·변화 추이·셀프 기록·영상·
  안내·FAQ·설정)는 전부 셸 밖 드릴인이다. **회원 홈의 정보 우선순위 재구성(계획서 §3.3의
  1~5)은 아직 안 했다** — 셸만 얹은 상태.
- **탭에는 "보는 면", 버튼에는 "하는 동작".** 일정 탭 루트가 예약 신청 화면이 아니라
  출석 달력인 이유 — 달력은 지난 출석과 다가올 PT 를 반복해서 *열람*하는 면이고, 예약
  신청은 가끔 하는 *동작*이라 달력의 FAB 로 뺐다. (처음엔 반대로 짰다가 뒤집음)
- **회원 셸엔 가운데 강조 버튼이 없다.** 트레이너의 "수업 기록"처럼 매번 반복되는 단일
  핵심 동작이 회원에겐 없어서다. 억지로 하나 띄우면 강조의 의미만 닳는다.

### 3.9 컨트롤러 생명주기 (반복 함정)
- **모달/시트의 `TextEditingController` 는 그 시트의 `State` 가 소유한다.** 바깥에서 만들어
  `showModalBottomSheet(...).whenComplete(ctrl.dispose)` 로 정리하면 안 된다 — 그 future 는
  `Navigator.pop()` 시점에 완료되는데 시트는 **닫히는 애니메이션 동안 아직 리빌드된다.**
  죽은 컨트롤러에 `TextField` 가 리스너를 붙이려다 터지고, 실패한 빌드가
  `Duplicate GlobalKeys` · `_dependents.isEmpty` 2차 예외를 수십 개 낳아 화면이 빨갛게 덮인다.
  **에러 화면 맨 위 메시지가 아니라 로그의 *첫* 예외를 볼 것** — 나머지는 전부 파생이다.
  회귀 테스트: `test/features/start_record_sheet_test.dart`.
- 시트에서 화면 이동은 **pop 전에 라우터를 잡아 두고** 이동한다. pop 뒤의 context 는 곧
  사라질 요소를 가리켜 `GoRouter.of(context)` 재탐색이 안전하지 않다.

---

## 4. 완료된 개선 트랙 — 결론만

### 운톡(경쟁 앱) 불만 대응 — 8건 중 7건 반영 완료
| 불만 | 우리 대응 |
|---|---|
| 기록이 사라짐 | 서버 저장 + RLS. 로컬 전용 저장 없음 |
| 아이디/비번 찾기 불가·소셜 로그인 없음 | 소셜 로그인(카카오·구글) + 비번 재설정 |
| 운동 안 한 날 확인 어려움 | 출석 달력(PT/셀프 색 구분) + 스트릭 |
| 알림 없음 | PT 시작 전 **기기 로컬** 알림(FCM 없이) |
| 탈퇴 후 재가입 불가 | 익명화 탈퇴 — 동일 이메일 재가입 가능 |
| 문의 창구 없음 | 인앱 문의함 + 운영자 미처리 배지 |
| 막다른 길(dead-end) 버튼 | 미구현 기능 진입점 노출 금지 원칙 |

> 남은 1건 = 카카오 **네이티브 SDK**(앱 핸드오프). 현재는 인앱 브라우저 OAuth 로 동작. 원본: `untok_improvement_plan.md`.

### 소셜 로그인 (P2-E)
- **신규 Dart 의존성 0** — `supabase_flutter` 내장 `signInWithOAuth` + PKCE + 딥링크(`io.supabase.gyman://login-callback`).
- 코드·빌드 완료. **실제 동작은 콘솔 설정에 의존**(리포 밖이라 코드로 확인 불가) → 절차는 `social_login_console_setup.md`.
- 웹에선 커스텀 스킴이라 OAuth 왕복 불가 → **안드로이드에서만 테스트 가능**.

### 동작 습관·체형 제약 코칭 (4.8 L1·L2)
- 트레이너가 등록한 체형 제약이 **동작 패턴 8종**과 매칭돼, 회원이 그 운동을 만나는 지점에서 큐로 뜬다.
- 트레이너가 영상 특정 시점에 남긴 지적이 **회원 재생 시 같은 지점에** 뜬다.
- 앱은 판단하지 않는다 — 트레이너의 판단을 구조화해 나를 뿐.

### 체형분석 A단계 (4.2)
- 스키마·버킷·동의·계산 도메인까지 완료. **ML Kit·카메라는 아직 없다**(B단계).
- 계산부(`posture_metrics.dart`)는 ML Kit 비의존 순수 Dart라 지금 전부 테스트로 고정돼 있다.

---

## 5. 문서 지도

| 문서 | 상태 | 언제 보나 |
|---|---|---|
| `develop_plan.md` | **정본·활성** | 앞으로 할 일·의사결정. 결정 바꿀 땐 여기부터 |
| `shipped.md` (본 문서) | 활성 | "지금 뭐가 있나 / 뭘 지켜야 하나" |
| `src/supabase/migrations/README.md` | **정본·활성** | 스키마 현황 (data_model.md 아님) |
| `design_body_analysis.md` | 활성 (B~D 남음) | 체형분석 이어서 할 때 |
| `design_ghost_overlay.md` | 활성 (전부 남음) | 고스트 착수할 때 |
| `design_class_video_tracking.md` | 활성 (전부 남음) | 영상 트래킹 착수할 때 |
| `design_movement_coaching.md` | 활성 (L3 남음) | 자동 검출 착수할 때 |
| `design_class_videos.md` | 활성 (압축·썸네일 남음) | 영상 품질 개선할 때 |
| `e2e_verification_script.md` | 활성 | 실기기 검증 세션 돌릴 때 |
| `qa_regression_checklist.md` | 활성 | 회귀 점검 |
| `social_login_console_setup.md` | 활성 | 콘솔 설정 작업 |
| `ios_beta_plan.md` | **활성 (1.12 정본)** | iOS/TestFlight 배포 — 블로커·애플 계정 작업·iOS 재검증 항목 |
| `ui_renewal_phase1_plan.md` | 활성 (트레이너 완료 / 회원 셸 남음) | UI 개편 방향·범위. 회원 앱 셸 착수할 때 |
| `untok_improvement_plan.md` | **아카이브** | 코드 주석이 근거로 참조 — 배경 확인용 |
| `social_login_plan.md` | **아카이브** | 위와 동일 |
| `data_model.md` | **아카이브(낡음)** | ⚠ 0020 까지만 반영 — 스키마는 migrations 참조 |
| `wireframes/` | **아카이브(낡음)** | v0.1 초안. 실제 화면이 훨씬 앞서감 |
