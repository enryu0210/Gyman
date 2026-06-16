-- =====================================================================
-- 0030_admin_dashboard_views.sql
--
-- 관리자 대시보드(C1) 데이터 소스 — Phase 3.1-B.
--
-- 무엇: 계약 1건 = 1행으로 펼친 집계용 view `v_admin_contract_overview`.
--   대시보드의 세 영역(센터 요약 / 트레이너별 성과 / 만료 임박 회원)을 전부
--   이 한 view 에서 파생한다. 회원명·트레이너명·잔여/사용 횟수·매출(price)·
--   완료/노쇼 수업 수를 한 행에 모아, 클라(Dart)는 group/sum 만 하면 된다.
--
-- 왜 view 한 개로 합치나:
--   - "매출 지표 일관성"이 핵심 요구(CLAUDE.md). 잔여/사용 횟수는 잔여 횟수의
--     UI source of truth 인 v_contract_status 를 재사용해 계산식을 통일한다.
--   - PostgREST 는 view 를 그냥 SELECT 할 수 있으므로(embed 불필요) 라운드트립 1회.
--   - 계약 단위(per-contract) grain 으로 두어 join 으로 인한 매출 중복 합산을
--     원천 차단한다(세션을 join 하면 price 가 수업 수만큼 뻥튀기됨 → 상관 서브쿼리로 분리).
--
-- 권한(중요): security_invoker=true.
--   → view 를 조회하는 사용자(관리자)의 RLS 가 base 테이블에 그대로 적용된다.
--     0029 의 admin RLS(member_admin_read / trainer_admin_read /
--     contract_admin_read / sessions_admin_read)가 "본인 center_id" 로 범위를
--     좁히므로, 관리자는 자기 센터 계약만 본다. 다른 센터 유출 불가.
--   security_invoker 를 빼면(PG15+ 기본 false) view 가 소유자 권한으로 base 를
--     읽어 RLS 를 우회한다 → 정보 유출. 반드시 true.
--
-- 멱등: CREATE OR REPLACE VIEW + SET (security_invoker=true) 반복 적용 안전.
--
-- 참고: docs/develop_plan.md §4 Phase 3.1-B, 0011/0013(v_contract_status),
--        0018(security_invoker 패턴), 0029(admin RLS).
-- =====================================================================

CREATE OR REPLACE VIEW v_admin_contract_overview AS
SELECT
  c.id                       AS contract_id,
  c.member_id,
  m.name                     AS member_name,
  m.center_id,
  c.trainer_id,
  t.name                     AS trainer_name,

  -- 잔여/사용/총 횟수: v_contract_status 재사용(계산식 통일). bigint → 클라에서 toInt.
  vc.total_sessions,
  vc.used_sessions,           -- = done + no_show + late_cancel (차감된 수업 총합 = 노쇼율 분모)
  vc.remaining_sessions,

  c.start_date,
  c.end_date,
  c.price,                    -- 원 단위. 매출 합산용(계약 단위라 중복 없음).

  -- 노쇼율 계산용 분자/참고치. 상관 서브쿼리로 두어 매출 중복 합산을 피한다.
  -- (sessions 를 직접 join 하면 한 계약의 price 가 수업 수만큼 곱해짐)
  (SELECT count(*) FROM sessions s
     WHERE s.contract_id = c.id AND s.status = 'done')    AS done_count,
  (SELECT count(*) FROM sessions s
     WHERE s.contract_id = c.id AND s.status = 'no_show')  AS no_show_count

FROM pt_contracts c
JOIN member_profiles m   ON m.id = c.member_id
LEFT JOIN trainer_profiles t ON t.user_id = c.trainer_id
JOIN v_contract_status vc    ON vc.contract_id = c.id
WHERE c.deleted_at IS NULL;

-- base 테이블 RLS 가 호출자(관리자) 기준으로 적용되도록 — 0018 과 동일 원칙.
ALTER VIEW v_admin_contract_overview SET (security_invoker = true);


-- ---------------------------------------------------------------------
-- 검증 SQL (적용 후 SQL Editor):
--
--   -- 1) view 와 security_invoker 확인
--   SELECT relname, reloptions FROM pg_class WHERE relname = 'v_admin_contract_overview';
--   → reloptions 에 {security_invoker=true} 포함 기대.
--
--   -- 2) 관리자 계정으로 로그인한 클라이언트에서 SELECT * FROM v_admin_contract_overview;
--   --    → 본인 센터 계약만, member_name/trainer_name/remaining/price 채워져 나오면 OK.
--   --    트레이너/회원 계정으로는 각자 RLS 범위(본인 계약)만 보여야 함(유출 없음).
-- ---------------------------------------------------------------------
