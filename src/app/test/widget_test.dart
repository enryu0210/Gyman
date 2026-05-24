// Phase 0.6 단계의 smoke test.
// 본격적인 단위 테스트(renewal_calculator, remaining_sessions, visibility)는
// develop_plan.md §5.1대로 Phase 1 진입 전에 TDD로 작성한다.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gyman/main.dart';

void main() {
  testWidgets('앱이 크래시 없이 빌드되고 로그인 화면이 표시된다', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: GymanApp()));
    // 초기 진입은 /login → AppBar 제목 "로그인" 확인
    await tester.pump();
    expect(find.text('로그인'), findsWidgets);
  });
}
