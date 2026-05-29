/// 회원 예약 신청 다이얼로그 (회원 로드맵 ⑤).
///
/// 회원이 계약/날짜/시각/메모를 골라 예약을 "신청"한다. 확정이 아니라 신청이며,
/// 트레이너 승인 후에야 확정(scheduled)된다. 신청 시점엔 잔여 횟수가 차감되지 않는다.
///
/// 잔여 0인 계약은 신청 시 한 번 더 확인(트레이너가 새 계약 등 판단할 여지는 남김).
///
/// UI 패턴은 트레이너 측 add_booking_dialog 와 일관되게 유지.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/util/date_format_ko.dart';
import 'member_booking_providers.dart';
import 'member_booking_repository.dart';

/// 다이얼로그 호출 — 신청 성공 시 true 반환.
Future<bool?> showRequestBookingDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _RequestBookingDialog(),
  );
}

class _RequestBookingDialog extends ConsumerStatefulWidget {
  const _RequestBookingDialog();

  @override
  ConsumerState<_RequestBookingDialog> createState() =>
      _RequestBookingDialogState();
}

class _RequestBookingDialogState extends ConsumerState<_RequestBookingDialog> {
  String? _contractId;
  // 기본 일시: 내일 같은 시각의 정시 — 회원은 보통 앞으로의 날짜를 신청.
  DateTime _scheduledAt = _defaultStart();
  final _memoCtrl = TextEditingController();
  bool _initialized = false;

  static DateTime _defaultStart() {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1, now.hour + 1);
    return tomorrow;
  }

  @override
  void dispose() {
    _memoCtrl.dispose();
    super.dispose();
  }

  void _autoSelectIfSingle(List<BookableContract> contracts) {
    if (_initialized) return;
    _initialized = true;
    if (contracts.length == 1) {
      _contractId = contracts.first.contractId;
    }
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt,
      // 회원 신청은 미래만 — 오늘부터 1년.
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: '희망 수업 일자',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt),
      helpText: '희망 수업 시각',
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

  /// 잔여 0인 계약이면 한 번 더 확인. true = 진행.
  Future<bool> _confirmIfExhausted(List<BookableContract> contracts) async {
    final c = contracts.firstWhere(
      (c) => c.contractId == _contractId,
      orElse: () => contracts.first,
    );
    if (!c.isExhausted) return true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('잔여 횟수 부족'),
        content: const Text(
          '선택한 계약의 잔여 횟수가 0회입니다.\n'
          '그래도 예약을 신청하시겠습니까?\n'
          '(트레이너가 계약을 확인 후 처리합니다.)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('신청'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _submit(List<BookableContract> contracts) async {
    if (_contractId == null) {
      _toast('계약을 선택해 주세요.');
      return;
    }
    if (_scheduledAt.isBefore(DateTime.now())) {
      _toast('지난 시각은 신청할 수 없습니다.');
      return;
    }
    if (!await _confirmIfExhausted(contracts)) return;
    if (!mounted) return;

    final memo = _memoCtrl.text.trim();
    await ref.read(memberBookingControllerProvider.notifier).request(
          contractId: _contractId!,
          scheduledAt: _scheduledAt,
          memo: memo.isEmpty ? null : memo,
        );

    if (!mounted) return;
    final state = ref.read(memberBookingControllerProvider);
    if (state.hasError) {
      _toast(state.error?.toString() ?? '예약 신청에 실패했습니다.');
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
    final contractsAsync = ref.watch(memberBookableContractsProvider);
    final saving = ref.watch(memberBookingControllerProvider).isLoading;

    Widget body;
    if (contractsAsync.isLoading) {
      body = const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (contractsAsync.hasError) {
      body = Text('계약 정보를 불러오지 못했습니다.\n${contractsAsync.error}');
    } else {
      final contracts = contractsAsync.value ?? const <BookableContract>[];
      if (contracts.isEmpty) {
        body = const Text(
          '등록된 PT 계약이 없습니다.\n담당 트레이너에게 계약 등록을 요청해 주세요.',
        );
      } else {
        _autoSelectIfSingle(contracts);
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
              onChanged:
                  saving ? null : (v) => setState(() => _contractId = v),
              items: [
                for (final c in contracts)
                  DropdownMenuItem(
                    value: c.contractId,
                    child: Text(_contractLabel(c)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: saving ? null : _pickDateTime,
              child: InputDecorator(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '희망 일시 *',
                  suffixIcon: Icon(Icons.calendar_today_outlined),
                ),
                child: Text(formatKoreanDateTime(_scheduledAt)),
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
                hintText: '예: 가능하면 오전이 좋아요 (선택)',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '신청 후 트레이너가 승인하면 확정됩니다.\n'
              '신청만으로는 잔여 횟수가 차감되지 않습니다.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        );
      }
    }

    final contracts = contractsAsync.value ?? const <BookableContract>[];
    return AlertDialog(
      title: const Text('예약 신청'),
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
          onPressed: (saving || contracts.isEmpty)
              ? null
              : () => _submit(contracts),
          child: saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('신청'),
        ),
      ],
    );
  }

  static String _contractLabel(BookableContract c) {
    final remaining = c.isExhausted ? '소진' : '잔여 ${c.remainingSessions}';
    return '${c.totalSessions}회 PT · $remaining';
  }
}
