-- =====================================================================
-- 0009_helper_functions.sql
-- RLS 정책에서 재사용할 헬퍼 함수
-- SECURITY DEFINER + STABLE: 정책 평가 시 효율적, 같은 쿼리 내 캐싱됨
-- 참고: docs/data_model.md §3.1
-- =====================================================================

-- 현재 로그인 사용자의 역할 (user_role)
-- 우선순위: trainer > admin > member (트레이너이면서 관리자인 경우 트레이너로 본다)
CREATE OR REPLACE FUNCTION current_user_role() RETURNS user_role
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT
    CASE
      WHEN EXISTS (
        SELECT 1 FROM trainer_profiles
        WHERE user_id = auth.uid() AND deleted_at IS NULL
      )
        THEN 'trainer'::user_role
      -- admin_profiles 테이블은 Phase 3에서 추가 예정.
      -- 현재는 미존재이므로 admin 분기는 주석 처리.
      -- WHEN EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid())
      --   THEN 'admin'::user_role
      WHEN EXISTS (
        SELECT 1 FROM member_profiles
        WHERE user_id = auth.uid() AND deleted_at IS NULL
      )
        THEN 'member'::user_role
    END
$$;


-- 현재 트레이너가 특정 회원의 담당인지 (현재 유효 계약 보유 여부)
-- RLS에서 "담당 회원만 조회/수정" 정책에 사용.
CREATE OR REPLACE FUNCTION is_member_of_trainer(p_member_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT EXISTS (
    SELECT 1 FROM pt_contracts
    WHERE member_id  = p_member_id
      AND trainer_id = auth.uid()
      AND deleted_at IS NULL
  )
$$;
