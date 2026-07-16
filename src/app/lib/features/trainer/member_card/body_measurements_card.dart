/// 회원 상세 "인바디 측정" 카드 (Phase 2 2.2, S1).
///
/// 구성:
///   - 상단: [측정 입력] 버튼
///   - 본문: 최근 측정 기록 목록(측정일 + 체중/체지방률/골격근량). 각 행에서 삭제 가능.
///
/// **회원에게도 보이는 데이터:** 트레이너 전용 메모와 달리 측정 수치는 객관적 사실이라
///   회원 본인이 변화 추이 그래프로 본다(0023 RLS). 그래서 "비공개" 표시를 하지 않는다.
///
/// 추가/삭제는 [bodyMeasurementControllerProvider] 경유. SnackBar 는 본 카드가,
/// 컨트롤러는 상태만 — UI/Riverpod 패턴(CLAUDE.md).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/util/date_format_ko.dart';
import '../../../domain/models/body_measurement.dart';
import 'add_body_measurement_dialog.dart';
import 'body_measurement_providers.dart';

class BodyMeasurementsCard extends ConsumerWidget {
  const BodyMeasurementsCard({
    super.key,
    required this.memberId,
    required this.memberName,
  });

  final String memberId;
  final String memberName;

  /// 최근 몇 건까지 카드에 펼쳐 보일지 — 전체는 회원 그래프에서 본다.
  static const _visibleCount = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final async = ref.watch(measurementsForMemberProvider(memberId));
    final busy = ref.watch(bodyMeasurementControllerProvider).isLoading;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.monitor_weight_outlined,
                    size: 18, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('인바디 측정', style: theme.textTheme.titleMedium),
                ),
                Tooltip(
                  message: '회원도 변화 추이 그래프에서 볼 수 있습니다',
                  child: Icon(Icons.visibility_outlined,
                      size: 16, color: colors.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: busy ? null : () => _add(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('측정 입력'),
              ),
            ),
            const SizedBox(height: 4),
            async.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('측정 기록을 불러오지 못했습니다.\n$e',
                    style: theme.textTheme.bodySmall),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '아직 측정 기록이 없습니다. [측정 입력]으로 체중/체지방률/골격근량을 기록하세요.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                final shown = list.take(_visibleCount).toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final m in shown)
                      _MeasurementTile(memberId: memberId, measurement: m),
                    if (list.length > shown.length)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '외 ${list.length - shown.length}건 더 있음',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final ok = await showAddBodyMeasurementDialog(context, memberId: memberId);
    if (ok == true && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('측정 기록이 저장되었습니다.')));
    }
  }
}

/// 측정 1건 행 — 측정일 + 지표 칩들 + 삭제.
class _MeasurementTile extends ConsumerWidget {
  const _MeasurementTile({required this.memberId, required this.measurement});

  final String memberId;
  final BodyMeasurement measurement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final m = measurement;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatKoreanDate(m.measuredAt),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (m.weightKg != null)
                      _MetricChip(label: '체중', value: '${_n(m.weightKg!)}kg'),
                    if (m.bodyFatPct != null)
                      _MetricChip(
                          label: '체지방', value: '${_n(m.bodyFatPct!)}%'),
                    if (m.skeletalMuscleKg != null)
                      _MetricChip(
                          label: '골격근', value: '${_n(m.skeletalMuscleKg!)}kg'),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '삭제',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.delete_outline, size: 20, color: colors.error),
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
    );
  }

  /// 72.0 → "72", 72.5 → "72.5" (불필요한 .0 제거).
  static String _n(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('측정 기록 삭제'),
        content: Text('${formatKoreanDate(measurement.measuredAt)} 측정 기록을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await ref
        .read(bodyMeasurementControllerProvider.notifier)
        .delete(id: measurement.id, memberId: memberId);

    if (!context.mounted) return;
    final state = ref.read(bodyMeasurementControllerProvider);
    final msg = state.hasError
        ? (state.error?.toString() ?? '삭제에 실패했습니다.')
        : '측정 기록이 삭제되었습니다.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            TextSpan(
              text: value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
