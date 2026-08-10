# Supabase 마이그레이션

> Gyman 백엔드(PostgreSQL via Supabase)의 스키마 + RLS 정책을 코드로 관리합니다.
> **이 폴더의 SQL 파일이 스키마 정본이다.** 구현 현황·지켜야 할 제약은
> [`docs/shipped.md`](../../../docs/shipped.md).
> (⚠ `docs/data_model.md` 는 0020 까지만 반영된 낡은 초안 — 스키마 근거로 쓰지 말 것)

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
| 0013 | `0013_member_profiles_offline_support.sql` | 회원 오프라인 등록(id PK, user_id nullable) |
| 0014 | `0014_member_created_by_trainer.sql` | created_by_trainer_id 로 RLS 한계 해결 |
| 0015 | `0015_trainer_favorite_exercises.sql` | 트레이너 즐겨찾기 종목 |
| 0016 | `0016_pre_session_notice_cron.sql` | Phase 1.8 수업 전날 안내 자동 적재(plpgsql + pg_cron) |
| 0017 | `0017_ai_call_logs.sql` | Phase 1.11 LLM 호출 감사 로그 + 일일 호출 한도 근거 |
| 0018 | `0018_view_security_invoker.sql` | v_contract_status RLS 일관성(security_invoker) |
| 0019 | `0019_member_invite_code.sql` | 회원 초대 코드 + 계정 연결 RPC(claim_member_profile) |
| 0020 | `0020_verify_invite_code.sql` | 초대 코드 검증 RPC(verify_invite_code, anon 실행 허용) |
| 0021 | `0021_session_status_requested.sql` | 회원 예약 신청용 session_status 'requested' 추가 (⑤) |
| 0022 | `0022_member_booking_request_rls.sql` | 회원 예약 신청 INSERT/철회 DELETE RLS (⑤) |
| 0023 | `0023_body_measurements.sql` | 인바디 수치(체중/체지방률/골격근량) — 변화 추이 그래프 S1 |
| 0024 | `0024_messages_rls_realtime.sql` | 채팅 RLS(`are_chat_peers` 계약 기반) + 실시간 publication (S2) |
| 0025 | `0025_trainer_dnd_and_msg_policy_cleanup.sql` | 트레이너 방해금지 시간 컬럼 + 메시지 정책 정리 |
| 0026 | `0026_chat_image_attachments.sql` | 채팅 사진 첨부 — 비공개 버킷 `chat-images` + Storage RLS |
| 0027 | `0027_class_videos.sql` | 수업 영상 보관 — 비공개 버킷 `class-videos` + RLS (2.7) |
| 0028 | `0028_self_workout_logs.sql` | 회원 셀프 운동 기록(컨디션 1~10) — 회원 rw / 트레이너 read (S4) |
| 0029 | `0029_admin_profiles.sql` | 관리자 인프라 — `admin_profiles` + 센터 범위 read RLS (3.1-A) |
| 0030 | `0030_admin_dashboard_views.sql` | 관리자 대시보드 집계 view(security_invoker) (3.1-B) |
| 0031 | `0031_center_settings.sql` | 센터 규정 + PT FAQ(`center_faqs`) + admin RLS 게이트 교체 (3.2-A) |
| 0032 | `0032_member_center_default.sql` | 버그 수정 — 회원 `center_id` NULL 로 FAQ·대시보드가 안 잡히던 문제 |
| 0033 | `0033_support_inquiries.sql` | 인앱 문의함 (3.5) |
| 0034 | `0034_account_deletion_and_consent.sql` | 익명화 탈퇴 로그 + 동의 이력(`user_consents`) (3.5) |
| 0035 | `0035_notice_read_tracking.sql` | 받은 안내 읽음 처리 — `read_at` + 좁은 SECURITY DEFINER RPC |
| 0036 | `0036_member_conditions.sql` | 회원 체형 특이사항(측만증·골반경사 등) + 출처 CHECK — 4.8 L1-a |
| 0037 | `0037_condition_coaching_rules.sql` | 제약 × 동작패턴 → 코칭 큐 규칙 + 기본 시드 19건 — 4.8 L1-b |
| 0038 | `0038_class_video_marks.sql` | 수업 영상 시점 지적(트레이너 마킹 → 회원 재생 시 표시) — 4.8 L2 |
| 0039 | `0039_body_assessment_foundation.sql` | 체형분석 기반 — 비공개 버킷 `body-photos` + Storage RLS + 사진 동의 컬럼 — 4.2 A |
| 0040 | `0040_member_ai_consent_optout.sql` | 회원 AI 사용 거부권 — `ai_consent_effective` 생성 컬럼 + 회원 전용 변경 트리거 (A-2) |
| 0041 | `0041_consent_coverage.sql` | 민감정보 동의 기록 + 미가입 회원 오프라인 동의 확인 게이트 (C·D-4) |

