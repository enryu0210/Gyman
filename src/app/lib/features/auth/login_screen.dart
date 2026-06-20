/// 로그인 화면.
///
/// **현재 (Phase 1.1) 범위:**
///   - 이메일/비밀번호 입력 → Supabase Auth 로그인
///   - 로딩 인디케이터 + 에러 메시지 표시
///   - Supabase 미설정 시 안내 카드 (개발 초기 진입점)
///
/// **회원가입은 의도적으로 미포함:**
///   베타 단계에선 트레이너가 회원을 직접 등록하는 흐름이므로
///   회원 자발적 가입 화면은 Phase 2 이후로 미룬다.
///   트레이너 본인 계정도 Supabase 대시보드에서 수동 생성 (develop_plan §0).
///
/// 참고: docs/wireframes/01_auth.md (와이어프레임).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show OAuthProvider;

import '../legal/legal_content.dart';
import '../settings/settings_providers.dart';
import 'auth_providers.dart';
import 'auth_repository.dart';
import 'password_reset_request_dialog.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  /// 초대 코드 — 회원가입 시 필수. 트레이너가 발급한 코드.
  final _codeCtrl = TextEditingController();
  bool _obscurePassword = true;

  /// false=로그인, true=회원가입(회원 셀프 가입). 트레이너 계정은 대시보드에서 생성.
  bool _isSignUp = false;

  /// 회원가입 시 필수 동의 — 둘 다 체크해야 가입 버튼 활성화(Phase 3.5).
  bool _agreeTerms = false;
  bool _agreePrivacy = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // 폼 검증 — 비어있거나 형식 잘못이면 즉시 종료
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // 키보드 닫기 — 모바일에서 에러 메시지 가리는 것 방지
    FocusScope.of(context).unfocus();

    final controller = ref.read(signInControllerProvider.notifier);
    if (_isSignUp) {
      await controller.signUp(
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
        inviteCode: _codeCtrl.text,
      );
    } else {
      await controller.signIn(
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
      );
    }

    // 로그인 성공 시 라우터 redirect가 자동으로 홈/연결 화면으로 보냄.
    // 회원가입은 이메일 인증 설정에 따라 안내가 필요해 별도 처리.
    if (!mounted) return;
    final state = ref.read(signInControllerProvider);
    if (_isSignUp && !state.hasError) {
      // 동의 기록 — 세션이 생긴 경우(이메일 인증 OFF)만 기록되고, 실패해도 가입은 유지.
      await ref.read(settingsRepositoryProvider).recordConsent();
      if (!mounted) return;
      // 인증 메일 발송(설정 ON) 또는 즉시 로그인(설정 OFF) 모두 대응되는 안내.
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('가입 완료. 이메일 인증이 필요하면 메일 확인 후 다시 로그인해 주세요.'),
        ));
    }
    // 실패 시 ref.listen에서 SnackBar 표시.
  }

  /// 소셜 로그인 시작 (카카오/구글).
  ///
  /// 성공 = "브라우저 오픈"이지 로그인 완료가 아니다. 인증 후 딥링크로 복귀하면
  /// authStateProvider 스트림이 세션을 받아 라우터가 자동 분기한다(신규 사용자는
  /// /member/claim 으로). 버튼 탭 = 약관·개인정보 동의 간주(하단 카피 명시),
  /// 실제 동의 기록은 첫 착지 화면(claim)에서 보장. 실패는 ref.listen 의 SnackBar.
  Future<void> _social(OAuthProvider provider) async {
    FocusScope.of(context).unfocus();
    await ref.read(signInControllerProvider.notifier).signInWithProvider(provider);
  }

  /// 비밀번호 재설정 — 이메일 입력 다이얼로그 → 메일 발송 안내.
  Future<void> _forgotPassword() async {
    FocusScope.of(context).unfocus();
    final sent = await showPasswordResetRequestDialog(context);
    if (sent != true || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('재설정 메일을 보냈어요. 메일의 링크로 새 비밀번호를 설정해 주세요.'),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final isReady = ref.watch(isSupabaseReadyProvider);
    final signInState = ref.watch(signInControllerProvider);

    // 로그인 실패 시 SnackBar로 메시지 표시 (state.hasError 감지)
    ref.listen(signInControllerProvider, (previous, next) {
      if (next.hasError && !next.isLoading) {
        final err = next.error;
        final msg = err is AuthFailure ? err.message : '알 수 없는 오류가 발생했습니다.';
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(msg)));
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(),
                  const SizedBox(height: 32),
                  if (!isReady) ...[
                    const _SupabaseMissingCard(),
                    const SizedBox(height: 16),
                  ],
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _emailCtrl,
                          enabled: isReady && !signInState.isLoading,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                            labelText: '이메일',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.mail_outline),
                          ),
                          validator: _validateEmail,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _passwordCtrl,
                          enabled: isReady && !signInState.isLoading,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          decoration: InputDecoration(
                            labelText: '비밀번호',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword ? '비밀번호 표시' : '비밀번호 숨김',
                              icon: Icon(_obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                          ),
                          validator: _validatePassword,
                          onFieldSubmitted: (_) => _submit(),
                        ),
                        // 회원가입 시에만 초대 코드 필수 — 유효 코드 없이는 가입 불가.
                        if (_isSignUp) ...[
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _codeCtrl,
                            enabled: isReady && !signInState.isLoading,
                            autocorrect: false,
                            textCapitalization: TextCapitalization.characters,
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(
                              labelText: '초대 코드',
                              hintText: '트레이너에게 받은 코드 (예: A3F9C2B1)',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.vpn_key_outlined),
                            ),
                            validator: (v) {
                              if (!_isSignUp) return null;
                              if ((v ?? '').trim().isEmpty) {
                                return '초대 코드를 입력해 주세요.';
                              }
                              return null;
                            },
                            onFieldSubmitted: (_) => _submit(),
                          ),
                          // 필수 동의 — 둘 다 체크해야 가입 가능(Phase 3.5).
                          const SizedBox(height: 8),
                          _ConsentCheckbox(
                            value: _agreeTerms,
                            enabled: isReady && !signInState.isLoading,
                            label: '[필수] 이용약관 동의',
                            onChanged: (v) =>
                                setState(() => _agreeTerms = v ?? false),
                            onView: () => context.push(LegalDoc.terms.route),
                          ),
                          _ConsentCheckbox(
                            value: _agreePrivacy,
                            enabled: isReady && !signInState.isLoading,
                            label: '[필수] 개인정보 처리방침 동의',
                            onChanged: (v) =>
                                setState(() => _agreePrivacy = v ?? false),
                            onView: () => context.push(LegalDoc.privacy.route),
                          ),
                        ],
                        const SizedBox(height: 24),
                        FilledButton(
                          // 회원가입 모드에선 필수 동의 2개를 모두 체크해야 활성화.
                          onPressed: (isReady &&
                                  !signInState.isLoading &&
                                  (!_isSignUp ||
                                      (_agreeTerms && _agreePrivacy)))
                              ? _submit
                              : null,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: signInState.isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(_isSignUp ? '회원가입' : '로그인'),
                        ),
                        // 비밀번호 재설정 — 로그인 모드에서만(가입 중엔 불필요).
                        if (!_isSignUp)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: (isReady && !signInState.isLoading)
                                  ? _forgotPassword
                                  : null,
                              child: const Text('비밀번호를 잊으셨나요?'),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 로그인 ↔ 회원가입 전환. 회원은 가입 후 초대 코드로 연결한다.
                  TextButton(
                    onPressed: (isReady && !signInState.isLoading)
                        ? () => setState(() => _isSignUp = !_isSignUp)
                        : null,
                    child: Text(_isSignUp
                        ? '이미 계정이 있으신가요? 로그인'
                        : '회원이신가요? 회원가입'),
                  ),
                  const SizedBox(height: 8),
                  // 소셜 로그인 — 카카오/구글(안드로이드 우선, 애플은 iOS 빌드 시 추가).
                  // Supabase 미설정 또는 진행 중이면 비활성.
                  const _OrDivider(),
                  const SizedBox(height: 16),
                  _SocialButton(
                    label: '카카오로 시작하기',
                    icon: Icons.chat_bubble,
                    background: const Color(0xFFFEE500),
                    foreground: const Color(0xFF191600),
                    onPressed: (isReady && !signInState.isLoading)
                        ? () => _social(OAuthProvider.kakao)
                        : null,
                  ),
                  const SizedBox(height: 10),
                  _SocialButton(
                    label: 'Google로 시작하기',
                    icon: Icons.g_mobiledata,
                    background: Colors.white,
                    foreground: const Color(0xFF1F1F1F),
                    border: true,
                    onPressed: (isReady && !signInState.isLoading)
                        ? () => _social(OAuthProvider.google)
                        : null,
                  ),
                  const SizedBox(height: 12),
                  // 소셜은 이메일 가입의 동의 체크박스 흐름을 안 타므로 "동의 간주"를 명시.
                  _SocialConsentNotice(),
                  const SizedBox(height: 16),
                  Text(
                    '회원가입에는 트레이너가 발급한 초대 코드가 필요합니다.\n'
                    '트레이너 계정은 관리자가 등록합니다.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 이메일 형식 검증 — RFC 정식 아닌 실용 수준.
  /// (예: 'a@b.c' 만 통과해도 충분, Supabase가 최종 검증)
  static String? _validateEmail(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return '이메일을 입력해 주세요.';
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v);
    if (!ok) return '이메일 형식이 올바르지 않습니다.';
    return null;
  }

  static String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return '비밀번호를 입력해 주세요.';
    if (value.length < 6) return '비밀번호는 6자 이상이어야 합니다.';
    return null;
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.fitness_center,
            size: 32,
            color: colors.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Gyman',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'PT 트레이너를 위한 회원 관리',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

