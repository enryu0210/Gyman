/// 트레이너 홈 "다음 수업 / 오늘의 타임라인" providers (UI 1차 개편 단계 B).
///
/// **새 조회를 추가하지 않는다:** 오늘 일정은 예약 화면이 이미 쓰는
/// [trainerBookingsProvider]`(TrainerBookingRange.today)` 를 그대로 재사용한다.
/// 같은 provider 를 쓰면 수업 저장·취소·승인 때 [SaveSessionController] 가 도는
/// 기존 invalidate 경로에 홈도 자동으로 얹힌다 — 홈만 조용히 낡는 사고를 구조적으로
/// 막는다. (계획서 §7 "기존 예약 데이터 재사용 가능 여부를 먼저 확인")
///
/// 상태 판정 자체는 순수 도메인 [buildTodaySchedule] 담당 — 여기서는 회원 표시정보
/// (이름·id)를 다시 붙여 주는 결합만 한다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/util/clock_providers.dart';
import '../../../domain/today_schedule.dart';
import '../session_log/session_providers.dart';
import '../session_log/session_repository.dart';

/// 타임라인 한 줄 — 도메인 판정 결과 + 화면에 필요한 회원 정보.
class TrainerTodayItem {
  const TrainerTodayItem({required this.slot, required this.row});

  final TodaySlot slot;
  final TrainerBookingRow row;

  String get memberId => row.memberId;
  String get memberName => row.memberName;
  DateTime get scheduledAt => slot.scheduledAt;
  TodaySessionState get state => slot.state;

  /// 예약 메모(회원 요청사항 등) — 없으면 null.
  String? get memo {
    final m = row.session.statusMemo;
    return (m == null || m.trim().isEmpty) ? null : m.trim();
  }
}

/// 홈이 필요로 하는 오늘 하루치 묶음.
class TrainerTodayView {
  const TrainerTodayView({
    required this.items,
    required this.focus,
    required this.awaitingRecordCount,
    required this.doneCount,
    required this.upcomingCount,
  });

  /// 시간 오름차순 타임라인 전체.
  final List<TrainerTodayItem> items;

  /// 홈 최상단 카드에 올릴 한 건(진행 중 → 다음 예약 → 승인 대기 순). 없으면 null.
  final TrainerTodayItem? focus;

  final int awaitingRecordCount;
  final int doneCount;
  final int upcomingCount;

  bool get isEmpty => items.isEmpty;

  /// 지금 바로 기록으로 이어갈 수 있는 수업들(진행 중 · 기록 대기).
  /// 가운데 "기록하기" 버튼이 무엇을 먼저 제안할지 정할 때 쓴다.
  List<TrainerTodayItem> get recordCandidates =>
      items.where((i) => i.slot.canRecordNow).toList(growable: false);

  static const empty = TrainerTodayView(
    items: [],
    focus: null,
    awaitingRecordCount: 0,
    doneCount: 0,
    upcomingCount: 0,
  );
}

/// 오늘 일정 + 현재 시각으로 계산된 홈용 뷰.
///
/// [nowProvider] 를 watch 하므로 30초마다 다시 계산된다 — 앱을 켜둔 채 수업 시간이
/// 지나면 표시가 알아서 "진행 중" → "기록 대기" 로 넘어간다.
final trainerTodayViewProvider =
    Provider<AsyncValue<TrainerTodayView>>((ref) {
  final now = ref.watch(nowProvider);
  final bookings =
      ref.watch(trainerBookingsProvider(TrainerBookingRange.today));

  return bookings.whenData((rows) => buildTrainerTodayView(rows, now));
});

/// 예약 행 목록 + 현재 시각 → 홈 뷰. (provider 밖으로 빼 두어 재사용/추적이 쉽게)
TrainerTodayView buildTrainerTodayView(
  List<TrainerBookingRow> rows,
  DateTime now,
) {
  if (rows.isEmpty) return TrainerTodayView.empty;

  final byId = {for (final r in rows) r.session.id: r};
  final schedule = buildTodaySchedule(
    inputs: rows
        .map((r) => TodaySlotInput(
              sessionId: r.session.id,
              scheduledAt: r.session.scheduledAt,
              status: r.session.status,
            ))
        .toList(growable: false),
    now: now,
  );

  TrainerTodayItem? toItem(TodaySlot? slot) {
    if (slot == null) return null;
    final row = byId[slot.sessionId];
    if (row == null) return null; // 이론상 불가 — 방어적으로 건너뜀.
    return TrainerTodayItem(slot: slot, row: row);
  }

  final items = schedule.slots
      .map(toItem)
      .whereType<TrainerTodayItem>()
      .toList(growable: false);

  return TrainerTodayView(
    items: items,
    focus: toItem(schedule.focus),
    awaitingRecordCount: schedule.awaitingRecordCount,
    doneCount: schedule.doneCount,
    upcomingCount: schedule.upcomingCount,
  );
}
