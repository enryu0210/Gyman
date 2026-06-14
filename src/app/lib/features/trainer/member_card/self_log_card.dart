/// 회원 상세 "회원 셀프 운동 기록" 카드 — 트레이너 읽기 전용 (S4 / Phase 2.5).
///
/// 회원이 혼자 운동한 날 직접 남긴 일지(운동·통증 메모)를 트레이너가 본다.
/// **읽기 전용**이다 — 셀프 기록은 회원의 것이라 트레이너는 입력/수정/삭제하지 않는다
/// (RLS self_log_trainer_read 가 SELECT 만 허용). 통증 내역을 보고 수업에 반영하는
/// 케어 목적.
///
/// 최근 [_visibleCount] 건만 펼쳐 보이고, 더 있으면 건수만 안내한다.
///
/// 참고: docs/develop_plan.md §4 Phase 2 2.5, 0028 RLS.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/util/date_format_ko.dart';
import '../../../domain/models/self_workout_log.dart';
import '../../self_log/self_log_providers.dart';

class SelfLogCard extends ConsumerWidget {
  const SelfLogCard({super.key, required this.memberId});

  final String memberId;

  /// 카드에 펼쳐 보일 최대 건수.
  static const _visibleCount = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final async = ref.watch(selfLogsForMemberProvider(memberId));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.edit_note_outlined, size: 18, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('회원 셀프 운동 기록',
                      style: theme.textTheme.titleMedium),
                ),
                Tooltip(
                  message: '회원이 직접 남긴 기록입니다 (읽기 전용)',
                  child: Icon(Icons.lock_outline,
                      size: 16, color: colors.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 12),
            async.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, _) => _InlineMessage(
                text: '기록을 불러오지 못했습니다.',
                onRetry: () =>
                    ref.invalidate(selfLogsForMemberProvider(memberId)),
              ),
              data: (logs) => _Body(logs: logs, visibleCount: _visibleCount),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.logs, required this.visibleCount});
  final List<SelfWorkoutLog> logs;
  final int visibleCount;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (logs.isEmpty) {
      return Text(
        '아직 회원이 남긴 셀프 기록이 없습니다.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
      );
    }

    final visible = logs.take(visibleCount).toList();
    final hiddenCount = logs.length - visible.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final log in visible) _LogRow(log: log),
        if (hiddenCount > 0) ...[
          const SizedBox(height: 4),
          Text(
            '외 $hiddenCount건 더 있음',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
          ),
        ],
      ],
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.log});
  final SelfWorkoutLog log;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                formatKoreanDate(log.loggedAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.primary,
                ),
              ),
              if (log.conditionScore != null) ...[
                const SizedBox(width: 8),
                Icon(Icons.mood, size: 14, color: colors.onSurfaceVariant),
                const SizedBox(width: 2),
                Text(
                  '컨디션 ${log.conditionScore}/10',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ],
          ),
          if ((log.workout ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('운동 · ${log.workout!}',
                  style: theme.textTheme.bodyMedium),
            ),
          if ((log.note ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '메모 · ${log.note!}',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({required this.text, required this.onRetry});
  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(text)),
        TextButton(onPressed: onRetry, child: const Text('다시 시도')),
      ],
    );
  }
}
