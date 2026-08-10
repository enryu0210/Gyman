// 공통 앱 셸(하단 탭 + 가운데 강조 액션) 동작 검증.
//
// UI 1차 개편에서 트레이너의 주 이동 수단이 홈 격자 → 하단 탭으로 바뀌었다.
// 이 바가 조용히 깨지면 회원·일정·채팅으로 갈 방법 자체가 사라지므로, 배치/배지/
// 콜백 같은 계약을 회귀로 고정한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/core/widgets/app_shell_scaffold.dart';

const _tabs = [
  AppShellTab(icon: Icons.home_outlined, selectedIcon: Icons.home, label: '홈'),
  AppShellTab(
    icon: Icons.groups_outlined,
    selectedIcon: Icons.groups,
    label: '회원',
  ),
  AppShellTab(
    icon: Icons.event_outlined,
    selectedIcon: Icons.event,
    label: '일정',
    badgeCount: 3,
  ),
  AppShellTab(
    icon: Icons.chat_bubble_outline,
    selectedIcon: Icons.chat_bubble,
    label: '채팅',
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  int currentIndex = 0,
  ValueChanged<int>? onTabSelected,
  AppShellAction? centerAction,
  List<AppShellTab> tabs = _tabs,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: AppShellScaffold(
        tabs: tabs,
        currentIndex: currentIndex,
        onTabSelected: onTabSelected ?? (_) {},
        centerAction: centerAction,
        child: const Center(child: Text('본문')),
      ),
    ),
  );
}

void main() {
  testWidgets('탭 라벨과 본문을 함께 그린다', (tester) async {
    await _pump(tester);
    expect(find.text('본문'), findsOneWidget);
    for (final label in ['홈', '회원', '일정', '채팅']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('선택된 탭만 채워진 아이콘을 쓴다 — 색 말고도 구분 신호가 있어야 함',
      (tester) async {
    await _pump(tester, currentIndex: 1);
    expect(find.byIcon(Icons.groups), findsOneWidget); // 선택
    expect(find.byIcon(Icons.groups_outlined), findsNothing);
    expect(find.byIcon(Icons.home_outlined), findsOneWidget); // 비선택
  });

  testWidgets('탭을 누르면 그 인덱스로 콜백한다', (tester) async {
    final tapped = <int>[];
    await _pump(tester, onTabSelected: tapped.add);
    await tester.tap(find.text('채팅'));
    expect(tapped, [3]);
  });

  testWidgets('배지 건수가 0보다 크면 숫자를 띄운다', (tester) async {
    await _pump(tester);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('배지 건수가 0이면 아무것도 안 띄운다', (tester) async {
    await _pump(tester, tabs: const [
      AppShellTab(icon: Icons.home_outlined, selectedIcon: Icons.home, label: '홈'),
    ]);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('세 자리 넘는 배지는 99+ 로 줄인다 — 바가 밀리지 않게', (tester) async {
    await _pump(tester, tabs: const [
      AppShellTab(
        icon: Icons.chat_bubble_outline,
        selectedIcon: Icons.chat_bubble,
        label: '채팅',
        badgeCount: 120,
      ),
    ]);
    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('가운데 강조 액션을 탭 목록 정중앙에 끼워 넣는다', (tester) async {
    await _pump(
      tester,
      centerAction: AppShellAction(
        icon: Icons.edit_note_outlined,
        label: '기록하기',
        onTap: () {},
      ),
    );

    double dx(String label) => tester.getCenter(find.text(label)).dx;
    // 홈 · 회원 · [기록하기] · 일정 · 채팅 순서.
    expect(dx('회원'), lessThan(dx('기록하기')));
    expect(dx('기록하기'), lessThan(dx('일정')));
  });

  testWidgets('강조 액션을 누르면 콜백이 실행된다 — 탭 전환은 일어나지 않는다',
      (tester) async {
    var fired = 0;
    final tapped = <int>[];
    await _pump(
      tester,
      onTabSelected: tapped.add,
      centerAction: AppShellAction(
        icon: Icons.edit_note_outlined,
        label: '기록하기',
        onTap: () => fired++,
      ),
    );

    await tester.tap(find.text('기록하기'));
    expect(fired, 1);
    expect(tapped, isEmpty);
  });

  testWidgets('강조 액션이 없으면 탭만 그린다', (tester) async {
    await _pump(tester);
    expect(find.byIcon(Icons.edit_note_outlined), findsNothing);
  });

  testWidgets('글자 확대 설정이 커도 하단 바가 넘치지 않는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: AppShellScaffold(
            tabs: _tabs,
            currentIndex: 0,
            onTabSelected: (_) {},
            centerAction: AppShellAction(
              icon: Icons.edit_note_outlined,
              label: '기록하기',
              onTap: () {},
            ),
            child: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    // 오버플로가 나면 pumpWidget 단계에서 예외로 잡힌다.
    expect(tester.takeException(), isNull);
  });
}
