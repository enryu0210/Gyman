/// 트레이너 ↔ 회원 1:1 채팅 화면 (S2 / 2.3). 양 역할 공용.
///
/// 호출 측이 [peerUserId](상대 auth user_id)와 [peerName](표시명)만 넘기면 된다.
/// 본인 user_id 는 authStateProvider 에서 가져온다. 들어오면 안 읽은 메시지를
/// 자동으로 읽음 처리한다.
///
/// 실시간: chatMessagesProvider 스트림이 새 메시지를 밀어주면 자동으로 하단 스크롤.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/chat_message.dart';
import '../auth/auth_providers.dart';
import 'chat_providers.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.peerUserId,
    required this.peerName,
  });

  /// 상대방 auth user_id (트레이너 또는 회원).
  final String peerUserId;

  /// 상대방 표시명(AppBar 제목).
  final String peerName;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// 새 메시지가 쌓이면 항상 최신(하단)으로.
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
    });
  }

  Future<void> _send(String receiverId) async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _inputCtrl.clear();
    await ref
        .read(sendMessageControllerProvider.notifier)
        .send(receiverId: receiverId, content: text);
    if (!mounted) return;
    final state = ref.read(sendMessageControllerProvider);
    if (state.hasError) {
      // 실패 시 입력을 복구해 다시 보낼 수 있게.
      _inputCtrl.text = text;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(state.error?.toString() ?? '전송에 실패했습니다.')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUserId = ref.watch(authStateProvider).value?.id;

    // 로그인 정보가 없으면 채팅 불가(이론상 라우터가 막지만 방어).
    if (myUserId == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.peerName)),
        body: const Center(child: Text('로그인이 필요합니다.')),
      );
    }

    final key = (myUserId, widget.peerUserId);
    final async = ref.watch(chatMessagesProvider(key));

    // 메시지가 갱신될 때마다: 상대가 보낸 안읽음을 읽음 처리 + 하단 스크롤.
    ref.listen(chatMessagesProvider(key), (_, next) {
      final list = next.value;
      if (list == null) return;
      _scrollToBottom();
      final hasUnread = list.any((m) => m.isUnreadBy(myUserId));
      if (hasUnread) {
        ref.read(chatRepositoryProvider).markReadFrom(widget.peerUserId);
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text(widget.peerName)),
      body: Column(
        children: [
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorView(
                onRetry: () => ref.invalidate(chatMessagesProvider(key)),
              ),
              data: (messages) {
                if (messages.isEmpty) return const _EmptyView();
                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final m = messages[i];
                    return _MessageBubble(
                      message: m,
                      isMine: m.isMine(myUserId),
                    );
                  },
                );
              },
            ),
          ),
          _InputBar(
            controller: _inputCtrl,
            onSend: () => _send(widget.peerUserId),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// 말풍선
// =====================================================================

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isMine});
  final ChatMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final bg = isMine ? colors.primary : colors.surfaceContainerHighest;
    final fg = isMine ? colors.onPrimary : colors.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 내 메시지: 시간(+읽음)을 말풍선 왼쪽에.
          if (isMine) _MetaLabel(message: message, mine: true),
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              margin: const EdgeInsets.symmetric(horizontal: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(message.content, style: TextStyle(color: fg)),
            ),
          ),
          // 상대 메시지: 시간을 오른쪽에.
          if (!isMine) _MetaLabel(message: message, mine: false),
        ],
      ),
    );
  }
}

/// 말풍선 옆 시간 + (내 메시지면) 읽음 표시.
class _MetaLabel extends StatelessWidget {
  const _MetaLabel({required this.message, required this.mine});
  final ChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = Theme.of(context)
        .textTheme
        .labelSmall
        ?.copyWith(color: colors.onSurfaceVariant, fontSize: 10);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        // 내가 보낸 메시지가 읽혔으면 "읽음".
        if (mine && message.readAt != null) Text('읽음', style: style),
        Text(_time(message.sentAt), style: style),
      ],
    );
  }

  /// "오후 2:05" 형태(간단). 날짜 구분선은 베타 범위 밖.
  static String _time(DateTime dt) {
    final isPm = dt.hour >= 12;
    var h = dt.hour % 12;
    if (h == 0) h = 12;
    final m = dt.minute.toString().padLeft(2, '0');
    return '${isPm ? '오후' : '오전'} $h:$m';
  }
}

// =====================================================================
// 입력 바
// =====================================================================

class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller, required this.onSend});
  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(color: colors.outlineVariant)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: '메시지 입력',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton.filled(
              onPressed: onSend,
              icon: const Icon(Icons.send),
              tooltip: '전송',
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// 빈/에러 뷰
// =====================================================================

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
            Icon(Icons.chat_bubble_outline, size: 48, color: colors.outline),
            const SizedBox(height: 12),
            Text(
              '아직 주고받은 메시지가 없습니다.\n첫 메시지를 보내보세요.',
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
              '메시지를 불러오지 못했습니다.\n잠시 후 다시 시도해 주세요.',
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
