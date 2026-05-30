/// 채팅 Riverpod providers (S2 / 2.3).
///
/// - [chatRepositoryProvider]
/// - [chatMessagesProvider] : (나, 상대) user_id 쌍별 실시간 메시지 스트림 (.family)
/// - [sendMessageControllerProvider] : 전송 액션 (`AsyncValue<void>`)
///
/// family 키는 Dart record `(String myUserId, String peerUserId)` — 값 동등성이
/// 있어 같은 대화는 캐시 공유, 다른 대화는 자동 분리된다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_client.dart';
import '../../domain/models/chat_message.dart';
import 'chat_repository.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return ChatRepository(client);
});

/// (나, 상대) 사이 메시지 실시간 스트림.
final chatMessagesProvider = StreamProvider.autoDispose
    .family<List<ChatMessage>, (String myUserId, String peerUserId)>(
        (ref, pair) {
  return ref.watch(chatRepositoryProvider).messagesWith(
        myUserId: pair.$1,
        peerUserId: pair.$2,
      );
});

/// 전송 컨트롤러. state = `AsyncValue<void>`.
///
/// 전송 성공 후 스트림이 새 메시지를 알아서 밀어주므로 별도 invalidate 불필요(실시간).
class SendMessageController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// [content] 전송. 빈/공백은 무시(스낵바 없이 조용히). 실패는 state.hasError 로.
  Future<void> send({
    required String receiverId,
    required String content,
  }) async {
    final text = content.trim();
    if (text.isEmpty) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(chatRepositoryProvider).send(
            receiverId: receiverId,
            content: text,
          );
    });
  }
}

final sendMessageControllerProvider =
    AutoDisposeAsyncNotifierProvider<SendMessageController, void>(
  SendMessageController.new,
);
