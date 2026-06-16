/// 회원 출석 달력 — PT/셀프 색 구분, 전체 기간 조회 (운톡 불만 #3·#4 대응).
///
/// 라우트: `/member/attendance`. 회원 홈에서 push 진입.
///
/// **운톡 대비 포인트:**
///   - #3 "일주일만 조회" → 이전/다음 달 자유 이동(과거 무제한, 미래는 이번 달까지).
///   - #4 "달력 UI 버그(말일 안 보임)" → 월 경계(시작 요일·말일)를 DateTime 산술로
///     정확히 계산하고, 빈 칸/말일까지 항상 채운다(U2 견고성).
///
/// **의존성 0:** table_calendar 등 외부 패키지 없이 커스텀 월 그리드로 그린다
///   (develop_plan §0 의존성 고정 유지, 렌더 버그 통제 용이).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/util/date_format_ko.dart';
import 'member_attendance_providers.dart';
import 'member_attendance_repository.dart';

/// 일~토 헤더 라벨(intl ko 미초기화 대비 리터럴 — CLAUDE.md).
const _weekdayLabels = ['일', '월', '화', '수', '목', '금', '토'];

class AttendanceCalendarScreen extends ConsumerStatefulWidget {
  const AttendanceCalendarScreen({super.key});

  @override
  ConsumerState<AttendanceCalendarScreen> createState() =>
      _AttendanceCalendarScreenState();
}

class _AttendanceCalendarScreenState
    extends ConsumerState<AttendanceCalendarScreen> {
  /// 현재 보고 있는 달(해당 월 1일).
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  /// 다음 달로 이동 가능한가 — 이번 달 이후(미래)는 막는다.
  bool get _canGoNext {
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month);
    return _month.isBefore(thisMonth);
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(attendanceDataProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('출석 달력')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(
          onRetry: () => ref.invalidate(attendanceDataProvider),
        ),
        data: (data) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(attendanceDataProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _MonthHeader(
                month: _month,
                canGoNext: _canGoNext,
                onPrev: () => _shiftMonth(-1),
                onNext: _canGoNext ? () => _shiftMonth(1) : null,
              ),
              const SizedBox(height: 12),
              _WeekdayHeader(),
              const SizedBox(height: 4),
              _MonthGrid(month: _month, data: data),
              const SizedBox(height: 20),
              const _Legend(),
            ],
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// 월 헤더 (이전/다음)
// =====================================================================

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.canGoNext,
    required this.onPrev,
    required this.onNext,
  });

  final DateTime month;
  final bool canGoNext;
  final VoidCallback onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          tooltip: '이전 달',
          icon: const Icon(Icons.chevron_left),
          onPressed: onPrev,
        ),
        Text(
          '${month.year}년 ${month.month}월',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        IconButton(
          tooltip: '다음 달',
          icon: const Icon(Icons.chevron_right),
          // 미래 달로는 못 가게 — onNext 가 null 이면 비활성.
          onPressed: onNext,
        ),
      ],
    );
  }
}

// =====================================================================
// 요일 헤더
// =====================================================================

class _WeekdayHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Center(
              child: Text(
                _weekdayLabels[i],
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      // 일요일 빨강, 토요일 파랑 — 한국 달력 관습.
                      color: i == 0
                          ? colors.error
                          : i == 6
                              ? colors.primary
                              : colors.onSurfaceVariant,
                    ),
              ),
            ),
          ),
      ],
    );
  }
}

// =====================================================================
// 월 그리드 — 주 단위 Row 들로 정확히 채운다
// =====================================================================

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.month, required this.data});

  final DateTime month;
  final AttendanceData data;

  @override
  Widget build(BuildContext context) {
    // 그 달 1일의 요일(월=1..일=7) → 일요일 시작 칼럼 기준 앞 빈칸 수.
    final firstWeekday = DateTime(month.year, month.month, 1).weekday;
    final leadingBlanks = firstWeekday % 7; // 일(7)→0, 월(1)→1, ... 토(6)→6
    // 말일 — 다음 달 0일 = 이번 달 마지막 날(연 경계도 안전).
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;

    // null(빈칸) + 1..daysInMonth 셀 목록을 만들고 7개씩 끊어 주를 만든다.
    final cells = <int?>[
      ...List<int?>.filled(leadingBlanks, null),
      for (var day = 1; day <= daysInMonth; day++) day,
    ];
    // 마지막 주를 7칸으로 채워(말일 잘림 방지).
    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    final weeks = <List<int?>>[
      for (var i = 0; i < cells.length; i += 7) cells.sublist(i, i + 7),
    ];

    return Column(
      children: [
        for (final week in weeks)
          Row(
            children: [
              for (final day in week)
                Expanded(
                  child: day == null
                      ? const SizedBox(height: 56)
                      : _DayCell(
                          date: DateTime(month.year, month.month, day),
                          hasPt: data.hasPt(
                              DateTime(month.year, month.month, day)),
                          hasSelf: data.hasSelf(
                              DateTime(month.year, month.month, day)),
                        ),
                ),
            ],
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.hasPt,
    required this.hasSelf,
  });

  final DateTime date;
  final bool hasPt;
  final bool hasSelf;

  bool get _isToday {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final attended = hasPt || hasSelf;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: attended
          ? () => _showDaySheet(context, date, hasPt: hasPt, hasSelf: hasSelf)
          : null,
      child: SizedBox(
        height: 56,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: _isToday
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.primary, width: 1.5),
                    )
                  : null,
              child: Text(
                '${date.day}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight:
                          _isToday ? FontWeight.w700 : FontWeight.w400,
                    ),
              ),
            ),
            const SizedBox(height: 3),
            // PT=파랑, 셀프=주황 점. 둘 다면 둘 다 표시.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (hasPt) const _Dot(color: Color(0xFF4F8EF7)),
                if (hasPt && hasSelf) const SizedBox(width: 3),
                if (hasSelf) const _Dot(color: Color(0xFFFF6B35)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

// 날짜 탭 시 그날 출석 종류 요약 시트.
void _showDaySheet(
  BuildContext context,
  DateTime date, {
  required bool hasPt,
  required bool hasSelf,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatKoreanDate(date),
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (hasPt)
            const _DaySheetRow(color: Color(0xFF4F8EF7), label: 'PT 수업'),
          if (hasSelf)
            const _DaySheetRow(color: Color(0xFFFF6B35), label: '셀프 운동'),
        ],
      ),
    ),
  );
}

class _DaySheetRow extends StatelessWidget {
  const _DaySheetRow({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          _Dot(color: color),
          const SizedBox(width: 10),
          Text(label, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}

// =====================================================================
// 범례 / 에러
// =====================================================================

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const _Dot(color: Color(0xFF4F8EF7)),
        const SizedBox(width: 6),
        Text('PT 수업', style: style),
        const SizedBox(width: 20),
        const _Dot(color: Color(0xFFFF6B35)),
        const SizedBox(width: 6),
        Text('셀프 운동', style: style),
      ],
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
            const Text('출석 기록을 불러오지 못했습니다.\n잠시 후 다시 시도해 주세요.',
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ),
      ),
    );
  }
}
