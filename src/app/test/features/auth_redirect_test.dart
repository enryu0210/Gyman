import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/core/router/auth_redirect.dart';
import 'package:gyman/domain/models/enums.dart';

/// [computeAuthRedirect] 순수 함수 테스트.
///
/// 핵심 회귀: **콜드스타트 첫 로그인 시 초대코드 화면으로 튕기는 버그**.
/// 로그인 직후 역할값이 아직 *이전(로그아웃) 값* 이면(resolvedForUserId 가
/// 현재 사용자와 다름) redirect 를 보류해야 한다 — 여기서 /member/claim 을
/// 반환하면 기존 트레이너/회원이 초대코드로 튕긴다.
void main() {
  // 자주 쓰는 기본 인자 — 케이스별로 필요한 것만 덮어씀.
  String? redirect({
    required String path,
    bool authLoading = false,
    bool isLoggedIn = true,
    String? currentUserId = 'user-x',
    bool passwordRecovery = false,
    bool roleLoading = false,
    UserRole? role,
    bool isAdmin = false,
    String? resolvedForUserId = 'user-x',
  }) {
    return computeAuthRedirect(
      path: path,
      authLoading: authLoading,
      isLoggedIn: isLoggedIn,
      currentUserId: currentUserId,
      passwordRecovery: passwordRecovery,
      roleLoading: roleLoading,
      role: role,
      isAdmin: isAdmin,
      resolvedForUserId: resolvedForUserId,
    );
  }

  group('staleness 가드 — 콜드스타트 첫 로그인 튕김 회귀', () {
    test('로그인 직후 역할값이 이전(로그아웃) 값(resolvedForUserId=null)이면 튕기지 않고 보류', () {
      // user-x 로 로그인했지만 역할 판정은 아직 이전 none(미로그인) 값이 남음.
      final target = redirect(
        path: '/trainer/home',
        role: null,
        resolvedForUserId: null, // 아직 이 사용자에 대해 확정 안 됨
      );
      // /member/claim 으로 튕기면 안 됨 — 판정이 따라올 때까지 보류(null).
      expect(target, isNull);
    });

    test('역할값이 다른 사용자 대상으로 확정된 경우에도 보류', () {
      final target = redirect(
        path: '/trainer/home',
        currentUserId: 'user-x',
        role: UserRole.trainer,
        resolvedForUserId: 'user-y', // 이전 사용자 값
      );
      expect(target, isNull);
    });

    test('현재 사용자에 대해 확정된 뒤엔 정상 라우팅(로그인 페이지→트레이너 홈)', () {
      final target = redirect(
        path: '/login',
        role: UserRole.trainer,
        resolvedForUserId: 'user-x',
      );
      expect(target, '/trainer/home');
    });
  });

  group('진짜 미연결(초대코드 필요) — 현재 사용자 대상으로 확정된 role=null', () {
    test('보호 경로에서 미연결이면 /member/claim 으로', () {
      final target = redirect(
        path: '/trainer/home',
        role: null,
        resolvedForUserId: 'user-x', // 이 사용자에 대해 확정된 "미연결"
      );
      expect(target, '/member/claim');
    });

    test('설정 화면은 미연결이어도 허용(U1 탈출구)', () {
      final target = redirect(
        path: '/settings',
        role: null,
        resolvedForUserId: 'user-x',
      );
      expect(target, isNull);
    });

    test('약관은 미연결이어도 허용', () {
      final target = redirect(
        path: '/legal/terms',
        role: null,
        resolvedForUserId: 'user-x',
      );
      expect(target, isNull);
    });
  });

  group('로딩/미로그인', () {
    test('인증 로딩 중이면 보류', () {
      expect(redirect(path: '/trainer/home', authLoading: true), isNull);
    });

    test('역할 판정 로딩 중이면 보류', () {
      expect(redirect(path: '/trainer/home', roleLoading: true), isNull);
    });

    test('미로그인 + 보호 경로 → /login', () {
      expect(
        redirect(path: '/trainer/home', isLoggedIn: false, currentUserId: null),
        '/login',
      );
    });

    test('미로그인 + 로그인 페이지 → 그대로', () {
      expect(
        redirect(path: '/login', isLoggedIn: false, currentUserId: null),
        isNull,
      );
    });

    test('미로그인 + 약관 → 그대로(가입 동의 링크)', () {
      expect(
        redirect(path: '/legal/privacy', isLoggedIn: false, currentUserId: null),
        isNull,
      );
    });
  });

  group('역할별 경로 분리', () {
    test('트레이너가 회원 경로 접근 → 트레이너 홈으로', () {
      expect(
        redirect(path: '/member/home', role: UserRole.trainer),
        '/trainer/home',
      );
    });

    test('회원이 트레이너 경로 접근 → 회원 홈으로', () {
      expect(
        redirect(path: '/trainer/members', role: UserRole.member),
        '/member/home',
      );
    });

    test('트레이너 겸 관리자(role=trainer, isAdmin=true)는 /admin/* 허용', () {
      expect(
        redirect(path: '/admin/dashboard', role: UserRole.trainer, isAdmin: true),
        isNull,
      );
    });

    test('관리자 아닌 트레이너가 /admin/* 접근 → 트레이너 홈으로', () {
      expect(
        redirect(path: '/admin/dashboard', role: UserRole.trainer, isAdmin: false),
        '/trainer/home',
      );
    });

    test('자기 역할 경로는 통과', () {
      expect(redirect(path: '/trainer/members', role: UserRole.trainer), isNull);
    });
  });

  group('비밀번호 재설정 복구 세션', () {
    test('복구 세션이면 /reset-password 로 강제', () {
      expect(
        redirect(path: '/trainer/home', passwordRecovery: true),
        '/reset-password',
      );
    });

    test('이미 /reset-password 면 그대로', () {
      expect(
        redirect(path: '/reset-password', passwordRecovery: true),
        isNull,
      );
    });
  });
}
