/// 트레이너 ↔ 회원 1:1 채팅 화면 (S2 / 2.3). 양 역할 공용.
///
/// 호출 측이 [peerUserId](상대 auth user_id)와 [peerName](표시명)만 넘기면 된다.
/// 본인 user_id 는 authStateProvider 에서 가져온다. 들어오면 안 읽은 메시지를
/// 자동으로 읽음 처리한다.
///
/// 실시간: chatMessagesProvider 스트림이 새 메시지를 밀어주면 자동으로 하단 스크롤.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/widgets/async_state_views.dart';
import '../../domain/models/chat_message.dart';
import '../auth/auth_providers.dart';
import 'chat_providers.dart';
import 'dnd_providers.dart';

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
  final _picker = ImagePicker();

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

  /// 갤러리에서 사진을 골라 전송. 카메라는 베타 범위 밖(갤러리만).
  ///
  /// `imageQuality`/`maxWidth` 로 업로드 전에 미리 줄여 5MB 버킷 상한·전송량을 아낀다.
  /// 사용자가 선택을 취소하면 picker 가 null 을 반환 → 조용히 종료.
  Future<void> _pickAndSendImage(String receiverId) async {
    final XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600, // 채팅 표시엔 충분, 원본 대용량 업로드 방지
        imageQuality: 80, // JPEG 재압축으로 용량 추가 절감
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('사진을 불러오지 못했습니다. 권한을 확인해 주세요.')),
        );
      return;
    }
    if (picked == null) return; // 사용자가 취소

    await ref
        .read(sendMessageControllerProvider.notifier)
        .sendImage(receiverId: receiverId, file: File(picked.path));
    if (!mounted) return;
    final state = ref.read(sendMessageControllerProvider);
    if (state.hasError) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(state.error?.toString() ?? '사진 전송에 실패했습니다.'),
          ),
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

    // 상대가 트레이너이고 지금이 방해금지 시간이면 안내 배너(회원 시점에서만 뜸 —
    // 상대가 회원이면 trainer_profiles 행이 없어 null).
    final peerDnd = ref.watch(peerDndProvider(widget.peerUserId)).value;
    final dndActive = peerDnd != null && peerDnd.isActiveAt(DateTime.now());

    return Scaffold(
      appBar: AppBar(title: Text(widget.peerName)),
      body: Column(
        children: [
          if (dndActive) _DndBanner(range: peerDnd.rangeLabel),
          Expanded(
            child: async.when(
              loading: () => const AppLoadingView(),
              error: (e, _) => AppErrorView(
                message: '메시지를 불러오지 못했습니다.\n잠시 후 다시 시도해 주세요.',
                onRetry: () => ref.invalidate(chatMessagesProvider(key)),
              ),
              data: (messages) {
                if (messages.isEmpty) {
                  return const AppEmptyView(
                    icon: Icons.chat_bubble_outline,
                    message: '아직 주고받은 메시지가 없습니다.\n첫 메시지를 보내보세요.',
                  );
                }
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
            onAttach: () => _pickAndSendImage(widget.peerUserId),
            // 업로드/전송 중이면 버튼을 잠가 중복 전송 방지.
            sending: ref.watch(sendMessageControllerProvider).isLoading,
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// 방해금지 안내 배너 (회원 시점)
// =====================================================================

/// 트레이너가 방해금지 시간일 때 회원에게 보이는 안내. 전송은 막지 않는다.
class _DndBanner extends StatelessWidget {
  const _DndBanner({required this.range});
  final String range;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: colors.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.bedtime_outlined,
              size: 18, color: colors.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              range.isEmpty
                  ? '지금은 트레이너 방해금지 시간이에요. 답장이 늦을 수 있어요.'
                  : '지금은 트레이너 방해금지 시간($range)이에요. 답장이 늦을 수 있어요.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSecondaryContainer,
                  ),
            ),
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
              // 이미지 말풍선은 패딩 없이 꽉 채우고, 텍스트는 기존 패딩 유지.
              padding: message.hasImage
                  ? EdgeInsets.zero
                  : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: message.hasImage ? Colors.transparent : bg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: message.hasImage
                  ? _ImageContent(objectKey: message.imagePath!)
                  : Text(message.content, style: TextStyle(color: fg)),
            ),
          ),
          // 상대 메시지: 시간을 오른쪽에.
          if (!isMine) _MetaLabel(message: message, mine: false),
        ],
      ),
    );
  }
}

/// 말풍선 안의 이미지. 비공개 버킷이라 서명 URL 을 발급받아 표시하고,
/// 탭하면 전체화면으로 크게 본다. 서명 발급/로딩/실패 상태를 각각 처리.
class _ImageContent extends ConsumerWidget {
  const _ImageContent({required this.objectKey});
  final String objectKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final urlAsync = ref.watch(chatImageUrlProvider(objectKey));

    // 서명 URL 발급 전/실패 시 자리표시(말풍선 높이 유지).
    Widget placeholder(IconData icon) => Container(
          width: 180,
          height: 180,
          alignment: Alignment.center,
          color: colors.surfaceContainerHighest,
          child: Icon(icon, color: colors.onSurfaceVariant),
        );

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: urlAsync.when(
        loading: () => placeholder(Icons.image_outlined),
        error: (_, _) => placeholder(Icons.broken_image_outlined),
        data: (url) => GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _FullScreenImage(url: url),
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: Image.network(
              url,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : placeholder(Icons.image_outlined),
              errorBuilder: (_, _, _) =>
                  placeholder(Icons.broken_image_outlined),
            ),
          ),
        ),
      ),
    );
  }
}

/// 이미지 전체화면 뷰어 — 핀치 줌(InteractiveViewer) 지원. 검은 배경.
class _FullScreenImage extends StatelessWidget {
  const _FullScreenImage({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Icon(
              Icons.broken_image_outlined,
              color: Colors.white54,
              size: 64,
            ),
          ),
        ),
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
  const _InputBar({
    required this.controller,
    required this.onSend,
    required this.onAttach,
    required this.sending,
  });
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttach;

  /// 업로드/전송 진행 중 — 버튼 잠금 + 전송 버튼을 스피너로.
  final bool sending;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(color: colors.outlineVariant)),
        ),
        child: Row(
          children: [
            // 사진 첨부 — 전송 중이면 비활성화.
            IconButton(
              onPressed: sending ? null : onAttach,
              icon: const Icon(Icons.photo_outlined),
              tooltip: '사진 보내기',
            ),
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
            // 전송 중이면 스피너, 아니면 전송 버튼.
            sending
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton.filled(
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

