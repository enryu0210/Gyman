# Gyman — Claude 작업 지침

## 프로젝트
헬스장 PT 트레이너 앱. Flutter(`src/app/`) + Supabase(`src/supabase/`).
모든 설계 결정의 출처는 `docs/develop_plan.md` — 결정 바꿀 때 그 파일을 먼저 갱신.

## 빌드 환경 (중요)
- **프로젝트 경로에 한글/non-ASCII 절대 금지** — Gradle이 빌드 거부함. 새 하위 프로젝트도 ASCII 경로 유지.
- **pub cache와 프로젝트는 같은 드라이브에 둘 것** — 다른 드라이브면 Kotlin incremental 컴파일의 cross-drive 상대 경로 계산이 깨져 `kotlin.incremental=false` 회피책이 필요해짐. 환경 강제할 수 없을 땐 `src/app/android/gradle.properties`에 그렇게 둠.
- 검증 체크리스트: `cd src/app && flutter pub get && flutter analyze && flutter test` → 통과 후 `flutter build apk --debug`.
- 빌드가 "Could not close incremental caches" / 파일 lock으로 깨지면 java/kotlin/gradle 데몬 종료 후 `flutter clean` 재시도. IDE에서 프로젝트 열어두면 Gradle sync와 충돌하므로 빌드 동안 닫기.
- 본인 머신 한정 환경 메모(설치 경로, JDK 버전 등)는 `CLAUDE.local.md`에 — gitignore 처리되어 공유되지 않음.
- `git` 명령은 항상 `git -C C:/dev/Gyman ...` 절대 경로로 — Bash 도구 cwd 드리프트로 `src/app/src/app/...` 이중화 사고 회피.

## 코드/구조
- `lib/{core,data,domain,features}` (develop_plan.md §1). features 하위: `auth`, `trainer/{session_log,member_card,booking,renewal}`, `member`, `admin`.
- `domain/`은 Flutter 의존 0의 순수 Dart. 재등록 계산/잔여 횟수/가시성은 **단위 테스트 필수** (develop_plan.md §5.1).
- 회원 식별자(0013 이후): `member_profiles.id` 가 PK, `user_id` 는 nullable UNIQUE FK (앱 미가입 회원 지원). 회원 참조 FK는 모두 `id`. 회원 측 RLS는 `current_member_profile_id()` 헬퍼 경유 — `auth.uid()` 직접 비교 금지.
- 의존성 결정(고정): `flutter_riverpod` / `go_router` / `supabase_flutter` / `flutter_dotenv` / `intl`. 추가·교체 시 develop_plan.md §0 표를 먼저 갱신.
- Supabase 테이블 추가 시 **마이그레이션 + RLS 정책 둘 다** 작성. 회원/트레이너 가시성 분리가 본 제품의 핵심 요구사항이라 RLS 누락은 즉시 베타 중단 사유.
- 잔여 횟수 표시 = DB `v_contract_status` view (UI source of truth). 도메인 `RemainingSessionsCalculator`는 audit/단위테스트용. 두 식이 어긋나면 베타 중단 사유.
- Supabase Dart SDK 는 multi-table 트랜잭션 미지원 — 두 테이블 변경 시 보상 트랜잭션 (1단계 성공 + 2단계 실패 → 1단계 hard delete). 예: `SessionRepository.createDoneSession`. 본격 운영 단계엔 SQL RPC 로 이전 검토.

## SQL 마이그레이션
- 멱등 패턴 필수: `CREATE OR REPLACE FUNCTION`, `DROP POLICY IF EXISTS … CREATE POLICY`, `ADD COLUMN IF NOT EXISTS`. 사용자가 SQL Editor에서 부분 적용 후 재실행하는 일이 잦음.
- PK/UNIQUE 변경 시 순서: **참조 FK 모두 DROP → PK 교체 → FK 재추가**. PG는 의존 객체가 있으면 PK 드롭 거부.
- 이미 적용된 파일 수정 금지 — 새 번호 파일(`0013_*.sql`, `0014_*.sql`) 추가.
- **PostgREST는 view에 embed(`!inner`) 불가** (view엔 FK 없음) → base 테이블을 1차 소스로 조회하고 view는 id로 별도 조회해 병합. (재등록 알림 조회 실패 사례)
- PG15+ view는 `security_invoker=false`가 기본이라 base RLS를 우회할 수 있음 → RLS 의존 view엔 `ALTER VIEW … SET (security_invoker=true)`.
- 로그인 전/미연결 사용자가 RLS로 못 닿는 작업(초대 코드 검증·연결 등)은 좁은 `SECURITY DEFINER` RPC + `GRANT EXECUTE TO anon/authenticated`.