/// 회원가입 필수 동의 한 줄 — 체크박스 + 라벨 + '보기'(약관/정책 열람).
class _ConsentCheckbox extends StatelessWidget {
  const _ConsentCheckbox({
    required this.value,
    required this.enabled,
    required this.label,
    required this.onChanged,
    required this.onView,
  });

  final bool value;
  final bool enabled;
  final String label;
  final ValueChanged<bool?> onChanged;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Checkbox(
          value: value,
          onChanged: enabled ? onChanged : null,
          visualDensity: VisualDensity.compact,
        ),
        Expanded(
          child: GestureDetector(
            onTap: enabled ? () => onChanged(!value) : null,
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ),
        TextButton(
          onPressed: onView,
          child: const Text('보기'),
        ),
      ],
    );
  }
}

/// "또는" 구분선 — 이메일 폼과 소셜 버튼 사이.
class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;
    final textStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    return Row(
      children: [
        Expanded(child: Divider(color: color)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('또는', style: textStyle),
        ),
        Expanded(child: Divider(color: color)),
      ],
    );
  }
}

/// 소셜 로그인 버튼 — 공급자별 브랜드 색을 받아 일관된 형태로 렌더.
/// onPressed 가 null 이면 비활성(Supabase 미설정/진행 중).
class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onPressed,
    this.border = false,
  });

  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback? onPressed;

  /// 흰 배경(구글)처럼 테두리가 필요한 경우.
  final bool border;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: foreground),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          elevation: 0,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: border
                ? BorderSide(color: Theme.of(context).colorScheme.outlineVariant)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }
}

/// 소셜 로그인 동의 간주 안내 + 약관/개인정보 처리방침 열람 링크.
class _SocialConsentNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    return Column(
      children: [
        Text(
          '소셜 로그인 시 아래 약관에 동의한 것으로 간주됩니다.',
          style: style,
          textAlign: TextAlign.center,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: () => context.push(LegalDoc.terms.route),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('이용약관'),
            ),
            Text('·', style: style),
            TextButton(
              onPressed: () => context.push(LegalDoc.privacy.route),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('개인정보 처리방침'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Supabase 키가 .env에 없을 때 표시되는 안내 카드.
/// 개발 초기 진입점 — 이걸 만나면 사용자가 셋업 안내(.env.example)를 따라 채워야 함.
class _SupabaseMissingCard extends StatelessWidget {
  const _SupabaseMissingCard();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, color: colors.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Supabase 환경변수가 비어있습니다.\n'
                'src/app/.env 파일에 SUPABASE_URL과 SUPABASE_ANON_KEY를 채워 주세요.',
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
