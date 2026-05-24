-- =====================================================================
-- 0011_triggers_views.sql
-- updated_at 자동 갱신 트리거 + 계약 상태 view
-- 참고: docs/data_model.md §4
-- =====================================================================

-- updated_at 자동 갱신 함수
CREATE OR REPLACE FUNCTION touch_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- updated_at 컬럼이 있는 테이블에 트리거 부착
CREATE TRIGGER trg_member_notes_touch
  BEFORE UPDATE ON member_notes
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER trg_session_records_touch
  BEFORE UPDATE ON session_records
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER trg_outgoing_notifications_touch
  BEFORE UPDATE ON outgoing_notifications
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();


-- =====================================================================
-- v_contract_status: 계약별 사용/잔여 횟수 실시간 계산 view
--
-- 도메인 로직(Dart)에서 이 view를 조회하거나, 클라이언트가 sessions를
-- 직접 count해도 결과는 같음. DB에 view를 둔 이유는 관리자 대시보드(Phase 3)
-- SQL과 계산식을 통일하여 매출 지표 일관성을 유지하기 위함.
--
-- 차감 대상: status IN ('done', 'no_show', 'late_cancel')
-- view 자체는 RLS가 없지만, 베이스 테이블(pt_contracts, sessions)의 RLS가
-- 그대로 적용되므로 권한 노출 위험 없음.
-- =====================================================================
CREATE OR REPLACE VIEW v_contract_status AS
SELECT
  c.id                              AS contract_id,
  c.member_id,
  c.trainer_id,
  c.total_sessions,
  COUNT(s.id) FILTER (
    WHERE s.status IN ('done', 'no_show', 'late_cancel')
  )                                 AS used_sessions,
  c.total_sessions
    - COUNT(s.id) FILTER (
        WHERE s.status IN ('done', 'no_show', 'late_cancel')
      )                             AS remaining_sessions,
  c.start_date,
  c.end_date
FROM pt_contracts c
LEFT JOIN sessions s ON s.contract_id = c.id
WHERE c.deleted_at IS NULL
GROUP BY c.id;
