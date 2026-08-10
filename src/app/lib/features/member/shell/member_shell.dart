/// 회원 앱 셸 — 고정 하단 탭 (UI 1차 개편 §3.3).
///
/// 탭 구성: 홈 · 일정 · 기록 · 채팅 · 내 정보.
///
/// **트레이너 셸과 다른 점 — 가운데 강조 버튼이 없다.** 트레이너에겐 "수업 기록"이라는
/// 매 수업마다 반복되는 단일 핵심 동작이 있지만, 회원의 하루는 그런 한 가지 동작으로
/// 수렴하지 않는다(예약·기록 열람·셀프 기록이 상황마다 다름). 억지로 하나를 라임으로
/// 띄우면 강조의 의미만 닳는다.
///
/// 셸 위젯 자체는 트레이너와 공유한다([AppShellScaffold]) — 두 역할의 하단 바 톤이
/// 어긋나지 않게.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_shell_scaffold.dart';
import '../chat/member_chat_providers.dart';
import '../notices/member_notices_providers.dart';

/// 탭 인덱스 — 셸 밖에서 탭 전환을 요청할 때도 쓰도록 이름을 붙인다.
class MemberTab {
  MemberTab._();
  static const home = 0;
  static const schedule = 1;
  static const records = 2;
  static const chat = 3;
  static const profile = 4;
}

class MemberShell extends ConsumerWidget {
  const MemberShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadChats = ref.watch(memberUnreadCountProvider);
    // 받은 안내는 "내 정보" 안에 있어 눈에 안 띄므로, 안 읽은 게 있으면 탭에 알린다.
    final unreadNotices = ref.watch(unreadNoticeCountProvider);

    return AppShellScaffold(
      currentIndex: navigationShell.currentIndex,
      onTabSelected: _goBranch,
      tabs: [
        const AppShellTab(
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
          label: '홈',
        ),
        const AppShellTab(
          icon: Icons.event_outlined,
          selectedIcon: Icons.event,
          label: '일정',
        ),
        const AppShellTab(
          icon: Icons.fitness_center_outlined,
          selectedIcon: Icons.fitness_center,
          label: '기록',
        ),
        AppShellTab(
          icon: Icons.chat_bubble_outline,
          selectedIcon: Icons.chat_bubble,
          label: '채팅',
          badgeCount: unreadChats,
        ),
        AppShellTab(
          icon: Icons.person_outline,
          selectedIcon: Icons.person,
          label: '내 정보',
          badgeCount: unreadNotices,
        ),
      ],
      child: navigationShell,
    );
  }

  /// 탭 이동. 이미 있는 탭을 다시 누르면 그 탭의 첫 화면으로 되돌린다.
  void _goBranch(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}
