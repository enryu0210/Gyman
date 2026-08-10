/// "오늘의 수업" 타임라인 계산 — **순수 도메인 로직** (Flutter/Riverpod 의존 0).
///
/// **왜 도메인으로 빼는가:**
///   트레이너 홈의 최상단(다음 수업 카드)과 타임라인은 *시간이 흐르면 표시가 바뀌는*
///   화면이다(예약 → 진행 중 → 기록 대기). 시각 의존 분기를 위젯 안에 두면 테스트가
///   불가능하고, 자정·수업 직후처럼 경계에서 조용히 틀어진다. `now` 를 인자로 받는
///   순수 함수로 고정해 단위 테스트로 못 박는다(CLAUDE.md 도메인 규칙).
///
/// 계획 출처: docs/ui_renewal_phase1_plan.md §3.2, §4.2
/// ("오늘 수업은 시간이 흐르면서 다음 수업 / 진행 중 / 기록 완료로 바뀌어야 한다").
library;

import 'models/enums.dart';

/// 오늘 일정 한 칸이 지금 이 순간 어떤 상태인지.
///
/// DB `session_status` 와 다른 개념이다 — DB 상태는 "예약(scheduled)" 하나지만,
/// 화면에서는 현재 시각에 따라 예정/진행 중/기록 대기로 갈린다.
enum TodaySessionState {
  /// 회원이 신청했고 트레이너 승인이 남음(DB requested).
  pending,

  /// 아직 시작 전인 예약.
  upcoming,

  /// 시작 시각을 지났고 아직 수업 시간 안(= 지금 하고 있을 시간).
  inProgress,

  /// 수업 시간이 끝났는데 기록이 안 됨 — 트레이너가 처리해야 할 일.
  awaitingRecord,

  /// 기록 완료(DB done).
  done,

  /// 노쇼.
  missed,

  /// 취소/지각취소.
  canceled,
}

/// 계산 입력 한 칸 — 화면 표시용 필드(회원명 등)는 담지 않는다.
///
/// 도메인이 리포지토리 행 타입(`TrainerBookingRow`)을 알면 그 타입 없이는 테스트를
/// 못 짜므로, 판정에 꼭 필요한 값만 받는다. 화면은 [TodaySlot.sessionId] 로 되짚는다.
class TodaySlotInput {
  const TodaySlotInput({
    required this.sessionId,
    required this.scheduledAt,
    required this.status,
  });

  final String sessionId;
  final DateTime scheduledAt;
  final SessionStatus status;
}

/// 상태 판정이 끝난 한 칸.
class TodaySlot {
  const TodaySlot({
    required this.sessionId,
    required this.scheduledAt,
    required this.status,
    required this.state,
  });

  final String sessionId;
  final DateTime scheduledAt;
  final SessionStatus status;
  final TodaySessionState state;

  /// 지금 바로 "기록하기"로 이어질 수 있는 칸인지.
  /// 진행 중이거나 이미 끝났는데 기록이 없는 경우 — 홈의 기록 동선 진입점.
  bool get canRecordNow =>
      state == TodaySessionState.inProgress ||
      state == TodaySessionState.awaitingRecord;
}

/// 오늘 하루치 계산 결과.
class TodaySchedule {
  const TodaySchedule({
    required this.slots,
    required this.focus,
    required this.awaitingRecordCount,
    required this.doneCount,
    required this.upcomingCount,
  });

  /// 시간 오름차순 정렬된 오늘 일정 전체.
  final List<TodaySlot> slots;

  /// 홈 최상단 카드에 올릴 한 건. 오늘 더 볼 수업이 없으면 null.
  final TodaySlot? focus;

  /// 수업 시간이 끝났는데 기록이 안 된 건수 — "처리할 일" 에 노출.
  final int awaitingRecordCount;

  /// 오늘 기록까지 끝난 건수.
  final int doneCount;

  /// 아직 시작 전인 예약 건수(승인 대기 제외).
  final int upcomingCount;

  bool get isEmpty => slots.isEmpty;

  static const empty = TodaySchedule(
    slots: [],
    focus: null,
    awaitingRecordCount: 0,
    doneCount: 0,
    upcomingCount: 0,
  );
}

