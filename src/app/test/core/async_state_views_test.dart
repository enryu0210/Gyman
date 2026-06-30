// 공용 비동기 상태 위젯(AppErrorView/AppEmptyView/AppLoadingView/AppInlineError)
// 동작 검증. U7(운톡 개선) 으로 화면마다 복붙되던 에러/빈/로딩 뷰를 한곳으로 모은 뒤,
// 핵심 동작(재시도 버튼 노출 조건·콜백·기본 카피)이 깨지지 않는지 회귀로 고정한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/core/widgets/async_state_views.dart';

/// 위젯 1개를 MaterialApp 으로 감싸 펌프하는 헬퍼.
Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  group('AppErrorView', () {
    testWidgets('onRetry 가 없으면 [다시 시도] 버튼을 숨긴다', (tester) async {
      await _pump(tester, const AppErrorView());
      expect(find.text('다시 시도'), findsNothing);
    });

    testWidgets('onRetry 가 있으면 버튼을 보이고 탭 시 콜백을 호출한다', (tester) async {
      var tapped = 0;
      await _pump(tester, AppErrorView(onRetry: () => tapped++));
      expect(find.text('다시 시도'), findsOneWidget);
      await tester.tap(find.text('다시 시도'));
      expect(tapped, 1);
    });

    testWidgets('message 를 비우면 기본 폴백 카피를 보여준다', (tester) async {
      await _pump(tester, const AppErrorView());
      expect(find.textContaining('불러오지 못했습니다'), findsOneWidget);
    });

    testWidgets('message·detail 을 주면 둘 다 보여준다', (tester) async {
      await _pump(
        tester,
        const AppErrorView(message: '목록을 불러오지 못했습니다.', detail: 'SocketException'),
      );
      expect(find.text('목록을 불러오지 못했습니다.'), findsOneWidget);
      expect(find.text('SocketException'), findsOneWidget);
    });
  });

  group('AppEmptyView', () {
    testWidgets('title·message·action 을 모두 렌더한다', (tester) async {
      await _pump(
        tester,
        AppEmptyView(
          title: '등록된 회원이 없습니다',
          message: '회원 추가 버튼으로 시작하세요.',
          action: FilledButton(onPressed: () {}, child: const Text('회원 추가')),
        ),
      );
      expect(find.text('등록된 회원이 없습니다'), findsOneWidget);
      expect(find.text('회원 추가 버튼으로 시작하세요.'), findsOneWidget);
      expect(find.text('회원 추가'), findsOneWidget);
    });

    testWidgets('title·action 이 없으면 message 만 렌더한다', (tester) async {
      await _pump(tester, const AppEmptyView(message: '들어온 문의가 없습니다.'));
      expect(find.text('들어온 문의가 없습니다.'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  group('AppInlineError', () {
    testWidgets('onRetry 가 없으면 버튼을 숨기고 메시지만 보인다', (tester) async {
      await _pump(tester, const AppInlineError(message: '기록을 불러오지 못했습니다.'));
      expect(find.text('기록을 불러오지 못했습니다.'), findsOneWidget);
      expect(find.text('다시 시도'), findsNothing);
    });

    testWidgets('onRetry 가 있으면 탭 시 콜백을 호출한다', (tester) async {
      var tapped = 0;
      await _pump(
        tester,
        AppInlineError(message: '실패', onRetry: () => tapped++),
      );
      await tester.tap(find.text('다시 시도'));
      expect(tapped, 1);
    });
  });

  group('AppLoadingView', () {
    testWidgets('진행 표시기를 보여준다', (tester) async {
      await _pump(tester, const AppLoadingView());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
