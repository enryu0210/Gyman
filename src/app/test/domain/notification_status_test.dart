/// NotificationStatus 게이트 규칙 단위 테스트 (AI 검수 흐름 2차 방어).
///
/// "트레이너 검수 없이는 회원에게 안 간다"의 클라이언트 2차 방어(도메인 enum)를
/// 고정한다. 1차 방어인 DB RLS(`notif_member_read_sent_only`) / CHECK
/// (`chk_sent_requires_approval`)는 마이그레이션 0007 검증 SQL 의 몫이며, 본
/// 테스트는 그와 같은 의미(sent 만 노출)를 도메인에서 회귀 방지로 못박는다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/domain/models/enums.dart';

void main() {
  group('isVisibleToMember — 회원 노출은 sent 만', () {
    test('sent 만 true', () {
      expect(NotificationStatus.sent.isVisibleToMember, isTrue);
    });

    test('draft/approved/canceled 는 모두 회원 비노출', () {
      expect(NotificationStatus.draft.isVisibleToMember, isFalse);
      expect(NotificationStatus.approved.isVisibleToMember, isFalse);
      expect(NotificationStatus.canceled.isVisibleToMember, isFalse);
    });

    test('전 상태 중 정확히 하나(sent)만 노출 — 새 상태 추가 시 회귀 감지', () {
      final visible =
          NotificationStatus.values.where((s) => s.isVisibleToMember).toList();
      expect(visible, [NotificationStatus.sent]);
    });
  });

  group('isPendingReview — 검수 대기는 draft 만', () {
    test('draft 만 true (홈 "검수 N건" 배지 기준)', () {
      expect(NotificationStatus.draft.isPendingReview, isTrue);
    });

    test('approved/sent/canceled 는 검수 대기 아님', () {
      expect(NotificationStatus.approved.isPendingReview, isFalse);
      expect(NotificationStatus.sent.isPendingReview, isFalse);
      expect(NotificationStatus.canceled.isPendingReview, isFalse);
    });
  });
}
