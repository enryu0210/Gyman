/// 앱 라우터 — go_router 기반 + Riverpod 인증/역할 redirect.
///
/// **redirect 정책:**
///   1) Auth/Role 로딩 중 → redirect 보류 (현재 위치 유지)
///   2) 미로그인 → /login (이미 /login이면 그대로)
///   3) 로그인 + 역할 미정(프로필 미생성) → /no-role 안내 화면
///   4) 로그인 + 역할 있음:
///       - /login에 머물러 있으면 역할 홈으로
///       - 다른 역할의 경로 접근 시 자기 홈으로 (권한 분리)
///
/// **왜 ChangeNotifier 어댑터?**
///   go_router의 [refreshListenable]은 Listenable 타입을 요구하지만,
///   Riverpod provider는 그것이 아니라서 변경을 ChangeNotifier로 받아넘긴다.
///   ref.listen → notifyListeners() 만 하면 끝.
///
/// 라우트 맵 출처: docs/develop_plan.md §3.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/enums.dart';
import '../../features/auth/auth_providers.dart';
import '../../features/auth/login_screen.dart';
import '../../features/trainer/member/member_detail_screen.dart';
import '../../features/trainer/member/member_list_screen.dart';
import '../../features/trainer/session_log/session_log_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  // Provider가 폐기될 때 listener도 같이 해제 — 메모리 누수 방지.
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/login',
    debugLogDiagnostics: true,
    refreshListenable: refresh,
    redirect: _redirect(ref),
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/no-role',
        builder: (context, state) => const _NoRoleScreen(),
      ),
      GoRoute(
        path: '/trainer/home',
        builder: (context, state) => const _TrainerHomeScreen(),
      ),
      GoRoute(
        path: '/trainer/members',
        builder: (context, state) => const MemberListScreen(),
        routes: [
          GoRoute(
            // 상세 — `/trainer/members/:id` 자식 라우트로 두면 뒤로가기가
            // 자연스럽게 목록으로 돌아간다.
            path: ':id',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return MemberDetailScreen(memberId: id);
            },
            routes: [
              // 수업 기록 — 회원 상세 하위에 두면 back nav 가 자연스럽게 상세로.
              // 신규: /trainer/members/:id/session/new
              // 수정: /trainer/members/:id/session/:sid
              GoRoute(
                path: 'session/new',
                builder: (context, state) {
                  final memberId = state.pathParameters['id']!;
                  return SessionLogScreen(memberId: memberId);
                },
              ),
              GoRoute(
                path: 'session/:sid',
                builder: (context, state) {
                  final memberId = state.pathParameters['id']!;
                  final sid = state.pathParameters['sid']!;
                  return SessionLogScreen(
                    memberId: memberId,
                    sessionId: sid,
                  );
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/member/home',
        builder: (context, state) => const _PlaceholderScreen(
          title: '회원 홈',
          subtitle: 'Phase 2 — 다음 수업 + 잔여 횟수',
        ),
      ),
      GoRoute(
        path: '/admin/dashboard',
        builder: (context, state) => const _PlaceholderScreen(
          title: '관리자 대시보드',
          subtitle: 'Phase 3 — 재등록률/매출/노쇼율 (C1)',
        ),
      ),
    ],
    errorBuilder: (context, state) => _PlaceholderScreen(
      title: '경로를 찾을 수 없음',
      subtitle: state.uri.toString(),
    ),
  );
});

