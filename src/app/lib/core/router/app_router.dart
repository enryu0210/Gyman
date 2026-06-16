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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/enums.dart';
import '../../features/admin/center/center_settings_screen.dart';
import '../../features/admin/dashboard/admin_dashboard_screen.dart';
import '../../features/auth/auth_providers.dart';
import '../../features/auth/claim_member_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/faq/faq_screen.dart';
import '../../features/member/booking/member_booking_screen.dart';
import '../../features/member/chat/member_chat_screen.dart';
import '../../features/member/home/member_home_screen.dart';
import '../../features/member/notices/member_notices_screen.dart';
import '../../features/member/progress/member_progress_screen.dart';
import '../../features/member/records/member_records_screen.dart';
import '../../features/member/self_log/self_log_screen.dart';
import '../../features/member/videos/member_videos_screen.dart';
import '../../features/trainer/ai_review/ai_review_screen.dart';
import '../../features/trainer/booking/booking_screen.dart';
import '../../features/trainer/chat/trainer_chat_list_screen.dart';
import '../../features/trainer/chat/trainer_member_chat_screen.dart';
import '../../features/trainer/home/trainer_home_screen.dart';
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
        // 로그인됐지만 프로필 미연결 → 초대 코드 입력(회원 연결).
        path: '/member/claim',
        builder: (context, state) => const ClaimMemberScreen(),
      ),
      GoRoute(
        path: '/trainer/home',
        builder: (context, state) => const TrainerHomeScreen(),
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
              // 회원과 채팅 — 상세 하위 라우트(뒤로가기가 상세로). S2 / 2.3.
              GoRoute(
                path: 'chat',
                builder: (context, state) {
                  final memberId = state.pathParameters['id']!;
                  return TrainerMemberChatScreen(memberId: memberId);
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/trainer/booking',
        builder: (context, state) => const BookingScreen(),
      ),
      GoRoute(
        path: '/trainer/ai-review',
        builder: (context, state) => const AiReviewScreen(),
      ),
      GoRoute(
        // 회원 채팅 대화 목록 (S2 / 2.3). 홈에서 push 진입.
        path: '/trainer/chat',
        builder: (context, state) => const TrainerChatListScreen(),
      ),
      GoRoute(
        path: '/member/home',
        builder: (context, state) => const MemberHomeScreen(),
      ),
      GoRoute(
        // 내 수업 기록 — 홈에서 context.push 로 진입하면 형제 최상위 라우트여도
        // 뒤로가기가 생긴다(CLAUDE.md go_router 지침). 라우트 맵 출처: develop_plan §3.2.
        path: '/member/records',
        builder: (context, state) => const MemberRecordsScreen(),
        routes: [
          // 변화 추이 — 기록 화면 하위 라우트로 두면 뒤로가기가 기록 화면으로.
          // 라우트 맵 출처: develop_plan §3.2(/member/records → 운동 기록 + 변화 추이 S1).
          GoRoute(
            path: 'progress',
            builder: (context, state) => const MemberProgressScreen(),
          ),
        ],
      ),
      GoRoute(
        // 받은 안내 — 홈에서 push 진입(뒤로가기 생성). 라우트 맵: develop_plan §3.2 확장.
        path: '/member/notices',
        builder: (context, state) => const MemberNoticesScreen(),
      ),
      GoRoute(
        // 예약 신청 — 홈에서 push 진입(뒤로가기 생성). 라우트 맵: develop_plan §3.2.
        path: '/member/booking',
        builder: (context, state) => const MemberBookingScreen(),
      ),
      GoRoute(
        // 트레이너와 채팅 — 홈에서 push 진입(뒤로가기 생성). S2 / 2.3.
        path: '/member/chat',
        builder: (context, state) => const MemberChatScreen(),
      ),
      GoRoute(
        // 내 수업 영상 — 홈에서 push 진입(뒤로가기 생성). S 시리즈(수업 영상 보관·열람).
        path: '/member/videos',
        builder: (context, state) => const MemberVideosScreen(),
      ),
      GoRoute(
        // 자주 묻는 질문(FAQ) — 홈에서 push 진입(뒤로가기 생성). S3 / 2.4.
        path: '/member/faq',
        builder: (context, state) => const FaqScreen(),
      ),
      GoRoute(
        // 셀프 운동 기록 — 홈에서 push 진입(뒤로가기 생성). S4 / 2.5.
        path: '/member/self-log',
        builder: (context, state) => const SelfLogScreen(),
      ),
      GoRoute(
        // 관리자 대시보드 (C1) — Phase 3.1-B. 역할 admin 만 진입(아래 redirect).
        path: '/admin/dashboard',
        builder: (context, state) => const AdminDashboardScreen(),
      ),
      GoRoute(
        // 센터 설정 (C2) — Phase 3.2. 규정 + PT 규정 FAQ 관리. 대시보드에서 push.
        path: '/admin/center',
        builder: (context, state) => const CenterSettingsScreen(),
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
    final isClaimPage = path == '/member/claim';

    // 2) 미로그인
    if (user == null) {
      return isLoggingIn ? null : '/login';
    }

    // 3) 로그인 됐는데 역할 판정 로딩 중 → 그대로 둠
    if (roleValue.isLoading) return null;
    final role = roleValue.value;

    // 3-1) 관리자 겸직 여부(트레이너 겸 관리자 판별). 판정 로딩 중이면 보류.
    //      역할 우선순위상 트레이너 겸 관리자는 role=trainer 라, /admin/* 허용은
    //      이 값으로 따로 본다(아래 5-2).
    final adminValue = ref.read(isAdminProvider);
    if (adminValue.isLoading) return null;
    final isAdmin = adminValue.value ?? false;

    // 4) 로그인됐는데 역할 미정 (프로필 미연결) → 초대 코드 입력으로
    if (role == null) {
      return isClaimPage ? null : '/member/claim';
    }

    // 5) 로그인 + 역할 있음
    final homeForRole = role.homeRoute;

    // 5-1) 로그인/연결 페이지에 머무름 → 자기 홈으로 (연결 직후 회원 홈 진입)
    if (isLoggingIn || isClaimPage) {
      return homeForRole;
    }

    // 5-2) 다른 역할의 경로 접근 차단 — 자기 홈으로 강제
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
    // 관리자 겸직 판정이 늦게 끝나도 redirect 가 재평가되도록 함께 구독.
    ref.listen<AsyncValue<dynamic>>(
      isAdminProvider,
      (_, _) => notifyListeners(),
    );
  }
}

// =====================================================================
// 임시/안내 화면들 — 각 feature 구현 시 교체됨
// =====================================================================

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

// 프로필 미연결 사용자는 더 이상 안내 화면(_NoRoleScreen)이 아니라
// 초대 코드 입력 화면(/member/claim, ClaimMemberScreen)으로 보낸다.
