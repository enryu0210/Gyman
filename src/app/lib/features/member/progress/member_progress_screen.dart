/// 회원 "변화 추이" 화면 (Phase 2 2.2, S1).
///
/// 라우트: `/member/records/progress` (내 수업 기록 하위 — 뒤로가기가 기록 화면으로).
///
/// 두 탭:
///   - **중량**: 종목을 골라 그 종목의 "수업별 최고 중량" 추이를 라인차트로.
///   - **인바디**: 체중/체지방률/골격근량 중 하나를 골라 측정 추이를 라인차트로.
///
/// 데이터는 본인 것만(RLS 위임). 차트는 의존성 없는 [SimpleLineChart].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/body_measurement.dart';
import '../../../domain/weight_trend.dart';
import 'member_progress_providers.dart';
import 'member_progress_repository.dart';
import 'simple_line_chart.dart';

class MemberProgressScreen extends ConsumerWidget {
  const MemberProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myProgressProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('변화 추이'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '중량', icon: Icon(Icons.fitness_center)),
              Tab(text: '인바디', icon: Icon(Icons.monitor_weight_outlined)),
            ],
          ),
        ),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorView(
            onRetry: () => ref.invalidate(myProgressProvider),
          ),
          data: (data) => TabBarView(
            children: [
              _WeightTab(data: data),
              _BodyTab(data: data),
            ],
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// 중량 탭 — 종목 선택 + 최고중량 추이
// =====================================================================

class _WeightTab extends StatefulWidget {
  const _WeightTab({required this.data});
  final ProgressData data;

  @override
  State<_WeightTab> createState() => _WeightTabState();
}

class _WeightTabState extends State<_WeightTab> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!widget.data.hasWeightData) {
      return const _EmptyView(
        icon: Icons.fitness_center,
        message: '아직 운동 기록이 없습니다.\n수업이 쌓이면 종목별 중량 변화를 볼 수 있어요.',
      );
    }

    // 종목별 시계열 + 빈도순 종목 목록(드롭다운 정렬).
    final trends = WeightTrendCalculator.byExercise(widget.data.workouts);
    final names = WeightTrendCalculator.exercisesByFrequency(widget.data.workouts);

    if (names.isEmpty) {
      return const _EmptyView(
        icon: Icons.fitness_center,
        message: '중량이 기록된 운동이 없습니다.\n무게를 입력한 수업이 있으면 추이가 표시됩니다.',
      );
    }

    // 선택값이 없거나 더 이상 목록에 없으면 가장 자주 한 종목으로 기본 선택.
    final selected = (_selected != null && names.contains(_selected))
        ? _selected!
        : names.first;
    final points = trends[selected] ?? const <TrendPoint>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        DropdownButtonFormField<String>(
          initialValue: selected,
          decoration: const InputDecoration(
            labelText: '종목',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.list_alt),
          ),
          items: [
            for (final n in names) DropdownMenuItem(value: n, child: Text(n)),
          ],
          onChanged: (v) => setState(() => _selected = v),
        ),
        const SizedBox(height: 8),
        _TrendSummary(points: points, unit: 'kg', theme: theme),
        const SizedBox(height: 8),
        _ChartCard(
          title: '$selected 최고 중량',
          points: points,
          unit: 'kg',
        ),
        const SizedBox(height: 8),
        Text(
          '각 점은 그날 수업에서 해당 종목으로 든 가장 무거운 무게입니다.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// =====================================================================
// 인바디 탭 — 지표 선택 + 측정 추이
// =====================================================================

/// 인바디 그래프로 볼 수 있는 지표.
enum _BodyMetric { weight, fat, muscle }

extension _BodyMetricX on _BodyMetric {
  String get label => switch (this) {
        _BodyMetric.weight => '체중',
        _BodyMetric.fat => '체지방률',
        _BodyMetric.muscle => '골격근량',
      };

  String get unit => switch (this) {
        _BodyMetric.weight => 'kg',
        _BodyMetric.fat => '%',
        _BodyMetric.muscle => 'kg',
      };

  /// 측정 1건에서 이 지표 값(미측정이면 null).
  double? valueOf(BodyMeasurement m) => switch (this) {
        _BodyMetric.weight => m.weightKg,
        _BodyMetric.fat => m.bodyFatPct,
        _BodyMetric.muscle => m.skeletalMuscleKg,
      };
}

class _BodyTab extends StatefulWidget {
  const _BodyTab({required this.data});
  final ProgressData data;

  @override
  State<_BodyTab> createState() => _BodyTabState();
}

class _BodyTabState extends State<_BodyTab> {
  _BodyMetric _metric = _BodyMetric.weight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!widget.data.hasBodyData) {
      return const _EmptyView(
        icon: Icons.monitor_weight_outlined,
        message: '아직 인바디 측정 기록이 없습니다.\n트레이너가 측정값을 입력하면 변화 추이가 표시됩니다.',
      );
    }

    // 선택 지표의 측정 시계열(미측정 시점은 제외 — 가짜 0/하락 방지).
    final points = <TrendPoint>[
      for (final m in widget.data.measurements)
        if (_metric.valueOf(m) != null)
          TrendPoint(date: m.measuredAt, value: _metric.valueOf(m)!),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // 지표 선택 칩.
        Wrap(
          spacing: 8,
          children: [
            for (final metric in _BodyMetric.values)
              ChoiceChip(
                label: Text(metric.label),
                selected: _metric == metric,
                onSelected: (_) => setState(() => _metric = metric),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (points.isEmpty)
          _EmptyView(
            icon: Icons.show_chart,
            message: '${_metric.label} 측정값이 없습니다.\n다른 지표를 선택하거나 트레이너에게 측정을 요청하세요.',
            embedded: true,
          )
        else ...[
          _TrendSummary(points: points, unit: _metric.unit, theme: theme),
          const SizedBox(height: 8),
          _ChartCard(
            title: '${_metric.label} 추이',
            points: points,
            unit: _metric.unit,
          ),
        ],
      ],
    );
  }
}

// =====================================================================
// 공용 위젯
// =====================================================================

/// 차트를 감싸는 카드.
class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.points,
    required this.unit,
  });

  final String title;
  final List<TrendPoint> points;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(title, style: theme.textTheme.titleSmall),
            ),
            const SizedBox(height: 8),
            SimpleLineChart(points: points, unit: unit),
          ],
        ),
      ),
    );
  }
}

