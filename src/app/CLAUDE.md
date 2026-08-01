# Gyman — Flutter 앱(`src/app/`) 작업 지침

> 이 파일은 `src/app/` 하위 파일을 다룰 때만 로드됩니다(지연 로딩).
> 프로젝트 전역 규칙·빌드 환경·보안·커밋 규칙은 리포 루트 `CLAUDE.md` 참조.

## 디자인 시스템
- **시각/UI 결정 전 `DESIGN.md`(리포 루트)를 먼저 읽는다.** 색·폰트·간격·형태의 단일 출처.
- 무드 = "블랙 + 볼트 라임" 에너제틱 스포츠. 구현체 = `lib/core/theme/app_theme.dart`(`ColorScheme` + 컴포넌트 테마) + `AppTheme` 상수(`ink`/`volt`/`onVolt`).
- **볼트 라임(`#C6FF00`)은 "채우기 배경 + 그 위 잉크색 글씨"로만** — 밝은 배경에 라임을 텍스트/아이콘 색으로 쓰면 대비 실패(안 보임). 강조 텍스트는 잉크(라이트)/`primary`(다크=볼트) 사용.
- 폰트 = **Pretendard** 가변폰트(`assets/fonts/PretendardVariable.ttf`, OFL). google_fonts 금지(deps 지침·오프라인).
- **이모지를 섹션 마커/아이콘으로 쓰지 않는다** — Material `*_outlined` 라인 아이콘 사용. (AI-slop 회피)
- 하드코딩 Material shade 색(`Colors.red.shade50` 등)은 다크 카드 위에서 밝은 블록으로 깨짐 → 밝기별 분기(`colors.brightness == Brightness.dark`)나 `ColorScheme` 역할 사용. (재등록 알림 사례)
- DESIGN.md와 app_theme.dart가 어긋나면 DESIGN.md를 기준으로 맞춘다.

## 소셜 로그인
- 클라 코드는 완성. 리디렉트가 커스텀 스킴(`io.supabase.gyman://login-callback`)이라 **웹에선 OAuth 라운드트립 불가 → 안드로이드에서만 테스트**. 실제 완료는 Supabase/Google/Kakao 콘솔 설정에 의존(리포 밖, 코드로 확인 불가). 상세 `docs/social_login_plan.md`.

## Dart 패턴
- 맵 리터럴의 조건부 엔트리는 `if (v != null) 'k': v` 가 아니라 **null-aware 엔트리** `'k': ?v` (Dart 3.9+, 린트 `use_null_aware_elements`).
- `library;` directive 위치: doc comment 직후, **import 앞**. import 뒤에 두면 `library_directive_not_first` 에러.
- Doc comment 내 제네릭은 백틱으로 감쌀 것: `` `AsyncValue<void>` `` — 아니면 `unintended_html_in_doc_comment`.
- `Env` 등 환경변수 getter는 dotenv 미초기화(테스트) 대비 try-catch로 빈 문자열 폴백.
- Repository row 매핑: `static T _fromRow(Map<String,dynamic>)` + `static DateTime? _parseDate(dynamic)` 헬퍼 한 쌍. `date` 컬럼은 `YYYY-MM-DD` 문자열로 INSERT/UPDATE (`toIso8601String()`은 시각이 같이 감).
- Repository 조회 컬럼은 `static const _columns = 'a, b, c'` 한 곳에 모으되, **테이블에 컬럼 추가 시 이 SELECT 문자열도 같이 갱신**할 것 — 빠뜨리면 매핑은 통과하고 그 필드만 조용히 null(분석/런타임 에러 없음). 모델·마이그레이션·`_columns` 셋을 한 묶음으로 수정. (`condition_score` 누락 버그 사례)
- PG `COUNT()` / 집계는 bigint → Dart에서 `(v as num).toInt()` 로 캐스팅. `as int` 직접하면 view 조회 시 런타임 타입 오류.
- `supabase_flutter` 가 export 하는 auth `Session` 이 도메인 `Session` 과 이름 충돌 → 도메인 측 import 하는 파일에서 `import 'package:supabase_flutter/supabase_flutter.dart' hide Session;`. 다른 도메인 모델명이 SDK 와 겹치면 같은 패턴.
- Flutter 3.32+ 변경 API: `DropdownButtonFormField` 는 `value` → `initialValue`. `RadioListTile` 은 `RadioGroup<T>(groupValue/onChanged)` 로 감싸고 자식엔 `value` 만. `RadioGroup.onChanged` 가 `ValueChanged<T?>` (non-nullable) 라 비활성화는 `null` 대신 `IgnorePointer(ignoring: ...)` 로 입력 차단.
- `ThemeData` 컴포넌트 테마는 `*ThemeData` 형 사용: `cardTheme: CardThemeData(...)`, `dialogTheme: DialogThemeData(...)` (구 `CardTheme`/`DialogTheme` 아님, Flutter 3.44). flat 룩은 `elevation:0` + `surfaceTintColor: Colors.transparent`.
- `intl` `DateFormat('...', 'ko')` 는 `initializeDateFormatting('ko')` (`intl/date_symbol_data_local.dart`) 선행 호출 필요. 현재 main.dart 미초기화 — 한국어 요일 필요해지면 main.dart 보강. 그 전까지 ASCII 포맷만.
- **수업 시각(`scheduled_at` 등 timestamptz) = "벽시계 그대로" 컨벤션:** 쓰기는 로컬 `DateTime`→`toIso8601String()`(offset 없는 naive → PG가 UTC로 적재), 읽기는 `DateTime.parse`만 하고 **`.toLocal()` 금지**(부르면 +9h 밀려 오후 2시가 23시로 — `member_attendance` 버그 사례). 다른 read repo 전부 toLocal 미사용. 진짜 UTC 왕복은 쓰기도 `toUtc()`인 경우만(`support_inquiries`). 단일 시간대 가정 — 다중 tz 필요 시 전면 정리.

