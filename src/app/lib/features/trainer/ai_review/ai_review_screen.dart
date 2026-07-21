/// AI 검수 허브 화면 (Phase 1.9, 와이어 6.1).
///
/// 라우트: `/trainer/ai-review`
///
/// **현재 범위 (검수 게이트 — 메시지):**
///   회원 안내 메시지 초안(draft) + 승인됨(approved, 과거 데이터)을 카드로 나열.
///   카드 탭 → [showMessageReviewDialog] 로 승인·발송/수정/취소.
///   "모두 발송" 일괄 처리 제공.
///   신규 흐름은 draft → (승인하고 발송) sent 로 한 번에. sent 는 회원 "받은 안내"에 노출.
///   발송은 FCM 없이 in-app(sent 전이 → 회원 RLS 노출).
///
/// **아직 없음:**
///   - 메모 초안 검수(AI-C) → 1.10
///   - AI 생성 자체(LLM) → Edge Function 배포 후
///
/// 와이어프레임 출처: docs/wireframes/06_ai_review.md 화면 6.1.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/async_state_views.dart';
import '../../../domain/models/enums.dart';
import 'ai_review_providers.dart';
import 'ai_review_repository.dart';
import 'message_review_dialog.dart';

class AiReviewScreen extends ConsumerWidget {
  const AiReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pendingMessagesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 검수'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(pendingMessagesProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => const AppLoadingView(),
        error: (e, _) => AppErrorView(
          message: '검수 목록을 불러오지 못했습니다.',
          detail: e.toString(),
          onRetry: () => ref.invalidate(pendingMessagesProvider),
        ),
        data: (list) {
          if (list.isEmpty) return const _EmptyView();
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(pendingMessagesProvider),
            child: _MessageList(items: list),
          );
        },
      ),
    );
  }
}

// =====================================================================
// 리스트 + 일괄 처리
// =====================================================================

class _MessageList extends ConsumerWidget {
  const _MessageList({required this.items});
  final List<MessageDraft> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 검수 대기(draft) 가 위로, 승인 대기(approved) 가 아래로.
    final drafts =
        items.where((m) => m.status == NotificationStatus.draft).toList();
    final approved =
        items.where((m) => m.status == NotificationStatus.approved).toList();
    final busy = ref.watch(messageReviewControllerProvider).isLoading;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // 상단 요약 + 일괄 승인
        Row(
          children: [
            Text(
              '검수 대기 ${drafts.length} · 승인 대기 ${approved.length}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const Spacer(),
            if (drafts.isNotEmpty)
              TextButton.icon(
                onPressed: busy
                    ? null
                    : () => _confirmSendAll(context, ref, drafts),
                icon: const Icon(Icons.done_all, size: 18),
                label: const Text('모두 발송'),
              ),
          ],
        ),
        const SizedBox(height: 4),

        if (drafts.isNotEmpty) ...[
          _SectionLabel(text: '검수 대기'),
          for (final m in drafts) _MessageCard(draft: m),
        ],
        if (approved.isNotEmpty) ...[
          const SizedBox(height: 8),
          _SectionLabel(text: '승인됨 — 탭하여 발송'),
          for (final m in approved) _MessageCard(draft: m),
        ],
      ],
    );
  }

  /// "모두 발송" — 실수 방지로 확인 후 일괄 승인+발송(회원에게 즉시 전달).
  Future<void> _confirmSendAll(
    BuildContext context,
    WidgetRef ref,
    List<MessageDraft> drafts,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('모두 발송'),
        content: Text('검수 대기 ${drafts.length}건을 승인하고 회원에게 바로 발송할까요?\n'
            '내용을 개별 확인하지 않고 발송됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('모두 발송'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await ref.read(messageReviewControllerProvider.notifier).approveAndSendMany(
          drafts.map((m) => m.id).toList(growable: false),
        );
    if (!context.mounted) return;
    final state = ref.read(messageReviewControllerProvider);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(state.hasError
            ? (state.error?.toString() ?? '일괄 발송 실패')
            : '${drafts.length}건을 발송했습니다.'),
      ));
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _MessageCard extends ConsumerWidget {
  const _MessageCard({required this.draft});
  final MessageDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final scheduled = DateFormat('M월 d일 HH:mm').format(draft.scheduledFor);
    final isApproved = draft.status == NotificationStatus.approved;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showMessageReviewDialog(context, draft: draft),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      draft.memberName,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (draft.aiGenerated)
                    _Pill(text: 'AI', color: colors.tertiaryContainer, fg: colors.onTertiaryContainer),
                  const SizedBox(width: 6),
                  _Pill(
                    text: isApproved ? '승인됨' : '검수 대기',
                    color: isApproved
                        ? colors.secondaryContainer
                        : colors.errorContainer,
                    fg: isApproved
                        ? colors.onSecondaryContainer
                        : colors.onErrorContainer,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${triggerTypeLabel(draft.triggerType)} · 발송 예정 $scheduled',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                draft.content,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  isApproved ? '발송 →' : '검수 →',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.primary,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color, required this.fg});
  final String text;
  final Color color;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// =====================================================================
// 빈/에러
// =====================================================================

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      // RefreshIndicator 가 빈 상태에서도 동작하도록 ListView 로.
      children: [
        const SizedBox(height: 120),
        Icon(Icons.mark_email_read_outlined, size: 64, color: colors.outline),
        const SizedBox(height: 12),
        Center(
          child: Text(
            '검수할 메시지가 없습니다',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            '수업 전날 안내(0016 cron)나 AI 메시지 초안이 생기면 여기에 쌓입니다.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
          ),
        ),
      ],
    );
  }
}
