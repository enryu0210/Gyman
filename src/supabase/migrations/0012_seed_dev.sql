-- =====================================================================
-- 0012_seed_dev.sql
-- 개발용 시드 데이터.
-- ⚠ 운영 환경에서는 절대 실행하지 말 것.
--
-- 사용 절차:
--   1. Supabase 대시보드에서 트레이너/회원 계정을 Auth로 미리 생성
--      (예: trainer1@gyman.dev, member1~3@gyman.dev)
--   2. 생성된 auth.users의 UUID를 아래 \set 변수에 입력
--   3. 이 파일 실행
--
-- 또는 본 파일을 그대로 실행하지 말고, 트레이너 앱에서 수동으로
-- 회원 등록/계약 등록을 테스트하는 것도 권장.
-- =====================================================================

-- 1. 테스트 센터 생성 (Auth 사용자와 무관, 즉시 INSERT 가능)
INSERT INTO centers (id, name, address, rules) VALUES
  (
    '00000000-0000-0000-0000-000000000001',
    '강남 테스트 센터',
    '서울 강남구 테헤란로 1',
    '{
      "late_cancel_hours": 24,
      "no_show_deduct": true,
      "late_arrival_minutes": 15
    }'::jsonb
  )
ON CONFLICT (id) DO NOTHING;


-- 2. 아래는 Auth 사용자가 먼저 생성된 후에 실행 (UUID 채워넣기)
-- ----------------------------------------------------------------------
-- \set trainer_uuid '00000000-0000-0000-0000-000000000010'
-- \set member1_uuid '00000000-0000-0000-0000-000000000020'
-- \set member2_uuid '00000000-0000-0000-0000-000000000021'
--
-- INSERT INTO trainer_profiles (user_id, center_id, name, phone, bio) VALUES
--   (:'trainer_uuid', '00000000-0000-0000-0000-000000000001',
--    '박트레이너', '010-1111-2222', '경력 5년');
--
-- INSERT INTO member_profiles
--   (user_id, center_id, name, phone, goal, experience, ai_consent) VALUES
--   (:'member1_uuid', '00000000-0000-0000-0000-000000000001',
--    '김민수', '010-1234-5678', '체중 감량 + 근력 향상',
--    '헬스 1년, PT 처음', true),
--   (:'member2_uuid', '00000000-0000-0000-0000-000000000001',
--    '이수진', '010-2345-6789', '체형 교정', '운동 초보', false);
--
-- INSERT INTO pt_contracts
--   (member_id, trainer_id, center_id, total_sessions, start_date, end_date, price) VALUES
--   (:'member1_uuid', :'trainer_uuid', '00000000-0000-0000-0000-000000000001',
--    20, '2026-03-15', '2026-06-15', 1200000);
-- ----------------------------------------------------------------------

-- 위 INSERT 들은 주석 처리. 사용자가 본인 환경의 Auth UUID로 채워서 실행.
