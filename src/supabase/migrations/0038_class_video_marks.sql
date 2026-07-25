-- =====================================================================
-- 0038_class_video_marks.sql
--
-- 수업 영상 "시점 지적" — 동작 습관·체형 제약 코칭 L2.
-- (docs/design_movement_coaching.md §3.4, develop_plan §4 Phase 4.8)
--
-- 무엇을 하는가:
--   트레이너가 회원 영상(0027)을 보다가 특정 시점에 코멘트를 남긴다.
--     0:12 · 무릎 · "여기서 오른쪽 무릎이 안으로 말림"
--   회원이 그 영상을 재생하면 **그 지점에서 코멘트가 자동으로 뜬다.**
--
-- 왜 이게 "동작 습관 피드백"의 본체인가:
--   자동 검출(L3)로 잡을 수 있는 건 사실상 무릎 모임(FPPA) 하나뿐이다(설계 §2).
--   반면 트레이너의 눈은 이미 모든 걸 보고 있고 정확도는 사람 수준이다.
--   CV 없이, 신규 의존성 없이, 요구의 대부분을 답하는 지점.
--
-- 부가 효과: 마킹이 쌓이면 L3(자동 검출)의 **검증 데이터셋**이 된다 —
--   "앱이 검출한 것 vs 트레이너가 마킹한 것"으로 정확도를 실측할 수 있다.
--
-- 검수 게이트가 없는 이유:
--   트레이너가 의도적으로 다는 코멘트라 AI 초안과 성격이 다르다.
--   영상 시스템(0027)·트래킹 설계와 같은 논리 — 사람이 쓴 글은 게이트 대상이 아니다.
--
-- 멱등: CREATE TABLE IF NOT EXISTS / DROP POLICY IF EXISTS → CREATE.
--
-- 참고: 0027(class_videos), 0036(member_conditions), 0009/0013(헬퍼).
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1. 테이블
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS class_video_marks (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- 대상 영상. 영상이 지워지면 마킹도 함께 정리(고아 방지).
  video_id   uuid NOT NULL REFERENCES class_videos(id) ON DELETE CASCADE,

  -- 영상 내 시점(ms). 0027 이 120초 상한이라 int 로 충분.
  t_ms       int NOT NULL CHECK (t_ms >= 0),

  -- 부위 태그(선택) — 'knee'|'hip'|'lumbar'|'shoulder'|'ankle'|'neck' 등.
  -- enum 이 아니라 text 인 이유는 member_conditions.code 와 같다: 목록이 트레이너
  -- 사용에 따라 바뀌고, 표시명은 앱이 들고 있으며, 모르는 값은 원문 표시로 흡수한다.
  body_part  text,

  -- 지적 내용. 빈 코멘트는 의미가 없으므로 CHECK 로 막는다.
  comment    text NOT NULL CHECK (length(trim(comment)) > 0),

  -- 남긴 트레이너. 계정 삭제돼도 코멘트는 보존 → SET NULL.
  created_by uuid REFERENCES trainer_profiles(user_id) ON DELETE SET NULL,

  created_at timestamptz NOT NULL DEFAULT now()
);

-- 주 조회 패턴 = "이 영상의 마킹을 시점 순으로".
CREATE INDEX IF NOT EXISTS idx_video_marks_video
  ON class_video_marks(video_id, t_ms);


-- ---------------------------------------------------------------------
-- 2. RLS
--
--   권한은 "그 영상을 볼 수 있는가"로 결정된다 → class_videos 를 경유해 판정.
--   ⓘ 정책 안의 서브쿼리에도 class_videos 의 RLS 가 그대로 적용된다.
--     즉 영상 자체가 안 보이는 사용자는 EXISTS 가 false 가 되어 마킹도 못 본다
--     — 권한 규칙이 한 곳(0027)에 남고 여기선 이중으로 막히는 셈.
--     아래 명시적 조건은 0027 정책이 바뀌어도 버티도록 남긴 방어선이다.
-- ---------------------------------------------------------------------
ALTER TABLE class_video_marks ENABLE ROW LEVEL SECURITY;

-- 2-1) 트레이너: 담당 회원 영상의 마킹을 남기고/고치고/지운다.
DROP POLICY IF EXISTS video_marks_trainer_rw ON class_video_marks;
CREATE POLICY video_marks_trainer_rw ON class_video_marks
  FOR ALL
  USING (
    current_user_role() = 'trainer'
    AND EXISTS (
      SELECT 1 FROM class_videos v
      WHERE v.id = class_video_marks.video_id
        AND is_member_of_trainer(v.member_id)
    )
  )
  WITH CHECK (
    current_user_role() = 'trainer'
    AND EXISTS (
      SELECT 1 FROM class_videos v
      WHERE v.id = class_video_marks.video_id
        AND is_member_of_trainer(v.member_id)
    )
  );

-- 2-2) 회원: 본인 영상의 마킹만 읽기.
DROP POLICY IF EXISTS video_marks_member_read ON class_video_marks;
CREATE POLICY video_marks_member_read ON class_video_marks
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM class_videos v
      WHERE v.id = class_video_marks.video_id
        AND v.member_id = current_member_profile_id()
    )
  );

COMMIT;


-- ---------------------------------------------------------------------
-- 검증 SQL (적용 후 SQL Editor):
--
--   -- 1) 정책 2개
--   SELECT policyname, cmd FROM pg_policies WHERE tablename = 'class_video_marks';
--   → video_marks_trainer_rw(ALL) / video_marks_member_read(SELECT) 기대.
--
--   -- 2) 빈 코멘트 차단
--   INSERT INTO class_video_marks (video_id, t_ms, comment)
--   VALUES ('<본인 담당 회원 영상 id>', 1000, '   ');
--   → check constraint 위반 기대.
--
--   -- 3) 음수 시점 차단
--   INSERT INTO class_video_marks (video_id, t_ms, comment)
--   VALUES ('<같은 영상 id>', -1, 'x');
--   → check constraint 위반 기대.
--
--   -- 4) 트레이너 계정: 담당 회원 영상에 INSERT 성공 → SELECT 로 보임
--   INSERT INTO class_video_marks (video_id, t_ms, body_part, comment)
--   VALUES ('<영상 id>', 12000, 'knee', '여기서 무릎이 안으로 말림');
--
--   -- 5) 회원 계정으로 로그인: 본인 영상 마킹만 보이는지
--   SELECT count(*) FROM class_video_marks;
--   → 본인 영상 것만 기대(타 회원 영상 마킹 0건).
--
--   -- 6) 영상 삭제 시 마킹도 사라지는지(CASCADE)
--   DELETE FROM class_videos WHERE id = '<영상 id>';
--   SELECT count(*) FROM class_video_marks WHERE video_id = '<영상 id>';  -- 0 기대
-- ---------------------------------------------------------------------
