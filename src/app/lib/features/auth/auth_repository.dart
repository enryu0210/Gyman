/// Supabase Auth 래퍼.
///
/// **왜 repository로 감싸나:**
///   - Supabase SDK의 [AuthException] 메시지가 영문이라 한국어 매핑 필요
///   - UI/Controller는 [SupabaseClient]를 직접 모르고, 본 repository 인터페이스만 본다
///     → 추후 Auth 제공자 교체(예: Firebase) 시 영향 범위 최소화
///   - 테스트에서 mocktail로 손쉽게 가짜 구현 주입 가능
///
/// 참고: docs/develop_plan.md §4 1.1 로그인 + 역할 분기.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';

/// 인증 관련 사용자 친화 예외.
/// Supabase 원본 메시지를 한국어로 치환해서 던진다.
class AuthFailure implements Exception {
  final String message;

  /// 원본 예외 (디버그 로그용). UI에는 노출하지 않음.
  final Object? cause;

  AuthFailure(this.message, {this.cause});

  @override
  String toString() => 'AuthFailure($message)';
}

class AuthRepository {
  final SupabaseClient _client;

  AuthRepository(this._client);

  /// 현재 로그인 세션의 사용자. 미로그인이면 null.
  User? get currentUser => _client.auth.currentUser;

  /// 인증 상태 변경 스트림 — 로그인/로그아웃/세션 갱신 시 발행.
  /// Riverpod의 StreamProvider에서 사용.
  Stream<User?> authStateChanges() =>
      _client.auth.onAuthStateChange.map((event) => event.session?.user);

  /// 비밀번호 재설정 딥링크로 복귀했을 때만 거른 스트림.
  ///
  /// 사용자가 재설정 메일의 링크를 탭하면 복구 세션이 생기며
  /// [AuthChangeEvent.passwordRecovery] 가 발행된다 → 라우터가 이를 보고
  /// `/reset-password`(새 비밀번호 입력)로 강제한다. (그냥 두면 복구 세션이
  /// 로그인으로 간주돼 역할 홈으로 가버려 비번 변경 기회를 잃음.)
  Stream<void> onPasswordRecovery() => _client.auth.onAuthStateChange
      .where((e) => e.event == AuthChangeEvent.passwordRecovery)
      .map((_) {});

