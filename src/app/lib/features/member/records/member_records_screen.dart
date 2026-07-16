/// 회원 "내 수업 기록" 화면 (Phase 2 회원 로드맵 ③).
///
/// 라우트: `/member/records`
///
/// 본인의 완료(done) 수업을 최신순 카드 리스트로 보여주고, 카드를 탭하면
/// 세트별 운동 내용까지 담은 상세 바텀시트를 연다.
///
/// **읽기 전용 + 가시성 분리:** 트레이너용 메모(next_memo)는 repository 단계에서
/// 아예 가져오지 않으므로 이 화면엔 운동 내용·컨디션·통증만 표시된다.
///
/// 날짜 표기는 `core/util/date_format_ko.dart`(수동 포맷) 공용 헬퍼 사용.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/util/date_format_ko.dart';
import '../../../core/widgets/async_state_views.dart';
import '../../../domain/models/session_record.dart';
import 'member_records_repository.dart';
import 'member_records_providers.dart';

class MemberRecordsScreen extends ConsumerWidget {
  const MemberRecordsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myRecordsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('내 수업 기록'),
        actions: [
          // 변화 추이 — 기록 하위 라우트로 push(뒤로가기가 기록 화면으로).
          IconButton(
            tooltip: '변화 추이',
            icon: const Icon(Icons.show_chart),
            onPressed: () => context.push('/member/records/progress'),
          ),
        ],
      ),
      body: async.when(
        loading: () => const AppLoadingView(),
        error: (e, _) => AppErrorView(
          message: '기록을 불러오지 못했습니다.\n잠시 후 다시 시도해 주세요.',
          onRetry: () => ref.invalidate(myRecordsProvider),
        ),
        data: (records) {
          if (records.isEmpty) {
            return const AppEmptyView(
              icon: Icons.fitness_center,
              message: '아직 기록된 수업이 없습니다.\n수업을 진행하면 여기에서 운동 내용을 볼 수 있어요.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myRecordsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              itemCount: records.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _RecordCard(item: records[i]),
            ),
          );
        },
      ),
    );
  }
}

// =====================================================================
// 기록 카드 1개
// =====================================================================

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.item});
  final MemberSessionRecord item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final record = item.record;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        // 기록이 있을 때만 상세 시트를 연다.
        onTap: record == null
            ? null
            : () => _showRecordDetailSheet(
                  context,
                  scheduledAt: item.scheduledAt,
                  record: record,
                ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.fitness_center, size: 18, color: colors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      formatKoreanDateTime(item.scheduledAt),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  if (record != null)
                    Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 8),
              if (record == null)
                Text(
                  '운동 기록이 비어 있습니다.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                )
              else ...[
                Text(
                  _exercisePreview(record.exercises),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _MetaChip(
                      icon: Icons.list_alt,
                      text:
                          '${record.exercises.length}종목 · ${record.totalSets}세트',
                    ),
                    if (record.totalVolume > 0)
                      _MetaChip(
                        icon: Icons.scale,
                        text: '총 ${record.totalVolume}kg',
                      ),
                    if ((record.condition ?? '').isNotEmpty)
                      _MetaChip(
                        icon: Icons.mood,
                        text: conditionLabel(record.condition!),
                      ),
                    if ((record.pain ?? '').isNotEmpty)
                      _MetaChip(
                        icon: Icons.healing_outlined,
                        text: '통증 기록',
                        // 주의 톤(주황) — 다크에선 밝게, 라이트에선 진하게.
                        color: theme.brightness == Brightness.dark
                            ? const Color(0xFFFFB870)
                            : const Color(0xFFD84315),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// "스쿼트, 데드리프트 외 3개" 한 줄 요약.
  static String _exercisePreview(List<Exercise> exercises) {
    final names = exercises.map((e) => e.name).where((n) => n.isNotEmpty).toList();
    if (names.isEmpty) return '운동 종목 없음';
    if (names.length <= 2) return names.join(', ');
    return '${names.take(2).join(', ')} 외 ${names.length - 2}개';
  }
}

// =====================================================================
// 상세 바텀시트 — 세트별 운동 내용
// =====================================================================

/// 수업 1건의 운동 내용을 세트 단위까지 펼쳐 보여주는 바텀시트.
///
/// 데이터는 이미 리스트에서 받아둔 것을 그대로 쓴다(재조회 없음).
Future<void> _showRecordDetailSheet(
  BuildContext context, {
  required DateTime scheduledAt,
  required SessionRecord record,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _RecordDetailSheet(
      scheduledAt: scheduledAt,
      record: record,
    ),
  );
}

class _RecordDetailSheet extends StatelessWidget {
  const _RecordDetailSheet({required this.scheduledAt, required this.record});
  final DateTime scheduledAt;
  final SessionRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Text(
            formatKoreanDateTime(scheduledAt),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${record.exercises.length}종목 · ${record.totalSets}세트'
            '${record.totalVolume > 0 ? ' · 총 ${record.totalVolume}kg' : ''}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),

          // 컨디션 / 통증
          if ((record.condition ?? '').isNotEmpty ||
              (record.pain ?? '').isNotEmpty) ...[
            if ((record.condition ?? '').isNotEmpty)
              _InfoRow(
                icon: Icons.mood,
                label: '컨디션',
                value: conditionLabel(record.condition!),
              ),
            if ((record.pain ?? '').isNotEmpty)
              _InfoRow(
                icon: Icons.healing_outlined,
                label: '통증/특이사항',
                value: record.pain!,
                // 주의 톤(주황) — 다크에선 밝게, 라이트에선 진하게.
                color: theme.brightness == Brightness.dark
                    ? const Color(0xFFFFB870)
                    : const Color(0xFFD84315),
              ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
          ],

          // 종목별 세트
          if (record.exercises.isEmpty)
            Text(
              '기록된 운동 종목이 없습니다.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            )
          else
            for (final ex in record.exercises) _ExerciseBlock(exercise: ex),
        ],
      ),
    );
  }
}

class _ExerciseBlock extends StatelessWidget {
  const _ExerciseBlock({required this.exercise});
  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            exercise.name.isEmpty ? '(종목명 없음)' : exercise.name,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          if (exercise.sets.isEmpty)
            Text(
              '세트 기록 없음',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            )
          else
            // 세트별 "1세트  60kg × 10회" 줄.
            for (var i = 0; i < exercise.sets.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 56,
                      child: Text(
                        '${i + 1}세트',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      '${exercise.sets[i].weight}kg × ${exercise.sets[i].reps}회',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: c),
          const SizedBox(width: 8),
          Text(
            '$label  ',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// 공용 작은 위젯 / 헬퍼
// =====================================================================

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: c),
        const SizedBox(width: 4),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c),
        ),
      ],
    );
  }
}

/// 컨디션 코드 → 한국어 라벨. 자유 입력은 그대로 표시.
String conditionLabel(String code) {
  switch (code) {
    case 'good':
      return '컨디션 좋음';
    case 'normal':
      return '컨디션 보통';
    case 'bad':
      return '컨디션 나쁨';
    default:
      return code;
  }
}
