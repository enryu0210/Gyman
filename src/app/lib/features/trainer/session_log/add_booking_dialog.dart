/// 예약 추가 다이얼로그 (Phase 1.6, 화면 5.2).
///
/// 회원 상세 화면에서 진입. 입력 항목:
///   - 계약 (활성 계약 1개면 자동 선택)
///   - 날짜 / 시각
///   - 메모(선택) — 회원 요청사항 등
///
/// **잔여 부족 경고:**
///   v_contract_status 의 remaining_sessions == 0 인 계약이라면 "잔여 0회. 진행?"
///   확인 다이얼로그 한 번 띄움. 베타 단계엔 새 계약 권장 메시지로 충분.
///
/// 와이어프레임 출처: docs/wireframes/05_booking.md 화면 5.2.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/pt_contract.dart';
import '../contract/contract_providers.dart';
import '../contract/contract_repository.dart';
import 'session_providers.dart';
import 'session_repository.dart';

/// 다이얼로그 호출 — 성공 시 true 반환.
Future<bool?> showAddBookingDialog(
  BuildContext context, {
  required String memberId,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AddBookingDialog(memberId: memberId),
  );
}

class _AddBookingDialog extends ConsumerStatefulWidget {
  const _AddBookingDialog({required this.memberId});
  final String memberId;

  @override
  ConsumerState<_AddBookingDialog> createState() => _AddBookingDialogState();
}

class _AddBookingDialogState extends ConsumerState<_AddBookingDialog> {
  String? _contractId;
  // 기본 일시: 오늘 (다음 정시). 가장 자주 잡는 케이스 가정 — "지금 회원이랑 다음 시간 잡자".
  DateTime _scheduledAt = _defaultStart();
  final _memoCtrl = TextEditingController();
  bool _initialized = false;

  static DateTime _defaultStart() {
    final now = DateTime.now();
    // 다음 정시 (예: 14:32 → 15:00)
    return DateTime(now.year, now.month, now.day, now.hour + 1);
  }

  @override
  void dispose() {
    _memoCtrl.dispose();
    super.dispose();
  }

  void _autoSelectIfSingle(List<PtContract> contracts) {
    if (_initialized) return;
    _initialized = true;
    if (contracts.length == 1) {
      _contractId = contracts.first.id;
    }
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt,
      // 과거 예약도 가능 — "어제 했는데 깜빡함" 케이스
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: '수업 일자',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt),
      helpText: '수업 시각',
    );
    if (time == null) return;
    setState(() {
      _scheduledAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  /// 잔여 0 인 계약이면 한 번 더 확인. true = 진행.
  Future<bool> _confirmIfExhausted(List<ContractStatusRow> statuses) async {
    final s = statuses.firstWhere(
      (s) => s.contractId == _contractId,
      orElse: () => statuses.first,
    );
    if (s.remainingSessions > 0) return true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('잔여 횟수 부족'),
        content: const Text(
          '선택한 계약의 잔여 횟수가 0회입니다.\n'
          '그래도 예약을 등록하시겠습니까?\n'
          '(권장: 새 계약을 먼저 등록)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('진행'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _submit({required List<ContractStatusRow> statuses}) async {
    if (_contractId == null) {
      _toast('계약을 선택해 주세요.');
      return;
    }
    if (!await _confirmIfExhausted(statuses)) return;
    if (!mounted) return;

    final memo = _memoCtrl.text.trim();
    await ref.read(saveSessionControllerProvider.notifier).createScheduled(
          memberId: widget.memberId,
          input: NewBookingInput(
            contractId: _contractId!,
            scheduledAt: _scheduledAt,
            memo: memo.isEmpty ? null : memo,
          ),
        );

    if (!mounted) return;
    final state = ref.read(saveSessionControllerProvider);
    if (state.hasError) {
      _toast(state.error?.toString() ?? '예약 등록에 실패했습니다.');
      return;
    }
    Navigator.of(context).pop(true);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final contractsAsync =
        ref.watch(contractsForMemberProvider(widget.memberId));
    final statusAsync =
        ref.watch(contractStatusForMemberProvider(widget.memberId));
    final saving = ref.watch(saveSessionControllerProvider).isLoading;
    final fmt = DateFormat('yyyy-MM-dd HH:mm');

    Widget body;
    if (contractsAsync.isLoading || statusAsync.isLoading) {
      body = const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (contractsAsync.hasError) {
      body = Text('계약 정보를 불러오지 못했습니다.\n${contractsAsync.error}');
    } else {
      final contracts = contractsAsync.value ?? const <PtContract>[];
      final statuses = statusAsync.value ?? const <ContractStatusRow>[];
      if (contracts.isEmpty) {
        body = const Text(
          '활성 계약이 없습니다. 회원 상세에서 [계약 추가] 후 다시 시도해 주세요.',
        );
      } else {
        _autoSelectIfSingle(contracts);
        final statusById = {for (final s in statuses) s.contractId: s};
        body = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _contractId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '계약 *',
              ),
              onChanged: saving
                  ? null
                  : (v) => setState(() => _contractId = v),
              items: [
                for (final c in contracts)
                  DropdownMenuItem(
                    value: c.id,
                    child: Text(_contractLabel(c, statusById[c.id])),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: saving ? null : _pickDateTime,
              child: InputDecorator(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '수업 일시 *',
                  suffixIcon: Icon(Icons.calendar_today_outlined),
                ),
                child: Text(fmt.format(_scheduledAt)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _memoCtrl,
              enabled: !saving,
              maxLines: 2,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '메모',
                hintText: '예: 회원 요청 시간 변경 (선택)',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '예약은 잔여 횟수에서 차감되지 않습니다.\n'
              '수업 후 [수업 기록] 으로 완료 처리하면 1회 차감됩니다.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        );
      }
    }

    return AlertDialog(
      title: const Text('예약 등록'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(child: body),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: (saving ||
                  contractsAsync.isLoading ||
                  (contractsAsync.value?.isEmpty ?? true))
              ? null
              : () => _submit(statuses: statusAsync.value ?? const []),
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

  static String _contractLabel(PtContract c, ContractStatusRow? s) {
    final remaining = s?.remainingSessions ?? c.totalSessions;
    return '${c.totalSessions}회 PT · 잔여 $remaining';
  }
}
