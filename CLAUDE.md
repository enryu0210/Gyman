# Gyman — Claude 작업 지침

## 프로젝트
헬스장 PT 트레이너 앱. Flutter(`src/app/`) + Supabase(`src/supabase/`).
모든 설계 결정의 출처는 `docs/develop_plan.md` — 결정 바꿀 때 그 파일을 먼저 갱신.
- **작업 시작 전 `docs/shipped.md` 를 읽을 것** — 이미 구현된 것과 **지켜야 할 제약**(가시성·식별자·의료 안전선·AI 원칙)이 거기 모여 있다. 새로 짜기 전에 이미 있는지부터 확인.
- `docs/data_model.md` 와 `docs/wireframes/` 는 **낡은 아카이브** — 스키마는 `src/supabase/migrations/`, 화면은 실제 코드가 정본.
- **Flutter 앱 관련 지침**(디자인 시스템·소셜 로그인·Dart 패턴·UI/Riverpod)은 `src/app/CLAUDE.md` — 해당 폴더 작업 시 자동 로드.
- **Supabase 백엔드 지침**(SQL 마이그레이션·Edge Functions/LLM)은 `src/supabase/CLAUDE.md` — 해당 폴더 작업 시 자동 로드.

## 빌드 환경 (중요)
- **프로젝트 경로에 한글/non-ASCII 절대 금지** — Gradle이 빌드 거부함. 새 하위 프로젝트도 ASCII 경로 유지.
- **pub cache와 프로젝트는 같은 드라이브에 둘 것** — 다른 드라이브면 Kotlin incremental 컴파일의 cross-drive 상대 경로 계산이 깨져 `kotlin.incremental=false` 회피책이 필요해짐. 환경 강제할 수 없을 땐 `src/app/android/gradle.properties`에 그렇게 둠.
- 검증 체크리스트: `cd src/app && flutter pub get && flutter analyze && flutter test` → 통과 후 `flutter build apk --debug`.
- 빌드가 "Could not close incremental caches" / 파일 lock으로 깨지면 java/kotlin/gradle 데몬 종료 후 `flutter clean` 재시도. IDE에서 프로젝트 열어두면 Gradle sync와 충돌하므로 빌드 동안 닫기.
- **AGP 9는 전이(transitive) `implementation`을 컴파일 클래스패스에 안 올림** — 네이티브 플러그인이 `class file for … not found`로 깨지면 그 서브프로젝트에만 의존성 주입: `android/build.gradle.kts`에 `subprojects { if (name == "<plugin>") afterEvaluate { dependencies.add("implementation", "<artifact>") } }`. (camera_android_camerax ↔ androidx.concurrent:concurrent-futures 사례)
- **APK 크기는 `flutter build apk --release --split-per-abi`로 잴 것** — 기본 fat APK는 전 ABI 합계라 실제 설치 크기의 2배 가까이 나옴. 판단 기준은 arm64-v8a.
- 본인 머신 한정 환경 메모(설치 경로, JDK 버전 등)는 `CLAUDE.local.md`에 — gitignore 처리되어 공유되지 않음.
- `git` 명령은 항상 `git -C F:/dev/Gyman ...` 절대 경로로 — Bash 도구 cwd 드리프트로 `src/app/src/app/...` 이중화 사고 회피.

## 코드/구조
- 아키텍처 = `lib/{core,data,domain,features}` 4계층 (세부 폴더 구조는 develop_plan.md §1).
- **설계 문서의 "선행 조건/블로커"는 착수 전 실제 마이그레이션·코드로 재확인** — 이미 해결된 경우가 있다(0008 FK 빚은 0013에서 처리됐는데 문서만 안 고쳐져 있었음).
- 네이티브 플러그인 실현성 검증은 **PoC 브랜치 + 별도 진입점**(`lib/main_poc.dart` + `flutter run -t`)으로 — 프로덕션 라우터·`main.dart` 무수정, 엎어지면 브랜치째 폐기.
- **PoC 앱은 `-Ppoc=true` 로 빌드**(`flutter run -t lib/main_poc.dart -Ppoc=true`) — `applicationId` 가 `com.gyman.poc` 로 갈려 프로덕션 앱과 나란히 설치된다. **빼먹으면 프로덕션 앱을 덮어쓴다.** flavor 대신 Gradle 프로퍼티를 쓴 이유는 flavor 가 모든 빌드에 `--flavor` 를 강제해 아래 검증 명령을 깨기 때문(`docs/poc_cv_track_results.md` §7).
- **빌드 설정을 임시로 고쳤으면 저장소에 남기거나 즉시 되돌릴 것** — 로컬에서만 고친 `applicationId` 가 커밋 안 돼 사라진 사고가 있었다(2026-07-26). 다음 빌드가 조용히 다른 앱을 덮어쓴다.
- `domain/`은 Flutter 의존 0의 순수 Dart. 재등록 계산/잔여 횟수/가시성은 **단위 테스트 필수** (develop_plan.md §5.1). 네이티브 플러그인 결과는 **어댑터로 도메인 타입에 변환** — 도메인이 플러그인 타입을 알면 플러그인 도입 전에 테스트를 못 짠다(`posture_metrics` ↔ `MlKitPoseAdapter`).
- 라이브 Supabase 통합 테스트 하네스는 없음(테스트는 전부 순수 Dart) → 리포지토리 write payload/집계는 **순수 static 함수로 분리**해 SupabaseClient 없이 단위 테스트(`AiReviewRepository.approvePayload`·`admin_dashboard_repository` 선례). RLS/CHECK 자체는 마이그레이션 검증 SQL 로만 확인.
- 회원 식별자(0013 이후): `member_profiles.id` 가 PK, `user_id` 는 nullable UNIQUE FK (앱 미가입 회원 지원). 회원 참조 FK는 모두 `id`. 회원 측 RLS는 `current_member_profile_id()` 헬퍼 경유 — `auth.uid()` 직접 비교 금지.
- 핵심 의존성은 **고정** — 추가·교체 시 develop_plan.md §0 표를 먼저 갱신(현재 목록은 `pubspec.yaml` / §0 참조).
- Supabase 테이블 추가 시 **마이그레이션 + RLS 정책 둘 다** 작성. 회원/트레이너 가시성 분리가 본 제품의 핵심 요구사항이라 RLS 누락은 즉시 베타 중단 사유.
- 잔여 횟수 표시 = DB `v_contract_status` view (UI source of truth). 도메인 `RemainingSessionsCalculator`는 audit/단위테스트용. 두 식이 어긋나면 베타 중단 사유.
- Supabase Dart SDK 는 multi-table 트랜잭션 미지원 — 두 테이블 변경 시 보상 트랜잭션 (1단계 성공 + 2단계 실패 → 1단계 hard delete). 예: `SessionRepository.createDoneSession`. 본격 운영 단계엔 SQL RPC 로 이전 검토.

## 보안
- `.env`는 커밋 금지(`.gitignore` 처리). `.env.example`만 커밋.
- `service_role` 키는 클라이언트에 절대 두지 않음 — `anon` 키만, 보안은 RLS로.
- LLM(외부 API) 호출 시 회원 식별정보(PII) 마스킹 필수 (develop_plan.md §6).

## 커밋
- 메시지: `feat(scope): Phase X.Y 설명` 또는 `docs: 설명`. 한국어 본문, "왜" 위주.
- Phase 단위로 커밋. analyze/test/build 통과 후 push.
- `flutter`/`pub get`이 `src/app/windows/flutter/generated_plugin_*`를 LF/CRLF만 바꿔 더럽힘 → 커밋 전 `git checkout -- src/app/windows/flutter/`로 제외.
