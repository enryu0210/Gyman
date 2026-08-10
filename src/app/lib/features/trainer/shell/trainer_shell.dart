/// 트레이너 앱 셸 — 고정 하단 탭 (UI 1차 개편 단계 A).
///
/// 탭 구성(계획서 §3.1): 홈 · 회원 · **기록하기(강조)** · 일정 · 채팅.
/// "기록하기"는 머무는 화면이 아니라 동작이라 탭이 아닌 가운데 강조 버튼이다
/// ([startRecordFlow] 참고).
///
/// **AI 검수는 탭에 두지 않는다.** 항상 처리해야 하는 핵심 업무처럼 보이면 안 되는
/// 기능이라, 홈의 "처리할 일"에서만 진입한다(계획서 §3.1 마지막 문단).
///
/// **상태 보존:** [StatefulShellRoute.indexedStack] 이 탭별 Navigator 를 살려 두므로
/// 탭을 오갔다 돌아와도 스크롤 위치와 목록 상태가 그대로다(계획서 §4.2).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_shell_scaffold.dart';
import '../chat/trainer_chat_providers.dart';
import '../session_log/session_providers.dart';
import '../session_log/start_record_sheet.dart';

/// 탭 인덱스 — 셸 밖(예: 홈 카드)에서 탭 전환을 요청할 때도 쓰도록 이름을 붙인다.
class TrainerTab {
  TrainerTab._();
  static const home = 0;
  static const members = 1;
  static const booking = 2;
  static const chat = 3;
}

class TrainerShell extends ConsumerWidget {
  const TrainerShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 하단 배지는 홈 히어로/격자와 같은 소스를 본다 — 두 곳 숫자가 어긋나지 않게.
    final pendingRequests = ref.watch(trainerPendingRequestCountProvider);
    final unreadChats = ref.watch(trainerUnreadCountProvider);

    return AppShellScaffold(
      currentIndex: navigationShell.currentIndex,
      onTabSelected: _goBranch,
      centerAction: AppShellAction(
        icon: Icons.edit_note_outlined,
        label: '기록하기',
        onTap: () => startRecordFlow(
          context,
          ref,
          // 제안할 수업이 없으면 회원 탭으로 — push 가 아니라 탭 전환이라야
          // 회원 목록이 두 겹으로 쌓이지 않는다.
          onPickMember: () => _goBranch(TrainerTab.members),
        ),
      ),
      tabs: [
        const AppShellTab(
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
          label: '홈',
        ),
        const AppShellTab(
          icon: Icons.groups_outlined,
          selectedIcon: Icons.groups,
          label: '회원',
        ),
        AppShellTab(
          icon: Icons.event_outlined,
          selectedIcon: Icons.event,
          label: '일정',
          badgeCount: pendingRequests,
        ),
        AppShellTab(
          icon: Icons.chat_bubble_outline,
          selectedIcon: Icons.chat_bubble,
          label: '채팅',
          badgeCount: unreadChats,
        ),
      ],
      child: navigationShell,
    );
  }

  /// 탭 이동. 이미 있는 탭을 다시 누르면 그 탭의 첫 화면으로 되돌린다
  /// (`initialLocation: true`) — 상세로 파고든 뒤 탭을 눌러 빠져나오는 관습.
  void _goBranch(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}
