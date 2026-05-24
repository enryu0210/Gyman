# Supabase 마이그레이션

> Gyman 백엔드(PostgreSQL via Supabase)의 스키마 + RLS 정책을 코드로 관리합니다.
> 참고 문서: [`docs/data_model.md`](../../../docs/data_model.md)

---

## 파일 구성

| # | 파일 | 역할 |
|---|------|------|
| 0001 | `0001_init_enums.sql` | ENUM 타입 정의 (역할/상태/가시성/AI 출처) |
| 0002 | `0002_init_centers.sql` | 헬스장 정보 |
| 0003 | `0003_init_profiles.sql` | 트레이너/회원 프로필 + AI 동의 컬럼 |
| 0004 | `0004_init_notes.sql` | 트레이너 전용 메모 + AI 출처 추적 |
| 0005 | `0005_init_contracts_sessions.sql` | PT 계약, 수업, 수업 기록 |
| 0006 | `0006_init_messages.sql` | 채팅 (Phase 2) |
| 0007 | `0007_init_outgoing_notifications.sql` | AI 안내 메시지 발송 큐 (AI-B) |
| 0008 | `0008_init_body_assessments.sql` | 체형 분석 (Phase 4) |
| 0009 | `0009_helper_functions.sql` | RLS 헬퍼 함수 |
| 0010 | `0010_rls_policies.sql` | 모든 RLS 정책 |
| 0011 | `0011_triggers_views.sql` | updated_at 트리거 + 계약 상태 view |
| 0012 | `0012_seed_dev.sql` | 개발용 시드 데이터 (수동 실행 가이드) |

---

## 적용 방법 (방법 A — 가장 쉬움, 권장)

**Supabase 대시보드에서 SQL Editor로 직접 실행.**

1. https://supabase.com/ 로그인 후 본인 프로젝트 진입
2. 좌측 메뉴 `SQL Editor` 클릭
3. 파일 **0001부터 0011까지 순서대로** 열어서 복사·붙여넣기·실행
4. 각 파일 실행 후 `Success. No rows returned` 또는 에러 메시지 확인
5. 0012는 시드 데이터 → 개발 환경에서만 실행

### 적용 후 확인
- 좌측 메뉴 `Table Editor` → 11개 테이블 (`centers`, `trainer_profiles`, ..., `body_assessments`) 보이면 OK
- 좌측 메뉴 `Database` → `Policies` → 각 테이블에 RLS 정책 적용된 것 확인

---

## 적용 방법 (방법 B — Supabase CLI 사용)

CI/CD나 여러 환경 관리할 때 권장. 사전 설치 필요.

```bash
# 1. Supabase CLI 설치 (npm 사용)
npm install -g supabase

# 2. 프로젝트 루트에서 Supabase 초기화
cd F:/일/Gyman
supabase init

# 3. 원격 프로젝트와 연결 (Supabase 대시보드에서 프로젝트 ref 확인)
supabase link --project-ref <your-project-ref>

# 4. 마이그레이션 적용
supabase db push
```

> CLI는 `migrations/` 폴더의 SQL을 알파벳순으로 자동 적용 + `schema_migrations` 테이블에 기록 → 다음 실행 시 이미 적용된 파일은 건너뜀.

---

## 핵심 안전장치 요약

본 스키마는 단순히 테이블을 만드는 게 아니라, 다음 보안 원칙을 **DB 레벨에서 강제**합니다.

| 원칙 | 강제 수단 | 적용 파일 |
|------|----------|----------|
| 트레이너 전용 메모는 회원이 못 본다 | RLS `notes_member_deny` (이중 안전장치) | 0010 |
| AI 안내 메시지는 트레이너 검수 없이 발송 불가 | `CHECK (status <> 'sent' OR approved_at IS NOT NULL)` + RLS | 0007, 0010 |
| AI 체형 분석 결과는 트레이너 코멘트 후에만 회원 노출 | RLS `assess_member_read_after_review` | 0010 |
| 회원은 본인 계약/수업/메시지만 본다 | RLS 정책 다수 | 0010 |

---

## 마이그레이션 적용 후 필수 — RLS 통합 테스트

`docs/data_model.md` §7의 13개 시나리오(RLS-1 ~ RLS-12, AI-1)를 통과해야 합니다.

- Phase 0 종료 전: RLS-1 ~ RLS-8 통과 필수
- Phase 1 1.9/1.10 완료 시: RLS-9 ~ RLS-12, AI-1 추가 통과

테스트 코드는 추후 `src/app/test/integration/rls_test.dart` 또는 별도 Node.js 스크립트로 작성 예정.

---

## 신규 변경 시 워크플로

1. 새 파일 추가: `0013_<설명>.sql` (번호는 12 다음부터 증가)
2. SQL 내용에 `-- 참고: docs/data_model.md §X` 같은 출처 주석 권장
3. Git 커밋
4. Supabase 대시보드/CLI로 적용
5. RLS 통합 테스트 영향 있는지 확인 후 시나리오 보강

> **절대 하지 말 것:** 이미 적용된 마이그레이션 파일을 수정하는 것.
> 새 파일을 추가해서 `ALTER TABLE ...` 형태로 변경하는 것이 원칙.