/// 수업 1회의 기본 길이 — "진행 중" 구간을 판정하는 데만 쓴다.
///
/// 실제 수업 길이는 계약/센터마다 다르지만 DB에 길이 컬럼이 없다(1차 개편은 스키마
/// 변경 없음). 50분은 PT 1회의 통상값이며, 여기서 조금 틀려도 결과는 "진행 중"이
/// "기록 대기"로 바뀌는 정도라 안전하다.
const kDefaultSessionDuration = Duration(minutes: 50);

/// 오늘 일정 목록 + 현재 시각 → 표시 상태와 대표 1건을 계산한다.
///
/// **focus 선택 순서 (계획서 §3.2 정보 우선순위 = "다음 수업"이 1번):**
///   1. 지금 진행 중인 수업
///   2. 아직 시작 전인 가장 이른 예약  ← "다음 수업"
///   3. 아직 승인 안 한 가장 이른 신청
///   4. 없으면 null (홈은 "오늘 예정된 수업이 없어요" 빈 상태로 전환)
///
/// 기록 대기(시간이 지났는데 미기록)는 일부러 focus 로 올리지 않는다 — 올리면 저녁에
/// 홈을 열 때 지난 수업이 "다음 수업" 자리를 계속 차지한다. 대신 [awaitingRecordCount]
/// 로 "처리할 일"에 세워 놓치지 않게 한다.
TodaySchedule buildTodaySchedule({
  required List<TodaySlotInput> inputs,
  required DateTime now,
  Duration sessionDuration = kDefaultSessionDuration,
}) {
  if (inputs.isEmpty) return TodaySchedule.empty;

  final slots = inputs
      .map((i) => TodaySlot(
            sessionId: i.sessionId,
            scheduledAt: i.scheduledAt,
            status: i.status,
            state: _resolveState(
              status: i.status,
              scheduledAt: i.scheduledAt,
              now: now,
              sessionDuration: sessionDuration,
            ),
          ))
      .toList()
    ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

  TodaySlot? firstWhereStateOrNull(TodaySessionState state) {
    for (final s in slots) {
      if (s.state == state) return s;
    }
    return null;
  }

  final focus = firstWhereStateOrNull(TodaySessionState.inProgress) ??
      firstWhereStateOrNull(TodaySessionState.upcoming) ??
      firstWhereStateOrNull(TodaySessionState.pending);

  var awaiting = 0;
  var done = 0;
  var upcoming = 0;
  for (final s in slots) {
    switch (s.state) {
      case TodaySessionState.awaitingRecord:
        awaiting++;
      case TodaySessionState.done:
        done++;
      case TodaySessionState.upcoming:
        upcoming++;
      case TodaySessionState.pending:
      case TodaySessionState.inProgress:
      case TodaySessionState.missed:
      case TodaySessionState.canceled:
        break;
    }
  }

  return TodaySchedule(
    slots: slots,
    focus: focus,
    awaitingRecordCount: awaiting,
    doneCount: done,
    upcomingCount: upcoming,
  );
}

/// DB 상태 + 현재 시각 → 화면 상태.
///
/// 예약(scheduled)만 시각에 따라 갈리고, 나머지는 이미 확정된 결과라 그대로 매핑된다.
TodaySessionState _resolveState({
  required SessionStatus status,
  required DateTime scheduledAt,
  required DateTime now,
  required Duration sessionDuration,
}) {
  switch (status) {
    case SessionStatus.requested:
      return TodaySessionState.pending;
    case SessionStatus.done:
      return TodaySessionState.done;
    case SessionStatus.noShow:
      return TodaySessionState.missed;
    case SessionStatus.canceled:
    case SessionStatus.lateCancel:
      return TodaySessionState.canceled;
    case SessionStatus.scheduled:
      final endsAt = scheduledAt.add(sessionDuration);
      // 시작 시각 정각은 "진행 중" 쪽에 포함(!isBefore) — 14:00 수업의 14:00 은
      // 아직 안 시작한 게 아니라 막 시작한 것으로 읽히는 게 자연스럽다.
      if (now.isBefore(scheduledAt)) return TodaySessionState.upcoming;
      if (now.isBefore(endsAt)) return TodaySessionState.inProgress;
      return TodaySessionState.awaitingRecord;
  }
}
