-- =====================================================================
-- 0008_init_body_assessments.sql
-- body_assessments: 체형 분석 (Phase 4 / C3)
-- Phase 1 데모에서는 사용하지 않지만 스키마 일관성 + RLS 일관성 위해 미리 생성.
-- 실제 사용 시점에 사진 보관 정책/동의 화면 등 추가 작업 필요.
-- 참고: docs/data_model.md §2.2
-- =====================================================================

CREATE TABLE body_assessments (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id       uuid NOT NULL REFERENCES member_profiles(user_id),
  -- 사진은 Supabase Storage에 저장하고 경로만 보관.
  -- 예: { "front": "bucket/path/front.jpg", "side": "...", "back": "..." }
  photos          jsonb NOT NULL,
  -- AI 분석 결과 (키포인트, 비대칭 각도 등)
  ai_result       jsonb,
  -- 트레이너 코멘트. NULL이면 회원에게 노출 금지 (RLS 조건, 0010).
  -- AI 단독으로 회원에게 결과 전달 못 하게 하는 안전 게이트.
  trainer_comment text,
  assessed_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_assess_member ON body_assessments(member_id);
