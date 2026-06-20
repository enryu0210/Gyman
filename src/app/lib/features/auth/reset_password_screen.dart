/// 새 비밀번호 입력 화면 — 비밀번호 재설정 딥링크 복귀 후 (E-2).
///
/// 라우트: `/reset-password`
///
/// 진입 시점: 재설정 메일의 링크를 탭해 앱이 열리고 [passwordRecoveryProvider] 가
///   true 가 된 상태. 라우터가 역할 홈 대신 이 화면으로 강제한다.
///
/// 흐름: 새 비밀번호 입력 → updateUser(password) → 복구 플래그 해제 →
///   역할 재판정 → 라우터가 역할 홈으로 redirect.
///
/// 취소 시: 복구 세션을 남기지 않도록 로그아웃 + 플래그 해제 → 로그인 화면.
///
/// 상세: docs/social_login_plan.md §3.4.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_providers.dart';
import 'auth_repository.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).updatePassword(_passwordCtrl.text);
      // 변경 성공 → 복구 모드 종료 → 라우터가 역할 홈으로 보냄.
      ref.read(passwordRecoveryProvider.notifier).clear();
      ref.invalidate(currentRoleProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('비밀번호가 변경되었습니다.')),
        );
    } catch (e) {
      if (!mounted) return;
      final msg = e is AuthFailure ? e.message : '비밀번호 변경에 실패했습니다.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 취소 — 복구 세션을 남기지 않도록 로그아웃하고 로그인 화면으로.
  Future<void> _cancel() async {
    setState(() => _busy = true);
    ref.read(passwordRecoveryProvider.notifier).clear();
    await ref.read(signInControllerProvider.notifier).signOut();
    // 로그아웃 → authState 가 null → 라우터가 /login 으로 redirect.
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('새 비밀번호 설정')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.lock_reset, size: 56, color: colors.primary),
                    const SizedBox(height: 16),
                    Text(
                      '새 비밀번호를 입력해 주세요',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _passwordCtrl,
                      enabled: !_busy,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: '새 비밀번호',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _obscure ? '비밀번호 표시' : '비밀번호 숨김',
                          icon: Icon(_obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: _validatePassword,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _confirmCtrl,
                      enabled: !_busy,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: '새 비밀번호 확인',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      onFieldSubmitted: (_) => _submit(),
                      // 일치 검증 — 위 필드와 같은 값인지.
                      validator: (v) {
                        if (v != _passwordCtrl.text) {
                          return '비밀번호가 일치하지 않습니다.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('비밀번호 변경'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy ? null : _cancel,
                      child: const Text('취소'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return '비밀번호를 입력해 주세요.';
    if (value.length < 6) return '비밀번호는 6자 이상이어야 합니다.';
    return null;
  }
}
