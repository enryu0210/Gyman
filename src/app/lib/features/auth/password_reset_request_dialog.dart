/// 비밀번호 재설정 요청 다이얼로그 — 이메일 입력 → 재설정 메일 발송 (E-2).
///
/// 로그인 화면의 "비밀번호를 잊으셨나요?" 에서 진입. 메일의 링크를 탭하면
/// 딥링크로 복귀해 `/reset-password`(새 비번 입력)로 이어진다.
///
/// 소셜 전용 계정(비번 없음)엔 메일이 무의미하므로, 계정 존재 여부를 노출하지
/// 않도록 "메일을 보냈어요" 로 통일하고 안내 카피로 소셜 로그인을 권한다.
///
/// 상세: docs/social_login_plan.md §3.4.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_providers.dart';
import 'auth_repository.dart';

/// 다이얼로그를 띄우고, 메일 발송에 성공하면 true 를 반환한다(호출 측이 SnackBar).
Future<bool?> showPasswordResetRequestDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (_) => const _PasswordResetRequestDialog(),
  );
}

class _PasswordResetRequestDialog extends ConsumerStatefulWidget {
  const _PasswordResetRequestDialog();

  @override
  ConsumerState<_PasswordResetRequestDialog> createState() =>
      _PasswordResetRequestDialogState();
}

class _PasswordResetRequestDialogState
    extends ConsumerState<_PasswordResetRequestDialog> {
  final _emailCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = '이메일을 입력해 주세요.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(email);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is AuthFailure ? e.message : '메일 발송에 실패했습니다.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('비밀번호 재설정'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '가입한 이메일로 재설정 링크를 보내드립니다.\n'
            '카카오 등 소셜로 가입했다면 소셜 로그인을 이용해 주세요.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _emailCtrl,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _send(),
            decoration: const InputDecoration(
              labelText: '이메일',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.mail_outline),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: _busy ? null : _send,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('메일 보내기'),
        ),
      ],
    );
  }
}
