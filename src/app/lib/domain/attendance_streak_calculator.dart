/// 출석 스트릭/이번 달 출석일 계산 — 회원 홈 동기부여 배지 (운톡 불만 #6 대응).
///
/// **왜 도메인 로직인가:**
///   "연속 며칠째", "이번 달 N일 출석" 같은 동기부여 수치는 정의(연속의 기준,
///   오늘 미출석 시 처리)가 흔들리기 쉽다. 한 곳에 모아 단위 테스트로 고정한다
///   (CLAUDE.md §5.1 — 가시성/계산은 단위 테스트 필수).
///
/// **출석 정의:** PT 완료 수업 날 + 셀프 운동 기록 날의 합집합(날짜 단위).
///   같은 날 PT·셀프 둘 다여도 하루로 센다.
///
/// **연속(currentStreak) 기준:** 오늘 출석했으면 오늘부터, 아직 안 했으면
///   어제부터 역순으로 끊기지 않고 이어진 날 수. 둘 다 없으면 0.
///   (오늘 아직 운동 안 했다고 어제까지의 연속이 0으로 보이면 동기부여가 깨지므로
///    어제 기준 연속을 살려준다.)
///
/// 참고: docs/untok_improvement_plan.md §5 D.
library;

/// 출석 통계 결과.
class AttendanceStats {
  /// 연속 출석일 수(오늘 또는 어제부터 역순).
  final int currentStreak;

  /// 기준일이 속한 달의 출석일 수.
  final int thisMonthCount;

  const AttendanceStats({
    required this.currentStreak,
    required this.thisMonthCount,
  });

  static const empty = AttendanceStats(currentStreak: 0, thisMonthCount: 0);
}

class AttendanceStreakCalculator {
  /// 시각을 떼고 날짜(자정)만 남긴다. set 키 정규화에 사용.
  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// 출석일 집합으로 통계 계산.
  ///
  /// [days]: 출석한 날들(시각 포함 가능 — 내부에서 날짜로 정규화).
  /// [today]: 기준일(테스트 결정성용 주입점). 미지정 시 DateTime.now().
  static AttendanceStats compute(Iterable<DateTime> days, {DateTime? today}) {
    final ref = dateOnly(today ?? DateTime.now());
    final norm = days.map(dateOnly).toSet();

    final monthCount = norm
        .where((d) => d.year == ref.year && d.month == ref.month)
        .length;

    return AttendanceStats(
      currentStreak: _streak(norm, ref),
      thisMonthCount: monthCount,
    );
  }

  static int _streak(Set<DateTime> days, DateTime ref) {
    // 시작점: 오늘 출석 → 오늘, 아니면 어제 출석 → 어제, 둘 다 없으면 연속 0.
    DateTime cursor;
    if (days.contains(ref)) {
      cursor = ref;
    } else {
      final yesterday = _prevDay(ref);
      if (days.contains(yesterday)) {
        cursor = yesterday;
      } else {
        return 0;
      }
    }

    var count = 0;
    while (days.contains(cursor)) {
      count++;
      cursor = _prevDay(cursor);
    }
    return count;
  }

  /// 하루 전 날짜. DateTime(y, m, d-1) 형태라 월/연 경계도 안전하게 넘어간다.
  static DateTime _prevDay(DateTime d) => DateTime(d.year, d.month, d.day - 1);
}
