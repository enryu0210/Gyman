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

```bash
# 예: LLM API 키 등록 (이름/공급자는 LLM 함수 구현 단계에서 확정)
!cd src && npx supabase secrets set LLM_API_KEY=sk-...

# 현재 등록된 시크릿 목록(값은 안 보임)
!cd src && npx supabase secrets list
```

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

## 로컬 실행(선택)

Docker 가 있으면 로컬에서 함수를 띄워볼 수 있다.

```bash
!cd src && npx supabase functions serve health --env-file ./supabase/functions/.env.local
```

- 로컬 시크릿은 `functions/.env.local` 에 두면 gitignore 됨(절대 커밋 금지).
