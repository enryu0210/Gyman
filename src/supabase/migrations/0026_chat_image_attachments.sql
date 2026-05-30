-- =====================================================================
-- 0026_chat_image_attachments.sql
--
-- 트레이너 ↔ 회원 채팅(0006/0024)에 "사진 첨부" 추가.
--   1) messages 에 image_path(Storage object key) 컬럼 추가 + content 를
--      nullable 로 풀고 "텍스트 또는 이미지 중 최소 하나" CHECK 로 강제.
--   2) 비공개 Storage 버킷 chat-images 생성.
--   3) storage.objects 에 RLS — 본인이 올린 것 + 채팅 상대가 올린 것만 열람.
--
-- 보안 설계(0024 are_chat_peers 재사용):
--   - 이미지 파일은 비공개 버킷에 두고, 표시는 항상 "서명 URL"로(공개 URL 금지).
--   - object key 첫 세그먼트 = 업로더 user_id → Storage RLS의 권한 키.
--     "{sender_user_id}/{uuid}.jpg" 규칙. (ASCII 고정 — 한글 금지)
--   - 업로드는 본인 폴더에만, 열람은 채팅 상대(유효 계약)까지, 삭제는 본인만
--     (보상 트랜잭션용).
--
-- 멱등: ADD COLUMN IF NOT EXISTS / DROP CONSTRAINT IF EXISTS → ADD /
--       INSERT ... ON CONFLICT DO NOTHING / DROP POLICY IF EXISTS → CREATE.
--
-- 참고: 0006(messages), 0024(채팅 RLS·are_chat_peers), docs/develop_plan.md §4 2.3.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. messages 스키마 확장
-- ---------------------------------------------------------------------

-- 이미지 메시지의 Storage object key. 텍스트 메시지면 NULL.
ALTER TABLE messages ADD COLUMN IF NOT EXISTS image_path text;

-- 이미지만 보내는 메시지는 본문이 비어 있어야 하므로 content 의 NOT NULL 해제.
ALTER TABLE messages ALTER COLUMN content DROP NOT NULL;

-- 빈 메시지 방지: 텍스트(공백 아님) 또는 이미지 중 최소 하나는 있어야 한다.
ALTER TABLE messages DROP CONSTRAINT IF EXISTS messages_content_or_image;
ALTER TABLE messages ADD CONSTRAINT messages_content_or_image CHECK (
  (content IS NOT NULL AND length(btrim(content)) > 0)
  OR image_path IS NOT NULL
);

-- ---------------------------------------------------------------------
-- 2. 비공개 Storage 버킷 chat-images
--    file_size_limit 5MB, 이미지 MIME 만 허용(서버단 1차 방어).
-- ---------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'chat-images',
  'chat-images',
  false,
  5242880, -- 5 * 1024 * 1024
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------------
-- 3. storage.objects RLS (버킷 chat-images)
--    폴더 첫 세그먼트(= 업로더 user_id)를 권한 키로 사용.
-- ---------------------------------------------------------------------

-- 3-1) 업로드: 본인 폴더("{내 user_id}/...")에만.
DROP POLICY IF EXISTS chat_images_insert ON storage.objects;
CREATE POLICY chat_images_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'chat-images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- 3-2) 열람: 내가 올린 것 또는 "채팅 상대(유효 계약)"가 올린 것만.
--      are_chat_peers 는 SECURITY DEFINER(0024) — 정책에서 호출 가능.
DROP POLICY IF EXISTS chat_images_select ON storage.objects;
CREATE POLICY chat_images_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'chat-images'
    AND (
      (storage.foldername(name))[1] = auth.uid()::text
      OR are_chat_peers(((storage.foldername(name))[1])::uuid, auth.uid())
    )
  );

-- 3-3) 삭제: 본인 폴더만(메시지 INSERT 실패 시 고아 파일 정리 = 보상 트랜잭션).
DROP POLICY IF EXISTS chat_images_delete ON storage.objects;
CREATE POLICY chat_images_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'chat-images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- ---------------------------------------------------------------------
-- 검증 SQL (적용 후):
--   -- 1) 컬럼/제약
--   SELECT column_name, is_nullable FROM information_schema.columns
--   WHERE table_name='messages' AND column_name IN ('content','image_path');
--   → content=YES(nullable), image_path=YES
--
--   -- 2) 버킷
--   SELECT id, public, file_size_limit FROM storage.buckets WHERE id='chat-images';
--   → 1행, public=false
--
--   -- 3) Storage 정책 3개
--   SELECT polname FROM pg_policies
--   WHERE schemaname='storage' AND tablename='objects'
--     AND polname LIKE 'chat_images_%';
--   → chat_images_insert / chat_images_select / chat_images_delete
-- ---------------------------------------------------------------------
