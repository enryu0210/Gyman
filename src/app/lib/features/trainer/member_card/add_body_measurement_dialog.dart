/// 인바디 측정 입력 다이얼로그 (Phase 2 2.2, S1).
///
/// **입력 항목(모두 선택이지만 최소 1개 필수):**
///   - 체중(kg) / 체지방률(%) / 골격근량(kg) — 소수 첫째자리까지
///   - 측정일(필수, 기본 오늘)
///
/// **검증:**
///   - 세 수치 모두 비면 invalid("최소 1개"). 음수/이상치는 폼에서 차단.
///   - 빈 칸은 해당 항목 미측정(null) — 0으로 채우지 않는다(가짜 추이 방지).
///
/// 다이얼로그 진입점 패턴: `Future<bool?> showXxxDialog(...)`, 성공 시 true.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/body_measurement.dart';
import 'body_measurement_providers.dart';

/// 측정 입력 다이얼로그 — 성공 시 true 반환.
Future<bool?> showAddBodyMeasurementDialog(
  BuildContext context, {
  required String memberId,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AddBodyMeasurementDialog(memberId: memberId),
  );
}

class _AddBodyMeasurementDialog extends ConsumerStatefulWidget {
  const _AddBodyMeasurementDialog({required this.memberId});
  final String memberId;

  @override
  ConsumerState<_AddBodyMeasurementDialog> createState() =>
      _AddBodyMeasurementDialogState();
}

class _AddBodyMeasurementDialogState
    extends ConsumerState<_AddBodyMeasurementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _weightCtrl = TextEditingController();
  final _fatCtrl = TextEditingController();
  final _muscleCtrl = TextEditingController();
  DateTime _measuredAt = _today();

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _fatCtrl.dispose();
    _muscleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _measuredAt,
      firstDate: DateTime(2020),
      lastDate: _today(), // 미래 측정일은 막음
      helpText: '측정일',
    );
    if (picked != null) setState(() => _measuredAt = picked);
  }

  /// 빈 칸 → null, 값 있으면 double. 소수 입력 허용.
  double? _parse(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final weight = _parse(_weightCtrl.text);
    final fat = _parse(_fatCtrl.text);
    final muscle = _parse(_muscleCtrl.text);

    // 최소 1개 항목 필수 — 빈 측정은 의미 없음.
    if (weight == null && fat == null && muscle == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('체중/체지방률/골격근량 중 최소 1개는 입력해 주세요.')),
        );
      return;
    }

    final measurement = BodyMeasurement(
      id: 'new', // DB 기본값으로 덮어씀
      memberId: widget.memberId,
      weightKg: weight,
      bodyFatPct: fat,
      skeletalMuscleKg: muscle,
      measuredAt: _measuredAt,
      createdAt: DateTime.now(),
    );

    await ref.read(bodyMeasurementControllerProvider.notifier).add(
          memberId: widget.memberId,
          measurement: measurement,
        );

    if (!mounted) return;
    final state = ref.read(bodyMeasurementControllerProvider);
    if (state.hasError) {
      final msg = state.error?.toString() ?? '측정 기록 저장에 실패했습니다.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final saving = ref.watch(bodyMeasurementControllerProvider).isLoading;
    final fmt = DateFormat('yyyy-MM-dd');

    return AlertDialog(
      title: const Text('인바디 측정 입력'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DateField(
                  label: '측정일 *',
                  value: fmt.format(_measuredAt),
                  enabled: !saving,
                  onTap: _pickDate,
                ),
                const SizedBox(height: 12),
                _NumberField(
                  controller: _weightCtrl,
                  enabled: !saving,
                  label: '체중',
                  suffix: 'kg',
                ),
                const SizedBox(height: 12),
                _NumberField(
                  controller: _fatCtrl,
                  enabled: !saving,
                  label: '체지방률',
                  suffix: '%',
                  max: 100, // 체지방률은 0~100% 범위
                ),
                const SizedBox(height: 12),
                _NumberField(
                  controller: _muscleCtrl,
                  enabled: !saving,
                  label: '골격근량',
                  suffix: 'kg',
                ),
                const SizedBox(height: 8),
                Text(
                  '비워둔 항목은 "미측정"으로 저장됩니다. 회원에게 변화 추이 그래프로 바로 표시됩니다.',
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
              : const Text('저장'),
        ),
      ],
    );
  }
}

/// 소수 1자리까지 허용하는 숫자 입력 필드. 빈 칸 허용(미측정).
class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.enabled,
    required this.label,
    required this.suffix,
    this.max,
  });

  final TextEditingController controller;
  final bool enabled;
  final String label;
  final String suffix;
  final double? max;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        // 숫자 + 소수점 1자리까지만.
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d?')),
      ],
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        border: const OutlineInputBorder(),
      ),
      validator: (v) {
        final t = (v ?? '').trim();
        if (t.isEmpty) return null; // 미측정 허용
        final n = double.tryParse(t);
        if (n == null || n <= 0) return '0보다 큰 숫자를 입력해 주세요.';
        if (max != null && n > max!) return '$max 이하로 입력해 주세요.';
        return null;
      },
    );
  }
}

/// 탭하면 DatePicker가 뜨는 InputDecorator (add_contract_dialog 패턴 재사용).
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        child: Text(value),
      ),
    );
  }
}
