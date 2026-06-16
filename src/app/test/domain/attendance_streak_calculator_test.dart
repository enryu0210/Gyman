import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/domain/attendance_streak_calculator.dart';

/// 출석 스트릭 계산기 단위 테스트.
///
/// **왜 핵심:** 동기부여 배지의 신뢰성. 연속 기준(오늘 미출석 시 어제 기준 유지),
/// 끊김 처리, 월 경계 카운트가 어긋나면 "이번 달 N일"이 틀려 신뢰를 잃는다.
void main() {
  // 기준일 고정 — 2026-06-16 (화). 결정적 테스트.
  final today = DateTime(2026, 6, 16, 9, 30);

  DateTime d(int y, int m, int day) => DateTime(y, m, day);

  group('compute — 빈/기본', () {
    test('빈 입력 → 연속 0, 이번 달 0', () {
      final s = AttendanceStreakCalculator.compute(const [], today: today);
      expect(s.currentStreak, 0);
      expect(s.thisMonthCount, 0);
    });
  });

  group('currentStreak', () {
    test('오늘 포함 연속 3일 → 3', () {
      final days = [d(2026, 6, 16), d(2026, 6, 15), d(2026, 6, 14)];
      final s = AttendanceStreakCalculator.compute(days, today: today);
      expect(s.currentStreak, 3);
    });

    test('오늘 미출석이어도 어제까지 연속이면 살린다 (어제·그제 → 2)', () {
      final days = [d(2026, 6, 15), d(2026, 6, 14)];
      final s = AttendanceStreakCalculator.compute(days, today: today);
      expect(s.currentStreak, 2);
    });

    test('오늘·어제 모두 미출석 → 연속 0 (그저께만 있어도 끊김)', () {
      final days = [d(2026, 6, 14), d(2026, 6, 13)];
      final s = AttendanceStreakCalculator.compute(days, today: today);
      expect(s.currentStreak, 0);
    });

    test('중간에 하루 비면 거기서 끊긴다 (오늘·어제 후 공백 → 2)', () {
      final days = [d(2026, 6, 16), d(2026, 6, 15), d(2026, 6, 13)];
      final s = AttendanceStreakCalculator.compute(days, today: today);
      expect(s.currentStreak, 2);
    });

    test('월 경계를 넘는 연속도 이어진다 (6/1, 5/31, 5/30 ...)', () {
      final base = DateTime(2026, 6, 1, 8);
      final days = [d(2026, 6, 1), d(2026, 5, 31), d(2026, 5, 30)];
      final s = AttendanceStreakCalculator.compute(days, today: base);
      expect(s.currentStreak, 3);
    });

    test('같은 날 PT·셀프 중복(시각 다름)은 하루로 센다', () {
      final days = [
        DateTime(2026, 6, 16, 7),
        DateTime(2026, 6, 16, 19),
        DateTime(2026, 6, 15, 18),
      ];
      final s = AttendanceStreakCalculator.compute(days, today: today);
      expect(s.currentStreak, 2);
    });
  });

  group('thisMonthCount', () {
    test('이번 달 출석일만 센다 (지난달은 제외)', () {
      final days = [
        d(2026, 6, 16),
        d(2026, 6, 10),
        d(2026, 6, 2),
        d(2026, 5, 31), // 지난달 — 제외
      ];
      final s = AttendanceStreakCalculator.compute(days, today: today);
      expect(s.thisMonthCount, 3);
    });

    test('같은 날 중복은 1일로', () {
      final days = [DateTime(2026, 6, 16, 7), DateTime(2026, 6, 16, 20)];
      final s = AttendanceStreakCalculator.compute(days, today: today);
      expect(s.thisMonthCount, 1);
    });
  });
}
