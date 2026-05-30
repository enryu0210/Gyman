/// 트레이너 ↔ 회원 1:1 채팅 repository (S2 / 2.3).
///
/// **역할 공용:** 트레이너든 회원이든 "상대(peer) user_id" 만 주면 동작한다.
///   본인 user_id 는 Supabase Auth 세션에서 가져온다.
///
/// **실시간:** Supabase `.stream()` 으로 messages 변경을 구독한다(0024 publication).
///   stream API 는 OR 필터를 못 거니, RLS 가 이미 "내 메시지"로 좁혀준 결과를 받아
///   클라이언트에서 peer 쌍만 추려낸다(회원은 트레이너 1명뿐이라 사실상 전부).
///
/// **보안:** sender 위조/무관한 상대 전송은 RLS(0024 messages_send)가 차단.
///   본 repository 는 sender_id 를 넣지 않고 DB 가 auth.uid() 로 강제하게 둔다.
///
/// 참고: 0006(messages), 0024(RLS·실시간), docs/develop_plan.md §4 2.3.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/chat_message.dart';

class ChatRepository {
  final SupabaseClient _client;
  ChatRepository(this._client);

  static const _table = 'messages';

  /// 나([myUserId])와 상대([peerUserId]) 사이 메시지를 실시간 스트림으로.
  /// 전송 시각 오름차순(오래된 것 위 → 최신 아래, 일반 채팅 순서).
  Stream<List<ChatMessage>> messagesWith({
    required String myUserId,
    required String peerUserId,
  }) {
    return _client
        .from(_table)
        .stream(primaryKey: ['id'])
        .order('sent_at')
        .map((rows) {
      return rows
          .map(ChatMessage.fromRow)
          // RLS 가 내 메시지로 좁혀주지만, 여러 상대가 있을 수 있는 트레이너를 위해
          // 이 peer 와 주고받은 것만 추린다.
          .where((m) =>
              (m.senderId == myUserId && m.receiverId == peerUserId) ||
              (m.senderId == peerUserId && m.receiverId == myUserId))
          .toList(growable: false);
    });
  }

  /// 메시지 전송. sender_id 는 넣지 않는다 — RLS 가 auth.uid() 로 강제(위조 차단).
  /// 빈/공백 메시지는 호출 측(컨트롤러)이 거른다.
  Future<void> send({
    required String receiverId,
    required String content,
  }) async {
    await _client.from(_table).insert({
      'receiver_id': receiverId,
      'content': content,
    });
  }

  /// 상대([peerUserId])가 보낸, 내가 아직 안 읽은 메시지를 읽음 처리.
  /// RLS(messages_mark_read)가 receiver=본인 행만 update 허용.
  Future<void> markReadFrom(String peerUserId) async {
    final me = _client.auth.currentUser;
    if (me == null) return;
    await _client
        .from(_table)
        .update({'read_at': DateTime.now().toIso8601String()})
        .eq('receiver_id', me.id)
        .eq('sender_id', peerUserId)
        .isFilter('read_at', null);
  }
}
