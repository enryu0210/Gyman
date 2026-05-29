/// 회원 예약 신청(requested) 승인/거절 bottom sheet (회원 로드맵 ⑤, 트레이너 측).
///
/// 트레이너 예약 화면의 "승인 대기" 카드 탭 시 노출. 일반 예약(scheduled 등)의
/// 상태 전이는 [showBookingStatusSheet] 가 담당하고, 본 시트는 신청 전용이다.
///
/// **동작:**
///   - 승인: requested → scheduled (확정). 잔여 횟수 영향 없음.
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

class _RequestActionSheet extends ConsumerWidget {
  const _RequestActionSheet({
    required this.session,
    required this.memberId,
    required this.memberName,
  });

  final Session session;
  final String memberId;
  final String memberName;

  Future<void> _approve(BuildContext context, WidgetRef ref) async {
    await ref.read(saveSessionControllerProvider.notifier).approveRequest(
          sessionId: session.id,
          memberId: memberId,
        );
    if (!context.mounted) return;
    _afterAction(context, ref, successMsg: '예약을 승인했습니다.');
  }

  Future<void> _reject(BuildContext context, WidgetRef ref) async {
    // 거절은 되돌릴 수 없으니 한 번 더 확인.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('신청 거절'),
        content: Text(
          '$memberName 님의 예약 신청을 거절할까요?\n'
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
    if (ok != true || !context.mounted) return;

    await ref.read(saveSessionControllerProvider.notifier).rejectRequest(
          sessionId: session.id,
          memberId: memberId,
        );
    if (!context.mounted) return;
    _afterAction(context, ref, successMsg: '예약 신청을 거절했습니다.');
  }

  /// 액션 후 공통 처리 — 에러면 SnackBar, 성공이면 닫고 true 반환.
  void _afterAction(
    BuildContext context,
    WidgetRef ref, {
    required String successMsg,
  }) {
    if (!context.mounted) return;
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
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final saving = ref.watch(saveSessionControllerProvider).isLoading;
    final memo = session.statusMemo ?? '';

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
            Text(memberName, style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              formatKoreanDateTime(session.scheduledAt),
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
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: saving ? null : () => _reject(context, ref),
                    child: const Text('거절'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: saving ? null : () => _approve(context, ref),
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
                    label: const Text('승인'),
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
