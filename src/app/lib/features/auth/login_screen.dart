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

import 'auth_providers.dart';
import 'auth_repository.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;

  /// false=로그인, true=회원가입(회원 셀프 가입). 트레이너 계정은 대시보드에서 생성.
  bool _isSignUp = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
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
      // 인증 메일 발송(설정 ON) 또는 즉시 로그인(설정 OFF) 모두 대응되는 안내.
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('가입 요청 완료. 이메일 인증이 필요하면 메일 확인 후 로그인하고, '
              '바로 진행되면 초대 코드 입력 화면으로 이동합니다.'),
        ));
    }
    // 실패 시 ref.listen에서 SnackBar 표시.
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
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: (isReady && !signInState.isLoading)
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
                  Text(
                    '회원은 가입 후 트레이너에게 받은 초대 코드로 연결합니다.\n'
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
