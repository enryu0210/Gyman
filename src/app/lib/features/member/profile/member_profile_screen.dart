/// 회원 "내 정보" 탭 (UI 1차 개편 §3.3).
///
/// 라우트: `/member/profile`
///
/// **역할:** 매일 쓰지는 않지만 반드시 닿아야 하는 보조 기능들의 집결지 —
/// 수업 영상·받은 안내·FAQ·설정. 홈이 "오늘의 운동"에 집중할 수 있게, 이 성격의
/// 진입점을 홈 격자에서 여기로 옮겼다.
///
/// **왜 설정을 여기에 두나:** 설정은 모든 역할 공통 화면(`/settings`)이라 셸 밖에 있다.
/// 회원에겐 앱바 아이콘보다 이 탭 안의 명시적인 줄이 찾기 쉽다(탈퇴·문의 탈출구 U1).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_menu_grid.dart';
import '../../auth/auth_providers.dart';
import '../notices/member_notices_providers.dart';

class MemberProfileScreen extends ConsumerWidget {
  const MemberProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadNotices = ref.watch(unreadNoticeCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('내 정보'),
        actions: [
          IconButton(
            tooltip: '설정',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          AppMenuGrid(
            items: [
              AppMenuItem(
                icon: Icons.play_circle_outline,
                label: '내 수업 영상',
                onTap: () => context.push('/member/videos'),
              ),
              AppMenuItem(
                icon: Icons.notifications_outlined,
                label: '받은 안내',
                badgeCount: unreadNotices,
                onTap: () async {
                  await context.push('/member/notices');
                  // 돌아오면 읽음 처리됐을 수 있으니 배지 갱신.
                  ref.invalidate(myNoticesProvider);
                },
              ),
              AppMenuItem(
                icon: Icons.help_outline,
                label: '자주 묻는 질문',
                onTap: () => context.push('/member/faq'),
              ),
              AppMenuItem(
                icon: Icons.settings_outlined,
                label: '설정',
                onTap: () => context.push('/settings'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // 로그아웃은 격자 타일로 두지 않는다 — 되돌리기 어려운 동작이라
          // 다른 진입점과 같은 무게로 나열하면 오탭 위험이 있다.
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () =>
                  ref.read(signInControllerProvider.notifier).signOut(),
              icon: const Icon(Icons.logout_outlined, size: 18),
              label: const Text('로그아웃'),
            ),
          ),
        ],
      ),
    );
  }
}
