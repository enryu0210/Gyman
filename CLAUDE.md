# Gyman — Claude 작업 지침

## 프로젝트
헬스장 PT 트레이너 앱. Flutter(`src/app/`) + Supabase(`src/supabase/`).
모든 설계 결정의 출처는 `docs/develop_plan.md` — 결정 바꿀 때 그 파일을 먼저 갱신.

## 빌드 환경 (중요)
- **프로젝트 경로에 한글/non-ASCII 절대 금지** — Gradle이 빌드 거부함. 현재 위치 `F:\dev\Gyman`은 그 이유로 이동된 것. 새 하위 프로젝트도 ASCII 경로 유지.
- `src/app/android/gradle.properties`의 `kotlin.incremental=false` 유지 — pub cache(C:)와 프로젝트(F:)가 다른 드라이브여서 cross-drive 상대 경로 계산이 깨지는 이슈 회피. 같은 드라이브로 정리되면 다시 켜도 됨.
- 검증 체크리스트: `cd src/app && flutter pub get && flutter analyze && flutter test` → 통과 후 `flutter build apk --debug`.
- 빌드가 "Could not close incremental caches" / 파일 lock으로 깨지면 java/kotlin/gradle 데몬 종료 후 `flutter clean` 재시도. IDE에서 프로젝트 열어두면 Gradle sync와 충돌하므로 빌드 동안 닫기.

## 코드/구조
- `lib/{core,data,domain,features}` (develop_plan.md §1). features 하위: `auth`, `trainer/{session_log,member_card,booking,renewal}`, `member`, `admin`.
- `domain/`은 Flutter 의존 0의 순수 Dart. 재등록 계산/잔여 횟수/가시성은 **단위 테스트 필수** (develop_plan.md §5.1).
- 의존성 결정(고정): `flutter_riverpod` / `go_router` / `supabase_flutter` / `flutter_dotenv` / `intl`. 추가·교체 시 develop_plan.md §0 표를 먼저 갱신.
- Supabase 테이블 추가 시 **마이그레이션 + RLS 정책 둘 다** 작성. 회원/트레이너 가시성 분리가 본 제품의 핵심 요구사항이라 RLS 누락은 즉시 베타 중단 사유.

## 보안
- `.env`는 커밋 금지(`.gitignore` 처리). `.env.example`만 커밋.
- `service_role` 키는 클라이언트에 절대 두지 않음 — `anon` 키만, 보안은 RLS로.
- LLM(외부 API) 호출 시 회원 식별정보(PII) 마스킹 필수 (develop_plan.md §6).

## 커밋
- 메시지: `feat(scope): Phase X.Y 설명` 또는 `docs: 설명`. 한국어 본문, "왜" 위주.
- Phase 단위로 커밋. analyze/test/build 통과 후 push.
