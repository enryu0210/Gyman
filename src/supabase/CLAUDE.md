# Gyman — Supabase 백엔드(`src/supabase/`) 작업 지침

> 이 파일은 `src/supabase/` 하위 파일을 다룰 때만 로드됩니다(지연 로딩).
> 프로젝트 전역 규칙·빌드 환경·보안·커밋 규칙은 리포 루트 `CLAUDE.md` 참조.

## SQL 마이그레이션
- 멱등 패턴 필수: `CREATE OR REPLACE FUNCTION`, `DROP POLICY IF EXISTS … CREATE POLICY`, `ADD COLUMN IF NOT EXISTS`. 사용자가 SQL Editor에서 부분 적용 후 재실행하는 일이 잦음.
- PK/UNIQUE 변경 시 순서: **참조 FK 모두 DROP → PK 교체 → FK 재추가**. PG는 의존 객체가 있으면 PK 드롭 거부.
- 이미 적용된 파일 수정 금지 — 새 번호 파일(`0013_*.sql`, `0014_*.sql`) 추가.
- **PostgREST는 view에 embed(`!inner`) 불가** (view엔 FK 없음) → base 테이블을 1차 소스로 조회하고 view는 id로 별도 조회해 병합. (재등록 알림 조회 실패 사례)
- PG15+ view는 `security_invoker=false`가 기본이라 base RLS를 우회할 수 있음 → RLS 의존 view엔 `ALTER VIEW … SET (security_invoker=true)`.
- 로그인 전/미연결 사용자가 RLS로 못 닿는 작업(초대 코드 검증·연결 등)은 좁은 `SECURITY DEFINER` RPC + `GRANT EXECUTE TO anon/authenticated`.
- 회원이 직접 INSERT 하는 테이블은 `member_id uuid NOT NULL DEFAULT current_member_profile_id()` 로 두면 클라가 id 를 안 넘겨도 되고, 위변조는 RLS `WITH CHECK (member_id = current_member_profile_id())` 가 막는다. (회원 rw / 트레이너 read-only 가시성 대칭은 `self_workout_logs` 0028 참조)

## Edge Functions / LLM
- CLI는 글로벌 설치 없이 `npx supabase`(검증 2.101.0). 명령은 **`src/`에서** 실행 — config는 `src/supabase/config.toml`(project_id=gyman).
- 함수는 **개별 배포** — `functions deploy <name>`은 그 함수만 올림. 미배포 함수 호출 시 클라엔 `ClientException: Failed to fetch`(404 아님).
- `functions deploy` 는 **로그인 선행** — `npx supabase login`(대화형) 또는 `SUPABASE_ACCESS_TOKEN` env. 미로그인 시 `Access token not provided`.
- LLM 키 등 시크릿은 `supabase secrets set`로 **서버에만**, 클라 노출 금지. 회원 PII는 LLM 전송 전 `{{NAME}}` 토큰으로 마스킹 후 응답에서 정규식 복원.
- AI 생성 함수(message-draft/memo-draft/renewal-pitch) 공통 골격: 인증→동의(`ai_consent`)→일일 한도→PII 마스킹→Gemini→`outgoing_notifications` draft. **일일 한도 카운트(`ai_call_logs`)엔 `trainer_id` 명시 필터 필수**(RLS만 믿지 말 것 — 향후 admin read 대비 defense in depth). 새 안내류 기능은 이 검수 게이트(승인→`markSent`) 재사용 — `trigger_type` 이 자유 text(CHECK 없음)라 새 값 추가에 **마이그레이션 불필요**.
- 함수 내 DB 접근은 **호출자 JWT 컨텍스트**(`createClient(url, anon, {global:{headers:{Authorization}}})`)로 → RLS 그대로 적용, service_role 불필요. 회원 데이터 함수는 `verify_jwt` 기본(true) 유지, 공개 헬스체크만 false.
- LLM 공급자 = **Google Gemini**(`gemini-3.5-flash`, env `LLM_MODEL`). **thinking 모델이라** `generationConfig.thinkingConfig.thinkingBudget=0` + `candidates[0].content.parts`에서 `thought!==true`만 join + `maxOutputTokens` 넉넉히. 안 하면 추론이 본문에 샘.
- 환각 억제: "기록에 없는 내용 지어내지 마라" 그라운딩 + 불릿 최소 개수 강제 금지 + 입력 비면 생성 차단. LLM 결과는 항상 트레이너 검수(draft) 게이트 통과.
- `functions.invoke` 실패는 `FunctionException`(`.details`=본문 JSON)으로 throw; 네트워크/미배포는 일반 예외 → **둘 다 잡아** code별 폴백(`AiGenerationException`).
