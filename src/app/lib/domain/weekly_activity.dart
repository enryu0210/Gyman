/// 이번 주 운동 현황 계산 — **순수 도메인 로직** (Flutter 의존 0).
///
/// 회원 홈 정보 우선순위 ③ "이번 주 운동 목표·출석 현황"(계획서 §3.3)의 계산부.
///
/// **왜 "목표"가 아니라 "현황"인가:**
///   계획서는 목표 대비 달성률을 말하지만, 주당 목표 횟수를 담을 컬럼이 DB에 없다
///   (`member_profiles.goal` 은 "체중감량" 같은 자유 텍스트 운동 목적이고, 1차 개편은
///   스키마 변경 범위 밖). 없는 목표를 임의 상수(주 3회 등)로 지어내면 회원마다 틀린
///   기준으로 달성/미달을 판정하게 되므로, 목표 없이 **한 주의 사실**만 보여준다.
///   목표 기능은 스키마가 생긴 뒤 이 계산기에 분모를 더하는 방식으로 확장한다.
///
/// **왜 도메인인가:** 주 시작 요일(월요일)·오늘 이후 칸의 처리·완료와 예정의 구분은
///   경계에서 조용히 틀어지는 규칙이다. `now` 를 주입받는 순수 함수로 고정해 단위
///   테스트로 못 박는다(CLAUDE.md 도메인 규칙).
///
/// **운동한 날의 정의는 스트릭과 동일** — 완료 PT + 셀프 기록의 합집합(날짜 단위).
///   두 지표가 다른 기준을 쓰면 "5일 연속인데 이번 주 3일" 같은 모순이 보인다.
library;

/// 이번 주 한 칸(하루).
class WeeklyDay {
  const WeeklyDay({
    required this.date,
    required this.workedOut,
    required this.hasPlannedPt,
    required this.isToday,
    required this.isPast,
  });

  /// 자정으로 정규화된 날짜.
  final DateTime date;

  /// 실제로 운동한 날(완료 PT 또는 셀프 기록).
  final bool workedOut;

  /// 아직 안 한 예정 PT 가 잡힌 날. 미래 칸의 "예정" 표시용.
  final bool hasPlannedPt;

  /// 오늘인가.
  final bool isToday;

  /// 오늘보다 이전인가(지나간 칸 — 여기의 미운동은 되돌릴 수 없다).
  final bool isPast;

  /// 지나갔는데 운동도 예정도 없던 날 — 화면에서 옅게 비워 두는 칸.
  bool get isMissed => isPast && !workedOut;
}

/// 이번 주(월~일) 요약.
class WeeklyActivity {
  const WeeklyActivity({
    required this.days,
    required this.workoutCount,
    required this.plannedCount,
  });

  /// 월요일부터 일요일까지 7칸(항상 7개).
  final List<WeeklyDay> days;

  /// 이번 주에 실제로 운동한 날 수.
  final int workoutCount;

  /// 이번 주에 남아 있는 예정 PT 가 있는 날 수(오늘 포함, 이미 한 날은 제외).
  final int plannedCount;

  static final empty = WeeklyActivity(
    days: List<WeeklyDay>.unmodifiable(const <WeeklyDay>[]),
    workoutCount: 0,
    plannedCount: 0,
  );
}

/// 시각을 떼고 날짜(자정)만 남긴다.
DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// [now] 가 속한 주의 월요일. `DateTime.weekday` 는 1=월 ~ 7=일.
DateTime weekStartOf(DateTime now) {
  final today = _dateOnly(now);
  // day - (weekday-1) 로 빼면 월/연 경계도 DateTime 이 알아서 넘긴다.
  return DateTime(today.year, today.month, today.day - (today.weekday - 1));
}

/// 이번 주 운동 현황을 만든다.
///
/// [workoutDays]  : 실제로 운동한 날(완료 PT + 셀프). 시각이 섞여 있어도 무방.
/// [plannedPtDays]: 아직 안 한 예정 PT 가 있는 날.
/// [now]          : 기준 시각(테스트 주입점).
///
/// 같은 날이 양쪽에 모두 있으면 **운동한 날이 이긴다** — 오전에 PT 를 마치고 저녁에
/// 또 예약이 있는 경우까지 "예정"으로 보이면 이미 한 운동이 지워진 것처럼 읽힌다.
WeeklyActivity buildWeeklyActivity({
  required Iterable<DateTime> workoutDays,
  required Iterable<DateTime> plannedPtDays,
  required DateTime now,
}) {
  final today = _dateOnly(now);
  final start = weekStartOf(now);
  final worked = workoutDays.map(_dateOnly).toSet();
  final planned = plannedPtDays.map(_dateOnly).toSet();

  final days = <WeeklyDay>[];
  var workoutCount = 0;
  var plannedCount = 0;

  for (var i = 0; i < 7; i++) {
    final date = DateTime(start.year, start.month, start.day + i);
    final didWorkout = worked.contains(date);
    // 운동한 날엔 예정 표시를 하지 않는다(위 주석의 이유).
    final hasPlanned = !didWorkout && planned.contains(date);

    if (didWorkout) workoutCount++;
    if (hasPlanned) plannedCount++;

    days.add(WeeklyDay(
      date: date,
      workedOut: didWorkout,
      hasPlannedPt: hasPlanned,
      isToday: date == today,
      isPast: date.isBefore(today),
    ));
  }

  return WeeklyActivity(
    days: List<WeeklyDay>.unmodifiable(days),
    workoutCount: workoutCount,
    plannedCount: plannedCount,
  );
}
