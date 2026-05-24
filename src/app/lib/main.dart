import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/env.dart';
import 'core/router/app_router.dart';
import 'core/supabase/supabase_client.dart';
import 'core/theme/app_theme.dart';

/// 앱 진입점.
///
/// 시작 순서:
///   1) Flutter 바인딩 준비
///   2) .env 로딩 (assets로 등록됨, pubspec.yaml 참고)
///   3) Supabase 키가 있으면 클라이언트 초기화. 없으면 UI 골격만 동작.
///      (개발 초기에 .env 미설정 상태로도 화면을 띄울 수 있게 하기 위함)
///   4) ProviderScope 안에서 GymanApp 실행
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  if (Env.isSupabaseConfigured) {
    await initSupabase();
  } else {
    debugPrint(
      '[WARN] Supabase 환경변수가 비어있습니다. UI 골격만 동작합니다. '
      '.env 파일에 SUPABASE_URL / SUPABASE_ANON_KEY를 채워 넣으세요.',
    );
  }

  runApp(const ProviderScope(child: GymanApp()));
}

/// 앱 루트 위젯. Router 기반 MaterialApp.
class GymanApp extends ConsumerWidget {
  const GymanApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Gyman',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system, // 시스템 라이트/다크 설정 따라감
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
