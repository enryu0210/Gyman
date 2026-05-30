/// 회원 예약 신청(requested) 승인/거절/일정변경 bottom sheet (회원 로드맵 ⑤, 트레이너 측).
///
/// 트레이너 예약 화면의 "승인 대기" 카드 탭 시 노출. 일반 예약(scheduled 등)의
/// 상태 전이는 [showBookingStatusSheet] 가 담당하고, 본 시트는 신청 전용이다.
///
/// **동작:**
///   - 승인: requested → scheduled (확정). 잔여 횟수 영향 없음.
///   - 일정 변경 후 승인: 회원이 "오전에도 괜찮아요" 처럼 여유를 준 경우, 트레이너가
///     새 일시를 골라 그 시간으로 확정. scheduled_at + status 를 한 번에 변경.
///   - 거절: 신청 행 삭제(흔적 없음, 베타 단순화).
///
/// 회원이 신청 시 남긴 메모(status_memo)를 함께 보여줘 트레이너가 판단하게 한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/util/date_format_ko.dart';
import '../../../domain/models/session.dart';
import '../session_log/session_providers.dart';

/// 시트 호출 — 처리(승인/거절)가 일어나면 true 반환.
Future<bool?> showRequestActionSheet(
  BuildContext context, {
  required Session session,
  required String memberId,
  required String memberName,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _RequestActionSheet(
      session: session,
      memberId: memberId,
      memberName: memberName,
    ),
  );
}

class _RequestActionSheet extends ConsumerStatefulWidget {
  const _RequestActionSheet({
    required this.session,
    required this.memberId,
    required this.memberName,
  });

  final Session session;
  final String memberId;
  final String memberName;

  @override
  ConsumerState<_RequestActionSheet> createState() =>
      _RequestActionSheetState();
}

class _RequestActionSheetState extends ConsumerState<_RequestActionSheet> {
  /// 트레이너가 고른 새 일시. null 이면 회원이 신청한 원래 시간 그대로 승인.
  DateTime? _newScheduledAt;

  Session get _session => widget.session;

  /// 실제로 확정될 시각 — 변경했으면 새 시간, 아니면 원래 신청 시간.
  DateTime get _effectiveAt => _newScheduledAt ?? _session.scheduledAt;

  /// 일정을 바꿨는지 — 버튼 라벨/표시 분기.
  bool get _rescheduled => _newScheduledAt != null;

  /// 날짜 → 시간 순서로 picker 를 띄워 새 일시를 고른다.
  Future<void> _pickNewSchedule() async {
    final base = _effectiveAt;
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: '변경할 날짜',
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
      helpText: '변경할 시간',
    );
    if (time == null || !mounted) return;

    setState(() {
      _newScheduledAt =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _approve() async {
    final notifier = ref.read(saveSessionControllerProvider.notifier);
    // 일정을 바꿨으면 새 시간으로 확정, 아니면 원래 시간 그대로 승인.
    if (_rescheduled) {
      await notifier.approveRequestWithReschedule(
        sessionId: _session.id,
        newScheduledAt: _newScheduledAt!,
        memberId: widget.memberId,
      );
    } else {
      await notifier.approveRequest(
        sessionId: _session.id,
        memberId: widget.memberId,
      );
    }
    if (!mounted) return;
    _afterAction(
      successMsg: _rescheduled ? '일정을 변경해 예약을 확정했습니다.' : '예약을 승인했습니다.',
    );
  }

  Future<void> _reject() async {
    // 거절은 되돌릴 수 없으니 한 번 더 확인.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('신청 거절'),
        content: Text(
          '${widget.memberName} 님의 예약 신청을 거절할까요?\n'
          '거절하면 신청이 삭제되어 되돌릴 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('거절'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    await ref.read(saveSessionControllerProvider.notifier).rejectRequest(
          sessionId: _session.id,
          memberId: widget.memberId,
        );
    if (!mounted) return;
    _afterAction(successMsg: '예약 신청을 거절했습니다.');
  }

  /// 액션 후 공통 처리 — 에러면 SnackBar, 성공이면 닫고 true 반환.
  void _afterAction({required String successMsg}) {
    if (!mounted) return;
    final state = ref.read(saveSessionControllerProvider);
    if (state.hasError) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(state.error?.toString() ?? '처리에 실패했습니다.')),
        );
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(successMsg)));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final saving = ref.watch(saveSessionControllerProvider).isLoading;
    final memo = _session.statusMemo ?? '';

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.pending_actions, color: colors.primary),
                const SizedBox(width: 8),
                Text('예약 신청', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            Text(widget.memberName, style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),

            // 신청 시간 — 일정을 바꿨으면 취소선 + 새 시간을 강조해서 보여준다.
            if (_rescheduled) ...[
              Text(
                formatKoreanDateTime(_session.scheduledAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(Icons.edit_calendar, size: 16, color: colors.primary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      formatKoreanDateTime(_newScheduledAt!),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: saving
                        ? null
                        : () => setState(() => _newScheduledAt = null),
                    child: const Text('되돌리기'),
                  ),
                ],
              ),
            ] else
              Text(
                formatKoreanDateTime(_session.scheduledAt),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),

            if (memo.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('회원 메모', style: theme.textTheme.labelMedium),
                    const SizedBox(height: 4),
                    Text(memo, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),

            // 일정 변경 — 회원 요구(예: "오전에도 괜찮아요")에 맞춰 시간 조정.
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: saving ? null : _pickNewSchedule,
                icon: const Icon(Icons.edit_calendar, size: 18),
                label: Text(_rescheduled ? '다른 시간으로 변경' : '일정 변경'),
              ),
            ),

            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: saving ? null : _reject,
                    child: const Text('거절'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: saving ? null : _approve,
                    icon: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check),
                    label: Text(_rescheduled ? '변경 후 승인' : '승인'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
