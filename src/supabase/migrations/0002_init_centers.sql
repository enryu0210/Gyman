-- =====================================================================
-- 0002_init_centers.sql
-- centers: 헬스장(센터) 정보. PT 규정(차감 정책 등)을 JSON으로 보관.
-- 참고: docs/data_model.md §2.2
-- =====================================================================

CREATE TABLE centers (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name       text NOT NULL,
  address    text,
  -- PT 규정을 JSON으로: 센터마다 다르므로 컬럼화하지 않음.
  -- 예: { "late_cancel_hours": 24, "no_show_deduct": true, "late_arrival_minutes": 15 }
  rules      jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);

-- RLS는 0010_rls_policies.sql에서 일괄 적용
