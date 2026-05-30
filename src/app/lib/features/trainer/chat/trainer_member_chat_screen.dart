/// 트레이너 → 회원 채팅 진입 화면 (S2 / 2.3).
///
/// 라우트: `/trainer/members/:id/chat`. 회원을 조회해 공용 [ChatScreen] 을 띄운다.
/// 회원이 앱 미연결(user_id == null)이면 채팅 불가 안내 — 초대 코드 연결 후 가능.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../chat/chat_screen.dart';
import '../member/member_providers.dart';

class TrainerMemberChatScreen extends ConsumerWidget {
  const TrainerMemberChatScreen({super.key, required this.memberId});

  /// 회원 member_profiles.id.
  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(memberByIdProvider(memberId));

    return async.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('채팅')),
        body: const Center(child: Text('회원 정보를 불러오지 못했습니다.')),
      ),
      data: (member) {
        if (member == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('채팅')),
            body: const Center(child: Text('회원을 찾을 수 없습니다.')),
          );
        }
        final userId = member.userId;
        if (userId == null) {
          // 앱 미연결 회원과는 채팅 불가 — 초대 코드 연결이 선행되어야 함.
          return Scaffold(
            appBar: AppBar(title: Text(member.name)),
            body: _NotLinkedView(name: member.name),
          );
        }
        return ChatScreen(peerUserId: userId, peerName: member.name);
      },
    );
  }
}

class _NotLinkedView extends StatelessWidget {
  const _NotLinkedView({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.link_off, size: 48, color: colors.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              '$name 님은 아직 앱에 연결되지 않았습니다.\n'
              '초대 코드로 계정을 연결하면 채팅을 시작할 수 있어요.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
