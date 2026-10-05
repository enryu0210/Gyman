// 양쪽 라벨이 같은 트리거를 인식해야 승인 후 회원 안내도 올바르게 분류된다.
import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/features/trainer/ai_review/ai_review_repository.dart';
import 'package:gyman/features/member/notices/member_notices_repository.dart';

void main() {
  test('코칭 가이드의 트레이너·회원 라벨', () {
    expect(triggerTypeLabel('coaching_guide'), '코칭 가이드(AI)');
    expect(memberNoticeLabel('coaching_guide'), '코칭 가이드');
  });
}
