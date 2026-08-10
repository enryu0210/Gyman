/// 회원 출석 달력 — PT/셀프 색 구분 + PT 시작 시간 표기, 전체 기간 조회.
///
/// 라우트: `/member/attendance`. 회원 홈에서 push 진입.
///
/// **운톡 대비 포인트:**
///   - #3 "일주일만 조회" → 이전/다음 달 자유 이동(과거 무제한, 미래는 예약이
///     잡힌 달까지 — 다가올 PT 를 미리 본다).
///   - #4 "달력 UI 버그(말일 안 보임)" → 월 경계(시작 요일·말일)를 DateTime 산술로
///     정확히 계산하고, 빈 칸/말일까지 항상 채운다(U2 견고성).
///
/// **표기 규칙:**
///   - PT 완료 = 채운 파랑 점, PT 예정(예약) = 빈 파랑 점, 셀프 운동 = 주황 점.
///   - PT 가 있는 날은 날짜 아래에 **가장 이른 PT 시작 시간**(예: `14:00`)을 표기.
///     같은 날 PT 가 2건 이상이면 `14:00 외`. 셀프는 시각 미저장이라 시간 표기 없음.
///
/// **의존성 0:** table_calendar 등 외부 패키지 없이 커스텀 월 그리드로 그린다
///   (develop_plan §0 의존성 고정 유지, 렌더 버그 통제 용이).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/util/date_format_ko.dart';
import '../../../core/widgets/async_state_views.dart';
import 'member_attendance_providers.dart';
import 'member_attendance_repository.dart';

/// 일~토 헤더 라벨(intl ko 미초기화 대비 리터럴 — CLAUDE.md).
const _weekdayLabels = ['일', '월', '화', '수', '목', '금', '토'];

/// PT=파랑 / 셀프=주황. 셀·시트·범례가 공유하는 색 상수.
const _ptColor = Color(0xFF4F8EF7);
const _selfColor = Color(0xFFFF6B35);

