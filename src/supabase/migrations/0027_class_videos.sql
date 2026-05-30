-- =====================================================================
-- 0027_class_videos.sql
--
-- 수업 영상 보관·열람 (Class Videos, S 시리즈).
--   트레이너가 짧은 자세/폼 체크 클립을 올려두면 "해당 회원만" 앱에서 다시 본다.
--   1) 메타데이터 테이블 class_videos (실파일은 Storage, DB엔 경로/메타만).
--   2) 비공개 Storage 버킷 class-videos.
--   3) storage.objects RLS — 폴더 첫 세그먼트(= member_id)를 권한 키로.
--
-- 설계 출처: docs/design_class_videos.md (§2 데이터모델 / §3 RLS).
--
-- 식별자 정책(0013 이후): member_id 는 member_profiles.id(PK)를 참조.
--   회원 측 RLS 는 current_member_profile_id() 헬퍼 경유(auth.uid() 직접 비교 금지).
--
-- 보안 설계(0026 chat-images 패턴 재사용하되 권한은 더 좁음):
--   - 영상은 비공개 버킷, 표시는 항상 "서명 URL"로(공개 URL 금지).
--   - object key 첫 세그먼트 = 대상 회원 member_id → Storage RLS의 권한 키.
--     "{member_id}/{video}.mp4" 규칙. (ASCII 고정 — 한글 금지)
--   - 채팅(are_chat_peers)과 달리 "본인 + 담당 트레이너"로만 한정 — 채팅 상대 개념 없음.
--
-- 멱등: CREATE TABLE IF NOT EXISTS / INSERT ... ON CONFLICT DO NOTHING /
--       DROP POLICY IF EXISTS → CREATE (SQL Editor 부분 적용 후 재실행 대비).
--
-- 참고: 0009/0013(헬퍼·RLS), 0023(body_measurements 카드 패턴), 0026(Storage RLS 패턴).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. 테이블
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS class_videos (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- 영상 대상 회원. 회원 삭제(hard)되면 영상 메타도 함께 정리(Storage 객체는 정리 잡).
  member_id     uuid NOT NULL
                  REFERENCES member_profiles(id) ON DELETE CASCADE,

  -- 특정 수업과 연결(선택). 수업이 삭제돼도 영상은 남기고 연결만 해제.
  session_id    uuid REFERENCES sessions(id) ON DELETE SET NULL,

  -- 비공개 버킷 내 object key. "{member_id}/{unique}.mp4" (ASCII).
  storage_path  text NOT NULL,

  -- "스쿼트 폼 체크" 등 표시 제목(선택).
  title         text,

  -- 길이(초). 상한(설계 §0.2 = 120초) 검증·표시용. nullable(추출 실패 대비).
  duration_sec  int,

  -- 용량(바이트). 모니터링/정리용.
  size_bytes    bigint,

  -- 업로드한 트레이너(감사/표시용). 계정 삭제 시에도 메타는 보존 → SET NULL.
  uploaded_by   uuid REFERENCES trainer_profiles(user_id) ON DELETE SET NULL,

  created_at    timestamptz NOT NULL DEFAULT now()
);

-- 회원별 + 최신순 조회가 주 패턴(목록) → 복합 인덱스.
CREATE INDEX IF NOT EXISTS idx_class_videos_member
  ON class_videos(member_id, created_at DESC);


-- ---------------------------------------------------------------------
-- 2. RLS (테이블)
--    PG15+ 는 테이블 RLS 가 기본 비활성이므로 명시적으로 켠다.
-- ---------------------------------------------------------------------
ALTER TABLE class_videos ENABLE ROW LEVEL SECURITY;

-- 2-1) 트레이너: 본인 담당 회원의 영상을 모두 다룸(조회/등록/삭제).
--      is_member_of_trainer(member_id) = 현재 유효 계약 보유 여부(0009/0013).
DROP POLICY IF EXISTS class_videos_trainer_rw ON class_videos;
CREATE POLICY class_videos_trainer_rw ON class_videos
  FOR ALL
  USING (
    current_user_role() = 'trainer'
    AND is_member_of_trainer(member_id)
  )
  WITH CHECK (
    current_user_role() = 'trainer'
    AND is_member_of_trainer(member_id)
  );

-- 2-2) 회원: 본인 영상만 조회(읽기 전용).
--      검수 게이트 없음 — 영상은 트레이너가 의도적으로 올린 자료(인바디 수치와 같은 결).
DROP POLICY IF EXISTS class_videos_member_read ON class_videos;
CREATE POLICY class_videos_member_read ON class_videos
  FOR SELECT
  USING (member_id = current_member_profile_id());


-- ---------------------------------------------------------------------
-- 3. 비공개 Storage 버킷 class-videos
--    file_size_limit 250MB(설계 §0.2 클립 상한과 일치), video/mp4 만 허용.
-- ---------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'class-videos',
  'class-videos',
  false,
  262144000, -- 250 * 1024 * 1024
  ARRAY['video/mp4']
)
ON CONFLICT (id) DO NOTHING;


-- ---------------------------------------------------------------------
-- 4. storage.objects RLS (버킷 class-videos)
--    폴더 첫 세그먼트(= 대상 회원 member_id)를 권한 키로 사용.
--    채팅과 달리: 업로더(트레이너)의 폴더가 아니라 "회원" 폴더에 넣는다.
-- ---------------------------------------------------------------------

-- 4-1) 트레이너: 담당 회원 폴더에 대해 모두 가능(업로드/열람/삭제=보상 트랜잭션).
DROP POLICY IF EXISTS class_videos_objects_trainer ON storage.objects;
CREATE POLICY class_videos_objects_trainer ON storage.objects
  FOR ALL TO authenticated
  USING (
    bucket_id = 'class-videos'
    AND current_user_role() = 'trainer'
    AND is_member_of_trainer( ((storage.foldername(name))[1])::uuid )
  )
  WITH CHECK (
    bucket_id = 'class-videos'
    AND current_user_role() = 'trainer'
    AND is_member_of_trainer( ((storage.foldername(name))[1])::uuid )
  );

-- 4-2) 회원: 본인 폴더의 영상만 열람(서명 URL 발급 시 이 정책을 통과해야 함).
DROP POLICY IF EXISTS class_videos_objects_member_read ON storage.objects;
CREATE POLICY class_videos_objects_member_read ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'class-videos'
    AND (storage.foldername(name))[1] = current_member_profile_id()::text
  );


-- ---------------------------------------------------------------------
-- 검증 SQL (적용 후 SQL Editor):
--   -- 1) 테이블/컬럼
--   SELECT column_name, data_type, is_nullable
--   FROM information_schema.columns WHERE table_name = 'class_videos';
--
--   -- 2) 테이블 RLS 정책 2개(rw=ALL / read=SELECT)
--   SELECT polname, cmd FROM pg_policies WHERE tablename = 'class_videos';
--   → class_videos_trainer_rw(ALL) / class_videos_member_read(SELECT)
--
--   -- 3) 버킷
--   SELECT id, public, file_size_limit FROM storage.buckets WHERE id='class-videos';
--   → 1행, public=false, 262144000
--
--   -- 4) Storage 정책 2개
--   SELECT polname FROM pg_policies
--   WHERE schemaname='storage' AND tablename='objects'
--     AND polname LIKE 'class_videos_objects_%';
--   → class_videos_objects_trainer / class_videos_objects_member_read
-- ---------------------------------------------------------------------
