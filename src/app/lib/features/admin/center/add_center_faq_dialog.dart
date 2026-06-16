/// 센터 PT 규정 FAQ 추가/수정 다이얼로그 — Phase 3.2 (C2).
///
/// [existing] 이 null 이면 추가, 있으면 수정. 성공 시 true 반환.
///
/// 입력: 질문(필수) / 답변(필수) / 노출 순서(선택, 기본 0).
/// 답변은 검수 게이트가 없는 콘텐츠라 단정적 의학 조언을 피하도록 안내 문구를 둔다.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'center_settings_providers.dart';
import 'center_settings_repository.dart';

/// 다이얼로그 호출 — 성공 시 true 반환. [existing] 있으면 수정 모드.
Future<bool?> showCenterFaqDialog(
  BuildContext context, {
  CenterFaq? existing,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CenterFaqDialog(existing: existing),
  );
}

class _CenterFaqDialog extends ConsumerStatefulWidget {
  const _CenterFaqDialog({this.existing});
  final CenterFaq? existing;

  @override
  ConsumerState<_CenterFaqDialog> createState() => _CenterFaqDialogState();
}

class _CenterFaqDialogState extends ConsumerState<_CenterFaqDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _questionCtrl;
  late final TextEditingController _answerCtrl;
  late final TextEditingController _sortCtrl;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _questionCtrl = TextEditingController(text: e?.question ?? '');
    _answerCtrl = TextEditingController(text: e?.answer ?? '');
    _sortCtrl = TextEditingController(text: (e?.sortOrder ?? 0).toString());
  }

  @override
  void dispose() {
    _questionCtrl.dispose();
    _answerCtrl.dispose();
    _sortCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final question = _questionCtrl.text.trim();
    final answer = _answerCtrl.text.trim();
    final sortOrder = int.tryParse(_sortCtrl.text.trim()) ?? 0;

    final controller = ref.read(centerSettingsControllerProvider.notifier);
    if (_isEdit) {
      await controller.editFaq(
        id: widget.existing!.id,
        question: question,
        answer: answer,
        sortOrder: sortOrder,
      );
    } else {
      await controller.addFaq(
        question: question,
        answer: answer,
        sortOrder: sortOrder,
      );
    }

    if (!mounted) return;
    final state = ref.read(centerSettingsControllerProvider);
    if (state.hasError) {
      final msg = state.error?.toString() ?? 'FAQ 저장에 실패했습니다.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final saving = ref.watch(centerSettingsControllerProvider).isLoading;

    return AlertDialog(
      title: Text(_isEdit ? 'PT 규정 FAQ 수정' : 'PT 규정 FAQ 추가'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _questionCtrl,
                  enabled: !saving,
                  decoration: const InputDecoration(
                    labelText: '질문 *',
                    hintText: '예: PT 수업은 며칠 전까지 취소해야 하나요?',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? '질문을 입력해 주세요.' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _answerCtrl,
                  enabled: !saving,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: '답변 *',
                    hintText: '예: 수업 24시간 전까지 취소하면 횟수가 차감되지 않습니다.',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? '답변을 입력해 주세요.' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _sortCtrl,
                  enabled: !saving,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '노출 순서',
                    helperText: '작을수록 위에 표시됩니다.',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: saving ? null : _submit,
          child: saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isEdit ? '수정' : '추가'),
        ),
      ],
    );
  }
}
