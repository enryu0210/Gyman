/// 트레이너 본인 예약 리스트 화면 (Phase 1.6, 화면 5.1 간소화).
///
/// 라우트: `/trainer/booking`
///
/// **간소화 결정:**
///   원 와이어(05_booking §5.1)는 월간/주간 캘린더 위젯이 있지만, Phase 1.6 에는
///   `table_calendar` 같은 dependency 를 추가하지 않고 chip 필터(오늘/내일/이번주/다음주)
///   만 제공한다. 1분 입력 UX/베타 정착이 우선이고, 캘린더 위젯은 1.7~ 정착 후 도입.
///
/// **카드 탭:** [showBookingStatusSheet] → 상태 전이.
///
/// 와이어프레임 출처: docs/wireframes/05_booking.md 화면 5.1.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/async_state_views.dart';
import '../../../domain/models/enums.dart';
import '../session_log/booking_status_sheet.dart';
import '../session_log/session_providers.dart';
import '../session_log/session_repository.dart';
import '../session_log/session_status_badge.dart';
import 'request_action_sheet.dart';

class BookingScreen extends ConsumerStatefulWidget {
  const BookingScreen({super.key});

  @override
  ConsumerState<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends ConsumerState<BookingScreen> {
  TrainerBookingRange _range = TrainerBookingRange.today;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(trainerBookingsProvider(_range));

    return Scaffold(
      appBar: AppBar(
        title: const Text('예약'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.invalidate(trainerBookingsProvider(_range)),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 승인 대기 신청 — 날짜 범위와 무관하게 항상 상단 노출.
          const _PendingRequestsSection(),
          // chip 필터 row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              spacing: 8,
              children: [
                for (final r in TrainerBookingRange.values)
                  ChoiceChip(
                    label: Text(r.label),
                    selected: _range == r,
                    onSelected: (selected) {
                      if (!selected) return;
                      setState(() => _range = r);
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: async.when(
              loading: () => const AppLoadingView(),
              error: (e, _) => AppErrorView(
                message: '예약을 불러오지 못했습니다.',
                detail: e.toString(),
                onRetry: () =>
                    ref.invalidate(trainerBookingsProvider(_range)),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return const AppEmptyView(
                    icon: Icons.event_note_outlined,
                    title: '선택한 범위에 예약이 없습니다',
                    message: '회원 상세에서 [예약 등록]으로 새 예약을 잡거나,\n'
                        '다른 범위를 선택해 주세요.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(trainerBookingsProvider(_range)),
                  child: _GroupedList(rows: list),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// 날짜별 그룹 리스트
// =====================================================================

class _GroupedList extends StatelessWidget {
  const _GroupedList({required this.rows});
  final List<TrainerBookingRow> rows;

  @override
  Widget build(BuildContext context) {
    // 날짜(yyyy-MM-dd) 기준으로 그룹.
    final groups = <String, List<TrainerBookingRow>>{};
    final keyFmt = DateFormat('yyyy-MM-dd');
    for (final r in rows) {
      final k = keyFmt.format(r.session.scheduledAt);
      groups.putIfAbsent(k, () => []).add(r);
    }
    final dateKeys = groups.keys.toList()..sort();
    final headerFmt = DateFormat('M월 d일');

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      itemCount: dateKeys.length,
      itemBuilder: (_, i) {
        final key = dateKeys[i];
        final dayRows = groups[key]!;
        final dayDate = DateTime.parse(key);
        final isToday = _isSameDay(dayDate, DateTime.now());

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 6),
              child: Row(
                children: [
                  Text(
                    '${headerFmt.format(dayDate)} (${_weekday(dayDate)})'
                    '${isToday ? ' · 오늘' : ''}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${dayRows.length}건',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            for (final r in dayRows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _BookingCard(row: r),
              ),
          ],
        );
      },
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _weekday(DateTime d) {
    const names = ['월', '화', '수', '목', '금', '토', '일'];
    return names[d.weekday - 1];
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.row});
  final TrainerBookingRow row;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final s = row.session;
    final hhmm = DateFormat('HH:mm').format(s.scheduledAt);

    return InkWell(
      // requested(승인 대기)는 승인/거절 시트, 그 외는 상태 전이 시트로 분기.
      onTap: () {
        if (s.status == SessionStatus.requested) {
          showRequestActionSheet(
            context,
            session: s,
            memberId: row.memberId,
            memberName: row.memberName,
          );
        } else {
          showBookingStatusSheet(
            context,
            session: s,
            memberId: row.memberId,
            memberName: row.memberName,
          );
        }
      },
      onLongPress: () =>
          context.push('/trainer/members/${row.memberId}'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.outlineVariant),
        ),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              child: Text(
                hhmm,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.memberName,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  if ((s.statusMemo ?? '').isNotEmpty)
                    Text(
                      s.statusMemo!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                ],
              ),
            ),
            SessionStatusBadge(status: s.status),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// 승인 대기 신청 섹션 — 날짜 범위와 무관하게 상단 고정
// =====================================================================

/// 회원이 신청(requested)한 예약을 모아 보여주는 카드.
///
/// 신청이 0건이면 아무것도 그리지 않는다(공간 차지 X). 카드 탭 → 승인/거절 시트.
class _PendingRequestsSection extends ConsumerWidget {
  const _PendingRequestsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(trainerPendingRequestsProvider);
    // 로딩/에러 시엔 조용히 비움 — 아래 예약 목록이 주 화면이므로 방해하지 않는다.
    final requests = async.maybeWhen(
      data: (list) => list,
      orElse: () => const <TrainerBookingRow>[],
    );
    if (requests.isEmpty) return const SizedBox.shrink();

    final fmt = DateFormat('M월 d일 HH:mm');

    // 승인 대기 = 주의(앰버) 블록. 밝은 shade 고정색은 다크에서 밝은 노랑 블록으로
    // 떠 깨지므로(다른 배지와 동일 함정) 밝기별로 배경/글씨를 분기한다.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final amberBg = isDark ? const Color(0xFF2A2410) : const Color(0xFFFFF6DC);
    final amberBorder =
        isDark ? const Color(0xFF4A3D18) : const Color(0xFFF6E2A0);
    final amberFg = isDark ? const Color(0xFFE7C15A) : const Color(0xFF8A6400);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: amberBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: amberBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pending_actions, size: 18, color: amberFg),
              const SizedBox(width: 6),
              Text(
                '승인 대기 ${requests.length}건',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: amberFg,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final r in requests)
            InkWell(
              onTap: () => showRequestActionSheet(
                context,
                session: r.session,
                memberId: r.memberId,
                memberName: r.memberName,
              ),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${r.memberName} · ${fmt.format(r.session.scheduledAt)}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: amberFg,
                            ),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: amberFg),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

