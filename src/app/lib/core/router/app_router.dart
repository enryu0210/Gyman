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
/// **트레이너 셸 (UI 1차 개편 단계 A):**
///   트레이너 경로는 [StatefulShellRoute.indexedStack] 아래 4개 브랜치(홈·회원·일정·
///   채팅)로 묶여 하단 탭이 항상 붙는다. 브랜치별 Navigator 가 살아 있어 탭을 오가도
///   스크롤 위치와 목록 상태가 보존된다.
///
///   **탭 루트 vs 드릴인 (계획서 §7 리스크 대응):** 회원 상세·수업 기록·1:1 채팅처럼
///   파고드는 화면은 브랜치 안에 넣지 않고 **셸 밖 최상위 라우트**로 둔다.
///     - 브랜치에 속한 라우트를 다른 탭에서 push 하면 셸이 그 브랜치로 따라 옮겨가
///       뒤로 나왔을 때 엉뚱한 탭이 선택돼 있다. 셸 밖이면 어느 탭에서 눌러도 동작이
///       같고, 뒤로가기는 누른 탭으로 그대로 복귀한다.
///     - 기록·채팅은 집중 화면이라 하단 바가 없는 편이 낫고, 키보드와도 안 겹친다.
///   경로 문자열(`/trainer/members/:id` …)은 개편 전과 **그대로** — 화면 코드의
///   push 대상과 역할 redirect 규칙을 건드리지 않는다.
///
/// 라우트 맵 출처: docs/develop_plan.md §3, docs/ui_renewal_phase1_plan.md §5.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_redirect.dart';
import '../../features/admin/center/center_settings_screen.dart';
import '../../features/admin/dashboard/admin_dashboard_screen.dart';
import '../../features/admin/support/support_inbox_screen.dart';
import '../../features/auth/auth_providers.dart';
import '../../features/auth/claim_member_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/reset_password_screen.dart';
import '../../features/faq/faq_screen.dart';
import '../../features/legal/legal_content.dart';
import '../../features/legal/legal_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/member/attendance/attendance_calendar_screen.dart';
import '../../features/member/booking/member_booking_screen.dart';
import '../../features/member/chat/member_chat_screen.dart';
import '../../features/member/home/member_home_screen.dart';
import '../../features/member/notices/member_notices_screen.dart';
import '../../features/member/profile/member_profile_screen.dart';
import '../../features/member/progress/member_progress_screen.dart';
import '../../features/member/records/member_records_screen.dart';
import '../../features/member/shell/member_shell.dart';
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
import '../../features/trainer/shell/trainer_shell.dart';

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
        // 비밀번호 재설정 딥링크 복귀 후 새 비번 입력 (E-2). 진입은
        // redirect 가 passwordRecovery 플래그를 보고 강제 — 직접 네비게이션 X.
        path: '/reset-password',
        builder: (context, state) => const ResetPasswordScreen(),
      ),
      // ───────────────────────── 트레이너 앱 셸 (하단 탭 4개) ─────────────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            TrainerShell(navigationShell: navigationShell),
        branches: [
          // 탭 0 — 홈
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/trainer/home',
                builder: (context, state) => const TrainerHomeScreen(),
              ),
            ],
          ),
          // 탭 1 — 회원 목록(탭 루트만). 상세 이하는 아래 셸 밖 라우트.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/trainer/members',
                builder: (context, state) => const MemberListScreen(),
              ),
            ],
          ),
          // 탭 2 — 일정(예약 관리 + 승인 요청)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/trainer/booking',
                builder: (context, state) => const BookingScreen(),
              ),
            ],
          ),
          // 탭 3 — 채팅 대화 목록 (S2 / 2.3)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/trainer/chat',
                builder: (context, state) => const TrainerChatListScreen(),
              ),
            ],
          ),
        ],
      ),
      // ─────────────────── 트레이너 드릴인 (셸 밖 = 하단 바 없음) ───────────────
      GoRoute(
        // 회원 상세. 셸의 회원 탭(`/trainer/members`)과 경로가 이어지지만 라우트
        // 계층상 형제 — 어느 탭에서 push 해도 셸의 선택 탭이 바뀌지 않는다.
        path: '/trainer/members/:id',
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
      GoRoute(
        // AI 검수 — 일부러 탭에 두지 않는다(계획서 §3.1). 홈의 "처리할 일"에서만
        // 진입하므로 셸 밖 최상위 라우트로 두어 전체 화면으로 열린다.
        path: '/trainer/ai-review',
        builder: (context, state) => const AiReviewScreen(),
      ),
      // ───────────────────────── 회원 앱 셸 (하단 탭 5개) ────────────────────
      // 트레이너 셸과 같은 원칙: 탭 루트만 브랜치에 두고, 파고드는 화면
      // (변화 추이·출석 달력·셀프 기록·영상·안내·FAQ)은 셸 밖 최상위 라우트.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MemberShell(navigationShell: navigationShell),
        branches: [
          // 탭 0 — 홈
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/member/home',
                builder: (context, state) => const MemberHomeScreen(),
              ),
            ],
          ),
          // 탭 1 — 일정(출석 달력). 지난 출석과 다가올 PT 를 한 화면에서 보는
          // **열람** 면이라 탭 루트로 맞다. 가끔 하는 **동작**인 예약 신청은
          // 이 화면의 FAB 로 push — 탭/버튼 역할을 뒤집어 잡았다.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/member/attendance',
                builder: (context, state) => const AttendanceCalendarScreen(),
              ),
            ],
          ),
          // 탭 2 — 기록(수업 기록). 셀프 기록·변화 추이는 이 화면에서 push.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/member/records',
                builder: (context, state) => const MemberRecordsScreen(),
              ),
            ],
          ),
          // 탭 3 — 트레이너와 채팅 (S2 / 2.3)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/member/chat',
                builder: (context, state) => const MemberChatScreen(),
              ),
            ],
          ),
          // 탭 4 — 내 정보(영상·안내·FAQ·설정 집결지)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/member/profile',
                builder: (context, state) => const MemberProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      // ─────────────────── 회원 드릴인 (셸 밖 = 하단 바 없음) ───────────────────
      GoRoute(
        // 변화 추이 — 기록 탭에서 push. 경로는 개편 전 그대로(`/member/records/progress`)
        // 지만 라우트 계층상 형제라, 어느 탭에서 눌러도 탭이 튀지 않는다.
        path: '/member/records/progress',
        builder: (context, state) => const MemberProgressScreen(),
      ),
      GoRoute(
        // 예약 신청 — 일정 탭(출석 달력)의 FAB 에서 push. 뒤로가기로 달력 복귀.
        path: '/member/booking',
        builder: (context, state) => const MemberBookingScreen(),
      ),
      GoRoute(
        // 받은 안내 — 내 정보 탭에서 push. 라우트 맵: develop_plan §3.2 확장.
        path: '/member/notices',
        builder: (context, state) => const MemberNoticesScreen(),
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
      GoRoute(
        // 운영자 문의함 — 관리자 대시보드에서 push. /admin/* 라 admin/겸직만 진입.
        path: '/admin/support',
        builder: (context, state) => const SupportInboxScreen(),
      ),
      GoRoute(
        // 설정 — 모든 역할 공통. 문의/약관/정책/로그아웃/탈퇴 집결지.
        // 역할 무관 진입 허용(미연결 사용자도 닿게 — U1). 진입은 각 홈에서 push.
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        // 이용약관 — 로그인 전(가입 동의 링크)에도 열람 가능(아래 redirect 예외).
        path: '/legal/terms',
        builder: (context, state) => const LegalScreen(doc: LegalDoc.terms),
      ),
      GoRoute(
        // 개인정보 처리방침 — 로그인 전에도 열람 가능.
        path: '/legal/privacy',
        builder: (context, state) => const LegalScreen(doc: LegalDoc.privacy),
      ),
    ],
    errorBuilder: (context, state) => _PlaceholderScreen(
      title: '경로를 찾을 수 없음',
      subtitle: state.uri.toString(),
    ),
  );
});

