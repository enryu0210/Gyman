import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/domain/member_home_focus.dart';
import 'package:gyman/domain/models/enums.dart';
import 'package:gyman/domain/models/session.dart';

/// 회원 홈 히어로 분기 단위 테스트.
///
/// **왜 핵심:** 회원이 앱을 열자마자 보는 한 칸이다. 시간이 흐르며 예정 → 진행 중 →
/// 끝남으로 바뀌어야 하고(경계 포함), 화면에 하나뿐인 볼트 강조를 히어로가 가져갈지
/// 격자의 "셀프 운동 기록"에 넘길지도 이 결과로 갈린다(계획서 §4.1).
void main() {
  // 기준 시각 고정 — 2026-08-13(목) 13:00.
  final now = DateTime(2026, 8, 13, 13);

  Session session(
    String id,
    DateTime at, {
    SessionStatus status = SessionStatus.scheduled,
  }) {
    return Session(
      id: id,
      contractId: 'contract-1',
      scheduledAt: at,
      status: status,
      createdAt: DateTime(2026, 8, 1),
    );
  }

  DateTime today(int hour, [int minute = 0]) =>
      DateTime(2026, 8, 13, hour, minute);

  group('오늘 남은 수업이 주인공', () {
    test('시작 전이면 todayUpcoming', () {
      final f = buildMemberHomeFocus(
        todaySessions: [session('s1', today(14))],
        nextSession: session('s1', today(14)),
        now: now,
      );
      expect(f.kind, MemberFocusKind.todayUpcoming);
      expect(f.at, today(14));
      expect(f.sessionId, 's1');
      expect(f.takesVoltAccent, isTrue);
    });

    test('시작 정각부터 수업 길이 안이면 inProgress', () {
      final f = buildMemberHomeFocus(
        todaySessions: [session('s1', today(13))], // 정각 = 막 시작
        nextSession: null,
        now: now,
      );
      expect(f.kind, MemberFocusKind.inProgress);
      expect(f.takesVoltAccent, isTrue);
    });

    test('진행 중 수업이 뒤의 예정보다 우선', () {
      final f = buildMemberHomeFocus(
        todaySessions: [session('later', today(19)), session('nowRunning', today(12, 30))],
        nextSession: session('later', today(19)),
        now: now,
      );
      expect(f.kind, MemberFocusKind.inProgress);
      expect(f.sessionId, 'nowRunning');
    });

    test('승인 대기 신청만 있으면 awaitingApproval — 강조는 넘긴다', () {
      final f = buildMemberHomeFocus(
        todaySessions: [
          session('req', today(18), status: SessionStatus.requested),
        ],
        nextSession: null,
        now: now,
      );
      expect(f.kind, MemberFocusKind.awaitingApproval);
      expect(f.at, today(18));
      // 승인은 트레이너가 하는 일 — 회원에게 시킬 행동이 없다.
      expect(f.takesVoltAccent, isFalse);
    });

    test('예정 수업이 승인 대기보다 우선', () {
      final f = buildMemberHomeFocus(
        todaySessions: [
          session('req', today(15), status: SessionStatus.requested),
          session('ok', today(17)),
        ],
        nextSession: session('ok', today(17)),
        now: now,
      );
      expect(f.kind, MemberFocusKind.todayUpcoming);
      expect(f.sessionId, 'ok');
    });
  });

  group('오늘 수업이 끝난 뒤', () {
    test('기록까지 됐으면 todayDone + 다음 수업을 부제로', () {
      final next = session('s2', DateTime(2026, 8, 15, 14));
      final f = buildMemberHomeFocus(
        todaySessions: [session('s1', today(9), status: SessionStatus.done)],
        nextSession: next,
        now: now,
      );
      expect(f.kind, MemberFocusKind.todayDone);
      expect(f.sessionId, 's1');
      expect(f.upNextAt, DateTime(2026, 8, 15, 14));
      // 오늘 할 운동은 끝났다 → 강조는 셀프 운동 기록에 양보.
      expect(f.takesVoltAccent, isFalse);
    });

    test('수업 시간은 지났는데 기록이 없으면 todayFinished', () {
      final f = buildMemberHomeFocus(
        // 09:00 수업은 50분 뒤 끝났고 아직 scheduled = 기록 대기.
        todaySessions: [session('s1', today(9))],
        nextSession: null,
        now: now,
      );
      expect(f.kind, MemberFocusKind.todayFinished);
      expect(f.takesVoltAccent, isFalse);
    });

    test('오늘 여러 건이면 가장 늦게 끝난 수업이 오늘을 대표한다', () {
      final f = buildMemberHomeFocus(
        todaySessions: [
          session('morning', today(7), status: SessionStatus.done),
          session('noon', today(11), status: SessionStatus.done),
        ],
        nextSession: null,
        now: now,
      );
      expect(f.sessionId, 'noon');
    });
  });

  group('오늘 일정이 없을 때', () {
    test('앞으로 예약이 있으면 future', () {
      final f = buildMemberHomeFocus(
        todaySessions: const [],
        nextSession: session('s9', DateTime(2026, 8, 17, 20)),
        now: now,
      );
      expect(f.kind, MemberFocusKind.future);
      expect(f.at, DateTime(2026, 8, 17, 20));
      // 부제로 또 같은 수업을 반복하지 않는다.
      expect(f.upNextAt, isNull);
      expect(f.takesVoltAccent, isFalse);
    });

    test('예약이 하나도 없으면 none — 이때는 예약 신청이 대표 행동', () {
      final f = buildMemberHomeFocus(
        todaySessions: const [],
        nextSession: null,
        now: now,
      );
      expect(f.kind, MemberFocusKind.none);
      expect(f.at, isNull);
      expect(f.takesVoltAccent, isTrue);
    });

    test('오늘 취소·노쇼만 있으면 주인공으로 세우지 않는다', () {
      final f = buildMemberHomeFocus(
        todaySessions: [
          session('c', today(10), status: SessionStatus.canceled),
          session('n', today(11), status: SessionStatus.noShow),
        ],
        nextSession: session('s9', DateTime(2026, 8, 18, 14)),
        now: now,
      );
      expect(f.kind, MemberFocusKind.future);
      expect(f.sessionId, 's9');
    });
  });
}
