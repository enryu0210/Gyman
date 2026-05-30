/// 트레이너 대화 목록 repository (S2 / 2.3 — 채팅 발견·안읽음).
///
/// 트레이너는 여러 회원과 채팅하므로, 회원 상세를 일일이 열지 않아도 "누구에게서
/// 메시지가 왔는지"를 한 화면에서 보게 한다. messages 를 상대(peer)별로 묶어
/// 마지막 메시지 + 안읽음 수를 집계한다.
///
/// RLS(0024)가 내 메시지만 노출하므로, 가져온 행을 클라이언트에서 peer 별로 그룹화한다.
/// 회원 이름은 member_profiles(트레이너 RLS: member_by_trainer)로 별도 조회해 병합.
///
/// 참고: 0024(messages RLS), docs/develop_plan.md §4 2.3.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/models/chat_message.dart';

/// 대화 1건 요약 — 목록 한 줄.
class TrainerConversation {
  /// 상대(회원) auth user_id.
  final String peerUserId;

  /// 상대 회원 member_profiles.id — 채팅 화면 라우팅에 사용.
  final String memberId;

  /// 상대 회원 표시명.
  final String memberName;

  /// 가장 최근 메시지 본문.
  final String lastMessage;

  /// 가장 최근 메시지 시각.
  final DateTime lastAt;

  /// 내가 아직 안 읽은(상대가 보낸) 메시지 수.
  final int unreadCount;

  const TrainerConversation({
    required this.peerUserId,
    required this.memberId,
    required this.memberName,
    required this.lastMessage,
    required this.lastAt,
    required this.unreadCount,
  });
}

class TrainerChatRepository {
  final SupabaseClient _client;
  TrainerChatRepository(this._client);

  static const _table = 'messages';

  /// 내가 안 읽은 메시지 총 개수 — 트레이너 홈 배지용(가벼운 조회).
  Future<int> unreadTotal() async {
    final me = _client.auth.currentUser;
    if (me == null) return 0;
    final rows = await _client
        .from(_table)
        .select('id')
        .eq('receiver_id', me.id)
        .isFilter('read_at', null);
    return (rows as List).length;
  }

  /// 대화 목록 — 최근 메시지 시각 내림차순.
  Future<List<TrainerConversation>> listConversations() async {
    final me = _client.auth.currentUser;
    if (me == null) return const [];
    final myId = me.id;

    // 1) 내가 주고받은 모든 메시지(RLS로 본인 것만). 최신 먼저.
    final rows = await _client
        .from(_table)
        .select('id, sender_id, receiver_id, content, sent_at, read_at')
        .order('sent_at', ascending: false);
    final messages = (rows as List)
        .cast<Map<String, dynamic>>()
        .map(ChatMessage.fromRow)
        .toList(growable: false);
    if (messages.isEmpty) return const [];

    // 2) peer(상대 user_id)별로 묶어 마지막 메시지 + 안읽음 수 집계.
    //    messages 가 최신순이라, 각 peer 의 첫 등장 = 마지막 메시지.
    final lastByPeer = <String, ChatMessage>{};
    final unreadByPeer = <String, int>{};
    for (final m in messages) {
      final peer = m.senderId == myId ? m.receiverId : m.senderId;
      lastByPeer.putIfAbsent(peer, () => m);
      if (m.isUnreadBy(myId)) {
        unreadByPeer[peer] = (unreadByPeer[peer] ?? 0) + 1;
      }
    }

    // 3) peer user_id → 회원(id, name) 해석. 트레이너 RLS(member_by_trainer)로 조회.
    final peerIds = lastByPeer.keys.toList(growable: false);
    final memberRows = await _client
        .from('member_profiles')
        .select('id, user_id, name')
        .inFilter('user_id', peerIds);
    final memberByUserId = <String, Map<String, dynamic>>{
      for (final r in (memberRows as List).cast<Map<String, dynamic>>())
        r['user_id'] as String: r,
    };

    // 4) 병합. 회원 매핑이 없으면(삭제 등) 건너뛴다.
    final conversations = <TrainerConversation>[];
    lastByPeer.forEach((peerId, last) {
      final member = memberByUserId[peerId];
      if (member == null) return;
      conversations.add(TrainerConversation(
        peerUserId: peerId,
        memberId: member['id'] as String,
        memberName: (member['name'] as String?) ?? '회원',
        lastMessage: last.content,
        lastAt: last.sentAt,
        unreadCount: unreadByPeer[peerId] ?? 0,
      ));
    });

    conversations.sort((a, b) => b.lastAt.compareTo(a.lastAt));
    return conversations;
  }
}
