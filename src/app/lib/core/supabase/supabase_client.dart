import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';

/// Supabase를 앱 시작 시점에 1회 초기화.
///
/// [Env.isSupabaseConfigured]가 false인 환경(예: 키 미설정)에서는 호출하지 않는다.
/// main.dart에서 분기해서 호출하므로 여기서는 검증만 한 번 더 한다.
Future<void> initSupabase() async {
  if (!Env.isSupabaseConfigured) {
    throw StateError(
      'Supabase 환경변수가 설정되지 않았습니다. .env 파일에 '
      'SUPABASE_URL과 SUPABASE_ANON_KEY를 채워 넣으세요. (.env.example 참고)',
    );
  }
  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
    // PKCE 플로우 — 소셜 로그인(signInWithOAuth)과 비밀번호 재설정의 딥링크 복귀에
    // 필요(code→session 교환을 클라가 안전하게 수행). 이메일/비번 로그인엔 영향 없음.
    // 상세: docs/social_login_plan.md §3.1.
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );
}

/// Supabase 클라이언트 Riverpod provider.
/// 모든 데이터 계층(repository)은 이 provider를 ref.watch / ref.read로 참조한다.
///
/// 주의: [initSupabase] 호출 전에 이 provider에 접근하면 예외가 발생한다.
/// 호출 순서는 main.dart의 책임.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// 현재 로그인된 사용자(User?) 스트림 — auth 상태 변경에 자동 반응.
///
/// 사용 예:
///   final user = ref.watch(currentUserProvider).value;
///   if (user == null) → 로그인 화면으로
final currentUserProvider = StreamProvider<User?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client.auth.onAuthStateChange.map((event) => event.session?.user);
});
