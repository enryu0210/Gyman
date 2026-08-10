// "기록하기" 시트의 **생명주기** 회귀 테스트.
//
// **왜 이 테스트가 있나 (실제로 터진 버그):**
//   검색용 TextEditingController 를 시트 바깥에서 만들어
//   `showModalBottomSheet(...).whenComplete(ctrl.dispose)` 로 정리했더니, 그 future 가
//   `Navigator.pop()` 시점에 완료되는 바람에 **시트가 닫히는 애니메이션 도중** 컨트롤러가
//   죽었다. 애니메이션 중 리빌드에서 TextField 가 죽은 컨트롤러에 리스너를 붙이려다
//   터졌고, 실패한 빌드가 Duplicate GlobalKeys · `_dependents.isEmpty` 예외를 줄줄이
//   낳아 화면이 빨간 에러로 덮였다.
//
//   컨트롤러 조기 dispose 는 이 프로젝트에서 반복되는 함정이라(CLAUDE.md UI 패턴),
//   "닫고 나서 애니메이션이 끝날 때까지 예외가 없다"를 못 박아 둔다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/domain/models/member.dart';
import 'package:gyman/features/trainer/home/trainer_today_providers.dart';
import 'package:gyman/features/trainer/member/member_providers.dart';
import 'package:gyman/features/trainer/session_log/start_record_sheet.dart';

Member _member(String id, String name) => Member(
      id: id,
      name: name,
      createdAt: DateTime(2026, 1, 1),
      goal: '체지방 감량',
    );

/// 시트를 여는 버튼 하나짜리 앱. Supabase 를 타지 않도록 provider 는 전부 override.
Future<void> _pumpSheetHost(
  WidgetTester tester, {
  List<Member> members = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // 오늘 일정은 이 테스트의 관심사가 아니다 — 빈 하루로 고정.
        trainerTodayViewProvider.overrideWithValue(
          const AsyncValue.data(TrainerTodayView.empty),
        ),
        membersListProvider.overrideWith((ref) async => members),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () =>
                    startRecordFlow(context, onOpenMembersTab: () {}),
                child: const Text('기록하기'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('시트를 닫아도 닫히는 애니메이션 동안 예외가 나지 않는다', (tester) async {
    await _pumpSheetHost(tester, members: [_member('m1', '김민수')]);

    await tester.tap(find.text('기록하기'));
    await tester.pumpAndSettle();
    expect(find.text('수업 기록 시작'), findsOneWidget);

    // 검색어를 넣어 컨트롤러가 실제로 쓰이는 상태로 만든다.
    await tester.enterText(find.byType(TextField), '김');
    await tester.pumpAndSettle();

    // 스크림(바깥)을 눌러 닫기 → 여기서 컨트롤러가 일찍 죽으면 퇴장 애니메이션
    // 프레임에서 예외가 난다. pumpAndSettle 로 애니메이션을 끝까지 돌린다.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('수업 기록 시작'), findsNothing);
  });

  testWidgets('시트를 두 번 여닫아도 컨트롤러가 매번 새로 만들어진다', (tester) async {
    await _pumpSheetHost(tester, members: [_member('m1', '김민수')]);

    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('기록하기'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '민');
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('검색어로 회원을 걸러낸다', (tester) async {
    await _pumpSheetHost(tester, members: [
      _member('m1', '김민수'),
      _member('m2', '이수진'),
    ]);

    await tester.tap(find.text('기록하기'));
    await tester.pumpAndSettle();
    expect(find.text('김민수'), findsOneWidget);
    expect(find.text('이수진'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '이수');
    await tester.pumpAndSettle();
    expect(find.text('김민수'), findsNothing);
    expect(find.text('이수진'), findsOneWidget);
  });

  testWidgets('회원이 없으면 막다른 길 대신 회원 추가 안내를 준다', (tester) async {
    await _pumpSheetHost(tester);

    await tester.tap(find.text('기록하기'));
    await tester.pumpAndSettle();

    expect(find.text('등록된 회원이 없습니다.'), findsOneWidget);
    expect(find.text('회원 추가하러 가기'), findsOneWidget);
  });
}