## UI/Riverpod 패턴
- 액션 컨트롤러: `AutoDisposeAsyncNotifier<void>` (Add/Edit/Delete 묶음). 성공 시 영향받는 provider만 `ref.invalidate`. SnackBar는 호출자가, 컨트롤러는 상태만.
- go_router: 홈→형제 최상위 라우트로 `context.go`는 스택을 교체해 **뒤로가기 버튼이 안 생김**. 드릴인 이동은 `context.push`.
- 액션 컨트롤러 메서드명에 `update` 금지 — `AutoDisposeAsyncNotifier.update(FutureOr<void> Function(T))` 와 시그니처 충돌 (invalid_override 에러). `editXxx` / `changeStatus` 등 동사+명사로.
- 엔티티-by-id 조회: `FutureProvider.family<T?, String>` — id 별 캐시 분리 + 부분 invalidate 가능.
- 다이얼로그 진입점: `Future<bool?> showXxxDialog(BuildContext, ...)`, 성공 시 true 반환. async gap 직후 `if (!mounted) return;` 필수.
- 함수형 `showXxxDialog`에서 `TextEditingController`는 `showDialog` **호출 전 1회 생성**해 클로저로 캡처(리빌드해도 한글 IME 조합 안 끊김) + `try/finally`로 `dispose()`. build() 안에서 컨트롤러 생성 금지.
- `AsyncValue.when`의 로딩/에러/빈 상태는 `core/widgets/async_state_views.dart`의 `AppLoadingView`/`AppErrorView`/`AppEmptyView`/`AppInlineError`(카드용) 사용 — 로컬 `_ErrorView`/`_EmptyView` 새로 정의 금지. raw 예외 문자열은 사용자에 직접 노출 말고 `AppErrorView(detail:)`로만(작은 회색).
- pull-to-refresh가 필요한 빈 상태는 `ListView` 기반이어야 함 — Center 기반 `AppEmptyView`를 `ListView` child로 넣으면 unbounded height로 깨짐(`member_booking`/`ai_review` 빈 뷰가 로컬 ListView 변형을 유지하는 이유).
- 타이핑에 반응하는 **파생 UI**(입력값 기반 배너·큐)는 상위 `setState` 대신 `ValueListenableBuilder`(컨트롤러 1개) / `ListenableBuilder`+`Listenable.merge`(여러 개)로 **그 블록만** 갱신 — 폼 전체 리빌드는 무겁고 한글 IME 조합에도 불리.
- 화면은 `features/<role>/<area>/` 하위에 `<area>_repository.dart` / `<area>_providers.dart` / `<area>_screen.dart` / `add_<area>_dialog.dart` 패턴으로 co-locate.
