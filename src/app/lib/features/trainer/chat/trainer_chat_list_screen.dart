/// 트레이너 "회원 채팅" 대화 목록 화면 (S2 / 2.3).
///
/// 라우트: `/trainer/chat`. 회원별 마지막 메시지 + 안읽음 배지. 탭 → 그 회원과 채팅.
///
/// 채팅에서 돌아오면(읽음 처리됨) 목록을 새로고침해 안읽음 배지를 갱신한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/util/date_format_ko.dart';
import 'dnd_settings_dialog.dart';
import 'trainer_chat_providers.dart';
import 'trainer_chat_repository.dart';

class TrainerChatListScreen extends ConsumerWidget {
  const TrainerChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(trainerConversationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('회원 채팅'),
        actions: [
          IconButton(
            tooltip: '방해금지 시간',
            icon: const Icon(Icons.do_not_disturb_on_outlined),
            onPressed: () => showDndSettingsDialog(context),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(
          onRetry: () => ref.invalidate(trainerConversationsProvider),
        ),
        data: (conversations) {
          if (conversations.isEmpty) return const _EmptyView();
          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(trainerConversationsProvider),
            child: ListView.separated(
              itemCount: conversations.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) =>
                  _ConversationTile(item: conversations[i]),
            ),
          );
        },
      ),
    );
  }
}

class _ConversationTile extends ConsumerWidget {
  const _ConversationTile({required this.item});
  final TrainerConversation item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasUnread = item.unreadCount > 0;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: colors.primaryContainer,
        child: Text(
          item.memberName.isNotEmpty ? item.memberName.characters.first : '?',
          style: TextStyle(color: colors.onPrimaryContainer),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              item.memberName,
              style: theme.textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            formatKoreanDate(item.lastAt),
            style: theme.textTheme.labelSmall
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
      subtitle: Text(
        item.lastMessage,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: hasUnread ? colors.onSurface : colors.onSurfaceVariant,
          fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: hasUnread
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colors.error,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${item.unreadCount}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.onError,
                ),
              ),
            )
          : null,
      onTap: () async {
        await context.push('/trainer/members/${item.memberId}/chat');
        // 돌아오면 읽음 상태가 바뀌었을 수 있으니 목록·배지 갱신.
        ref.invalidate(trainerConversationsProvider);
        ref.invalidate(trainerUnreadTotalProvider);
      },
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.forum_outlined, size: 48, color: colors.outline),
            const SizedBox(height: 12),
            Text(
              '아직 대화가 없습니다.\n회원 상세에서 채팅을 시작할 수 있어요.',
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

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            Text(
              '대화를 불러오지 못했습니다.\n잠시 후 다시 시도해 주세요.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ),
      ),
    );
  }
}
