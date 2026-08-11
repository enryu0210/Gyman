// 회원 홈의 **정보 우선순위** 회귀 테스트 (UI 1차 개편 §3.3).
//
// **왜 이 테스트가 있나:** 개편의 핵심 결정은 "잔여 횟수보다 운동 경험을 먼저"다.
// 카드 하나를 옮기다 순서가 되돌아가도 analyze/test 는 통과하므로, 화면에 그려진
// y 좌표로 순서를 못 박는다. 함께 고정하는 것:
//   - 상황에 따라 히어로가 바뀐다(오늘 수업 / 완료 / 예약 없음)
//   - 화면당 볼트 강조 1개(§4.1) — 히어로가 가져가면 격자 타일은 강조를 뺀다
//   - 보여 줄 게 없는 카드(안 읽은 소식·인바디)는 아예 그리지 않는다

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/core/theme/app_theme.dart';
import 'package:gyman/core/util/date_format_ko.dart';
import 'package:gyman/domain/models/body_measurement.dart';
import 'package:gyman/domain/models/enums.dart';
import 'package:gyman/domain/models/session.dart';
import 'package:gyman/domain/pt_reminder.dart';
import 'package:gyman/features/member/attendance/member_attendance_providers.dart';
import 'package:gyman/features/member/attendance/member_attendance_repository.dart';
import 'package:gyman/features/member/chat/member_chat_providers.dart';
import 'package:gyman/features/member/home/member_home_providers.dart';
import 'package:gyman/features/member/home/member_home_repository.dart';
import 'package:gyman/features/member/home/member_home_screen.dart';
import 'package:gyman/features/member/notices/member_notices_providers.dart';
import 'package:gyman/features/member/notices/member_notices_repository.dart';
import 'package:gyman/features/member/notifications/pt_reminder_providers.dart';

/// PT 알림 재동기화는 홈이 initState 에서 fire&forget 으로 부른다. 실제 컨트롤러는
/// SharedPreferences·알림 플러그인·Supabase 를 타므로 테스트에선 통째로 무력화한다.
class _SilentReminderController extends PtReminderLeadController {
  @override
  Future<PtReminderLead> build() async => PtReminderLead.off;

  @override
  Future<void> resync() async {}
}

Session _session(
  String id,
  DateTime at, {
  SessionStatus status = SessionStatus.scheduled,
}) {
  return Session(
    id: id,
    contractId: 'contract-1',
    scheduledAt: at,
    status: status,
    createdAt: DateTime(2026, 1, 1),
  );
}

MemberContractStatus _contract({int remaining = 8, int total = 10}) {
  return MemberContractStatus(
    contractId: 'contract-1',
    totalSessions: total,
    usedSessions: total - remaining,
    remainingSessions: remaining,
    startDate: DateTime(2026, 1, 1),
  );
}

MemberNotice _notice({required bool read, String content = '이번 주 수업 안내입니다.'}) {
  return MemberNotice(
    id: 'notice-1',
    triggerType: 'pre_session',
    content: content,
    sentAt: DateTime(2026, 8, 10),
    readAt: read ? DateTime(2026, 8, 10, 12) : null,
  );
}

/// 회원 홈을 띄운다. Supabase 를 타는 provider 는 전부 override.
Future<void> _pumpHome(
  WidgetTester tester, {
  Session? nextSession,
  List<Session> todaySessions = const [],
  List<MemberContractStatus> contracts = const [],
  List<BodyMeasurement> measurements = const [],
  List<MemberNotice> notices = const [],
  int unreadChats = 0,
  AttendanceData attendance = AttendanceData.empty,
}) async {
  // 기본 테스트 화면(800×600)에선 아래쪽 섹션이 아예 빌드되지 않아 순서를 못 잰다
  // (ListView 는 보이는 것만 만든다) → 홈 전체가 한 화면에 들어가는 크기로 늘린다.
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        memberHomeSummaryProvider.overrideWith((ref) async => MemberHomeSummary(
              memberName: '홍길동',
              nextSession: nextSession,
              todaySessions: todaySessions,
              contracts: contracts,
              recentMeasurements: measurements,
            )),
        attendanceDataProvider.overrideWith((ref) async => attendance),
        myNoticesProvider.overrideWith((ref) async => notices),
        memberUnreadTotalProvider.overrideWith((ref) async => unreadChats),
        ptReminderLeadProvider.overrideWith(_SilentReminderController.new),
      ],
      child: const MaterialApp(home: MemberHomeScreen()),
    ),
  );
  // FutureProvider 해소 + 첫 프레임.
  await tester.pumpAndSettle();
}

