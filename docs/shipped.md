# 구현 완료 현황 (Shipped) — 결과만

> **이 문서의 용도:** "지금 앱에 무엇이 있고, 앞으로 코드를 만질 때 무엇을 지켜야 하는가"만 모은다.
> **왜 그렇게 됐는지(과정·대안 비교)는 여기 없다** — git 이력과 각 원본 설계 문서에 있다(§5).
> 앞으로 할 일은 여기 없다 → `docs/develop_plan.md`.
>
> 최종 갱신: 2026-07-25 (마이그레이션 0001~0039 전부 적용 완료 시점)

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

- **마이그레이션 `0001~0039`** — 전부 적용 완료. 목록·역할은 `src/supabase/migrations/README.md`(정본).
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
| `untok_improvement_plan.md` | **아카이브** | 코드 주석이 근거로 참조 — 배경 확인용 |
| `social_login_plan.md` | **아카이브** | 위와 동일 |
| `data_model.md` | **아카이브(낡음)** | ⚠ 0020 까지만 반영 — 스키마는 migrations 참조 |
| `wireframes/` | **아카이브(낡음)** | v0.1 초안. 실제 화면이 훨씬 앞서감 |
