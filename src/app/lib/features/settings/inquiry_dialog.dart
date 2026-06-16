/// 문의 작성 다이얼로그.
///
/// 진입점: `Future<bool?> showInquiryDialog(context)` — 전송 성공 시 true 반환.
/// 운영자(관리자)가 문의함에서 확인한다(support_inquiries, 0033).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_providers.dart';

Future<bool?> showInquiryDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (_) => const _InquiryDialog(),
  );
}

class _InquiryDialog extends ConsumerStatefulWidget {
  const _InquiryDialog();

  @override
  ConsumerState<_InquiryDialog> createState() => _InquiryDialogState();
}

class _InquiryDialogState extends ConsumerState<_InquiryDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      setState(() => _error = '문의 내용을 입력해 주세요.');
      return;
    }
    FocusScope.of(context).unfocus();
    await ref.read(inquiryControllerProvider.notifier).submit(text);
    if (!mounted) return;
    final state = ref.read(inquiryControllerProvider);
    if (state.hasError) {
      setState(() => _error = '전송에 실패했습니다. 잠시 후 다시 시도해 주세요.');
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(inquiryControllerProvider).isLoading;

    return AlertDialog(
      title: const Text('문의하기'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '불편한 점이나 궁금한 점을 남겨 주세요. 운영자가 확인 후 처리합니다.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            enabled: !busy,
            minLines: 3,
            maxLines: 6,
            maxLength: 1000,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText: '문의 내용을 입력하세요',
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: busy ? null : _submit,
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('보내기'),
        ),
      ],
    );
  }
}