  /// 이메일/비밀번호 로그인.
  ///
  /// 실패 시 [AuthFailure] 던짐. 호출 측에서 try/catch로 메시지 표시.
  ///
  /// 예시:
  ///   await repo.signInWithPassword('trainer@test.com', 'password123');
  ///   → 성공: currentUser 채워짐, authStateChanges에 event 발행
  ///   → 실패: AuthFailure('이메일 또는 비밀번호가 올바르지 않습니다')
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    try {
      await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
    } on AuthException catch (e) {
      throw AuthFailure(_mapAuthMessage(e), cause: e);
    } catch (e) {
      // 네트워크 오류 등 — Supabase가 아닌 일반 예외
      throw AuthFailure('네트워크 연결을 확인해 주세요.', cause: e);
    }
  }

  /// 이메일/비밀번호 회원가입 (회원 셀프 가입용).
  ///
  /// Supabase 프로젝트의 "Confirm email" 설정이 켜져 있으면 가입 후 인증 메일을
  /// 보내고 세션이 바로 생기지 않는다(로그인 화면에서 인증 안내). 꺼져 있으면
  /// 가입 즉시 로그인 상태가 되어 초대 코드 입력 화면으로 진입한다.
  Future<void> signUp({
    required String email,
    required String password,
  }) async {
    try {
      await _client.auth.signUp(email: email.trim(), password: password);
    } on AuthException catch (e) {
      throw AuthFailure(_mapAuthMessage(e), cause: e);
    } catch (e) {
      throw AuthFailure('네트워크 연결을 확인해 주세요.', cause: e);
    }
  }

  /// 소셜 로그인(카카오/구글/애플 등) 시작.
  ///
  /// **중요 — 이메일 로그인과 다른 비동기 모델:**
  ///   이 메서드는 인앱 브라우저로 공급자 로그인 페이지를 *여는 데까지*만 await 한다.
  ///   실제 세션은 사용자가 인증을 마치고 [Env.oauthRedirectUrl] 딥링크로 복귀한 뒤
  ///   `onAuthStateChange` 에 비동기로 들어온다. 따라서 호출 측은 세션을 기다리지 말고,
  ///   기존 [authStateChanges] 스트림(→ 라우터 redirect)이 처리하도록 둔다.
  ///
  /// 신규 소셜 사용자는 member_profile 이 없어 역할 미정 → 라우터가 자동으로
  /// `/member/claim`(초대 코드 연결)로 보낸다(app_router 의 role==null 분기 재사용).
  ///
  /// 상세: docs/social_login_plan.md §3.1.
  Future<void> signInWithOAuth(OAuthProvider provider) async {
    try {
      await _client.auth.signInWithOAuth(
        provider,
        redirectTo: Env.oauthRedirectUrl,
        // 시스템 브라우저로 — 일부 공급자(카카오 등)가 인앱 웹뷰 로그인을 막아서.
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
    } on AuthException catch (e) {
      throw AuthFailure(_mapAuthMessage(e), cause: e);
    } catch (e) {
      throw AuthFailure('소셜 로그인을 시작할 수 없습니다. 잠시 후 다시 시도해 주세요.',
          cause: e);
    }
  }

  /// 비밀번호 재설정 메일 발송 (이메일 가입자 한정).
  ///
  /// 메일의 링크를 탭하면 [Env.oauthRedirectUrl] 딥링크로 복귀하고
  /// `onAuthStateChange` 에 `passwordRecovery` 이벤트가 발행된다 → 새 비밀번호
  /// 입력 화면으로 유도(호출 측 책임). 소셜 전용 계정엔 메일이 무의미하므로 UI에서
  /// "카카오로 가입한 계정일 수 있어요" 안내로 보완한다.
  ///
  /// 존재하지 않는 이메일이어도 Supabase는 (계정 존재 여부 노출 방지를 위해) 성공처럼
  /// 응답할 수 있다 → "메일을 보냈어요" 카피로 통일.
  Future<void> sendPasswordReset(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: Env.oauthRedirectUrl,
      );
    } on AuthException catch (e) {
      throw AuthFailure(_mapAuthMessage(e), cause: e);
    } catch (e) {
      throw AuthFailure('네트워크 연결을 확인해 주세요.', cause: e);
    }
  }

  /// 새 비밀번호로 변경 (비번 재설정 딥링크 복귀 후, 복구 세션이 있는 상태에서 호출).
  Future<void> updatePassword(String newPassword) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (e) {
      throw AuthFailure(_mapAuthMessage(e), cause: e);
    } catch (e) {
      throw AuthFailure('비밀번호 변경에 실패했습니다. 다시 시도해 주세요.', cause: e);
    }
  }

  /// 로그아웃. 실패해도 클라이언트 측은 세션 비움.
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (e) {
      // 서버 호출 실패해도 로컬 세션은 비워둠 (방어적)
      throw AuthFailure('로그아웃 중 오류가 발생했습니다.', cause: e);
    }
  }

  /// Supabase AuthException 메시지를 한국어로 매핑.
  ///
  /// 매핑 키는 Supabase Go-True 응답의 `error_code` 또는 `message` 시그니처를 본다.
  /// 누락된 케이스는 원본 메시지를 그대로 사용해 디버깅 단서를 남긴다.
  static String _mapAuthMessage(AuthException e) {
    final code = e.code;
    final msg = e.message.toLowerCase();

    // Supabase가 표준화된 error code 제공 시 우선 사용
    switch (code) {
      case 'invalid_credentials':
        return '이메일 또는 비밀번호가 올바르지 않습니다.';
      case 'email_not_confirmed':
        return '이메일 인증이 필요합니다. 받은 메일의 인증 링크를 확인해 주세요.';
      case 'user_not_found':
        return '해당 이메일로 등록된 계정이 없습니다.';
      case 'over_email_send_rate_limit':
      case 'over_request_rate_limit':
        return '요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.';
      // 회원가입 관련
      case 'user_already_exists':
      case 'email_exists':
        return '이미 가입된 이메일입니다. 로그인해 주세요.';
      case 'weak_password':
        return '비밀번호가 너무 약합니다. 더 복잡하게 설정해 주세요.';
      case 'signup_disabled':
        return '현재 회원가입이 비활성화되어 있습니다.';
    }

    // code가 없는 구버전 응답 대비: message 내용으로 추정
    if (msg.contains('invalid login credentials')) {
      return '이메일 또는 비밀번호가 올바르지 않습니다.';
    }
    if (msg.contains('email not confirmed')) {
      return '이메일 인증이 필요합니다.';
    }

    // 그 외는 원본 메시지로 폴백 (베타 단계에선 디버깅 단서 노출이 더 유익)
    return '로그인에 실패했습니다: ${e.message}';
  }
}
