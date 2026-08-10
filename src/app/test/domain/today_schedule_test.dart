import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/domain/models/enums.dart';
import 'package:gyman/domain/today_schedule.dart';

/// 오늘 일정 타임라인 계산 단위 테스트.
///
/// **왜 핵심:** 트레이너 홈 최상단이 이 결과 하나로 결정된다. 경계(시작 정각,
/// 수업 종료 직후)에서 잘못 판정하면 "다음 수업" 자리에 엉뚱한 수업이 뜨고,
/// 기록 대기가 조용히 사라져 수업 기록을 통째로 놓친다.
void main() {
  // 오늘 = 2026-08-10. 기준 시각은 각 테스트에서 바꿔가며 확인.
  TodaySlotInput slot(
    String id,
    int hour,
    SessionStatus status, {
    int minute = 0,
  }) =>
      TodaySlotInput(
        sessionId: id,
        scheduledAt: DateTime(2026, 8, 10, hour, minute),
        status: status,
      );

  TodaySlot? slotById(TodaySchedule s, String id) {
    for (final x in s.slots) {
      if (x.sessionId == id) return x;
    }
    return null;
  }

  group('상태 판정', () {
    test('시작 전 예약은 upcoming', () {
      final result = buildTodaySchedule(
        inputs: [slot('s1', 14, SessionStatus.scheduled)],
        now: DateTime(2026, 8, 10, 13, 28),
      );
      expect(slotById(result, 's1')!.state, TodaySessionState.upcoming);
    });

    test('시작 정각은 진행 중으로 본다 (경계 포함)', () {
      final result = buildTodaySchedule(
        inputs: [slot('s1', 14, SessionStatus.scheduled)],
        now: DateTime(2026, 8, 10, 14),
      );
      expect(slotById(result, 's1')!.state, TodaySessionState.inProgress);
    });

    test('수업 시간 안이면 진행 중', () {
      final result = buildTodaySchedule(
        inputs: [slot('s1', 14, SessionStatus.scheduled)],
        now: DateTime(2026, 8, 10, 14, 49),
      );
      expect(slotById(result, 's1')!.state, TodaySessionState.inProgress);
    });

    test('수업 시간이 끝났는데 미기록이면 기록 대기', () {
      final result = buildTodaySchedule(
        inputs: [slot('s1', 14, SessionStatus.scheduled)],
        now: DateTime(2026, 8, 10, 14, 50),
      );
      expect(slotById(result, 's1')!.state, TodaySessionState.awaitingRecord);
      expect(result.awaitingRecordCount, 1);
    });

    test('DB 확정 상태는 시각과 무관하게 그대로 매핑', () {
      final result = buildTodaySchedule(
        inputs: [
          slot('done', 9, SessionStatus.done),
          slot('noshow', 10, SessionStatus.noShow),
          slot('cancel', 11, SessionStatus.canceled),
          slot('late', 12, SessionStatus.lateCancel),
          slot('req', 13, SessionStatus.requested),
        ],
        now: DateTime(2026, 8, 10, 23, 59),
      );
      expect(slotById(result, 'done')!.state, TodaySessionState.done);
      expect(slotById(result, 'noshow')!.state, TodaySessionState.missed);
      expect(slotById(result, 'cancel')!.state, TodaySessionState.canceled);
      expect(slotById(result, 'late')!.state, TodaySessionState.canceled);
      expect(slotById(result, 'req')!.state, TodaySessionState.pending);
    });

    test('수업 길이를 바꾸면 진행 중 구간도 따라 늘어난다', () {
      final result = buildTodaySchedule(
        inputs: [slot('s1', 14, SessionStatus.scheduled)],
        now: DateTime(2026, 8, 10, 15, 10),
        sessionDuration: const Duration(minutes: 90),
      );
      expect(slotById(result, 's1')!.state, TodaySessionState.inProgress);
    });
  });

  group('focus 선택', () {
    test('진행 중 수업이 있으면 그것이 최우선', () {
      final result = buildTodaySchedule(
        inputs: [
          slot('now', 14, SessionStatus.scheduled),
          slot('later', 16, SessionStatus.scheduled),
        ],
        now: DateTime(2026, 8, 10, 14, 20),
      );
      expect(result.focus!.sessionId, 'now');
      expect(result.focus!.state, TodaySessionState.inProgress);
    });

    test('진행 중이 없으면 가장 이른 다음 예약', () {
      final result = buildTodaySchedule(
        inputs: [
          slot('late', 19, SessionStatus.scheduled),
          slot('soon', 16, SessionStatus.scheduled),
        ],
        now: DateTime(2026, 8, 10, 15),
      );
      expect(result.focus!.sessionId, 'soon');
    });

    test('예정 수업이 없으면 승인 대기 신청이 focus', () {
      final result = buildTodaySchedule(
        inputs: [
          slot('done', 9, SessionStatus.done),
          slot('req', 20, SessionStatus.requested),
        ],
        now: DateTime(2026, 8, 10, 15),
      );
      expect(result.focus!.sessionId, 'req');
      expect(result.focus!.state, TodaySessionState.pending);
    });

    test('기록 대기는 focus 로 올리지 않는다 — 다음 수업 자리를 뺏지 않게', () {
      final result = buildTodaySchedule(
        inputs: [
          slot('missedRecord', 10, SessionStatus.scheduled),
          slot('next', 19, SessionStatus.scheduled),
        ],
        now: DateTime(2026, 8, 10, 15),
      );
      expect(result.focus!.sessionId, 'next');
      // 대신 처리할 일 카운트로 남아 놓치지 않는다.
      expect(result.awaitingRecordCount, 1);
    });

    test('남은 수업이 없으면 focus 는 null', () {
      final result = buildTodaySchedule(
        inputs: [
          slot('a', 9, SessionStatus.done),
          slot('b', 11, SessionStatus.canceled),
        ],
        now: DateTime(2026, 8, 10, 22),
      );
      expect(result.focus, isNull);
      expect(result.doneCount, 1);
    });

    test('오늘 일정이 아예 없으면 빈 결과', () {
      final result = buildTodaySchedule(
        inputs: const [],
        now: DateTime(2026, 8, 10, 9),
      );
      expect(result.isEmpty, isTrue);
      expect(result.focus, isNull);
    });
  });

  group('정렬과 집계', () {
    test('입력 순서와 무관하게 시간 오름차순으로 정렬된다', () {
      final result = buildTodaySchedule(
        inputs: [
          slot('c', 19, SessionStatus.scheduled),
          slot('a', 9, SessionStatus.done),
          slot('b', 14, SessionStatus.scheduled),
        ],
        now: DateTime(2026, 8, 10, 12),
      );
      expect(
        result.slots.map((s) => s.sessionId).toList(),
        ['a', 'b', 'c'],
      );
    });

    test('상태별 건수를 각각 집계한다', () {
      final result = buildTodaySchedule(
        inputs: [
          slot('done1', 8, SessionStatus.done),
          slot('done2', 9, SessionStatus.done),
          slot('await', 10, SessionStatus.scheduled),
          slot('next1', 18, SessionStatus.scheduled),
          slot('next2', 20, SessionStatus.scheduled),
          slot('cancel', 11, SessionStatus.canceled),
        ],
        now: DateTime(2026, 8, 10, 15),
      );
      expect(result.doneCount, 2);
      expect(result.awaitingRecordCount, 1);
      expect(result.upcomingCount, 2);
    });

    test('canRecordNow 는 진행 중·기록 대기에서만 참', () {
      final result = buildTodaySchedule(
        inputs: [
          slot('await', 10, SessionStatus.scheduled),
          slot('running', 15, SessionStatus.scheduled, minute: 30),
          slot('next', 18, SessionStatus.scheduled),
          slot('done', 8, SessionStatus.done),
        ],
        now: DateTime(2026, 8, 10, 15, 40),
      );
      expect(slotById(result, 'await')!.canRecordNow, isTrue);
      expect(slotById(result, 'running')!.canRecordNow, isTrue);
      expect(slotById(result, 'next')!.canRecordNow, isFalse);
      expect(slotById(result, 'done')!.canRecordNow, isFalse);
    });
  });
}
