/// 회원 홈 최상단(히어로) 분기 — **순수 도메인 로직** (Flutter 의존 0).
///
/// 회원 홈 정보 우선순위 ① "다음 PT 또는 오늘의 운동"(계획서 §3.3)의 판정부.
///
/// **왜 도메인인가:** 같은 예약이라도 시간이 흐르면 표시가 바뀐다(오늘 예정 → 진행 중
///   → 수업 끝남). 위젯 안에서 `DateTime.now()` 로 분기하면 자정·수업 시작 정각 같은
///   경계를 테스트할 수 없다. 트레이너 홈이 쓰는 [buildTodaySchedule] 을 그대로 재사용해
///   **두 역할의 "진행 중" 판정 기준을 하나로** 유지한다(수업 길이 상수까지 공유).
///
/// **회원 관점에서 트레이너와 다른 점:**
///   트레이너에게 "시간이 지났는데 미기록"은 처리할 일이지만, 회원에겐 할 일이 아니라
///   기다림이다. 그래서 같은 상태를 [MemberFocusKind.todayFinished] 로 부르고 행동을
///   요구하지 않는다. 반대로 회원에게만 있는 상태가 [MemberFocusKind.none] — 잡힌 예약이
///   아예 없는 경우로, 이때는 "예약 신청"이 그 화면의 대표 행동이 된다.
library;

import 'models/session.dart';
import 'today_schedule.dart';

/// 회원 홈 히어로가 말할 상황.
enum MemberFocusKind {
  /// 지금 수업 중.
  inProgress,

  /// 오늘 아직 시작 전인 수업이 남았다.
  todayUpcoming,

  /// 오늘 신청했고 트레이너 승인을 기다리는 중.
  awaitingApproval,

  /// 오늘 수업이 기록까지 끝났다.
  todayDone,

  /// 오늘 수업 시간은 지났지만 아직 기록이 안 올라왔다.
  todayFinished,

  /// 오늘은 수업이 없고, 앞으로 잡힌 예약이 있다.
  future,

  /// 잡힌 예약이 하나도 없다.
  none,
}

/// 히어로가 그릴 내용 한 묶음.
class MemberHomeFocus {
  const MemberHomeFocus({
    required this.kind,
    this.at,
    this.sessionId,
    this.upNextAt,
  });

  final MemberFocusKind kind;

  /// 주인공 수업의 시각. [MemberFocusKind.none] 이면 null.
  final DateTime? at;

  /// 주인공 수업 id — "수업 기록 보기"로 되짚을 때 쓴다.
  final String? sessionId;

  /// 오늘 일정이 끝난 뒤 부제로 붙일 **다음** 수업 시각.
  /// 주인공이 이미 미래 수업([MemberFocusKind.future])이면 중복이므로 null.
  final DateTime? upNextAt;

  /// 화면에 하나뿐인 볼트 라임 강조를 이 히어로가 가져가는가(계획서 §4.1).
  ///
  /// - 오늘 수업이 진행 중이거나 아직 남았으면: 그 수업이 오늘의 주인공이다.
  /// - 잡힌 예약이 아예 없으면: "예약 신청"이 이 화면의 대표 행동이다.
  ///
  /// 그 밖의 경우(오늘 수업을 이미 마쳤거나, 다음 수업이 며칠 뒤거나, 승인 대기)에는
  /// 히어로가 알려 줄 뿐 시킬 일이 없다 → 강조를 "셀프 운동 기록"에 양보한다.
  bool get takesVoltAccent =>
      kind == MemberFocusKind.inProgress ||
      kind == MemberFocusKind.todayUpcoming ||
      kind == MemberFocusKind.none;
}

/// 오늘 수업 목록 + 다음 예약 + 현재 시각 → 히어로 상태.
///
/// [todaySessions] : 오늘(자정~자정) 안에 잡힌 모든 수업. 상태 무관하게 넘긴다 —
///                   취소/노쇼 판정은 [buildTodaySchedule] 이 한다.
/// [nextSession]   : 지금 이후 가장 가까운 예정 수업(오늘 것일 수도 있다).
/// [now]           : 기준 시각(테스트 주입점).
///
/// **판정 순서** (앞의 것이 뒤의 것을 이긴다):
///   1. 오늘 진행 중 / 오늘 남은 예정 / 오늘 승인 대기  ← [buildTodaySchedule] 의 focus
///   2. 오늘 이미 지나간 수업 중 가장 늦은 것(기록 완료 / 기록 대기)
///   3. 앞으로 잡힌 예약
///   4. 없음
///
/// 취소·노쇼는 주인공으로 세우지 않는다 — 이미 끝난 일을 홈 맨 위에 며칠씩 붙잡아 두면
/// 정작 다음 수업이 안 보인다(취소 이력은 일정 탭의 달력에서 확인).
MemberHomeFocus buildMemberHomeFocus({
  required List<Session> todaySessions,
  required Session? nextSession,
  required DateTime now,
}) {
  final schedule = buildTodaySchedule(
    inputs: todaySessions
        .map((s) => TodaySlotInput(
              sessionId: s.id,
              scheduledAt: s.scheduledAt,
              status: s.status,
            ))
        .toList(growable: false),
    now: now,
  );

  // 1. 오늘 아직 남은 일 — 트레이너 홈과 같은 우선순위(진행 중 > 예정 > 승인 대기).
  final focus = schedule.focus;
  if (focus != null) {
    return MemberHomeFocus(
      kind: switch (focus.state) {
        TodaySessionState.inProgress => MemberFocusKind.inProgress,
        TodaySessionState.pending => MemberFocusKind.awaitingApproval,
        _ => MemberFocusKind.todayUpcoming,
      },
      at: focus.scheduledAt,
      sessionId: focus.sessionId,
    );
  }

  // 2. 오늘 이미 지나간 수업 — 여러 건이면 가장 늦게 끝난 것이 "오늘"을 대표한다.
  TodaySlot? lastFinished;
  for (final slot in schedule.slots) {
    final isFinished = slot.state == TodaySessionState.done ||
        slot.state == TodaySessionState.awaitingRecord;
    if (!isFinished) continue;
    if (lastFinished == null ||
        slot.scheduledAt.isAfter(lastFinished.scheduledAt)) {
      lastFinished = slot;
    }
  }
  if (lastFinished != null) {
    return MemberHomeFocus(
      kind: lastFinished.state == TodaySessionState.done
          ? MemberFocusKind.todayDone
          : MemberFocusKind.todayFinished,
      at: lastFinished.scheduledAt,
      sessionId: lastFinished.sessionId,
      // 오늘 운동은 끝났으니, 그다음으로 회원이 궁금한 건 "언제 또 오나".
      upNextAt: nextSession?.scheduledAt,
    );
  }

  // 3. 오늘은 아무 일도 없고 앞으로 예약이 있다.
  if (nextSession != null) {
    return MemberHomeFocus(
      kind: MemberFocusKind.future,
      at: nextSession.scheduledAt,
      sessionId: nextSession.id,
    );
  }

  // 4. 잡힌 예약이 없다.
  return const MemberHomeFocus(kind: MemberFocusKind.none);
}
