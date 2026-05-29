# Supabase Edge Functions — 배포 파이프라인

> Gyman 의 서버 사이드 로직(특히 **외부 LLM API 호출**)을 담는 곳.
> AI 안내 메시지(AI-B)/메모 초안(AI-C) 생성은 **반드시 여기서** 처리한다 —
> LLM API 키를 클라이언트(Flutter)에 두면 안 되기 때문(CLAUDE.md 보안, develop_plan §6).
> Flutter 는 `supabase.functions.invoke('함수명')` 로 호출만 한다.

---

## 왜 CLI 인가 (마이그레이션은 SQL Editor 인데)

마이그레이션(`../migrations/`)은 SQL Editor 수동 적용이 1순위지만,
Edge Function 은 **배포(deploy)** 가 필요해 Supabase CLI 가 필수다.
설치 없이 `npx supabase` 로 쓴다 (검증 버전: **2.101.0**, 글로벌 설치 불필요).

> ⚠️ 경로 주의: CLI 는 `src/supabase/config.toml` 기준으로 동작한다.
> 모든 명령은 **`src/` 디렉토리에서** 실행하거나 `--workdir src` 를 붙인다.

---

## 최초 1회 셋업 (사용자 인증 필요 — 대화형)

아래 두 단계는 **본인 Supabase 계정 인증**이 필요해 직접 실행해야 한다.
Claude Code 프롬프트에서 `!` 를 앞에 붙이면 이 세션에서 바로 실행된다.

```bash
# 1) 로그인 (브라우저 인증 또는 access token)
!cd src && npx supabase login

# 2) 원격 프로젝트 연결 (project ref = 대시보드 URL https://<ref>.supabase.co 의 <ref>)
#    실행하면 DB 비밀번호를 물어볼 수 있음.
!cd src && npx supabase link --project-ref <your-project-ref>
```

`link` 가 성공하면 `src/supabase/.temp/` 에 연결 정보가 캐시된다(gitignore 처리됨).

---

## 시크릿(LLM 키 등) 설정 — 서버에만 저장

키는 **레포에 절대 커밋하지 않는다.** 원격 프로젝트의 시크릿 저장소에만 넣는다.

공급자: **Google Gemini API**(호스팅+키 → Edge Function 적합). 키는 Google AI Studio 발급.

```bash
# 필수: Gemini API 키
!cd src && npx supabase secrets set LLM_API_KEY=<gemini-api-key>

# 선택: 모델/한도 (미설정 시 기본값 사용)
!cd src && npx supabase secrets set LLM_MODEL=gemini-3.5-flash
!cd src && npx supabase secrets set AI_DAILY_LIMIT=50

# 현재 등록된 시크릿 목록(값은 안 보임)
!cd src && npx supabase secrets list
```

> 개발은 무료 티어로 가능하나 **무료 티어는 데이터가 학습에 쓰일 수 있음** → PII 마스킹
> 필수(함수가 실명을 {{NAME}} 토큰으로 보냄). 실제 회원 데이터 베타 전 결제(Tier 1) 검토.

---

## 배포 & 검증 (health 함수)

`health` 는 파이프라인이 살아있는지 확인하는 최소 함수다.

```bash
# 배포
!cd src && npx supabase functions deploy health

# 호출 (verify_jwt=false 라 anon 키만으로 호출 가능)
#   <ref>, <anon-key> 는 .env 의 SUPABASE_URL / SUPABASE_ANON_KEY 와 동일
curl -i "https://<ref>.supabase.co/functions/v1/health" \
  -H "Authorization: Bearer <anon-key>"
```

정상 응답 예:

```json
{ "status": "ok", "time": "2026-05-29T...Z", "llmKeyConfigured": false }
```

- `status: ok` → 배포·호출 OK
- `llmKeyConfigured` → `LLM_API_KEY` 시크릿을 set 한 뒤 다시 호출하면 `true` → 시크릿 주입 OK

---

## 새 함수 추가 워크플로

```bash
!cd src && npx supabase functions new <function-name>   # functions/<name>/index.ts 생성
# 코드 작성 후
!cd src && npx supabase functions deploy <function-name>
```

- **인증 정책:** 회원 데이터를 다루는 함수(AI-B/AI-C)는 `verify_jwt` 기본값(true) 유지 →
  인증된 트레이너만 호출. `config.toml` 의 `[functions.<name>]` 에서 함수별 조정.
- **PII 마스킹:** LLM 으로 보내기 전 회원 실명 등 식별정보 마스킹 필수(develop_plan §6, 1.11).

---

## 함수 목록

| 함수 | 인증 | 역할 |
|------|------|------|
| `health` | verify_jwt=false | 배포/호출/시크릿 주입 검증 |
| `generate-message-draft` | verify_jwt=true | AI-B 회원 안내 메시지 초안 생성(1.9/1.11). 동의 확인 + PII 마스킹 + 일일 한도 + 장애 폴백 → `outgoing_notifications` draft 적재 |

### generate-message-draft 배포 & 사전 조건

```bash
# 사전: 0017_ai_call_logs.sql 적용(SQL Editor) + LLM_API_KEY 시크릿 설정
!cd src && npx supabase functions deploy generate-message-draft
```

호출(앱에서 `supabase.functions.invoke('generate-message-draft', body: {...})`):

```jsonc
// 요청
{ "memberId": "<member_profiles.id>", "triggerType": "renewal_five_left", "tone": "친근하게" }
// 성공
{ "ok": true, "draftId": "...", "content": "..." }
// 실패(앱은 수동 입력으로 폴백) — code: consent_required | rate_limited | llm_failed ...
{ "ok": false, "code": "llm_failed", "message": "..." }
```

---

## 로컬 실행(선택)

Docker 가 있으면 로컬에서 함수를 띄워볼 수 있다.

```bash
!cd src && npx supabase functions serve health --env-file ./supabase/functions/.env.local
```

- 로컬 시크릿은 `functions/.env.local` 에 두면 gitignore 됨(절대 커밋 금지).