/// 최신값 + 시작 대비 변화량을 한 줄로 요약.
class _TrendSummary extends StatelessWidget {
  const _TrendSummary({
    required this.points,
    required this.unit,
    required this.theme,
  });

  final List<TrendPoint> points;
  final String unit;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();

    final latest = points.last.value;
    final first = points.first.value;
    final diff = latest - first;
    final colors = theme.colorScheme;

    // 증가/감소/유지 — 색은 가치판단 없이 중립(체중↓이 목표일 수도, 근육↑이 목표일 수도).
    final (arrow, diffColor) = diff > 0
        ? ('▲', colors.primary)
        : diff < 0
            ? ('▼', colors.tertiary)
            : ('–', colors.onSurfaceVariant);

    return Row(
      children: [
        Text(
          '현재 ${_n(latest)}$unit',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 12),
        if (points.length > 1)
          Text(
            '$arrow ${_n(diff.abs())}$unit (처음 대비)',
            style: theme.textTheme.bodyMedium?.copyWith(color: diffColor),
          ),
      ],
    );
  }

  static String _n(double v) {
    final r = (v * 10).round() / 10;
    return r == r.roundToDouble() ? r.toInt().toString() : r.toString();
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({
    required this.icon,
    required this.message,
    this.embedded = false,
  });

  final IconData icon;
  final String message;

  /// true면 리스트 안에 끼워 넣는 형태(중앙정렬 미사용).
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 48, color: colors.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
        ),
      ],
    );
    if (embedded) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 32), child: content);
    }
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: content));
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
              '추이 데이터를 불러오지 못했습니다.\n잠시 후 다시 시도해 주세요.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ),
      ),
    );
  }
}
