/// 회원 탈퇴 다이얼로그 — 사유 선택 + 데이터 처리 안내 + 확인.
///
/// 진입점: `Future<bool?> showDeleteAccountDialog(context)` — 탈퇴 성공 시 true.
/// 성공하면 컨트롤러가 로그아웃까지 하므로, 라우터가 /login 으로 보낸다.
///
/// 운톡 불만 #1(탈퇴 불가) 해결 — "탈퇴까지 3탭 이내, 데이터 처리 명확 안내".
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_providers.dart';

/// 탈퇴 사유 선택지 — (코드, 표시 라벨). 코드는 로그(account_deletion_logs)에 저장.
const List<({String code, String label})> _reasons = [
  (code: 'not_using', label: '더 이상 이용하지 않아요'),
  (code: 'switched', label: '다른 센터/앱으로 옮겼어요'),
  (code: 'privacy', label: '개인정보가 걱정돼요'),
  (code: 'inconvenient', label: '사용이 불편해요'),
  (code: 'etc', label: '기타'),
];

Future<bool?> showDeleteAccountDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (_) => const _DeleteAccountDialog(),
  );
}

class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog();

  @override
  ConsumerState<_DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  String _reason = _reasons.first.code;
  final _detailCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _detailCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    await ref.read(deleteAccountControllerProvider.notifier).deleteAccount(
          reason: _reason,
          detail: _detailCtrl.text,
        );
    if (!mounted) return;
    final state = ref.read(deleteAccountControllerProvider);
    if (state.hasError) {
      final err = state.error;
      setState(() => _error = err is Exception
          ? err.toString().replaceFirst('SettingsFailure(', '').replaceFirst(')', '')
          : '탈퇴 처리에 실패했습니다. 잠시 후 다시 시도해 주세요.');
      return;
    }
    // 성공 — 컨트롤러가 로그아웃했고, 라우터가 /login 으로 보낸다.
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final busy = ref.watch(deleteAccountControllerProvider).isLoading;

    return AlertDialog(
      title: const Text('회원 탈퇴'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 데이터 처리 안내 — 익명화 정책 명확히(분쟁 방지).
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '탈퇴하면 이름·연락처 등 개인정보는 즉시 익명 처리되어 복구할 수 없습니다.\n'
                '계정이 삭제되며 다시 로그인할 수 없습니다.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onErrorContainer,
                    ),
              ),
            ),
            const SizedBox(height: 16),
            Text('탈퇴 사유', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            // 사유 선택 — RadioGroup 으로 감싸고 자식엔 value 만(CLAUDE.md Flutter 3.32+).
            // 비활성화는 IgnorePointer 로(RadioGroup.onChanged 는 non-null 시그니처).
            IgnorePointer(
              ignoring: busy,
              child: RadioGroup<String>(
                groupValue: _reason,
                onChanged: (v) => setState(() => _reason = v ?? _reason),
                child: Column(
                  children: [
                    for (final r in _reasons)
                      RadioListTile<String>(
                        value: r.code,
                        title: Text(r.label),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _detailCtrl,
              enabled: !busy,
              minLines: 2,
              maxLines: 4,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: '의견 (선택)',
                hintText: '개선에 참고할 의견을 남겨 주세요',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!, style: TextStyle(color: colors.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('취소'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: colors.error,
            foregroundColor: colors.onError,
          ),
          onPressed: busy ? null : _confirm,
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('탈퇴하기'),
        ),
      ],
    );
  }
}
