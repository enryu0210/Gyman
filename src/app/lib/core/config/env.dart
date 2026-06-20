import 'package:flutter_dotenv/flutter_dotenv.dart';

/// 환경변수 접근 단일 진입점.
///
/// 실제 값은 프로젝트 루트의 `.env` 파일에 있고, 그 파일은 `.gitignore` 처리되어
/// 절대 커밋되지 않는다. 키 발급 방법은 `.env.example` 참조.
///
/// 왜 클래스로 감쌌나:
///   - 키 이름 오타(`SUPABSE_URL` 같은)를 컴파일 타임에 잡기 위해
///   - 키가 비어있을 때 일관된 fallback 동작을 보장하기 위해
///   - dotenv 미초기화 환경(테스트 등)에서도 안전하게 빈 문자열을 반환
class Env {
  /// dotenv 미초기화 상태에서도 안전하게 키를 읽는다.
  ///
  /// 테스트 환경에서는 `dotenv.load()`를 호출하지 않으므로 `dotenv.env`에 접근
  /// 자체가 `NotInitializedError`를 던진다. 본 wrapper로 한 곳에서 흡수해서
  /// "키 미설정 = 빈 문자열" 일관성을 유지한다.
  static String _read(String key) {
    try {
      return dotenv.env[key] ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Supabase 프로젝트 URL. 미설정 시 빈 문자열.
  static String get supabaseUrl => _read('SUPABASE_URL');

  /// Supabase 익명 키 (anon key). 미설정 시 빈 문자열.
  /// 익명 키는 클라이언트 노출이 전제이므로 공개돼도 무방하지만, RLS 정책이
  /// 모든 보안의 핵심 — RLS 없이 service_role 키를 클라이언트에 두면 절대 안 됨.
  static String get supabaseAnonKey => _read('SUPABASE_ANON_KEY');

  /// Supabase 키가 모두 설정되어 있는지 여부.
  /// 미설정 시에는 앱이 Supabase 없이 UI 골격만 동작하도록 main.dart에서 분기.
  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// 소셜 로그인·비밀번호 재설정 OAuth 콜백 딥링크.
  ///
  /// 공급자(카카오/구글/애플) 인증 후 이 scheme 으로 앱에 복귀한다. 값은
  /// Android `intent-filter` / iOS `CFBundleURLTypes` / Supabase 대시보드의
  /// Redirect URLs 셋과 **정확히 일치**해야 한다(불일치 시 콜백 미수신).
  ///
  /// .env 미설정 시 기본값(`io.supabase.gyman://login-callback`)으로 폴백 —
  /// 코드/네이티브 배선이 같은 상수를 공유하도록 한 곳에 고정. 상세:
  /// docs/social_login_plan.md §3.3.
  static String get oauthRedirectUrl {
    final v = _read('OAUTH_REDIRECT_URL');
    return v.isNotEmpty ? v : 'io.supabase.gyman://login-callback';
  }
}
