import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/domain/weekly_activity.dart';

/// 이번 주 운동 현황 계산 단위 테스트.
///
/// **왜 핵심:** 회원 홈 ③ 카드가 "이번 주 N일" 과 요일 도트를 이 결과로 그린다.
/// 주 시작 요일(월)·주 경계·오늘 이후 칸 처리가 어긋나면 지난주 운동이 이번 주로
/// 새거나, 아직 오지 않은 날이 "빠뜨린 날"로 보인다.
void main() {
  // 기준일 고정 — 2026-08-13 (목). 이 주의 월요일은 8/10, 일요일은 8/16.
  final now = DateTime(2026, 8, 13, 10);

  DateTime d(int day) => DateTime(2026, 8, day);

  group('weekStartOf', () {
    test('목요일 → 같은 주 월요일', () {
      expect(weekStartOf(now), DateTime(2026, 8, 10));
    });

    test('월요일이면 그날이 주 시작', () {
      expect(weekStartOf(DateTime(2026, 8, 10, 23)), DateTime(2026, 8, 10));
    });

    test('일요일은 지난 월요일이 주 시작 (일=주의 끝)', () {
      expect(weekStartOf(DateTime(2026, 8, 16, 1)), DateTime(2026, 8, 10));
    });

    test('월 경계를 넘어가도 안전 (8/2 일요일 → 7/27 월요일)', () {
      expect(weekStartOf(DateTime(2026, 8, 2)), DateTime(2026, 7, 27));
    });
  });

  group('days 구성', () {
    test('항상 월~일 7칸이고 첫 칸이 월요일', () {
      final w = buildWeeklyActivity(
        workoutDays: const [],
        plannedPtDays: const [],
        now: now,
      );
      expect(w.days.length, 7);
      expect(w.days.first.date, DateTime(2026, 8, 10));
      expect(w.days.last.date, DateTime(2026, 8, 16));
      expect(w.days.first.date.weekday, DateTime.monday);
    });

    test('오늘 칸만 isToday, 이전 칸만 isPast', () {
      final w = buildWeeklyActivity(
        workoutDays: const [],
        plannedPtDays: const [],
        now: now,
      );
      final today = w.days.firstWhere((x) => x.isToday);
      expect(today.date, d(13));
      expect(w.days.where((x) => x.isToday).length, 1);
      // 8/10·11·12 = 3칸이 지나간 날. 오늘(8/13)은 isPast 아님.
      expect(w.days.where((x) => x.isPast).length, 3);
      expect(today.isPast, isFalse);
    });
  });

  group('workoutCount', () {
    test('이번 주 운동일만 센다 (지난주·다음주 제외)', () {
      final w = buildWeeklyActivity(
        workoutDays: [d(9), d(10), d(12), d(17)], // 9=지난주 일, 17=다음주 월
        plannedPtDays: const [],
        now: now,
      );
      expect(w.workoutCount, 2);
      expect(w.days[0].workedOut, isTrue); // 8/10
      expect(w.days[2].workedOut, isTrue); // 8/12
    });

    test('같은 날 여러 건(시각 다름)은 하루로', () {
      final w = buildWeeklyActivity(
        workoutDays: [
          DateTime(2026, 8, 12, 7),
          DateTime(2026, 8, 12, 19),
        ],
        plannedPtDays: const [],
        now: now,
      );
      expect(w.workoutCount, 1);
    });
  });

  group('plannedPt', () {
    test('예정 PT 가 있는 날은 hasPlannedPt', () {
      final w = buildWeeklyActivity(
        workoutDays: const [],
        plannedPtDays: [d(14)],
        now: now,
      );
      expect(w.days[4].hasPlannedPt, isTrue); // 8/14 금
      expect(w.plannedCount, 1);
    });

    test('이미 운동한 날은 예정 표시를 하지 않는다 (한 운동이 지워져 보이면 안 됨)', () {
      final w = buildWeeklyActivity(
        workoutDays: [d(13)],
        plannedPtDays: [d(13)], // 오전에 하고 저녁에 또 예약
        now: now,
      );
      final today = w.days.firstWhere((x) => x.isToday);
      expect(today.workedOut, isTrue);
      expect(today.hasPlannedPt, isFalse);
      expect(w.workoutCount, 1);
      expect(w.plannedCount, 0);
    });
  });

  group('isMissed', () {
    test('지나갔고 운동도 없던 날만 놓친 칸', () {
      final w = buildWeeklyActivity(
        workoutDays: [d(10)],
        plannedPtDays: [d(14)],
        now: now,
      );
      expect(w.days[0].isMissed, isFalse); // 8/10 운동함
      expect(w.days[1].isMissed, isTrue); // 8/11 지나갔고 안 함
      // 오늘과 미래는 아직 놓친 게 아니다.
      expect(w.days[3].isMissed, isFalse); // 8/13 오늘
      expect(w.days[4].isMissed, isFalse); // 8/14 미래
    });
  });
}