/// 라벨을 담은 위젯의 화면상 y 좌표(위쪽이 작다).
double _y(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

void main() {
  // 화면은 내부에서 `DateTime.now()` 로 분기하므로 테스트가 시각을 주입할 수 없다.
  // 그래서 고정 시각("오후 11시") 대신 **지금으로부터의 상대 시각**을 쓴다 — 밤늦게
  // 돌려도 "아직 시작 전"이 유지돼 결과가 흔들리지 않는다.
  final now = DateTime.now();
  final upcomingAt = now.add(const Duration(minutes: 90));
  DateTime todayAt(int hour) => DateTime(now.year, now.month, now.day, hour);

  group('정보 우선순위 (§3.3)', () {
    testWidgets('운동 경험(주간 현황)이 잔여 횟수보다 위에 온다', (tester) async {
      await _pumpHome(tester, contracts: [_contract()]);

      expect(_y(tester, '잔여 횟수'), greaterThan(_y(tester, '이번 주 0일 운동했어요')));
      // 바로가기는 항상 맨 아래.
      expect(_y(tester, '바로가기'), greaterThan(_y(tester, '잔여 횟수')));
    });

    testWidgets('잔여 횟수는 아래로 내려가도 히어로 부제로 한 번 더 보인다', (tester) async {
      await _pumpHome(tester, contracts: [_contract(remaining: 8)]);
      expect(find.text('잔여 8회'), findsOneWidget);
    });
  });

  group('히어로 분기', () {
    testWidgets('예약이 없으면 예약 신청이 대표 행동', (tester) async {
      await _pumpHome(tester);

      expect(find.text('다음 수업을 잡아 볼까요?'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '예약 신청'), findsOneWidget);
    });

    testWidgets('오늘 남은 수업이 있으면 그 시각을 주인공으로', (tester) async {
      await _pumpHome(
        tester,
        todaySessions: [_session('s1', upcomingAt)],
        nextSession: _session('s1', upcomingAt),
      );

      expect(find.text('오늘 수업'), findsOneWidget);
      expect(find.text('${formatHm(upcomingAt)} PT'), findsOneWidget);
    });

    testWidgets('오늘 수업을 마쳤으면 완료로 알리고 다음 수업을 덧붙인다', (tester) async {
      final next = DateTime(now.year, now.month, now.day + 2, 14);
      await _pumpHome(
        tester,
        todaySessions: [
          _session('s1', todayAt(0), status: SessionStatus.done),
        ],
        nextSession: _session('s2', next),
      );

      expect(find.text('오늘 운동을 마쳤어요'), findsOneWidget);
      expect(find.textContaining('다음 수업은'), findsOneWidget);
    });
  });

  group('볼트 강조는 화면에 하나 (§4.1)', () {
    /// "셀프 운동 기록" 격자 타일의 배경색 — 강조 타일이면 볼트.
    Color? selfLogTileColor(WidgetTester tester) {
      final material = tester.widget<Material>(
        find
            .ancestor(
              of: find.text('셀프 운동 기록'),
              matching: find.byType(Material),
            )
            .first,
      );
      return material.color;
    }

    testWidgets('오늘 수업이 남았으면 히어로가 가져가고 격자 타일은 강조하지 않는다',
        (tester) async {
      await _pumpHome(
        tester,
        todaySessions: [_session('s1', upcomingAt)],
        nextSession: _session('s1', upcomingAt),
      );
      expect(selfLogTileColor(tester), isNot(AppTheme.volt));
    });

    testWidgets('오늘 할 수업이 없으면 셀프 운동 기록이 강조를 가져간다', (tester) async {
      await _pumpHome(
        tester,
        nextSession: _session('s2', DateTime(now.year, now.month, now.day + 3, 14)),
      );
      expect(selfLogTileColor(tester), AppTheme.volt);
    });
  });

  group('보여 줄 게 없으면 카드를 그리지 않는다', () {
    testWidgets('안 읽은 채팅·안내가 없으면 소식 카드 없음', (tester) async {
      await _pumpHome(tester, notices: [_notice(read: true)]);
      expect(find.textContaining('트레이너 메시지'), findsNothing);
    });

    testWidgets('안 읽은 안내가 있으면 내용 한 줄까지 보여 준다', (tester) async {
      await _pumpHome(
        tester,
        unreadChats: 2,
        notices: [_notice(read: false, content: '금요일 수업은 10시로 옮겼습니다.')],
      );
      expect(find.text('트레이너 메시지 2건'), findsOneWidget);
      expect(find.text('금요일 수업은 10시로 옮겼습니다.'), findsOneWidget);
    });

    testWidgets('인바디 측정이 없으면 최근 변화 카드 없음', (tester) async {
      await _pumpHome(tester);
      expect(find.text('최근 변화'), findsNothing);
    });

    testWidgets('인바디가 있으면 최근값과 증감을 함께 적는다', (tester) async {
      await _pumpHome(tester, measurements: [
        BodyMeasurement(
          id: 'm1',
          memberId: 'member-1',
          measuredAt: DateTime(2026, 8, 1),
          createdAt: DateTime(2026, 8, 1),
          weightKg: 73.2,
        ),
        BodyMeasurement(
          id: 'm2',
          memberId: 'member-1',
          measuredAt: DateTime(2026, 8, 8),
          createdAt: DateTime(2026, 8, 8),
          weightKg: 72.4,
        ),
      ]);

      expect(find.text('최근 변화'), findsOneWidget);
      expect(find.text('72.4'), findsOneWidget);
      // 증감은 부호를 붙이되 좋다/나쁘다로 색칠하지 않는다.
      expect(find.text('-0.8'), findsOneWidget);
    });
  });
}
