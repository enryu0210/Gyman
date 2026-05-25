-- =====================================================================
-- 0014_member_created_by_trainer.sql
--
-- 회원이 PT 계약 없이 등록만 된 상태에서도 트레이너가 본인 화면에서 볼 수
-- 있도록 RLS 정책을 확장한다.
--
-- 문제 (0013까지):
--   member_by_trainer 정책은 "계약 보유 회원" 만 보여준다.
--   따라서 회원을 INSERT한 직후엔 응답으로 1행 받지만, 새로고침/재진입 시
--   계약이 없어서 RLS가 차단 → 트레이너 입장에서 회원이 사라진 듯 보임.
--
-- 해결:
--   1. member_profiles에 created_by_trainer_id 컬럼 추가
--   2. DB default를 auth.uid()로 설정 → INSERT 시 자동으로 트레이너 본인 ID 기록
--   3. member_by_trainer 정책에 "본인이 만든 회원" 조건 OR 추가
--
-- 인수인계 (Phase 3) 대비:
--   created_by_trainer_id는 "처음 만든 사람" 기록 — 인수인계 후엔 그 시점의
--   pt_contracts.trainer_id 가 권한 결정. 두 조건을 OR로 묶어서 모두 보이게.
--
-- 적용 전제: 기존 member_profiles 데이터 0건 (베타 시작 직후).
--           NOT NULL 추가가 안전하려면 기존 행이 없거나, 있다면 별도 백필 필요.
--
-- 참고: docs/data_model.md §3.2 (갱신 예정), feat(member) Phase 1.2-A.
-- =====================================================================

BEGIN;

-- 1. created_by_trainer_id 컬럼 추가 + 기본값 auth.uid()
--    auth.uid()는 STABLE 함수이므로 INSERT 시 호출 가능.
ALTER TABLE member_profiles
  ADD COLUMN created_by_trainer_id uuid REFERENCES trainer_profiles(user_id);

-- 기본값을 별도 ALTER로 설정 — 컬럼 추가 시 한 번에 하지 않은 이유는
-- 기존 행에 default가 적용되지 않게 하기 위함. (있다면 별도 백필 필요)
ALTER TABLE member_profiles
  ALTER COLUMN created_by_trainer_id SET DEFAULT auth.uid();

-- 베타 시작 시 기존 데이터 0건 가정 — 안전하게 NOT NULL 강제.
-- 데이터가 있다면 이 줄을 주석 처리하고 별도 UPDATE로 백필 후 다시 ALTER.
ALTER TABLE member_profiles
  ALTER COLUMN created_by_trainer_id SET NOT NULL;

-- 본인이 만든 회원 빠른 조회용 인덱스 (트레이너 홈/목록의 자주 쓰는 패턴)
CREATE INDEX idx_member_created_by
  ON member_profiles(created_by_trainer_id);


-- 2. member_by_trainer 정책 확장
--    기존: 계약 보유 회원만
--    신규: 본인이 만든 회원 OR 계약 보유 회원 (인수인계 후도 포함)
DROP POLICY IF EXISTS member_by_trainer ON member_profiles;
CREATE POLICY member_by_trainer ON member_profiles
  FOR ALL USING (
    current_user_role() = 'trainer'
    AND (
      created_by_trainer_id = auth.uid()  -- 직접 등록한 회원
      OR is_member_of_trainer(id)         -- 계약으로 인수받은 회원 (Phase 3 대비)
    )
  );


COMMIT;

-- ---------------------------------------------------------------------
-- 적용 후 검증 SQL:
--
--   -- 1) 컬럼/기본값/NOT NULL 적용 확인
--   SELECT column_name, is_nullable, column_default
--   FROM information_schema.columns
--   WHERE table_name = 'member_profiles'
--     AND column_name = 'created_by_trainer_id';
--   → is_nullable NO / column_default 'auth.uid()' 기대.
--
--   -- 2) 정책 갱신 확인
--   SELECT polname, polcmd FROM pg_policy
--   WHERE polrelid = 'member_profiles'::regclass
--   ORDER BY polname;
--   → member_by_trainer, member_self_rw 두 행 기대.
--
--   -- 3) 트레이너로 로그인한 상태에서 회원 추가 → 새로고침 후에도 목록에 떠야 함.
-- ---------------------------------------------------------------------
