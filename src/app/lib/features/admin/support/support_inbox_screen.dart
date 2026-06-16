/// 운영자 문의함 화면 — 사용자 문의 확인·처리 (`/admin/support`).
///
/// 관리자 대시보드에서 push 진입. 미처리(open) 문의가 위에, 처리완료는 아래에.
/// '처리완료' 버튼으로 상태를 바꾼다(본문은 수정하지 않음).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/util/date_format_ko.dart';
import 'support_inbox_providers.dart';
import 'support_inbox_repository.dart';

class SupportInboxScreen extends ConsumerWidget {
  const SupportInboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(supportInquiriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('문의함')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(
          onRetry: () => ref.invalidate(supportInquiriesProvider),
        ),
        data: (items) {
          if (items.isEmpty) return const _EmptyView();
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(supportInquiriesProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _InquiryCard(item: items[i]),
            ),
          );
        },
      ),
    );
  }
}

class _InquiryCard extends ConsumerWidget {
  const _InquiryCard({required this.item});
  final SupportInquiry item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final busy = ref.watch(markInquiryHandledControllerProvider).isLoading;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StatusChip(isOpen: item.isOpen),
                const SizedBox(width: 8),
                if (item.role != null)
                  Text(
                    _roleLabel(item.role!),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                const Spacer(),
                if (item.createdAt != null)
                  Text(
                    formatKoreanDateTime(item.createdAt!),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(item.message, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                if (item.appVersion != null)
                  Text(
                    'v${item.appVersion}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                const Spacer(),
                if (item.isOpen)
                  TextButton.icon(
                    onPressed: busy
                        ? null
                        : () => ref
                            .read(markInquiryHandledControllerProvider.notifier)
                            .markHandled(item.id),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('처리완료'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _roleLabel(String role) {
    switch (role) {
      case 'trainer':
        return '트레이너';
      case 'member':
        return '회원';
      case 'admin':
        return '관리자';
      default:
        return role;
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.isOpen});
  final bool isOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bg = isOpen ? colors.errorContainer : colors.surfaceContainerHighest;
    final fg = isOpen ? colors.onErrorContainer : colors.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        isOpen ? '미처리' : '처리완료',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: colors.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              '들어온 문의가 없습니다.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('문의를 불러오지 못했습니다.\n잠시 후 다시 시도해 주세요.',
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ),
      ),
    );
  }
}
