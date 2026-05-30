import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/domain/models/chat_message.dart';

/// ChatMessage 단위 테스트.
///
/// **검증 포인트:**
///   - 시점 중립: 같은 메시지가 보는 사람에 따라 isMine 이 달라짐
///   - 안읽음 판정(받은 사람 + read_at null)
///   - fromRow 매핑(read_at null 보존)
void main() {
  ChatMessage msg({
    String sender = 'trainer1',
    String receiver = 'member1',
    DateTime? readAt,
  }) =>
      ChatMessage(
        id: 'm1',
        senderId: sender,
        receiverId: receiver,
        content: '안녕하세요',
        sentAt: DateTime(2026, 5, 30, 10),
        readAt: readAt,
      );

  group('isMine (시점 중립)', () {
    test('보낸 사람 시점에선 내 것', () {
      expect(msg().isMine('trainer1'), isTrue);
    });
    test('받은 사람 시점에선 내 것 아님', () {
      expect(msg().isMine('member1'), isFalse);
    });
  });

  group('isUnreadBy', () {
    test('받은 사람이고 read_at 이 null 이면 안읽음', () {
      expect(msg(readAt: null).isUnreadBy('member1'), isTrue);
    });
    test('읽은 시각이 있으면 읽음', () {
      expect(msg(readAt: DateTime(2026, 5, 30, 11)).isUnreadBy('member1'),
          isFalse);
    });
    test('보낸 사람 입장에선 안읽음 대상 아님(내가 보낸 것)', () {
      expect(msg(readAt: null).isUnreadBy('trainer1'), isFalse);
    });
  });

  group('fromRow', () {
    test('read_at null 보존', () {
      final m = ChatMessage.fromRow({
        'id': 'm1',
        'sender_id': 'trainer1',
        'receiver_id': 'member1',
        'content': '안녕하세요',
        'sent_at': '2026-05-30T10:00:00.000Z',
        'read_at': null,
      });
      expect(m.readAt, isNull);
      expect(m.content, '안녕하세요');
      expect(m.isUnreadBy('member1'), isTrue);
    });

    test('read_at 있으면 파싱', () {
      final m = ChatMessage.fromRow({
        'id': 'm1',
        'sender_id': 'trainer1',
        'receiver_id': 'member1',
        'content': '네',
        'sent_at': '2026-05-30T10:00:00.000Z',
        'read_at': '2026-05-30T10:05:00.000Z',
      });
      expect(m.readAt, DateTime.parse('2026-05-30T10:05:00.000Z'));
    });
  });
}
