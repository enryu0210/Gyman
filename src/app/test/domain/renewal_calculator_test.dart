import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/domain/models/enums.dart';
import 'package:gyman/domain/models/pt_contract.dart';
import 'package:gyman/domain/models/session.dart';
import 'package:gyman/domain/renewal_calculator.dart';

/// 재등록 계산기 단위 테스트.
///
/// **왜 핵심:** 재등록 타이밍을 놓치면 매출 직접 손실. 너무 일찍 알리면
/// 트레이너가 "재등록 권유 빨라" 부담. 임계값 정확도가 곧 사용성.
void main() {
  final now = DateTime(2026, 2, 1, 12);

  PtContract makeContract({
    int total = 10,
    DateTime? endDate,
    DateTime? startDate,
  }) =>
      PtContract(
        id: 'c1',
        memberId: 'm1',
        trainerId: 't1',
        totalSessions: total,
        startDate: startDate ?? DateTime(2026, 1, 1),
        endDate: endDate,
        createdAt: DateTime(2026, 1, 1),
      );

  Session makeSession({
    required String id,
    required SessionStatus status,
    required DateTime scheduledAt,
    String contractId = 'c1',
  }) =>
      Session(
        id: id,
        contractId: contractId,
        status: status,
        scheduledAt: scheduledAt,
        createdAt: scheduledAt,
      );

  group('estimateExpiryDate — 데이터 부족 케이스', () {
    test('차감 세션 0개 + end_date null → null', () {
      final result = RenewalCalculator.estimateExpiryDate(
        makeContract(),
        [],
        now: now,
      );
      expect(result, isNull);
    });

    test('차감 세션 0개지만 end_date 있으면 end_date 반환', () {
      final end = DateTime(2026, 3, 1);
      final result = RenewalCalculator.estimateExpiryDate(
        makeContract(endDate: end),
        [],
        now: now,
      );
      expect(result, end);
    });

    test('첫 차감이 6일 전 (< 7일) → 페이스 부족, end_date 폴백', () {
      final sessions = [
        makeSession(
          id: 's1',
          status: SessionStatus.done,
          scheduledAt: now.subtract(const Duration(days: 6)),
        ),
      ];
      final result = RenewalCalculator.estimateExpiryDate(
        makeContract(),
        sessions,
        now: now,
      );
      expect(result, isNull, reason: 'end_date 없으니 null');
    });
  });

  group('estimateExpiryDate — 정상 추정', () {
    test('4주간 주당 2회 페이스, 잔여 2회 → 약 1주 후 만료 예상', () {
      // 첫 차감 = now - 28일, 차감 8회
      final sessions = List.generate(
        8,
        (i) => makeSession(
          id: 's$i',
          status: SessionStatus.done,
          scheduledAt: now.subtract(Duration(days: 28 - i * 3)),
        ),
      );
      final result = RenewalCalculator.estimateExpiryDate(
        makeContract(total: 10),
        sessions,
        now: now,
      );
      expect(result, isNotNull);
      final daysUntil = result!.difference(now).inDays;
      // 잔여 2 / (8/4주) = 1주 ≒ 7일. 반올림 오차 ±1.
      expect(daysUntil, inInclusiveRange(6, 8),
          reason: '주당 2회 페이스 + 잔여 2회 → 약 7일');
    });

    test('잔여 0 → now 반환 (이미 만료)', () {
      final sessions = List.generate(
        10,
        (i) => makeSession(
          id: 's$i',
          status: SessionStatus.done,
          scheduledAt: now.subtract(Duration(days: 30 - i * 3)),
        ),
      );
      final result = RenewalCalculator.estimateExpiryDate(
        makeContract(total: 10),
        sessions,
        now: now,
      );
      expect(result, now);
    });
  });

  group('estimateExpiryDate — end_date와 추정값 중 빠른 날', () {
    test('추정 만료일 > end_date → end_date 우선', () {
      // 페이스 느림 (4주에 4회), 잔여 6 → 약 6주 후 추정
      // 그런데 end_date가 2주 후라면 end_date 우선
      final sessions = List.generate(
        4,
        (i) => makeSession(
          id: 's$i',
          status: SessionStatus.done,
          scheduledAt: now.subtract(Duration(days: 28 - i * 7)),
        ),
      );
      final endDate = now.add(const Duration(days: 14));
      final result = RenewalCalculator.estimateExpiryDate(
        makeContract(total: 10, endDate: endDate),
        sessions,
        now: now,
      );
      expect(result, endDate);
    });

    test('추정 만료일 < end_date → 추정 우선', () {
      // 빠른 페이스로 곧 만료 예상인데 end_date는 한참 뒤
      final sessions = List.generate(
        8,
        (i) => makeSession(
          id: 's$i',
          status: SessionStatus.done,
          scheduledAt: now.subtract(Duration(days: 28 - i * 3)),
        ),
      );
      final farEnd = now.add(const Duration(days: 365));
      final result = RenewalCalculator.estimateExpiryDate(
        makeContract(total: 10, endDate: farEnd),
        sessions,
        now: now,
      );
      expect(result, isNot(farEnd));
      expect(result!.isBefore(farEnd), isTrue);
    });
  });

  group('getAlertLevel — none', () {
    test('사용 0회 → none', () {
      final result = RenewalCalculator.getAlertLevel(
        makeContract(total: 10),
        [],
        now: now,
      );
      expect(result, RenewalAlertLevel.none);
    });

    test('사용 4회 (절반 미만) + 페이스 데이터 부족 → none', () {
      final sessions = [
        makeSession(
          id: 's1',
          status: SessionStatus.done,
          scheduledAt: now.subtract(const Duration(days: 3)),
        ),
      ];
      final result = RenewalCalculator.getAlertLevel(
        makeContract(total: 10),
        sessions,
        now: now,
      );
      expect(result, RenewalAlertLevel.none);
    });
  });

  group('getAlertLevel — half', () {
    test('used 절반 + 잔여 > 5 → half (예: 20회 중 10회 사용)', () {
      // total 20, used 10 → remaining 10 (fiveLeft 아님, half O)
      // 페이스 느려서 expiring도 아님
      final sessions = List.generate(
        10,
        (i) => makeSession(
          id: 's$i',
          status: SessionStatus.done,
          scheduledAt: now.subtract(Duration(days: 120 - i * 12)),
        ),
      );
      final result = RenewalCalculator.getAlertLevel(
        makeContract(total: 20),
        sessions,
        now: now,
      );
      expect(result, RenewalAlertLevel.half);
    });

    test('used 정확히 절반 경계 — total 짝수 (12/24) → half', () {
      // 경계 케이스: used*2 == total 일 때도 half에 포함되는지
      final sessions = List.generate(
        12,
        (i) => makeSession(
          id: 's$i',
          status: SessionStatus.done,
          scheduledAt: now.subtract(Duration(days: 180 - i * 14)),
        ),
      );
      final result = RenewalCalculator.getAlertLevel(
        makeContract(total: 24),
        sessions,
        now: now,
      );
      expect(result, RenewalAlertLevel.half);
    });
  });

  group('getAlertLevel — fiveLeft', () {
    test('잔여 5회 정확히 (total 10, used 5) → fiveLeft (half보다 우선)', () {
      // total 10, used 5 → remaining 5. half 조건도 만족하지만 fiveLeft가 우선순위 위.
      final sessions = List.generate(
        5,
        (i) => makeSession(
          id: 's$i',
          status: SessionStatus.done,
          scheduledAt: now.subtract(Duration(days: 90 - i * 18)),
        ),
      );
      final result = RenewalCalculator.getAlertLevel(
        makeContract(total: 10),
        sessions,
        now: now,
      );
      expect(result, RenewalAlertLevel.fiveLeft);
    });

    test('잔여 3회, 페이스 느림 → fiveLeft (expiring 아님)', () {
      // 12주에 7회 → 주당 0.58회 → 잔여 3회 / 0.58 ≒ 5주 → 7일 초과
      final sessions = List.generate(
        7,
        (i) => makeSession(
          id: 's$i',
          status: SessionStatus.done,
          scheduledAt: now.subtract(Duration(days: 84 - i * 12)),
        ),
      );
      final result = RenewalCalculator.getAlertLevel(
        makeContract(total: 10),
        sessions,
        now: now,
      );
      expect(result, RenewalAlertLevel.fiveLeft);
    });
  });

  group('getAlertLevel — expiring (최우선)', () {
    test('잔여 0 → expiring', () {
      final sessions = List.generate(
        10,
        (i) => makeSession(
          id: 's$i',
          status: SessionStatus.done,
          scheduledAt: now.subtract(Duration(days: 30 - i * 3)),
        ),
      );
      final result = RenewalCalculator.getAlertLevel(
        makeContract(total: 10),
        sessions,
        now: now,
      );
      expect(result, RenewalAlertLevel.expiring);
    });

    test('end_date가 7일 이내 → expiring (잔여 많아도)', () {
      final result = RenewalCalculator.getAlertLevel(
        makeContract(total: 10, endDate: now.add(const Duration(days: 5))),
        [],
        now: now,
      );
      expect(result, RenewalAlertLevel.expiring);
    });

    test('빠른 페이스로 추정 만료일이 7일 이내 → expiring', () {
      // 4주간 8회 (주당 2회), 잔여 2회 → 약 1주 후 만료 예상
      final sessions = List.generate(
        8,
        (i) => makeSession(
          id: 's$i',
          status: SessionStatus.done,
          scheduledAt: now.subtract(Duration(days: 28 - i * 3)),
        ),
      );
      final result = RenewalCalculator.getAlertLevel(
        makeContract(total: 10),
        sessions,
        now: now,
      );
      expect(result, RenewalAlertLevel.expiring);
    });
  });

  group('getAlertLevel — 우선순위 검증 (한 계약이 여러 조건 만족)', () {
    test('half + fiveLeft + expiring 동시 만족 → expiring', () {
      // 4주간 8회 사용 (페이스 빠름, 잔여 2), total 10
      // → half (8/10 >= 0.5), fiveLeft (잔여 2 <= 5), expiring (추정 1주)
      final sessions = List.generate(
        8,
        (i) => makeSession(
          id: 's$i',
          status: SessionStatus.done,
          scheduledAt: now.subtract(Duration(days: 28 - i * 3)),
        ),
      );
      final result = RenewalCalculator.getAlertLevel(
        makeContract(total: 10),
        sessions,
        now: now,
      );
      expect(result, RenewalAlertLevel.expiring,
          reason: '가장 강한 신호가 이긴다');
    });

    test('half + fiveLeft (expiring X) → fiveLeft 우선', () {
      // total 10, used 6 → remaining 4 (fiveLeft 만족, half도 만족)
      // 페이스 느려서 expiring 아님
      final sessions = List.generate(
        6,
        (i) => makeSession(
          id: 's$i',
          status: SessionStatus.done,
          scheduledAt: now.subtract(Duration(days: 120 - i * 18)),
        ),
      );
      final result = RenewalCalculator.getAlertLevel(
        makeContract(total: 10),
        sessions,
        now: now,
      );
      expect(result, RenewalAlertLevel.fiveLeft);
    });
  });

  // =================================================================
  // getAlertLevelFromCounts — 트레이너 홈 알림 카드용 가벼운 변종
  // =================================================================
  //
  // 본 메서드는 v_contract_status 행에서 직접 used/remaining/total/endDate 만
  // 받아 판정한다 (세션 리스트 fetch 없음). 페이스 기반 만료일 추정은 *하지 않는다*.
  group('getAlertLevelFromCounts — none / half / fiveLeft', () {
    test('used 0 → none', () {
      final r = RenewalCalculator.getAlertLevelFromCounts(
        total: 10,
        used: 0,
        remaining: 10,
        now: now,
      );
      expect(r, RenewalAlertLevel.none);
    });

    test('used 정확히 절반 → half', () {
      final r = RenewalCalculator.getAlertLevelFromCounts(
        total: 20,
        used: 10,
        remaining: 10,
        now: now,
      );
      expect(r, RenewalAlertLevel.half);
    });

    test('remaining 5 → fiveLeft (half 보다 우선)', () {
      final r = RenewalCalculator.getAlertLevelFromCounts(
        total: 10,
        used: 5,
        remaining: 5,
        now: now,
      );
      expect(r, RenewalAlertLevel.fiveLeft);
    });

    test('remaining 4 → fiveLeft', () {
      final r = RenewalCalculator.getAlertLevelFromCounts(
        total: 20,
        used: 16,
        remaining: 4,
        now: now,
      );
      expect(r, RenewalAlertLevel.fiveLeft);
    });
  });

  group('getAlertLevelFromCounts — expiring (최우선)', () {
    test('remaining 0 → expiring', () {
      final r = RenewalCalculator.getAlertLevelFromCounts(
        total: 10,
        used: 10,
        remaining: 0,
        now: now,
      );
      expect(r, RenewalAlertLevel.expiring);
    });

    test('endDate 7일 이내 → expiring (remaining 많아도)', () {
      final r = RenewalCalculator.getAlertLevelFromCounts(
        total: 20,
        used: 4,
        remaining: 16,
        endDate: now.add(const Duration(days: 5)),
        now: now,
      );
      expect(r, RenewalAlertLevel.expiring);
    });

    test('endDate 정확히 7일 → expiring (경계 포함)', () {
      final r = RenewalCalculator.getAlertLevelFromCounts(
        total: 20,
        used: 4,
        remaining: 16,
        endDate: now.add(const Duration(days: 7)),
        now: now,
      );
      expect(r, RenewalAlertLevel.expiring);
    });

    test('endDate 8일 이후 → endDate 영향 없음 (다른 조건도 미충족 → none)', () {
      final r = RenewalCalculator.getAlertLevelFromCounts(
        total: 20,
        used: 4,
        remaining: 16,
        endDate: now.add(const Duration(days: 30)),
        now: now,
      );
      expect(r, RenewalAlertLevel.none);
    });
  });

  group('getAlertLevelFromCounts — 본 변종은 페이스 추정 없음', () {
    // getAlertLevel(sessions 있는 본 버전) 은 페이스 기반 expiring 추정을 하지만,
    // FromCounts 는 endDate / remaining=0 만 본다. 같은 입력으로 둘이 다를 수 있음을 명시.
    test('remaining 많고 endDate 도 없으면 → none (페이스 expiring 미적용)', () {
      final r = RenewalCalculator.getAlertLevelFromCounts(
        total: 20,
        used: 14, // half 충족 (14*2 >= 20)
        remaining: 6, // fiveLeft 미충족
        now: now,
      );
      // half 조건만 만족 (14*2=28>=20) → half
      expect(r, RenewalAlertLevel.half);
    });
  });
}
