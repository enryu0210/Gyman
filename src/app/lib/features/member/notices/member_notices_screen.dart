/// 회원 "받은 안내" 화면 (Phase 2 회원 로드맵 ④).
///
/// 라우트: `/member/notices`
///
/// 트레이너가 검수·발송(sent)한 안내만 최신순 카드로 보여준다(읽기 전용).
/// 별도 푸시 없이, 트레이너가 발송하는 순간 RLS로 여기에 나타난다.
///
/// 날짜 표기는 `core/util/date_format_ko.dart`(수동 포맷) 공용 헬퍼 사용.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/util/date_format_ko.dart';
import '../../../core/widgets/async_state_views.dart';
import 'member_notices_repository.dart';
import 'member_notices_providers.dart';

class MemberNoticesScreen extends ConsumerWidget {
  const MemberNoticesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myNoticesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('받은 안내')),
      body: async.when(
        loading: () => const AppLoadingView(),
        error: (e, _) => AppErrorView(
          message: '안내를 불러오지 못했습니다.\n잠시 후 다시 시도해 주세요.',
          onRetry: () => ref.invalidate(myNoticesProvider),
        ),
        data: (notices) {
          if (notices.isEmpty) {
            return const AppEmptyView(
              icon: Icons.mark_email_read_outlined,
              message: '아직 받은 안내가 없습니다.\n트레이너가 안내를 보내면 여기에 표시됩니다.',
            );
          }
          final unread = notices.where((n) => !n.isRead).length;
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myNoticesProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                if (unread > 0) _UnreadHeader(count: unread),
                for (final n in notices) ...[
                  _NoticeCard(notice: n),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 목록 맨 위 "안읽음 N개" 요약 — 몇 건이 새로 왔는지 한눈에.
class _UnreadHeader extends StatelessWidget {
  const _UnreadHeader({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        '안읽음 $count개',
        // 강조 텍스트는 primary(라이트=잉크/다크=볼트) — DESIGN.md 대비 규칙.
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// 안내 카드. **안읽음이면 강조**(강조색 점 + 테두리), 탭하면 읽음 처리.
/// 읽음 카드는 탭 대상 아님(할 일 없음) — 체크 아이콘으로 구분.
class _NoticeCard extends ConsumerWidget {
  const _NoticeCard({required this.notice});
  final MemberNotice notice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final sentLabel = notice.sentAt == null
        ? ''
        : formatKoreanDateTime(notice.sentAt!);
    final unread = !notice.isRead;

    return Card(
      margin: EdgeInsets.zero,
      // 안읽음은 강조색 테두리로 살짝 띄운다. 읽음은 기본 카드.
      shape: unread
          ? RoundedRectangleBorder(
              side: BorderSide(color: colors.primary.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        // 안읽음일 때만 탭 → 읽음 처리. 읽음은 no-op(ripple 없음).
        onTap: unread
            ? () => ref
                .read(noticeReadControllerProvider.notifier)
                .markRead(notice.id)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (unread)
                    // 안읽음 점(강조색 fill).
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: colors.primary,
                        shape: BoxShape.circle,
                      ),
                    )
                  else
                    Icon(Icons.check, size: 16, color: colors.onSurfaceVariant),
                  const SizedBox(width: 8),
                  _CategoryPill(label: memberNoticeLabel(notice.triggerType)),
                  const Spacer(),
                  if (sentLabel.isNotEmpty)
                    Text(
                      sentLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(notice.content, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: colors.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// =====================================================================
// 빈/에러 뷰
// =====================================================================

