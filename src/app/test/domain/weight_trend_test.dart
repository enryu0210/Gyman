import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/domain/models/session_record.dart';
import 'package:gyman/domain/weight_trend.dart';

/// 중량 추이 계산기 단위 테스트 (S1 그래프의 진실의 원천).
///
/// **검증 포인트:**
///   - 한 수업의 종목별 "최고 세트 중량" 추출
///   - 여러 수업 → 날짜 오름차순 시계열 (입력 순서 무관)
///   - 맨몸/무게 0 종목·빈 종목명 제외 (가짜 0 방지)
///   - 한 수업에 같은 종목 중복 시 최고값으로 합침
///   - 빈도순 종목 정렬
void main() {
  // 테스트용 종목 생성 헬퍼.
  Exercise ex(String name, List<int> weights) => Exercise(
        name: name,
        sets: [for (final w in weights) ExerciseSet(weight: w, reps: 10)],
      );

  group('WeightTrendCalculator.byExercise', () {
    test('빈 입력 → 빈 맵', () {
      expect(WeightTrendCalculator.byExercise(const []), isEmpty);
    });

    test('한 수업의 종목별 최고 세트 중량을 점으로', () {
      final entries = [
        WorkoutEntry(
          date: DateTime(2026, 3, 1),
          exercises: [
            ex('스쿼트', [60, 70, 65]), // 최고 70
            ex('벤치', [50, 55]), // 최고 55
          ],
        ),
      ];

      final trend = WeightTrendCalculator.byExercise(entries);
      expect(trend['스쿼트'], [TrendPoint(date: DateTime(2026, 3, 1), value: 70)]);
      expect(trend['벤치'], [TrendPoint(date: DateTime(2026, 3, 1), value: 55)]);
    });

    test('여러 수업 → 날짜 오름차순 시계열 (입력이 뒤죽박죽이어도 정렬)', () {
      final entries = [
        WorkoutEntry(date: DateTime(2026, 3, 8), exercises: [ex('스쿼트', [80])]),
        WorkoutEntry(date: DateTime(2026, 3, 1), exercises: [ex('스쿼트', [70])]),
        WorkoutEntry(date: DateTime(2026, 3, 15), exercises: [ex('스쿼트', [85])]),
      ];

      final points = WeightTrendCalculator.byExercise(entries)['스쿼트']!;
      expect(points.map((p) => p.date).toList(), [
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 8),
        DateTime(2026, 3, 15),
      ]);
      expect(points.map((p) => p.value).toList(), [70, 80, 85]);
    });

    test('해당 종목을 안 한 수업은 그 종목 시계열에서 건너뜀', () {
      final entries = [
        WorkoutEntry(date: DateTime(2026, 3, 1), exercises: [ex('스쿼트', [70])]),
        WorkoutEntry(date: DateTime(2026, 3, 8), exercises: [ex('벤치', [50])]),
      ];

      final trend = WeightTrendCalculator.byExercise(entries);
      expect(trend['스쿼트']!.length, 1); // 3/8엔 스쿼트 없음 → 점 없음
      expect(trend['벤치']!.length, 1);
    });

    test('맨몸 운동(전 세트 0kg)은 중량 추이에서 제외', () {
      final entries = [
        WorkoutEntry(
          date: DateTime(2026, 3, 1),
          exercises: [
            ex('스쿼트', [70]),
            ex('푸시업', [0, 0]), // 무게 0 → 제외
          ],
        ),
      ];

      final trend = WeightTrendCalculator.byExercise(entries);
      expect(trend.containsKey('스쿼트'), isTrue);
      expect(trend.containsKey('푸시업'), isFalse);
    });

    test('빈 종목명은 집계에서 제외', () {
      final entries = [
        WorkoutEntry(
          date: DateTime(2026, 3, 1),
          exercises: [
            ex('', [60]),
            ex('   ', [60]), // 공백만
          ],
        ),
      ];
      expect(WeightTrendCalculator.byExercise(entries), isEmpty);
    });

    test('한 수업에 같은 종목 중복 → 최고값으로 합침', () {
      final entries = [
        WorkoutEntry(
          date: DateTime(2026, 3, 1),
          exercises: [
            ex('스쿼트', [60]),
            ex('스쿼트', [80]), // 같은 날 두 번 → 80 하나로
          ],
        ),
      ];
      final points = WeightTrendCalculator.byExercise(entries)['스쿼트']!;
      expect(points.length, 1);
      expect(points.single.value, 80);
    });
  });

  group('WeightTrendCalculator.exercisesByFrequency', () {
    test('많이 한 종목 먼저, 동률은 이름순', () {
      final entries = [
        WorkoutEntry(date: DateTime(2026, 3, 1), exercises: [ex('스쿼트', [70]), ex('벤치', [50])]),
        WorkoutEntry(date: DateTime(2026, 3, 8), exercises: [ex('스쿼트', [75])]),
        WorkoutEntry(date: DateTime(2026, 3, 15), exercises: [ex('데드', [100]), ex('벤치', [55])]),
      ];
      // 스쿼트 2회, 벤치 2회, 데드 1회 → [벤치/스쿼트(이름순), 데드]
      final names = WeightTrendCalculator.exercisesByFrequency(entries);
      expect(names, ['벤치', '스쿼트', '데드']);
    });

    test('무게 0/빈 이름은 빈도 집계에서도 제외', () {
      final entries = [
        WorkoutEntry(date: DateTime(2026, 3, 1), exercises: [ex('푸시업', [0]), ex('', [60])]),
      ];
      expect(WeightTrendCalculator.exercisesByFrequency(entries), isEmpty);
    });
  });
}
