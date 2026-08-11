import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/domain/body_change_summary.dart';
import 'package:gyman/domain/models/body_measurement.dart';

/// 최근 인바디 변화 요약 단위 테스트.
///
/// **왜 핵심:** 회원 홈 ④ 카드가 "체중 72.4kg (-0.8)" 처럼 회원의 몸에 대한 수치를
/// 단정적으로 말한다. 지표별 nullable(일부만 측정) 처리가 틀리면 비교 대상이 아닌
/// 값끼리 빼서 있지도 않은 변화를 보여주게 된다.
void main() {
  BodyMeasurement m(
    int day, {
    double? weight,
    double? fat,
    double? muscle,
    int createdHour = 9,
  }) {
    return BodyMeasurement(
      id: 'measure-$day-$createdHour',
      memberId: 'member-1',
      measuredAt: DateTime(2026, 8, day),
      createdAt: DateTime(2026, 8, day, createdHour),
      weightKg: weight,
      bodyFatPct: fat,
      skeletalMuscleKg: muscle,
    );
  }

  group('빈 입력', () {
    test('측정이 없으면 empty — 홈이 카드를 안 그린다', () {
      final s = buildBodyChangeSummary(const []);
      expect(s.isEmpty, isTrue);
      expect(s.metrics, isEmpty);
      expect(s.latestMeasuredAt, isNull);
    });

    test('행은 있지만 세 지표가 모두 null 이면 empty', () {
      final s = buildBodyChangeSummary([m(1)]);
      expect(s.isEmpty, isTrue);
    });
  });

  group('기본 비교', () {
    test('최근값과 직전값의 차이를 부호 그대로 돌려준다', () {
      final s = buildBodyChangeSummary([
        m(1, weight: 73.2, fat: 22.0, muscle: 30.0),
        m(8, weight: 72.4, fat: 21.2, muscle: 30.5),
      ]);
      expect(s.weightKg!.latest, 72.4);
      expect(s.weightKg!.previous, 73.2);
      expect(s.weightKg!.delta, closeTo(-0.8, 1e-9));
      expect(s.bodyFatPct!.delta, closeTo(-0.8, 1e-9));
      expect(s.skeletalMuscleKg!.delta, closeTo(0.5, 1e-9));
      expect(s.isEmpty, isFalse);
    });

    test('측정이 한 번뿐이면 비교 없음(첫 기록)', () {
      final s = buildBodyChangeSummary([m(8, weight: 72.4)]);
      expect(s.weightKg!.latest, 72.4);
      expect(s.weightKg!.hasComparison, isFalse);
      expect(s.weightKg!.delta, isNull);
      expect(s.bodyFatPct, isNull);
    });

    test('입력 순서가 뒤섞여 있어도 측정일 기준으로 최신을 고른다', () {
      final s = buildBodyChangeSummary([
        m(8, weight: 72.4),
        m(1, weight: 73.2),
      ]);
      expect(s.weightKg!.latest, 72.4);
      expect(s.weightKg!.previous, 73.2);
    });
  });

  group('지표별 독립 탐색 (일부 항목만 측정한 회차)', () {
    test('중간 회차에 체중만 쟀어도 체지방 비교는 그 전 회차와 이어진다', () {
      final s = buildBodyChangeSummary([
        m(1, weight: 73.2, fat: 22.0),
        m(8, weight: 72.8), // 체중만 측정
        m(15, weight: 72.4, fat: 21.0),
      ]);
      // 체중: 15일(72.4) vs 8일(72.8)
      expect(s.weightKg!.delta, closeTo(-0.4, 1e-9));
      expect(s.weightKg!.previousAt, DateTime(2026, 8, 8));
      // 체지방: 15일(21.0) vs 1일(22.0) — 8일 회차는 값이 없어 건너뛴다.
      expect(s.bodyFatPct!.delta, closeTo(-1.0, 1e-9));
      expect(s.bodyFatPct!.previousAt, DateTime(2026, 8, 1));
    });

    test('최신 회차에 없는 지표는 그 값이 있는 마지막 회차를 최근값으로 본다', () {
      final s = buildBodyChangeSummary([
        m(1, muscle: 30.0),
        m(8, muscle: 30.6),
        m(15, weight: 72.4), // 골격근 미측정
      ]);
      expect(s.skeletalMuscleKg!.latest, 30.6);
      expect(s.skeletalMuscleKg!.latestAt, DateTime(2026, 8, 8));
      expect(s.skeletalMuscleKg!.delta, closeTo(0.6, 1e-9));
      // 카드 부제는 지표 중 가장 최근 측정일.
      expect(s.latestMeasuredAt, DateTime(2026, 8, 15));
    });
  });

  group('같은 날 두 번 측정', () {
    test('행 생성 시각이 늦은 쪽이 최근값', () {
      final s = buildBodyChangeSummary([
        m(8, weight: 72.9, createdHour: 8),
        m(8, weight: 72.4, createdHour: 20),
      ]);
      expect(s.weightKg!.latest, 72.4);
      expect(s.weightKg!.previous, 72.9);
    });
  });
}
