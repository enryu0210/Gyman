/// 회원 체형 제약 등록 다이얼로그 (L1-a — docs/design_movement_coaching.md).
///
/// **입력 항목:**
///   - 제약 항목(필수, 카탈로그 선택 / '직접 입력' 시 자유 텍스트)
///   - 출처(필수) — 의료기관 진단 / 트레이너 관찰
///   - 회원에게 보일 설명(선택), 트레이너 전용 메모(선택)
///
/// **⚠ 이 화면이 지켜야 하는 것 (설계 §5 의료·법적 안전선):**
///   트레이너는 의료인이 아니라 진단 권한이 없다. 그래서 출처를 **선택이 아니라 필수**로
///   두고, '트레이너 관찰'을 고르면 "진단이 아닙니다"를 화면에 명시한다.
///   문구도 "진단"이 아니라 "기록/관찰"로 쓴다 — 앱이 판정하는 것처럼 읽히면 안 된다.
///
/// 다이얼로그 진입점 패턴: `Future<bool?> showXxxDialog(...)`, 성공 시 true.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/member_condition.dart';
import 'member_condition_providers.dart';

/// 제약 등록 다이얼로그 — 성공 시 true 반환.
Future<bool?> showAddMemberConditionDialog(
  BuildContext context, {
  required String memberId,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AddMemberConditionDialog(memberId: memberId),
  );
}

class _AddMemberConditionDialog extends ConsumerStatefulWidget {
  const _AddMemberConditionDialog({required this.memberId});
  final String memberId;

  @override
  ConsumerState<_AddMemberConditionDialog> createState() =>
      _AddMemberConditionDialogState();
}

class _AddMemberConditionDialogState
    extends ConsumerState<_AddMemberConditionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _labelCtrl = TextEditingController();
  final _memberNoteCtrl = TextEditingController();
  final _trainerNoteCtrl = TextEditingController();

  /// 선택된 제약 코드. 기본값은 카탈로그 첫 항목.
  String _code = ConditionCatalog.items.first.code;

  /// 출처. 기본은 더 보수적인 쪽(관찰) — 실수로 "의료기관 진단"이 되지 않게.
  ConditionSource _source = ConditionSource.trainerObservation;

  bool get _isCustom => _code == ConditionCatalog.customCode;

  @override
  void dispose() {
    _labelCtrl.dispose();
    _memberNoteCtrl.dispose();
    _trainerNoteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final now = DateTime.now();
    final condition = MemberCondition(
      id: 'new', // DB 기본값으로 덮어씀
      memberId: widget.memberId,
      code: _code,
      label: _isCustom ? _labelCtrl.text : null,
      source: _source,
      memberNote: _memberNoteCtrl.text,
      trainerNote: _trainerNoteCtrl.text,
      createdAt: now,
      updatedAt: now,
    );

    await ref.read(memberConditionControllerProvider.notifier).add(
          memberId: widget.memberId,
          condition: condition,
        );

    if (!mounted) return;
    final state = ref.read(memberConditionControllerProvider);
    if (state.hasError) {
      final err = state.error;
      // 중복 등록 등은 repository 가 사람이 읽을 메시지로 바꿔 던진다.
      final msg = err is StateError ? err.message : '등록에 실패했습니다.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final saving = ref.watch(memberConditionControllerProvider).isLoading;
    final hint = ConditionCatalog.find(_code)?.hint;

    return AlertDialog(
      title: const Text('체형 특이사항 기록'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── 항목 선택 ─────────────────────────────────────────
                DropdownButtonFormField<String>(
                  initialValue: _code, // Flutter 3.32+ 는 value → initialValue
                  decoration: const InputDecoration(
                    labelText: '항목 *',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final item in ConditionCatalog.items)
                      DropdownMenuItem(
                        value: item.code,
                        child: Text(item.label),
                      ),
                  ],
                  onChanged:
                      saving ? null : (v) => setState(() => _code = v ?? _code),
                ),
                if (hint != null && !_isCustom)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text(
                      hint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),

                // ── 직접 입력일 때만 표시명 필드 ─────────────────────
                if (_isCustom) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _labelCtrl,
                    enabled: !saving,
                    decoration: const InputDecoration(
                      labelText: '항목명 *',
                      hintText: '예: 우측 발목 가동범위 제한',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (!_isCustom) return null;
                      return (v ?? '').trim().isEmpty ? '항목명을 입력해 주세요.' : null;
                    },
                  ),
                ],

                const SizedBox(height: 16),

                // ── 출처 (법적 안전선) ────────────────────────────────
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('출처 *', style: theme.textTheme.labelLarge),
                ),
                const SizedBox(height: 6),
                SegmentedButton<ConditionSource>(
                  segments: [
                    for (final s in ConditionSource.values)
                      ButtonSegment(value: s, label: Text(s.label)),
                  ],
                  selected: {_source},
                  onSelectionChanged: saving
                      ? null
                      : (sel) => setState(() => _source = sel.first),
                ),
                const SizedBox(height: 8),
                _SourceNotice(source: _source),

                const SizedBox(height: 16),

                // ── 메모 2종 (가시성이 다름) ──────────────────────────
                TextFormField(
                  controller: _memberNoteCtrl,
                  enabled: !saving,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '회원에게 보일 설명 (선택)',
                    hintText: '예: 오른쪽 어깨가 조금 낮은 편이에요',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _trainerNoteCtrl,
                  enabled: !saving,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: '트레이너 전용 메모 (선택)',
                    hintText: '회원에게 보이지 않습니다',
                    border: const OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline,
                        size: 18, color: colors.onSurfaceVariant),
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

/// 출처별 안내 문구 — "관찰은 진단이 아니다"를 화면에서 못 놓치게 한다.
class _SourceNotice extends StatelessWidget {
  const _SourceNotice({required this.source});
  final ConditionSource source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isMedical = source == ConditionSource.medical;

    final text = isMedical
        ? '회원이 제출한 의료기관 진단 이력을 옮겨 적습니다. 진단 내용을 임의로 해석하지 마세요.'
        : '수업 중 관찰한 소견입니다. 진단이 아니며, 통증이 있으면 의료기관 진료를 안내하세요.';

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isMedical ? Icons.local_hospital_outlined : Icons.visibility_outlined,
            size: 16,
            color: colors.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