## Dart 패턴
- `library;` directive 위치: doc comment 직후, **import 앞**. import 뒤에 두면 `library_directive_not_first` 에러.
- Doc comment 내 제네릭은 백틱으로 감쌀 것: `` `AsyncValue<void>` `` — 아니면 `unintended_html_in_doc_comment`.
- `Env` 등 환경변수 getter는 dotenv 미초기화(테스트) 대비 try-catch로 빈 문자열 폴백.
- Repository row 매핑: `static T _fromRow(Map<String,dynamic>)` + `static DateTime? _parseDate(dynamic)` 헬퍼 한 쌍. `date` 컬럼은 `YYYY-MM-DD` 문자열로 INSERT/UPDATE (`toIso8601String()`은 시각이 같이 감).
- PG `COUNT()` / 집계는 bigint → Dart에서 `(v as num).toInt()` 로 캐스팅. `as int` 직접하면 view 조회 시 런타임 타입 오류.
- `supabase_flutter` 가 export 하는 auth `Session` 이 도메인 `Session` 과 이름 충돌 → 도메인 측 import 하는 파일에서 `import 'package:supabase_flutter/supabase_flutter.dart' hide Session;`. 다른 도메인 모델명이 SDK 와 겹치면 같은 패턴.
- Flutter 3.32+ 변경 API: `DropdownButtonFormField` 는 `value` → `initialValue`. `RadioListTile` 은 `RadioGroup<T>(groupValue/onChanged)` 로 감싸고 자식엔 `value` 만. `RadioGroup.onChanged` 가 `ValueChanged<T?>` (non-nullable) 라 비활성화는 `null` 대신 `IgnorePointer(ignoring: ...)` 로 입력 차단.
- `intl` `DateFormat('...', 'ko')` 는 `initializeDateFormatting('ko')` (`intl/date_symbol_data_local.dart`) 선행 호출 필요. 현재 main.dart 미초기화 — 한국어 요일 필요해지면 main.dart 보강. 그 전까지 ASCII 포맷만.

## Edge Functions / LLM (Supabase)
- CLI는 글로벌 설치 없이 `npx supabase`(검증 2.101.0). 명령은 **`src/`에서** 실행 — config는 `src/supabase/config.toml`(project_id=gyman).
- 함수는 **개별 배포** — `functions deploy <name>`은 그 함수만 올림. 미배포 함수 호출 시 클라엔 `ClientException: Failed to fetch`(404 아님).
- LLM 키 등 시크릿은 `supabase secrets set`로 **서버에만**, 클라 노출 금지. 회원 PII는 LLM 전송 전 `{{NAME}}` 토큰으로 마스킹 후 응답에서 정규식 복원.
- 함수 내 DB 접근은 **호출자 JWT 컨텍스트**(`createClient(url, anon, {global:{headers:{Authorization}}})`)로 → RLS 그대로 적용, service_role 불필요. 회원 데이터 함수는 `verify_jwt` 기본(true) 유지, 공개 헬스체크만 false.
- LLM 공급자 = **Google Gemini**(`gemini-3.5-flash`, env `LLM_MODEL`). **thinking 모델이라** `generationConfig.thinkingConfig.thinkingBudget=0` + `candidates[0].content.parts`에서 `thought!==true`만 join + `maxOutputTokens` 넉넉히. 안 하면 추론이 본문에 샘.
- 환각 억제: "기록에 없는 내용 지어내지 마라" 그라운딩 + 불릿 최소 개수 강제 금지 + 입력 비면 생성 차단. LLM 결과는 항상 트레이너 검수(draft) 게이트 통과.
- `functions.invoke` 실패는 `FunctionException`(`.details`=본문 JSON)으로 throw; 네트워크/미배포는 일반 예외 → **둘 다 잡아** code별 폴백(`AiGenerationException`).

## UI/Riverpod 패턴
- 액션 컨트롤러: `AutoDisposeAsyncNotifier<void>` (Add/Edit/Delete 묶음). 성공 시 영향받는 provider만 `ref.invalidate`. SnackBar는 호출자가, 컨트롤러는 상태만.
- go_router: 홈→형제 최상위 라우트로 `context.go`는 스택을 교체해 **뒤로가기 버튼이 안 생김**. 드릴인 이동은 `context.push`.
- 액션 컨트롤러 메서드명에 `update` 금지 — `AutoDisposeAsyncNotifier.update(FutureOr<void> Function(T))` 와 시그니처 충돌 (invalid_override 에러). `editXxx` / `changeStatus` 등 동사+명사로.
- 엔티티-by-id 조회: `FutureProvider.family<T?, String>` — id 별 캐시 분리 + 부분 invalidate 가능.
- 다이얼로그 진입점: `Future<bool?> showXxxDialog(BuildContext, ...)`, 성공 시 true 반환. async gap 직후 `if (!mounted) return;` 필수.
- 화면은 `features/<role>/<area>/` 하위에 `<area>_repository.dart` / `<area>_providers.dart` / `<area>_screen.dart` / `add_<area>_dialog.dart` 패턴으로 co-locate.

## 보안
- `.env`는 커밋 금지(`.gitignore` 처리). `.env.example`만 커밋.
- `service_role` 키는 클라이언트에 절대 두지 않음 — `anon` 키만, 보안은 RLS로.
- LLM(외부 API) 호출 시 회원 식별정보(PII) 마스킹 필수 (develop_plan.md §6).

## 커밋
- 메시지: `feat(scope): Phase X.Y 설명` 또는 `docs: 설명`. 한국어 본문, "왜" 위주.
- Phase 단위로 커밋. analyze/test/build 통과 후 push.
- `flutter`/`pub get`이 `src/app/windows/flutter/generated_plugin_*`를 LF/CRLF만 바꿔 더럽힘 → 커밋 전 `git checkout -- src/app/windows/flutter/`로 제외.
