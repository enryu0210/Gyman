/// 트레이너 홈 "재등록 알림" 카드 (Phase 1.7).
///
/// 트레이너 본인 모든 활성 계약을 [trainerRenewalAlertsProvider] 로 받아,
/// 알림 단계(expiring / fiveLeft / half) 가 있는 항목만 상위 [_visibleLimit] 건 표시.
///
/// **표시 정책:**
///   - [RenewalAlertLevel.none] 은 카드에서 제외 (전체 카운트에서만 가볍게 노출)
///   - 단계별 색/아이콘 구분 — 트레이너가 한눈에 우선순위 인식
///   - 회원 탭 → 해당 회원 상세로 이동
///
/// **빈 상태:**
///   "알림 대상이 없습니다" — 부정적 인상이 들지 않게 격려성 문구로.
///
/// 참고: docs/develop_plan.md §4 Phase 1.7, docs/wireframes/02_trainer_home.md.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/async_state_views.dart';
import '../../../domain/models/enums.dart';
import 'renewal_alert_providers.dart';
import 'renewal_alert_repository.dart';

class RenewalAlertsCard extends ConsumerWidget {
  const RenewalAlertsCard({super.key});

  /// 카드 안에 표시할 알림 최대 건수. 더 많으면 "더 보기" 안내 텍스트.
  static const _visibleLimit = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(trainerRenewalAlertsProvider);
    final colors = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notifications_active_outlined,
                    size: 18, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '재등록 알림',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: '새로고침',
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: () =>
                      ref.invalidate(trainerRenewalAlertsProvider),
                ),
              ],
            ),
            const SizedBox(height: 4),
            async.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => AppInlineError(
                message: '알림을 불러오지 못했습니다.',
                onRetry: () =>
                    ref.invalidate(trainerRenewalAlertsProvider),
              ),
              data: (all) {
                // 단계 있는 항목만 필터 — 우선순위 정렬은 repository 가 끝낸 상태.
                final alerts = all
                    .where((i) => i.level != RenewalAlertLevel.none)
                    .toList();
                if (alerts.isEmpty) {
                  return _EmptyView(totalActiveContracts: all.length);
                }
                final visible = alerts.take(_visibleLimit).toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final item in visible)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: _AlertRow(item: item),
                      ),
                    if (alerts.length > visible.length)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '총 ${alerts.length}건 중 ${visible.length}건만 표시',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
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
}

// =====================================================================
// 빈/에러 뷰
// =====================================================================

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.totalActiveContracts});
  final int totalActiveContracts;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final msg = totalActiveContracts == 0
        ? '활성 계약이 없습니다. 회원을 등록하고 첫 계약부터 시작하세요.'
        : '지금 챙길 알림이 없습니다. 활성 계약 $totalActiveContracts건 모두 양호.';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        msg,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
      ),
    );
  }
}


// =====================================================================
// 알림 1줄
// =====================================================================

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.item});
  final RenewalAlertItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final style = renewalAlertStyle(item.level, colors);
    final fmt = DateFormat('yyyy-MM-dd');

    final endText = item.endDate != null
        ? '만료 ${fmt.format(item.endDate!)}'
        : '만료일 미정';

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => context.push('/trainer/members/${item.memberId}'),
      child: Container(
        decoration: BoxDecoration(
          color: style.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: style.border),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Icon(style.icon, size: 18, color: style.fg),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        item.memberName,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        style.label,
                        style: TextStyle(
                          fontSize: 11,
                          color: style.fg,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '잔여 ${item.remainingSessions}회 / 총 ${item.totalSessions}회 · $endText',
                    style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// 공용 알림 단계 스타일 — 회원 상세 chip 에서도 재사용
// =====================================================================

/// 알림 단계별 색/아이콘/라벨. 한 곳에 모아둬서 색 톤 바꿀 때 한 줄만 수정.
class RenewalAlertStyle {
  final String label;
  final IconData icon;
  final Color fg;
  final Color bg;
  final Color border;

  const RenewalAlertStyle({
    required this.label,
    required this.icon,
    required this.fg,
    required this.bg,
    required this.border,
  });
}

RenewalAlertStyle renewalAlertStyle(
  RenewalAlertLevel level,
  ColorScheme colors,
) {
  switch (level) {
    case RenewalAlertLevel.expiring:
      return RenewalAlertStyle(
        label: '만료 임박',
        icon: Icons.warning_amber_rounded,
        fg: Colors.red.shade800,
        bg: Colors.red.shade50,
        border: Colors.red.shade100,
      );
    case RenewalAlertLevel.fiveLeft:
      return RenewalAlertStyle(
        label: '5회 이하',
        icon: Icons.priority_high,
        fg: Colors.orange.shade900,
        bg: Colors.orange.shade50,
        border: Colors.orange.shade100,
      );
    case RenewalAlertLevel.half:
      return RenewalAlertStyle(
        label: '절반 사용',
        icon: Icons.timelapse,
        fg: colors.primary,
        bg: colors.primaryContainer.withValues(alpha: 0.3),
        border: colors.primaryContainer,
      );
    case RenewalAlertLevel.none:
      return RenewalAlertStyle(
        label: '양호',
        icon: Icons.check_circle_outline,
        fg: colors.onSurfaceVariant,
        bg: colors.surfaceContainerHighest,
        border: colors.outlineVariant,
      );
  }
}
