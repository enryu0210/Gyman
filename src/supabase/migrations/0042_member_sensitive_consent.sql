-- 트레이너 JWT에는 회원 동의 행의 RLS 접근권한이 없으므로 판정값만 공개한다.
-- 담당 관계와 가입 여부를 확인해 다른 회원의 동의 정보 노출을 막는다.
CREATE OR REPLACE FUNCTION public.member_sensitive_consent(p_member_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT public.is_member_of_trainer(p_member_id) AND EXISTS (
    SELECT 1 FROM public.member_profiles AS member
    JOIN public.user_consents AS consent ON consent.user_id = member.user_id
    WHERE member.id = p_member_id
      AND member.user_id IS NOT NULL
      AND consent.sensitive_version IS NOT NULL
  );
$$;
REVOKE ALL ON FUNCTION public.member_sensitive_consent(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.member_sensitive_consent(uuid) TO authenticated;

-- 검증 SQL (적용 후 각 계정의 JWT 컨텍스트에서 실행)
-- SELECT public.member_sensitive_consent('<회원_ID>'::uuid);
-- 담당 트레이너 + 가입 회원 + 민감정보 동의: true
-- 담당 아닌 트레이너 / 회원 계정 / 미가입 회원 / 미동의 / 행 없음: false
-- anon 계정: 실행 권한 거부
-- SELECT prosecdef, proconfig FROM pg_proc
-- WHERE oid = 'public.member_sensitive_consent(uuid)'::regprocedure;
-- 예상: prosecdef=true, proconfig={search_path=public}
-- SELECT has_function_privilege('anon', 'public.member_sensitive_consent(uuid)', 'EXECUTE');
-- 예상: false
