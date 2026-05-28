/// PT 계약 등록 다이얼로그 (Phase 1.3).
///
/// **입력 항목:**
///   - 총 횟수(필수, > 0)
///   - 시작일(필수, 기본 오늘)
///   - 만료일(선택, start_date 이후만)
///   - 가격(선택, 양수)
///   - 메모(선택)
///
/// **숫자 입력 검증:**
///   - parseInt 실패하면 폼 invalid. 빈 칸은 가격에 한해 허용(null).
///   - "0회 계약" 은 DB CHECK(total_sessions > 0)에서도 차단되지만 UI 단에서 미리.
///
/// 와이어프레임 출처: docs/wireframes/04_member_card.md 화면 4.4 "계약" 영역.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'contract_providers.dart';
import 'contract_repository.dart';

/// 다이얼로그 호출 — 성공 시 true 반환.
Future<bool?> showAddContractDialog(
  BuildContext context, {
  required String memberId,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AddContractDialog(memberId: memberId),
  );
}

class _AddContractDialog extends ConsumerStatefulWidget {
  const _AddContractDialog({required this.memberId});
  final String memberId;

  @override
  ConsumerState<_AddContractDialog> createState() => _AddContractDialogState();
}

class _AddContractDialogState extends ConsumerState<_AddContractDialog> {
  final _formKey = GlobalKey<FormState>();
  final _totalCtrl = TextEditingController(text: '20');
  final _priceCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();
  DateTime _startDate = _today();
  DateTime? _endDate;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void dispose() {
    _totalCtrl.dispose();
    _priceCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: '계약 시작일',
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        // 만료일이 시작일보다 빠르면 초기화 — 검증 통과 위해.
        if (_endDate != null && _endDate!.isBefore(_startDate)) {
          _endDate = null;
        }
      });
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate.add(const Duration(days: 90)),
      firstDate: _startDate,
      lastDate: DateTime(2100),
      helpText: '계약 만료일 (선택)',
    );
    if (picked != null) {
      setState(() => _endDate = picked);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final total = int.tryParse(_totalCtrl.text.trim());
    if (total == null || total <= 0) return;

    final priceText = _priceCtrl.text.trim();
    final price = priceText.isEmpty ? null : int.tryParse(priceText);

    final memo = _memoCtrl.text.trim();

    final input = NewContractInput(
      memberId: widget.memberId,
      totalSessions: total,
      startDate: _startDate,
      endDate: _endDate,
      price: price,
      memo: memo.isEmpty ? null : memo,
    );

    await ref.read(addContractControllerProvider.notifier).addContract(input);

    if (!mounted) return;
    final state = ref.read(addContractControllerProvider);
    if (state.hasError) {
      final msg = state.error?.toString() ?? '계약 등록에 실패했습니다.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final saving = ref.watch(addContractControllerProvider).isLoading;
    final fmt = DateFormat('yyyy-MM-dd');

    return AlertDialog(
      title: const Text('PT 계약 등록'),
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
                  controller: _totalCtrl,
                  enabled: !saving,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '총 횟수 *',
                    suffixText: '회',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final n = int.tryParse((v ?? '').trim());
                    if (n == null || n <= 0) return '1 이상의 숫자를 입력해 주세요.';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _DateField(
                  label: '시작일 *',
                  value: fmt.format(_startDate),
                  enabled: !saving,
                  onTap: _pickStartDate,
                ),
                const SizedBox(height: 12),
                _DateField(
                  label: '만료일',
                  value: _endDate == null ? '선택 안 함' : fmt.format(_endDate!),
                  enabled: !saving,
                  onTap: _pickEndDate,
                  onClear: _endDate == null
                      ? null
                      : () => setState(() => _endDate = null),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _priceCtrl,
                  enabled: !saving,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '가격',
                    suffixText: '원',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return null;
                    final n = int.tryParse(t);
                    if (n == null || n < 0) return '0 이상의 숫자만 입력 가능합니다.';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _memoCtrl,
                  enabled: !saving,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '메모',
                    hintText: '예: 카드 결제, 친구 추천 할인',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '잔여 횟수는 수업 기록(Phase 1.4)이 쌓이면 자동으로 줄어듭니다.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
              : const Text('등록'),
        ),
      ],
    );
  }
}

/// 탭하면 DatePicker가 뜨는 InputDecorator. 만료일은 onClear로 비울 수도 있음.
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final String value;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final hasClear = onClear != null;
    return InkWell(
      onTap: enabled ? onTap : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: hasClear
              ? IconButton(
                  tooltip: '비우기',
                  icon: const Icon(Icons.close),
                  onPressed: enabled ? onClear : null,
                )
              : const Icon(Icons.calendar_today_outlined),
        ),
        child: Text(value),
      ),
    );
  }
}
