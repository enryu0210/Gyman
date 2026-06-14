/// 회원 셀프 운동 기록 화면 (S4 / Phase 2.5).
///
/// 라우트: `/member/self-log` (회원 홈에서 push 진입 → 뒤로가기 생성).
///
/// 혼자 운동한 날 "어떤 동작에서 어디가 아팠고 어떻게 나아졌다"를 간단히 남긴다
/// (기획서 답변 11). FAB 로 작성, 카드 탭으로 수정, 메뉴로 삭제.
/// 담당 트레이너도 이 기록을 읽을 수 있다(회원 상세의 셀프 기록 카드).
///
/// 참고: docs/develop_plan.md §4 Phase 2 2.5.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/util/date_format_ko.dart';
import '../../../domain/models/self_workout_log.dart';
import '../../self_log/self_log_providers.dart';
import 'self_log_editor_dialog.dart';

class SelfLogScreen extends ConsumerWidget {
  const SelfLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(mySelfLogsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('셀프 운동 기록')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('기록'),
      ),
      body: logsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _ErrorView(
          onRetry: () => ref.invalidate(mySelfLogsProvider),
        ),
        data: (logs) {
          if (logs.isEmpty) return const _EmptyView();
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(mySelfLogsProvider),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
              itemCount: logs.length,
              itemBuilder: (_, i) => _LogCard(log: logs[i]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    SelfWorkoutLog? existing,
  }) async {
    final saved = await showSelfLogEditorDialog(context, existing: existing);
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(existing == null ? '기록을 저장했어요.' : '기록을 수정했어요.')),
        );
    }
  }
}

// =====================================================================
// 기록 카드 — 탭하면 수정, 메뉴에서 삭제
// =====================================================================

class _LogCard extends ConsumerWidget {
  const _LogCard({required this.log});
  final SelfWorkoutLog log;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _edit(context, ref),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.event_note_outlined,
                      size: 18, color: colors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      formatKoreanDate(log.loggedAt),
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  _CardMenu(
                    onEdit: () => _edit(context, ref),
                    onDelete: () => _confirmDelete(context, ref),
                  ),
                ],
              ),
              if ((log.workout ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.fitness_center,
                        size: 16, color: colors.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(log.workout!,
                          style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ],
              if ((log.note ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.healing_outlined,
                        size: 16, color: colors.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        log.note!,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final saved = await showSelfLogEditorDialog(context, existing: log);
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('기록을 수정했어요.')));
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('기록 삭제'),
        content: const Text('이 운동 기록을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    await ref.read(selfLogControllerProvider.notifier).remove(log.id);
    if (!context.mounted) return;
    final state = ref.read(selfLogControllerProvider);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(state.hasError
            ? (state.error?.toString() ?? '삭제에 실패했습니다.')
            : '기록을 삭제했어요.'),
      ));
  }
}

class _CardMenu extends StatelessWidget {
  const _CardMenu({required this.onEdit, required this.onDelete});
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '메뉴',
      icon: const Icon(Icons.more_vert),
      onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'edit',
          child: ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('수정'),
            dense: true,
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline, color: Colors.red),
            title: Text('삭제', style: TextStyle(color: Colors.red)),
            dense: true,
          ),
        ),
      ],
    );
  }
}

// =====================================================================
// 비어있음 / 에러
// =====================================================================

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.edit_note_outlined, size: 64, color: colors.outline),
            const SizedBox(height: 16),
            Text(
              '아직 남긴 기록이 없어요',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '혼자 운동한 날, 어떤 동작에서 어디가 아팠고\n'
              '어떻게 했더니 나아졌는지 간단히 남겨보세요.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 48, color: colors.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              '기록을 불러오지 못했습니다.\n잠시 후 다시 시도해 주세요.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}
