// Phase 1.1 — 로그인 화면 smoke test.
//
// .env가 비어있어도(Supabase 미설정) 앱이 크래시 없이 로그인 화면을 그려야 한다.
// 실제 로그인 시나리오(이메일/비번 입력 → Supabase 호출)는 통합 테스트 영역.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gyman/main.dart';

void main() {
  testWidgets('앱이 크래시 없이 빌드되고 로그인 화면이 표시된다', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: GymanApp()));
    // 라우터 redirect + StreamProvider 초기 발행이 한 프레임 더 필요할 수 있음
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 헤더 브랜드 + 로그인 버튼 라벨 확인 — LoginScreen 렌더링 신호
    expect(find.text('Gyman'), findsOneWidget);
    expect(find.text('로그인'), findsOneWidget);
  });

  testWidgets('Supabase 미설정 환경이면 안내 카드가 표시된다', (tester) async {
    // 테스트 환경은 dotenv.load도 안 되어있으므로 isSupabaseConfigured=false
    await tester.pumpWidget(const ProviderScope(child: GymanApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.textContaining('Supabase 환경변수가 비어있습니다'),
      findsOneWidget,
      reason: '미설정 환경에서는 사용자에게 명확한 안내가 떠야 함',
    );
  });
}
