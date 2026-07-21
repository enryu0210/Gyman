/// 인증/역할 기반 라우터 redirect 결정 — **순수 함수**(Flutter/Riverpod 의존 0).
///
/// app_router 의 redirect closure 는 provider 값을 읽어 이 함수에 넘기기만 한다.
/// 분기를 여기 모아, "로그인 직후 이전(로그아웃) 역할값으로 초대코드에 튕기는"
/// 류의 회귀를 단위 테스트로 고정한다(이 영역이 반복 버그라 테스트 가치가 큼).
///
/// 참고: docs/develop_plan.md §3 라우트 맵, features/auth/role_repository.dart.
library;

import '../../domain/models/enums.dart';

/// 현재 상태에서 가야 할 redirect 경로. `null` = 현재 위치 유지.
///
/// 파라미터는 전부 provider 에서 뽑은 원시값 — 이 함수는 I/O 를 하지 않는다.
String? computeAuthRedirect({
  required String path,
  required bool authLoading,
  required bool isLoggedIn,
  required String? currentUserId,
  required bool passwordRecovery,
  required bool roleLoading,
  required UserRole? role,
  required bool isAdmin,
  required String? resolvedForUserId,
}) {
  final isLoginPage = path == '/login';
  final isClaimPage = path == '/member/claim';
  // 약관/정책은 로그인 전 가입 동의 링크에서도 열람해야 하므로 인증 게이트 예외.
  final isLegal = path.startsWith('/legal');

  // 1) 인증 로딩 중 → 그대로 둠(깜빡임 방지).
  if (authLoading) return null;

  // 2) 미로그인 → 로그인/약관만 허용, 나머지는 /login.
  if (!isLoggedIn) {
    return (isLoginPage || isLegal) ? null : '/login';
  }

  // 2-1) 비밀번호 재설정 딥링크 복귀(복구 세션) → 역할 분기보다 먼저 가로채
  //      새 비번 입력 화면으로 강제.
  if (passwordRecovery) {
    return path == '/reset-password' ? null : '/reset-password';
  }

  // 3) 역할 판정 로딩 중 → 그대로 둠.
  if (roleLoading) return null;

  // 3-1) **staleness 가드(회귀 방어).** 역할값이 *현재 로그인 사용자* 에 대해
  //      확정된 게 아니면(로그인 직후 아직 이전 값이 남아있는 창) 판정이 따라잡을
  //      때까지 보류한다. 이게 없으면 라우터가 이전(로그아웃) role=null 을 보고
  //      기존 트레이너/회원을 초대코드 화면으로 튕긴다(실측된 콜드스타트 레이스).
  if (resolvedForUserId != currentUserId) return null;

  // 4) 로그인됐는데 역할 미정(프로필 미연결) → 초대 코드 입력으로.
  //    단, 설정/약관/정책은 미연결 상태에서도 닿게 허용(U1: 탈퇴·문의 탈출구).
  if (role == null) {
    final allowedWhenUnlinked = isClaimPage || path == '/settings' || isLegal;
    return allowedWhenUnlinked ? null : '/member/claim';
  }

  // 5) 로그인 + 역할 있음.
  final homeForRole = role.homeRoute;

  // 5-1) 로그인/연결 페이지에 머무름 → 자기 홈으로.
  if (isLoginPage || isClaimPage) return homeForRole;

  // 5-2) 다른 역할의 경로 접근 차단 — 자기 홈으로 강제.
  if (path.startsWith('/trainer/') && role != UserRole.trainer) {
    return homeForRole;
  }
  if (path.startsWith('/member/') && role != UserRole.member) {
    return homeForRole;
  }
  // 관리자 경로는 admin 역할이거나 관리자 겸직(트레이너 겸 관리자)이면 허용.
  if (path.startsWith('/admin/') && role != UserRole.admin && !isAdmin) {
    return homeForRole;
  }

  return null;
}