/// redirect 함수 빌더 — ref를 closure로 캡처해서 provider 값을 읽고,
/// 순수 함수 [computeAuthRedirect] 에 넘긴다(분기 로직은 그쪽에서 테스트됨).
///
/// 역할/겸직/확정대상 user 를 **단일 소스** [currentRoleInfoProvider] 에서 함께
/// 읽어, 셋이 서로 어긋나는 순간(로그인 직후 stale)을 구조적으로 없앤다.
GoRouterRedirect _redirect(Ref ref) {
  return (context, state) {
    final authValue = ref.read(authStateProvider);
    final roleInfoValue = ref.read(currentRoleInfoProvider);
    final user = authValue.value;
    final info = roleInfoValue.value;

    return computeAuthRedirect(
      path: state.matchedLocation,
      authLoading: authValue.isLoading,
      isLoggedIn: user != null,
      currentUserId: user?.id,
      passwordRecovery: ref.read(passwordRecoveryProvider),
      roleLoading: roleInfoValue.isLoading,
      role: info?.role,
      isAdmin: info?.isAdmin ?? false,
      resolvedForUserId: info?.resolvedForUserId,
    );
  };
}

/// Riverpod provider 변경을 go_router에 알려주는 어댑터.
///
/// authStateProvider 또는 currentRoleInfoProvider가 바뀔 때마다 [notifyListeners]
/// 호출 → go_router가 redirect 재평가.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen<AsyncValue<dynamic>>(
      authStateProvider,
      (_, _) => notifyListeners(),
    );
    // 역할·겸직·확정대상 user 를 한 소스로 구독 — redirect 도 이 소스만 읽으므로
    // 로딩→확정 전이가 한 번에 반영된다(파생 provider 를 따로 구독할 필요 없음).
    ref.listen<AsyncValue<dynamic>>(
      currentRoleInfoProvider,
      (_, _) => notifyListeners(),
    );
    // 비번 재설정 딥링크 복귀 플래그가 바뀌면 redirect 재평가(→ /reset-password).
    ref.listen<bool>(
      passwordRecoveryProvider,
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