---

## 적용 현황

> ✅ **0001~0040 Supabase SQL Editor 적용 완료**
> (0001~0034: 2026-07-06 / 0035~0039: 2026-07-25 / 0040: 2026-08-10).
> ⬜ **0041 미적용** — 아래 주의사항을 읽고 앱 배포와 **함께** 적용할 것.
>
> ⚠ **0041 은 앱과 짝을 이룬다.** `member_profiles` 에 BEFORE INSERT 트리거를 걸어
> 동의 확인 없는 회원 등록을 거부하므로, 마이그레이션만 먼저 적용하면 구버전 앱의
> [회원 추가]가 그 순간부터 실패한다. 0040 은 서버(Edge Function) 재배포로 끝났지만
> 0041 은 **사용자 기기의 앱**이 짝이라 되돌리기가 느리다 — 둘을 붙여서 내보낼 것.
>
> 남은 것은 스키마 적용이 아니라 **각 기능의 end-to-end 동작·RLS 검증** — 체크리스트는
> [`docs/develop_plan.md`](../../../docs/develop_plan.md) §8 참조.

---

## 적용 방법 (방법 A — 가장 쉬움, 권장)

**Supabase 대시보드에서 SQL Editor로 직접 실행.**

1. https://supabase.com/ 로그인 후 본인 프로젝트 진입
2. 좌측 메뉴 `SQL Editor` 클릭
3. 파일 **0001부터 0041까지 번호 순서대로** 열어서 복사·붙여넣기·실행 (0012 제외 — 아래 5번)
4. 각 파일 실행 후 `Success. No rows returned` 또는 에러 메시지 확인
5. 0012는 시드 데이터 → 개발 환경에서만 실행
6. 각 파일 하단의 **검증 SQL 주석**을 실행해 정책·CHECK 가 실제로 도는지 확인

### 적용 후 확인
- 좌측 메뉴 `Table Editor` → 위 표의 테이블들이 보이면 OK
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
(그 문서는 아카이브지만 **§7 시나리오는 아직 유효**하다. 실기기 대본은 `docs/e2e_verification_script.md`.)

- Phase 0 종료 전: RLS-1 ~ RLS-8 통과 필수
- Phase 1 1.9/1.10 완료 시: RLS-9 ~ RLS-12, AI-1 추가 통과

테스트 코드는 추후 `src/app/test/integration/rls_test.dart` 또는 별도 Node.js 스크립트로 작성 예정.

---

## 신규 변경 시 워크플로

1. 새 파일 추가: `0040_<설명>.sql` (번호는 마지막 파일 다음부터 증가 — 현재 마지막은 0039)
2. SQL 내용에 `-- 참고: docs/develop_plan.md §X` 같은 출처 주석 권장
3. Git 커밋
4. Supabase 대시보드/CLI로 적용
5. RLS 통합 테스트 영향 있는지 확인 후 시나리오 보강

> **절대 하지 말 것:** 이미 적용된 마이그레이션 파일을 수정하는 것.
> 새 파일을 추가해서 `ALTER TABLE ...` 형태로 변경하는 것이 원칙.
