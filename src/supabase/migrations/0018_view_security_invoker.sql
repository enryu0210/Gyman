-- =====================================================================
-- 0018_view_security_invoker.sql
-- v_contract_status view 에 security_invoker 적용 (RLS 일관성)
--
-- 왜:
--   PG15+ 에서 view 기본값은 security_invoker=false → view 는 소유자(postgres)
--   권한으로 base 테이블을 읽어 RLS 를 우회할 수 있다. v_contract_status 는
--   잔여 횟수의 UI source of truth 라(회원/트레이너 양측 조회) RLS 가 호출자
--   기준으로 적용돼야 안전하다.
--   security_invoker=true 로 두면 view 조회 시 base 테이블 RLS 가 호출자 권한으로
--   평가된다 → 회원은 본인 계약만, 트레이너는 본인 계약만.
--
-- 멱등: SET (security_invoker = true) 는 반복 적용해도 안전.
-- 참고: docs/develop_plan.md §0, CLAUDE.md(잔여 횟수 정책), 0011/0013 view 정의.
-- =====================================================================

ALTER VIEW v_contract_status SET (security_invoker = true);

-- ---------------------------------------------------------------------
-- 검증 SQL:
--   SELECT relname, reloptions FROM pg_class WHERE relname = 'v_contract_status';
--   → reloptions 에 {security_invoker=true} 포함 기대.
-- ---------------------------------------------------------------------