/// 날짜 셀 높이 — 날짜 + 점 + PT 시간 한 줄을 담는다(시간 표기로 살짝 키움).
const _cellHeight = 66.0;

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

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(attendanceDataProvider);

    return Scaffold(
      // 회원 셸의 "일정" 탭 루트 — 지난 출석과 다가올 PT 를 한 화면에서 본다.
      appBar: AppBar(title: const Text('일정')),
      // 예약 신청은 가끔 하는 **동작**이라 탭이 아닌 버튼으로 둔다. 아이콘만으론
      // 회원이 못 찾을 수 있어(예약은 회원의 핵심 행동) 라벨 있는 FAB 로.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/member/booking');
          // 예약을 신청/철회하고 돌아오면 달력의 예정 표시가 달라진다.
          ref.invalidate(attendanceDataProvider);
        },
        icon: const Icon(Icons.event_available_outlined),
        label: const Text('예약 신청'),
      ),
      body: async.when(
        loading: () => const AppLoadingView(),
        error: (e, _) => AppErrorView(
          message: '출석 기록을 불러오지 못했습니다.\n잠시 후 다시 시도해 주세요.',
          onRetry: () => ref.invalidate(attendanceDataProvider),
        ),
        data: (data) {
          // 미래로는 예약이 잡힌 달까지만 넘어갈 수 있게(빈 미래 무한 이동 방지).
          final canGoNext = _month.isBefore(data.latestMonthWithSchedule);
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(attendanceDataProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _MonthHeader(
                  month: _month,
                  onPrev: () => _shiftMonth(-1),
                  onNext: canGoNext ? () => _shiftMonth(1) : null,
                ),
                const SizedBox(height: 12),
                _WeekdayHeader(),
                const SizedBox(height: 4),
                _MonthGrid(month: _month, data: data),
                const SizedBox(height: 20),
                const _Legend(),
              ],
            ),
          );
        },
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
    required this.onPrev,
    required this.onNext,
  });

  final DateTime month;
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
          // 예약 잡힌 달 이후로는 못 가게 — onNext 가 null 이면 비활성.
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
                      ? const SizedBox(height: _cellHeight)
                      : _DayCell(
                          date: DateTime(month.year, month.month, day),
                          ptEntries: data
                              .ptOn(DateTime(month.year, month.month, day)),
                          hasSelf: data
                              .hasSelf(DateTime(month.year, month.month, day)),
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
    required this.ptEntries,
    required this.hasSelf,
  });

  final DateTime date;
  final List<PtEntry> ptEntries;
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
    final hasDonePt = ptEntries.any((p) => p.done);
    final hasScheduledPt = ptEntries.any((p) => !p.done);
    final attended = ptEntries.isNotEmpty || hasSelf;

    // A안: 그날 가장 이른 PT 시작 시간 표기. 2건 이상이면 '외' 덧붙임.
    // ptEntries 는 repository 에서 시각 오름차순 정렬되어 있어 first 가 가장 이름.
    String? timeLabel;
    if (ptEntries.isNotEmpty) {
      timeLabel = formatHm(ptEntries.first.at);
      if (ptEntries.length > 1) timeLabel = '$timeLabel 외';
    }

    // 점: PT 완료(채운 파랑) / PT 예정(빈 파랑) / 셀프(주황). 사이 간격 3.
    final dots = <Widget>[
      if (hasDonePt) const _Dot(color: _ptColor),
      if (hasScheduledPt) const _Dot(color: _ptColor, filled: false),
      if (hasSelf) const _Dot(color: _selfColor),
    ];

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: attended
          ? () => _showDaySheet(context, date,
              ptEntries: ptEntries, hasSelf: hasSelf)
          : null,
      child: SizedBox(
        height: _cellHeight,
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < dots.length; i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  dots[i],
                ],
              ],
            ),
            // A안 — PT 시작 시간(없으면 자리 비움).
            if (timeLabel != null) ...[
              const SizedBox(height: 2),
              Text(
                timeLabel,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: const TextStyle(
                  fontSize: 10,
                  height: 1.0,
                  color: _ptColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, this.filled = true});
  final Color color;

  /// false 면 외곽선만 있는 빈 점(예정 PT 구분).
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: filled ? color : null,
        shape: BoxShape.circle,
        border: filled ? null : Border.all(color: color, width: 1.2),
      ),
    );
  }
}

// 날짜 탭 시 그날 출석 상세 시트 — PT 는 시작 시간·완료/예정, 셀프는 한 줄.
void _showDaySheet(
  BuildContext context,
  DateTime date, {
  required List<PtEntry> ptEntries,
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
          for (final p in ptEntries)
            _DaySheetRow(
              color: _ptColor,
              filled: p.done,
              label: '${formatHm(p.at)} PT 수업 · ${p.done ? '완료' : '예정'}',
            ),
          if (hasSelf)
            const _DaySheetRow(color: _selfColor, label: '셀프 운동'),
        ],
      ),
    ),
  );
}

class _DaySheetRow extends StatelessWidget {
  const _DaySheetRow({
    required this.color,
    required this.label,
    this.filled = true,
  });
  final Color color;
  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          _Dot(color: color, filled: filled),
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
    // 항목이 3개라 좁은 폭에서 줄바꿈되도록 Wrap 사용.
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 18,
      runSpacing: 6,
      children: [
        _LegendItem(dot: const _Dot(color: _ptColor), label: 'PT 완료', style: style),
        _LegendItem(
            dot: const _Dot(color: _ptColor, filled: false),
            label: 'PT 예정',
            style: style),
        _LegendItem(
            dot: const _Dot(color: _selfColor), label: '셀프 운동', style: style),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.dot,
    required this.label,
    required this.style,
  });
  final Widget dot;
  final String label;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot,
        const SizedBox(width: 6),
        Text(label, style: style),
      ],
    );
  }
}

