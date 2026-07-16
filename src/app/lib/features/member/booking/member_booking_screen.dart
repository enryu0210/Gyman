/// 회원 예약 신청 화면 (회원 로드맵 ⑤).
///
/// 라우트: `/member/booking`
///
/// **구성:**
///   1. "새 예약 신청" 버튼 → [showRequestBookingDialog]
///   2. 승인 대기(requested) 목록 — 각 항목 철회 가능
///   3. 확정 예정(scheduled, 지금 이후) 목록 — 읽기 전용
///
/// 트레이너가 승인하면 requested → scheduled 로 바뀌어 "확정 예정"으로 이동한다.
/// 거절하면 신청이 사라진다(별도 알림 없음 — 베타 단순화).
///
/// 날짜 표기는 `core/util/date_format_ko.dart` 공용 헬퍼 사용.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/util/date_format_ko.dart';
import '../../../core/widgets/async_state_views.dart';
import '../../../core/widgets/session_status_badge.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/session.dart';
import 'member_booking_providers.dart';
import 'request_booking_dialog.dart';

class MemberBookingScreen extends ConsumerWidget {
  const MemberBookingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myBookingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('예약 신청')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openRequestDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('새 예약 신청'),
      ),
      body: async.when(
        loading: () => const AppLoadingView(),
        error: (e, _) => AppErrorView(
          message: '예약 정보를 불러오지 못했습니다.\n잠시 후 다시 시도해 주세요.',
          onRetry: () => ref.invalidate(myBookingsProvider),
        ),
        data: (bookings) {
          // requested(승인 대기) / 확정 예정(scheduled, 지금 이후)로 분리.
          final now = DateTime.now();
          final pending = bookings
              .where((s) => s.status == SessionStatus.requested)
              .toList(growable: false);
          final confirmed = bookings
              .where((s) =>
                  s.status == SessionStatus.scheduled &&
                  s.scheduledAt.isAfter(now))
              .toList(growable: false);

          if (pending.isEmpty && confirmed.isEmpty) {
            return const _EmptyView();
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myBookingsProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                if (pending.isNotEmpty) ...[
                  const _SectionTitle('승인 대기'),
                  const SizedBox(height: 8),
                  for (final s in pending)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _PendingCard(session: s),
                    ),
                  const SizedBox(height: 8),
                ],
                if (confirmed.isNotEmpty) ...[
                  const _SectionTitle('확정 예정'),
                  const SizedBox(height: 8),
                  for (final s in confirmed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ConfirmedCard(session: s),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openRequestDialog(BuildContext context) async {
    final ok = await showRequestBookingDialog(context);
    if (ok == true && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('예약을 신청했습니다. 트레이너 승인을 기다려 주세요.')),
        );
    }
  }
}

// =====================================================================
// 섹션 제목
// =====================================================================

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

// =====================================================================
// 승인 대기 카드 — 철회 가능
// =====================================================================

class _PendingCard extends ConsumerWidget {
  const _PendingCard({required this.session});
  final Session session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final withdrawing =
        ref.watch(memberBookingControllerProvider).isLoading;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              // 공용 세션 상태 배지(밝기 대응) — amber 하드코딩 대신.
              child: SessionStatusBadge(status: SessionStatus.requested),
            ),
            const SizedBox(height: 10),
            Text(
              formatKoreanDateTime(session.scheduledAt),
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            if ((session.statusMemo ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                session.statusMemo!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed:
                    withdrawing ? null : () => _withdraw(context, ref),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('신청 취소'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _withdraw(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('신청 취소'),
        content: const Text('이 예약 신청을 취소할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('닫기'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('신청 취소'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    await ref
        .read(memberBookingControllerProvider.notifier)
        .withdraw(session.id);
    if (!context.mounted) return;
    final state = ref.read(memberBookingControllerProvider);
    final msg = state.hasError
        ? (state.error?.toString() ?? '취소에 실패했습니다.')
        : '신청을 취소했습니다.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }
}

// =====================================================================
// 확정 예정 카드 — 읽기 전용
// =====================================================================

class _ConfirmedCard extends StatelessWidget {
  const _ConfirmedCard({required this.session});
  final Session session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.event_available, size: 18, color: colors.primary),
                const SizedBox(width: 6),
                Text(
                  '확정',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: colors.primary),
                ),
                const Spacer(),
                Text(
                  untilLabel(session.scheduledAt),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              formatKoreanDateTime(session.scheduledAt),
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            if ((session.statusMemo ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                session.statusMemo!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// 빈/에러 뷰
// =====================================================================

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // ListView 로 감싸 당겨서 새로고침이 빈 상태에서도 동작하게.
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 80),
        Icon(Icons.event_note_outlined, size: 56, color: colors.outline),
        const SizedBox(height: 16),
        Text(
          '신청한 예약이 없습니다.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          '아래 [새 예약 신청] 으로 원하는 시간을 신청해 보세요.\n'
          '트레이너가 승인하면 확정됩니다.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

