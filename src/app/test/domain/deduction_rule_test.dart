import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/domain/deduction_rule.dart';
import 'package:gyman/domain/models/enums.dart';

/// 차감 규정 단위 테스트.
///
/// **왜 중요한가:** 회원이 "어제 취소했는데 왜 차감됐냐"고 항의하는 케이스가
/// 가장 흔한 분쟁. 경계 시간(정확히 24시간 전) 처리가 코드와 다르면 신뢰 손상.
void main() {
  group('SessionStatus.deducts — 어떤 상태가 차감되는가', () {
    test('done은 차감 대상', () {
      expect(SessionStatus.done.deducts, isTrue);
    });

    test('noShow는 차감 대상', () {
      expect(SessionStatus.noShow.deducts, isTrue);
    });

    test('lateCancel은 차감 대상', () {
      expect(SessionStatus.lateCancel.deducts, isTrue);
    });

    test('scheduled는 차감 X', () {
      expect(SessionStatus.scheduled.deducts, isFalse);
    });

    test('canceled는 차감 X', () {
      expect(SessionStatus.canceled.deducts, isFalse);
    });
  });

  group('DeductionRule.classifyCancellation — 정책 24시간 기준', () {
    // 수업 일시: 2026-01-10 19:00 (고정 시각으로 테스트 결정성 확보)
    final scheduled = DateTime(2026, 1, 10, 19, 0);

    test('25시간 전 취소 → canceled', () {
      final result = DeductionRule.classifyCancellation(
        scheduledAt: scheduled,
        cancelAt: DateTime(2026, 1, 9, 18, 0), // 25시간 전
      );
      expect(result, SessionStatus.canceled);
    });

    test('정확히 24시간 전 취소 → canceled (회원에게 유리한 경계)', () {
      final result = DeductionRule.classifyCancellation(
        scheduledAt: scheduled,
        cancelAt: DateTime(2026, 1, 9, 19, 0), // 정확히 24시간 전
      );
      expect(result, SessionStatus.canceled,
          reason: '경계는 회원에게 유리하게: 정확히 24시간 전이면 무료 취소');
    });

    test('23시간 59분 전 취소 → lateCancel', () {
      final result = DeductionRule.classifyCancellation(
        scheduledAt: scheduled,
        cancelAt: DateTime(2026, 1, 9, 19, 1), // 23시간 59분 전
      );
      expect(result, SessionStatus.lateCancel);
    });

    test('수업 30분 전 취소 → lateCancel', () {
      final result = DeductionRule.classifyCancellation(
        scheduledAt: scheduled,
        cancelAt: DateTime(2026, 1, 10, 18, 30),
      );
      expect(result, SessionStatus.lateCancel);
    });

    test('수업 시작 이후 취소 → lateCancel (데이터 오류 방어)', () {
      // 시작 후 "취소"는 노쇼로 처리하는 게 자연스럽지만,
      // 트레이너 실수 입력 시 도메인은 일관되게 차감 측으로 분류해 안전 우선.
      final result = DeductionRule.classifyCancellation(
        scheduledAt: scheduled,
        cancelAt: DateTime(2026, 1, 10, 19, 30),
      );
      expect(result, SessionStatus.lateCancel);
    });
  });

  group('DeductionRule.classifyCancellation — 센터별 정책 오버라이드', () {
    final scheduled = DateTime(2026, 1, 10, 19, 0);
    const lenient = DeductionPolicy(cancelDeadlineHoursBefore: 12);
    const strict = DeductionPolicy(cancelDeadlineHoursBefore: 48);

    test('12시간 정책: 13시간 전 취소 → canceled', () {
      final result = DeductionRule.classifyCancellation(
        scheduledAt: scheduled,
        cancelAt: DateTime(2026, 1, 10, 6, 0), // 13시간 전
        policy: lenient,
      );
      expect(result, SessionStatus.canceled);
    });

    test('12시간 정책: 11시간 전 취소 → lateCancel', () {
      final result = DeductionRule.classifyCancellation(
        scheduledAt: scheduled,
        cancelAt: DateTime(2026, 1, 10, 8, 0), // 11시간 전
        policy: lenient,
      );
      expect(result, SessionStatus.lateCancel);
    });

    test('48시간 정책: 36시간 전 취소도 lateCancel (엄격)', () {
      final result = DeductionRule.classifyCancellation(
        scheduledAt: scheduled,
        cancelAt: DateTime(2026, 1, 9, 7, 0), // 36시간 전
        policy: strict,
      );
      expect(result, SessionStatus.lateCancel);
    });
  });

  group('DeductionRule.isDeducted — enum 차감 판정 래퍼', () {
    test('SessionStatusRule.deducts와 일치', () {
      for (final status in SessionStatus.values) {
        expect(DeductionRule.isDeducted(status), status.deducts,
            reason: '$status에서 두 방식이 불일치하면 안 됨');
      }
    });
  });
}
