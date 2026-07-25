-- =====================================================================
-- 0039_body_assessment_foundation.sql
--
-- 체형 분석 기반 정비 — Phase 4.2 A단계 (docs/design_body_analysis.md §7 A).
-- UI·카메라·ML 없이 **스키마 / 스토리지 / 동의**만 먼저 세운다.
--
-- ⚠ 설계 문서(§2.1·§9)가 "0008 스키마 빚(member_id 가 user_id 참조) 정리 선행"을
--   착수 조건으로 걸어뒀는데, **확인해 보니 0013 에서 이미 해결돼 있었다**:
--     - FK  : body_assessments.member_id → member_profiles(id)   (0013 L85-88)
--     - RLS : assess_member_read_after_review 가 current_member_profile_id() 사용
--   → 본 파일은 그 빚을 갚는 게 아니라, **남아 있던 실제 구멍**만 메운다.
--
-- 이 파일이 하는 일:
--   1. body_assessments 보강 — recorded_by(감사) + ON DELETE CASCADE + 조회 인덱스
--   2. 트레이너 RW 정책에 WITH CHECK 명시(쓰기 경로 방어를 눈에 보이게)
--   3. 신체사진 전용 비공개 버킷 `body-photos` + Storage RLS
--   4. member_profiles.body_photo_consent — 사진 촬영·보관 별도 동의
--
-- ⚠⚠ 왜 사진 동의가 ai_consent 와 별개인가 (설계 §3.4):
--   ai_consent 는 "외부 LLM 으로 데이터를 보내도 되는가"에 대한 동의다.
--   체형 분석은 **분석이 100% 온디바이스라 외부 전송이 0** 이므로 LLM 동의 대상이
--   아니지만, 신체 사진의 **촬영·저장·보관** 자체는 성격이 다른 민감정보라
--   별도 동의가 필요하다. 두 플래그를 섞으면 둘 중 하나가 잘못된 근거가 된다.
--
-- 멱등: ADD COLUMN IF NOT EXISTS / DROP POLICY IF EXISTS → CREATE /
--       INSERT ... ON CONFLICT DO NOTHING / 제약은 DROP → ADD.
--
-- 참고: docs/design_body_analysis.md, 0008(원본 테이블), 0013(FK·RLS 정리),
--       0026(비공개 버킷 + Storage RLS 선례), 0009/0013(헬퍼).
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1. body_assessments 보강
-- ---------------------------------------------------------------------

-- 촬영·등록한 트레이너(감사·표시용). 계정이 지워져도 분석 이력은 보존 → SET NULL.
ALTER TABLE body_assessments
  ADD COLUMN IF NOT EXISTS recorded_by uuid
    REFERENCES trainer_profiles(user_id) ON DELETE SET NULL;

-- 회원이 hard delete 되면 분석도 함께 정리한다.
-- 0013 이 FK 를 id 로 옮길 때 CASCADE 를 안 붙여서, 지금은 회원 삭제가 FK 위반으로
-- 막힌다(신체사진 같은 민감 데이터가 남는 쪽이 더 나쁘다) → CASCADE 로 교체.
ALTER TABLE body_assessments
  DROP CONSTRAINT IF EXISTS body_assessments_member_id_fkey;
ALTER TABLE body_assessments
  ADD CONSTRAINT body_assessments_member_id_fkey
  FOREIGN KEY (member_id) REFERENCES member_profiles(id) ON DELETE CASCADE;

-- 주 조회 = "이 회원의 분석을 최신순" + 4·8·12주 비교 → 복합 인덱스로 교체.
DROP INDEX IF EXISTS idx_assess_member;
CREATE INDEX IF NOT EXISTS idx_assess_member_date
  ON body_assessments(member_id, assessed_at DESC);


-- ---------------------------------------------------------------------
-- 2. RLS — 트레이너 정책에 WITH CHECK 명시
--
--    FOR ALL 에서 WITH CHECK 를 생략하면 PG 가 USING 을 그대로 쓴다(동작은 동일).
--    다만 이 테이블은 "AI 결과를 회원에게 함부로 못 보이게" 하는 게 핵심이라,
--    쓰기 경로 조건이 코드에 드러나 있는 편이 리뷰에서 안전하다.
--    회원 read 게이트(trainer_comment 필수)는 0013 판을 그대로 둔다 — 이미 옳다.
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS assess_trainer_rw ON body_assessments;
CREATE POLICY assess_trainer_rw ON body_assessments
  FOR ALL
  USING (
    current_user_role() = 'trainer'
    AND is_member_of_trainer(member_id)
  )
  WITH CHECK (
    current_user_role() = 'trainer'
    AND is_member_of_trainer(member_id)
  );