/// redirect 함수 빌더 — ref를 closure로 캡처해서 provider 값을 읽는다.
GoRouterRedirect _redirect(Ref ref) {
  return (context, state) {
    final authValue = ref.read(authStateProvider);
    final roleValue = ref.read(currentRoleProvider);
    final path = state.matchedLocation;

    // 1) 로딩 중이면 그대로 둠 — 깜빡임 방지
    if (authValue.isLoading) return null;

    final user = authValue.value;
    final isLoggingIn = path == '/login';
    final isNoRolePage = path == '/no-role';

    // 2) 미로그인
    if (user == null) {
      return isLoggingIn ? null : '/login';
    }

    // 3) 로그인 됐는데 역할 판정 로딩 중 → 그대로 둠
    if (roleValue.isLoading) return null;
    final role = roleValue.value;

    // 4) 로그인됐는데 역할 미정 (프로필 미생성)
    if (role == null) {
      return isNoRolePage ? null : '/no-role';
    }

    // 5) 로그인 + 역할 있음
    final homeForRole = role.homeRoute;

    // 5-1) 로그인/노롤 페이지에 머무름 → 자기 홈으로
    if (isLoggingIn || isNoRolePage) {
      return homeForRole;
    }

    // 5-2) 다른 역할의 경로 접근 차단 — 자기 홈으로 강제
    if (path.startsWith('/trainer/') && role != UserRole.trainer) {
      return homeForRole;
    }
    if (path.startsWith('/member/') && role != UserRole.member) {
      return homeForRole;
    }
    if (path.startsWith('/admin/') && role != UserRole.admin) {
      return homeForRole;
    }

    return null;
  };
}

/// Riverpod provider 변경을 go_router에 알려주는 어댑터.
///
/// authStateProvider 또는 currentRoleProvider가 바뀔 때마다 [notifyListeners]
/// 호출 → go_router가 redirect 재평가.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen<AsyncValue<dynamic>>(
      authStateProvider,
      (_, _) => notifyListeners(),
    );
    ref.listen<AsyncValue<dynamic>>(
      currentRoleProvider,
      (_, _) => notifyListeners(),
    );
  }
}

// =====================================================================
// 임시/안내 화면들 — 각 feature 구현 시 교체됨
// =====================================================================

/// 트레이너 홈 임시 화면.
/// Phase 1.7에서 "오늘 수업 + 재등록 알림" 위젯들로 본격 교체됨.
/// 현재(1.2-A)는 회원 목록으로 진입하는 카드 1개 + 로그아웃만.
class _TrainerHomeScreen extends ConsumerWidget {
  const _TrainerHomeScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('트레이너 홈'),
        actions: [
          IconButton(
            tooltip: '로그아웃',
            icon: const Icon(Icons.logout),
            onPressed: () =>
                ref.read(signInControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '환영합니다 👋',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '회원 관리부터 시작해 보세요.\n'
                '오늘 수업, 재등록 알림 등은 다음 단계에서 추가됩니다.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () => context.go('/trainer/members'),
                icon: const Icon(Icons.group),
                label: const Text('회원 목록'),
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 골격 단계의 임시 화면. 실제 구현은 각 feature 하위에서.
class _PlaceholderScreen extends ConsumerWidget {
  const _PlaceholderScreen({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: '로그아웃',
            icon: const Icon(Icons.logout),
            onPressed: () =>
                ref.read(signInControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 로그인은 됐지만 trainer_profiles/member_profiles 행이 없는 사용자용.
///
/// 베타 단계 시나리오: 트레이너가 Supabase 대시보드에서 user는 만들었는데
/// trainer_profiles INSERT를 깜빡한 케이스. 사용자가 막막하지 않게 명확한 안내.
class _NoRoleScreen extends ConsumerWidget {
  const _NoRoleScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.account_circle_outlined, size: 64, color: colors.outline),
                const SizedBox(height: 16),
                Text(
                  '계정 설정이 완료되지 않았습니다',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  '로그인은 됐지만 트레이너/회원 프로필이 등록되어 있지 않습니다.\n'
                  '담당 트레이너 또는 관리자에게 문의해 주세요.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton.tonal(
                  onPressed: () =>
                      ref.read(signInControllerProvider.notifier).signOut(),
                  child: const Text('로그아웃'),
                ),
                if (kDebugMode) ...[
                  const SizedBox(height: 16),
                  Text(
                    '[Dev] Supabase SQL:\n'
                    "INSERT INTO trainer_profiles (user_id, name)\n"
                    "VALUES ('<auth.uid()>', '이름');",
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: colors.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
