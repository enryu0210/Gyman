import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 앱 라우터 — go_router 기반.
///
/// 현재(Phase 0.6)는 골격만 잡아두는 placeholder 라우트들이다.
/// 각 화면은 Phase 1.1~1.7에서 실제 구현으로 교체된다.
///
/// 라우트 맵 출처: docs/develop_plan.md §3
///   /login                       → 로그인 (역할 자동 분기)
///   /trainer/home                → 트레이너 홈
///   /member/home                 → 회원 홈
///   /admin/dashboard             → 관리자 대시보드
///
/// 역할 분기는 Phase 1.1에서 [currentUserProvider]와 redirect 로직으로 처리한다.
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    debugLogDiagnostics: true,
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const _PlaceholderScreen(
          title: '로그인',
          subtitle: 'Phase 1.1에서 Supabase Auth + 역할 분기 구현',
        ),
      ),
      GoRoute(
        path: '/trainer/home',
        builder: (context, state) => const _PlaceholderScreen(
          title: '트레이너 홈',
          subtitle: 'Phase 1 — 오늘 수업 + 재등록 알림 (M1)',
        ),
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

/// 골격 단계의 임시 화면. 실제 구현은 각 feature 하위에서.
class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
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
              const SizedBox(height: 32),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in const [
                    ('/login', '로그인'),
                    ('/trainer/home', '트레이너'),
                    ('/member/home', '회원'),
                    ('/admin/dashboard', '관리자'),
                  ])
                    OutlinedButton(
                      onPressed: () => context.go(r.$1),
                      child: Text(r.$2),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
