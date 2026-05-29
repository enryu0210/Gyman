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

import '../../../domain/models/enums.dart';
import '../session_log/booking_status_sheet.dart';
import '../session_log/session_providers.dart';
import '../session_log/session_repository.dart';

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
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorView(
                error: e,
                onRetry: () =>
                    ref.invalidate(trainerBookingsProvider(_range)),
              ),
              data: (list) {
                if (list.isEmpty) return const _EmptyView();
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
    final (label, bg, fg) = _statusStyle(s.status, colors);

    return InkWell(
      onTap: () => showBookingStatusSheet(
        context,
        session: s,
        memberId: row.memberId,
        memberName: row.memberName,
      ),
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// recent_sessions_section 과 일관된 색 — 한 곳에 모아두는 게 이상적이지만
  /// 양쪽 다 좁은 책임이라 일단 복제. 색 톤 바꿀 일이 생기면 한 곳으로 통합.
  static (String, Color, Color) _statusStyle(
    SessionStatus s,
    ColorScheme colors,
  ) {
    switch (s) {
      case SessionStatus.done:
        return ('완료', colors.primaryContainer, colors.onPrimaryContainer);
      case SessionStatus.scheduled:
        return ('예약', colors.surfaceContainerHighest, colors.onSurfaceVariant);
      case SessionStatus.noShow:
        return ('노쇼', Colors.red.shade100, Colors.red.shade800);
      case SessionStatus.canceled:
        return ('취소', colors.surfaceContainerHighest, colors.onSurfaceVariant);
      case SessionStatus.lateCancel:
        return ('지각취소', Colors.orange.shade100, Colors.orange.shade900);
    }
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_note_outlined, size: 64, color: colors.outline),
            const SizedBox(height: 12),
            Text(
              '선택한 범위에 예약이 없습니다',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '회원 상세에서 [예약 등록] 으로 새 예약을 잡거나,\n'
              '다른 범위를 선택해 주세요.',
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
  const _ErrorView({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(
              '예약을 불러오지 못했습니다\n$error',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ),
      ),
    );
  }
}