-- ---------------------------------------------------------------------
-- 3. 신체사진 버킷 `body-photos`
--
--    채팅 이미지(0026)와 같은 구조이되 **권한은 더 좁다**:
--    채팅은 "대화 상대"라는 개념이 있지만, 신체사진은 **본인 + 담당 트레이너뿐**이다.
--    그래서 are_chat_peers 를 쓰지 않는다.
--
--    object key 규칙(ASCII 고정 — 한글 금지):
--      "{member_id}/{assessment_id}/{front|side|back}.jpg"
--      첫 세그먼트 = member_id → Storage RLS 의 권한 키.
--      (채팅은 첫 세그먼트가 업로더 user_id 였다. 여기선 대상 회원 — 0027 영상과 같은 결.)
-- ---------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'body-photos',
  'body-photos',
  false,          -- 절대 공개 금지. 표시는 항상 단기 서명 URL.
  5242880,        -- 5MB — 업로드 전 1600px/품질80 압축 전제(0026 패턴 재사용)
  ARRAY['image/jpeg']
)
ON CONFLICT (id) DO NOTHING;

-- 3-1) 트레이너 업로드: 담당 회원 폴더에만.
--      ⓘ 폴더명을 uuid 로 캐스팅한다 — 앱만 쓰는 경로라 형식이 보장되고,
--        INSERT 정책이 그 형식을 강제하므로 이후 SELECT 도 안전하다(0026 선례).
DROP POLICY IF EXISTS body_photos_trainer_insert ON storage.objects;
CREATE POLICY body_photos_trainer_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'body-photos'
    AND current_user_role() = 'trainer'
    AND is_member_of_trainer(((storage.foldername(name))[1])::uuid)
  );

-- 3-2) 열람: 담당 트레이너 또는 본인 회원.
DROP POLICY IF EXISTS body_photos_select ON storage.objects;
CREATE POLICY body_photos_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'body-photos'
    AND (
      is_member_of_trainer(((storage.foldername(name))[1])::uuid)
      OR (storage.foldername(name))[1] = current_member_profile_id()::text
    )
  );

-- 3-3) 삭제: 담당 트레이너만.
--      메타 INSERT 실패 시 업로드한 사진을 되돌리는 **보상 트랜잭션**에 필요하고
--      (CLAUDE.md — SDK 가 멀티테이블 트랜잭션 미지원), 잘못 찍은 사진 제거에도 쓴다.
--      회원에게 삭제권을 주지 않는 이유: 분석 이력의 근거 자료라 임의 삭제되면
--      트레이너 코멘트가 근거 없는 글이 된다.
DROP POLICY IF EXISTS body_photos_trainer_delete ON storage.objects;
CREATE POLICY body_photos_trainer_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'body-photos'
    AND current_user_role() = 'trainer'
    AND is_member_of_trainer(((storage.foldername(name))[1])::uuid)
  );


-- ---------------------------------------------------------------------
-- 4. 신체사진 촬영·보관 동의 (ai_consent 와 별개 — 상단 주석 참조)
--
--    기본값 false = 명시적으로 받기 전엔 촬영·저장 불가.
--    앱은 이 값이 false 면 촬영 진입 자체를 막는다(트레이너 측 게이트, 설계 §4.1).
--    ⓘ 분석(온디바이스 수치 계산)과 저장은 분리 가능하다 — 미동의 회원에게
--      "사진 저장 없이 수치만" 제공할지는 아직 미결(설계 §8.2).
-- ---------------------------------------------------------------------
ALTER TABLE member_profiles
  ADD COLUMN IF NOT EXISTS body_photo_consent boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN member_profiles.body_photo_consent IS
  '신체사진 촬영·저장·보관 동의. ai_consent(외부 LLM 전송 동의)와 별개 — '
  '체형분석은 온디바이스라 외부 전송이 없지만 사진 보관 자체에 동의가 필요함.';

COMMIT;


-- ---------------------------------------------------------------------
-- 검증 SQL (적용 후 SQL Editor):
--
--   -- 1) 컬럼 추가 확인
--   SELECT column_name FROM information_schema.columns
--   WHERE table_name='body_assessments' AND column_name='recorded_by';
--   SELECT column_name, column_default FROM information_schema.columns
--   WHERE table_name='member_profiles' AND column_name='body_photo_consent';
--   → body_photo_consent 기본값 false 기대.
--
--   -- 2) FK 가 id 참조 + CASCADE 인지
--   SELECT conname, confdeltype FROM pg_constraint
--   WHERE conname = 'body_assessments_member_id_fkey';
--   → confdeltype='c'(CASCADE) 기대.
--
--   -- 3) 버킷 (비공개여야 함)
--   SELECT id, public, file_size_limit FROM storage.buckets WHERE id='body-photos';
--   → 1행, public=false, 5242880.
--
--   -- 4) Storage 정책 3개
--   SELECT policyname FROM pg_policies
--   WHERE schemaname='storage' AND tablename='objects'
--     AND policyname LIKE 'body_photos_%';
--   → insert / select / delete 3행.
--
--   -- 5) 회원 read 게이트가 살아 있는지(가장 중요 — AI 단독 노출 차단)
--   --    트레이너 계정으로 trainer_comment 없이 1행 INSERT 한 뒤,
--   --    그 회원 계정으로 로그인해:
--   SELECT count(*) FROM body_assessments;   -- 0 기대
--   --    트레이너가 trainer_comment 를 채우면:
--   SELECT count(*) FROM body_assessments;   -- 1 기대
-- ---------------------------------------------------------------------
