/// 회원 "트레이너와 채팅" 진입 화면 (S2 / 2.3).
///
/// 라우트: `/member/chat`. 본인 트레이너를 해석해 공용 [ChatScreen] 을 띄운다.
/// 계약/트레이너가 아직 없으면 안내 화면.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/async_state_views.dart';
import '../../chat/chat_screen.dart';
import 'member_chat_providers.dart';

class MemberChatScreen extends ConsumerWidget {
  const MemberChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myTrainerProvider);

    return async.when(
      loading: () => const Scaffold(body: AppLoadingView()),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('트레이너와 채팅')),
        body: AppErrorView(
          message: '연결 정보를 불러오지 못했습니다.\n잠시 후 다시 시도해 주세요.',
          onRetry: () => ref.invalidate(myTrainerProvider),
        ),
      ),
      data: (trainer) {
        if (trainer == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('트레이너와 채팅')),
            body: const AppEmptyView(
              icon: Icons.person_search_outlined,
              message: '아직 연결된 트레이너가 없습니다.\n계약이 등록되면 채팅을 시작할 수 있어요.',
            ),
          );
        }
        // 트레이너가 해석되면 공용 채팅 화면으로.
        return ChatScreen(
          peerUserId: trainer.userId,
          peerName: trainer.name,
        );
      },
    );
  }
}

