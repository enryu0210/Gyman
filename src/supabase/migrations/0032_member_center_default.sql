-- =====================================================================
-- 0032_member_center_default.sql
--
-- 버그 수정: 트레이너가 등록한 회원의 member_profiles.center_id 가 항상 NULL.
--
-- 증상: 관리자가 입력한 PT 규정 FAQ(center_faqs, 0031)가 회원에게 안 보임.
--   회원 read RLS(center_faq_member_read)는 "회원.center_id == FAQ.center_id" 를
--   요구하는데, 회원 center_id 가 NULL 이라 영영 매칭되지 않는다. (FAQ 화면은
--   조회 실패/빈 결과를 "준비 중" 폴백으로 가려서 원인이 잘 안 보였음.)
--   또한 0031 이후 admin 의 센터 범위 대시보드 read 도 회원 center_id 에 의존한다.
--
-- 근본 원인: 회원 등록 화면(add_member_dialog)이 center_id 를 안 넘겨 NULL 로 INSERT.
--
-- 해결(클라 변경 없이 DB 에서 보장 — created_by_trainer_id DEFAULT auth.uid() 와 동일 취지):
--   1. BEFORE INSERT 트리거 — center_id 가 NULL 이면 '만든 트레이너의 센터' 로 채움.
--   2. 기존 NULL 회원 백필 — 만든 트레이너의 center_id 로.
--
-- 전제: 트레이너의 trainer_profiles.center_id 가 채워져 있어야 한다(수동 등록한
--   베타 센터장이면 SQL 로 먼저 세팅). 아래 검증 SQL 참고.
--
-- 멱등: CREATE OR REPLACE / DROP TRIGGER IF EXISTS / UPDATE 는 반복 안전.
--
-- 참고: 0003(member_profiles.center_id), 0014(created_by_trainer_id),
--        0031(center_faqs RLS), docs/develop_plan.md §4 Phase 3.2.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. BEFORE INSERT 트리거 — center_id 자동 채움
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_member_center_from_trainer() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  -- 클라가 명시적으로 center_id 를 넘기면 존중하고, 비었을 때만 트레이너 센터로.
  IF NEW.center_id IS NULL THEN
    NEW.center_id := (
      SELECT center_id FROM trainer_profiles
      WHERE user_id = auth.uid()
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_member_center_default ON member_profiles;
CREATE TRIGGER trg_member_center_default
  BEFORE INSERT ON member_profiles
  FOR EACH ROW EXECUTE FUNCTION set_member_center_from_trainer();


-- ---------------------------------------------------------------------
-- 2. 기존 NULL 회원 백필 — '만든 트레이너'의 센터로
--    (트레이너 center_id 가 NULL 이면 이 회원은 그대로 NULL — 아래 검증 참고)
-- ---------------------------------------------------------------------
UPDATE member_profiles m
SET center_id = t.center_id
FROM trainer_profiles t
WHERE m.center_id IS NULL
  AND m.created_by_trainer_id = t.user_id
  AND t.center_id IS NOT NULL;


-- ---------------------------------------------------------------------
-- 검증 / 수동 보정 SQL (적용 후 SQL Editor):
--
--   -- 1) 트레이너 center_id 가 비어있으면 먼저 채운다(수동 등록한 센터장 등).
--   --    '<center_id>' 는 SELECT id, name FROM centers; 로 확인.
--   --   UPDATE trainer_profiles SET center_id = '<center_id>' WHERE center_id IS NULL;
--   --   → 그 다음 위 2번 백필 UPDATE 를 다시 실행하면 회원도 채워진다.
--
--   -- 2) 아직 NULL 인 회원이 남았는지
--   SELECT id, name, center_id, created_by_trainer_id
--   FROM member_profiles WHERE center_id IS NULL AND deleted_at IS NULL;
--   → 0행이면 정상. 남아있으면 1)에서 트레이너 center_id 부터 확인.
--
--   -- 3) 회원 center_id 와 FAQ center_id 가 일치하는지(일치해야 FAQ 가 보임)
--   SELECT (SELECT center_id FROM center_faqs WHERE deleted_at IS NULL LIMIT 1) AS faq_center,
--          (SELECT center_id FROM member_profiles WHERE deleted_at IS NULL LIMIT 1) AS member_center;
-- ---------------------------------------------------------------------
