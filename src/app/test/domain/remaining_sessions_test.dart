import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/domain/models/enums.dart';
import 'package:gyman/domain/models/pt_contract.dart';
import 'package:gyman/domain/models/session.dart';
import 'package:gyman/domain/remaining_sessions.dart';

/// 잔여 횟수 계산 단위 테스트.
///
/// **왜 핵심:** 매출/분쟁 직결 로직. "내 10회 중 몇 회 남았냐"가 틀리면
/// 회원은 즉시 신뢰를 잃는다. develop_plan §5.1 Critical 표시.
void main() {
  /// 테스트 공용 빌더 — 매번 모든 필드 지정하면 가독성 떨어져서 빌더 사용.
  PtContract makeContract({int total = 10}) => PtContract(
        id: 'c1',
        memberId: 'm1',
        trainerId: 't1',
        totalSessions: total,
        startDate: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
      );

  Session makeSession({
    required String id,
    required SessionStatus status,
    String contractId = 'c1',
    DateTime? scheduledAt,
  }) =>
      Session(
        id: id,
        contractId: contractId,
        status: status,
        scheduledAt: scheduledAt ?? DateTime(2026, 1, 10, 19),
        createdAt: DateTime(2026, 1, 1),
      );

  group('빈 sessions / 예약만 있는 케이스', () {
    test('세션이 0개면 used 0, remaining = total', () {
      final s = RemainingSessionsCalculator.calculate(makeContract(total: 10), []);
      expect(s.used, 0);
      expect(s.remaining, 10);
    });

    test('모두 scheduled면 차감 0', () {
      final sessions = List.generate(
        5,
        (i) => makeSession(id: 's$i', status: SessionStatus.scheduled),
      );
      final s = RemainingSessionsCalculator.calculate(
        makeContract(total: 10),
        sessions,
      );
      expect(s.used, 0);
      expect(s.remaining, 10);
      expect(s.scheduledCount, 5);
    });
  });

  group('requested(회원 신청) — 차감 안 됨', () {
    test('requested만 4개 → used 0, remaining = total, requestedCount 4', () {
      // 회원이 신청만 하고 트레이너 미승인 상태. 잔여에 영향 주면 안 됨(0021).
      final sessions = List.generate(
        4,
        (i) => makeSession(id: 's$i', status: SessionStatus.requested),
      );
      final s = RemainingSessionsCalculator.calculate(
        makeContract(total: 10),
        sessions,
      );
      expect(s.used, 0);
      expect(s.remaining, 10);
      expect(s.requestedCount, 4);
      expect(s.scheduledCount, 0, reason: 'requested 가 scheduled 로 새면 안 됨');
    });
  });

  group('단일 상태 누적', () {
    test('done만 4개 → used 4, remaining 6', () {
      final sessions = List.generate(
        4,
        (i) => makeSession(id: 's$i', status: SessionStatus.done),
      );
      final s = RemainingSessionsCalculator.calculate(
        makeContract(total: 10),
        sessions,
      );
      expect(s.used, 4);
      expect(s.remaining, 6);
      expect(s.doneCount, 4);
    });

    test('noShow만 3개 → 차감 3 (회원에게 가장 억울한 케이스지만 규정)', () {
      final sessions = List.generate(
        3,
        (i) => makeSession(id: 's$i', status: SessionStatus.noShow),
      );
      final s = RemainingSessionsCalculator.calculate(
        makeContract(total: 10),
        sessions,
      );
      expect(s.used, 3);
      expect(s.noShowCount, 3);
    });

    test('lateCancel만 2개 → 차감 2', () {
      final sessions = List.generate(
        2,
        (i) => makeSession(id: 's$i', status: SessionStatus.lateCancel),
      );
      final s = RemainingSessionsCalculator.calculate(
        makeContract(total: 10),
        sessions,
      );
      expect(s.used, 2);
      expect(s.lateCancelCount, 2);
    });

    test('canceled(정상)만 5개 → 차감 0', () {
      final sessions = List.generate(
        5,
        (i) => makeSession(id: 's$i', status: SessionStatus.canceled),
      );
      final s = RemainingSessionsCalculator.calculate(
        makeContract(total: 10),
        sessions,
      );
      expect(s.used, 0);
      expect(s.remaining, 10);
      expect(s.canceledCount, 5);
    });
  });

  group('혼합 케이스 (현실 시나리오)', () {
    test('done 4 + noShow 1 + lateCancel 1 + canceled 1 + scheduled 2', () {
      final sessions = <Session>[
        ...List.generate(4, (i) => makeSession(id: 'd$i', status: SessionStatus.done)),
        makeSession(id: 'n1', status: SessionStatus.noShow),
        makeSession(id: 'l1', status: SessionStatus.lateCancel),
        makeSession(id: 'c1', status: SessionStatus.canceled),
        ...List.generate(2, (i) => makeSession(id: 'sc$i', status: SessionStatus.scheduled)),
      ];
      final s = RemainingSessionsCalculator.calculate(
        makeContract(total: 10),
        sessions,
      );
      expect(s.used, 6, reason: 'done 4 + noShow 1 + lateCancel 1');
      expect(s.remaining, 4);
      expect(s.doneCount, 4);
      expect(s.noShowCount, 1);
      expect(s.lateCancelCount, 1);
      expect(s.canceledCount, 1);
      expect(s.scheduledCount, 2);
    });

    test('잔여가 정확히 0일 때 isExhausted=true', () {
      final sessions = List.generate(
        10,
        (i) => makeSession(id: 's$i', status: SessionStatus.done),
      );
      final s = RemainingSessionsCalculator.calculate(
        makeContract(total: 10),
        sessions,
      );
      expect(s.remaining, 0);
      expect(s.isExhausted, isTrue);
    });
  });

  group('방어 동작', () {
    test('다른 계약의 세션이 섞여 있으면 무시', () {
      final sessions = <Session>[
        makeSession(id: 'mine', status: SessionStatus.done),
        // 다른 계약 — 합산되면 안 됨
        makeSession(
          id: 'others',
          status: SessionStatus.done,
          contractId: 'OTHER_CONTRACT',
        ),
        makeSession(
          id: 'others2',
          status: SessionStatus.noShow,
          contractId: 'OTHER_CONTRACT',
        ),
      ];
      final s = RemainingSessionsCalculator.calculate(
        makeContract(total: 10),
        sessions,
      );
      expect(s.used, 1, reason: 'OTHER_CONTRACT 의 세션은 무시');
      expect(s.remaining, 9);
    });

    test('과기록(used > total)이라도 remaining은 0으로 클램프', () {
      final sessions = List.generate(
        12,
        (i) => makeSession(id: 's$i', status: SessionStatus.done),
      );
      final s = RemainingSessionsCalculator.calculate(
        makeContract(total: 10),
        sessions,
      );
      expect(s.used, 12);
      expect(s.remaining, 0, reason: '음수 방지 — UI 깨짐 방지');
      expect(s.isExhausted, isTrue);
    });
  });

  group('편의 메서드 remaining()', () {
    test('calculate(...).remaining 과 동일한 값 반환', () {
      final contract = makeContract(total: 8);
      final sessions = [
        makeSession(id: 's1', status: SessionStatus.done),
        makeSession(id: 's2', status: SessionStatus.done),
      ];
      expect(
        RemainingSessionsCalculator.remaining(contract, sessions),
        RemainingSessionsCalculator.calculate(contract, sessions).remaining,
      );
    });
  });
}
