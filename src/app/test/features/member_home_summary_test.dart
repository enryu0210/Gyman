/// MemberHomeSummary 집계 로직 단위 테스트.
///
/// 잔여 횟수는 매출/분쟁 직결이라(프로젝트 지침) view 값을 합산하는 본 모델의
/// 합계·음수 클램프·계약 유무 판정을 회귀 테스트로 고정한다.
///
/// 데이터 조회(Supabase) 자체는 RLS에 위임하므로 여기서는 순수 합산만 검증.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/features/member/home/member_home_repository.dart';

MemberContractStatus _status({
  required int remaining,
  int total = 10,
  int used = 0,
}) {
  return MemberContractStatus(
    contractId: 'c-$remaining-$total',
    totalSessions: total,
    usedSessions: used,
    remainingSessions: remaining,
    startDate: DateTime(2026, 1, 1),
  );
}

MemberHomeSummary _summary(List<MemberContractStatus> contracts) {
  // 이 테스트가 보는 건 잔여 횟수 합산뿐 — 오늘 수업·인바디는 빈 값으로 둔다.
  return MemberHomeSummary(
    memberName: '홍길동',
    nextSession: null,
    todaySessions: const [],
    contracts: contracts,
    recentMeasurements: const [],
  );
}

void main() {
  group('MemberHomeSummary.totalRemaining', () {
    test('여러 계약의 잔여를 합산한다', () {
      final s = _summary([
        _status(remaining: 3),
        _status(remaining: 7),
      ]);
      expect(s.totalRemaining, 10);
    });

    test('계약이 없으면 0', () {
      expect(_summary([]).totalRemaining, 0);
    });

    test('잔여가 음수인 계약이 섞여도 전체 합계는 0 미만으로 내려가지 않는다', () {
      // 데이터 이상(초과 차감)으로 음수가 나와도 회원에게 음수 잔여를 보이지 않는다.
      final s = _summary([
        _status(remaining: -5),
        _status(remaining: 2),
      ]);
      expect(s.totalRemaining, 0);
    });
  });

  group('MemberHomeSummary.hasContract', () {
    test('계약이 하나라도 있으면 true', () {
      expect(_summary([_status(remaining: 1)]).hasContract, isTrue);
    });

    test('계약이 없으면 false', () {
      expect(_summary([]).hasContract, isFalse);
    });
  });

  group('MemberContractStatus.isExhausted', () {
    test('잔여 0 이하면 소진으로 본다', () {
      expect(_status(remaining: 0).isExhausted, isTrue);
      expect(_status(remaining: -1).isExhausted, isTrue);
    });

    test('잔여가 남아 있으면 소진 아님', () {
      expect(_status(remaining: 1).isExhausted, isFalse);
    });
  });
}
