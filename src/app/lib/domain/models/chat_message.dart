/// 채팅 메시지 1건. messages 테이블의 1행과 1:1 대응 (S2 / 2.3).
///
/// **방향(보낸 사람 판별)을 모델이 안 정하는 이유:**
///   같은 메시지라도 보는 사람(트레이너/회원)에 따라 "내 말풍선"인지가 달라진다.
///   그래서 senderId 만 들고 있고, "내 것인지"는 화면이 [isMine]에 본인 user_id 를
///   넘겨 판별한다(모델은 시점 중립).
///
/// 불변 객체 — 다른 도메인 모델과 동일.
library;

class ChatMessage {
  final String id;

  /// 보낸 사람 auth user_id (트레이너 또는 회원).
  final String senderId;

  /// 받는 사람 auth user_id.
  final String receiverId;

  final String content;

  /// 전송 시각.
  final DateTime sentAt;

  /// 받는 사람이 읽은 시각. null 이면 아직 안 읽음.
  final DateTime? readAt;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.content,
    required this.sentAt,
    this.readAt,
  });

  /// [myUserId] 기준으로 내가 보낸 메시지인지 — 말풍선 정렬에 사용.
  bool isMine(String myUserId) => senderId == myUserId;

  /// [myUserId] 가 아직 안 읽은(내가 받은) 메시지인지 — 안읽음 배지/읽음처리 대상.
  bool isUnreadBy(String myUserId) =>
      receiverId == myUserId && readAt == null;

  /// messages 행 → 도메인 객체. timestamptz 는 ISO8601 문자열.
  factory ChatMessage.fromRow(Map<String, dynamic> row) {
    return ChatMessage(
      id: row['id'] as String,
      senderId: row['sender_id'] as String,
      receiverId: row['receiver_id'] as String,
      content: row['content'] as String,
      sentAt: DateTime.parse(row['sent_at'] as String),
      readAt: row['read_at'] == null
          ? null
          : DateTime.tryParse(row['read_at'] as String),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessage &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          readAt == other.readAt;

  // id + readAt 을 해시에 포함 — 읽음 상태 변경이 리스트 갱신으로 이어지게.
  @override
  int get hashCode => Object.hash(id, readAt);

  @override
  String toString() => 'ChatMessage($senderId→$receiverId, read:$readAt)';
}
