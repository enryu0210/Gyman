/// 관리자(센터장) 대시보드 화면 — Phase 3.1-B (C1).
///
/// 라우트: `/admin/dashboard` (역할이 admin 인 사용자만 진입 — app_router redirect).
///
/// **표시 영역:**
///   1. 센터 요약 카드 4종 — 활성 회원 / 진행 중 계약 / 누적 매출 / 노쇼율
///   2. 트레이너별 성과 — 담당 회원·완료 수업·매출·노쇼율
///   3. 만료 임박 회원 — 재등록 권유 대상(잔여 적은 순)
///
/// 데이터는 전부 [adminDashboardProvider] 한 곳에서 — 본인 센터로 RLS 범위 한정(0029/0030).
///
/// 참고: docs/develop_plan.md §3.3 관리자 앱 라우트 맵, §4 Phase 3.1-B.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/async_state_views.dart';
import '../support/support_inbox_providers.dart';
import 'admin_dashboard_providers.dart';
import 'admin_dashboard_repository.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(adminDashboardProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('관리자 대시보드'),
        actions: [
          IconButton(
            tooltip: '센터 설정',
            icon: const Icon(Icons.apartment_outlined),
            // push 진입이라 뒤로가기로 대시보드 복귀(CLAUDE.md go_router 지침).
            onPressed: () => context.push('/admin/center'),
          ),
          const _SupportInboxButton(),
          IconButton(
            tooltip: '설정',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: dashboard.when(
        loading: () => const AppLoadingView(),
        error: (e, _) => AppErrorView(
          message: '대시보드를 불러오지 못했습니다.',
          detail: e.toString(),
          onRetry: () => ref.invalidate(adminDashboardProvider),
        ),
        data: (data) => RefreshIndicator(
          // 당겨서 새로고침 — 집계는 캐시되므로 명시적 invalidate 로 다시 로드.
          onRefresh: () async => ref.invalidate(adminDashboardProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _SummarySection(summary: data.summary),
              const SizedBox(height: 24),
              _TrainerSection(stats: data.trainerStats),
              const SizedBox(height: 24),
              _ExpiringSection(expiring: data.expiring),
              if (data.isEmpty) ...[
                const SizedBox(height: 24),
                const _EmptyHint(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 문의함 진입 버튼 — 미처리(open) 건수를 배지로(현 FCM 미도입의 '알람' 대체).
class _SupportInboxButton extends ConsumerWidget {
  const _SupportInboxButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(openInquiryCountProvider).value ?? 0;
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          tooltip: '문의함',
          icon: const Icon(Icons.inbox_outlined),
          onPressed: () => context.push('/admin/support'),
        ),
        if (count > 0)
          Positioned(
            right: 6,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error,
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(minWidth: 16),
              child: Text(
                '$count',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onError,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// =====================================================================
// 1. 센터 요약 카드 4종
// =====================================================================

class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.summary});

  final AdminCenterSummary summary;

  @override
  Widget build(BuildContext context) {
    final won = NumberFormat('#,###');
    // 노쇼율은 소수 1자리 % 로. 분모 0이면 '-' 표기로 "데이터 없음"을 구분.
    final noShowText = summary.noShowRate == 0
        ? '0.0%'
        : '${(summary.noShowRate * 100).toStringAsFixed(1)}%';

    final cards = <Widget>[
      _MetricCard(
        icon: Icons.people_alt_outlined,
        label: '활성 회원',
        value: '${summary.activeMemberCount}명',
      ),
      _MetricCard(
        icon: Icons.assignment_outlined,
        label: '진행 중 계약',
        value: '${summary.activeContractCount}건',
      ),
      _MetricCard(
        icon: Icons.payments_outlined,
        label: '누적 매출',
        value: '${won.format(summary.totalRevenue)}원',
      ),
      _MetricCard(
        icon: Icons.event_busy_outlined,
        label: '노쇼율',
        value: noShowText,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('센터 요약'),
        const SizedBox(height: 8),
        // 2열 그리드 — 카드 폭을 화면에 맞춰 균등 분할.
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.7,
          children: cards,
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(label, style: theme.textTheme.bodyMedium),
              ],
            ),
            const SizedBox(height: 8),
            // 누적 매출처럼 긴 숫자가 셀 폭을 넘겨 2줄로 줄바꿈되면 카드가 세로로
            // 넘친다("BOTTOM OVERFLOWED"). 한 줄 고정 + 폭 초과 시 축소해 방지.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                softWrap: false,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// 2. 트레이너별 성과
// =====================================================================

class _TrainerSection extends StatelessWidget {
  const _TrainerSection({required this.stats});

  final List<AdminTrainerStat> stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('트레이너별 성과'),
        const SizedBox(height: 8),
        if (stats.isEmpty)
          const _MutedRow('등록된 트레이너 계약이 없습니다.')
        else
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < stats.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _TrainerTile(stat: stats[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _TrainerTile extends StatelessWidget {
  const _TrainerTile({required this.stat});

  final AdminTrainerStat stat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final won = NumberFormat('#,###');
    final noShowText = stat.noShowRate == 0
        ? '0%'
        : '${(stat.noShowRate * 100).toStringAsFixed(0)}%';

    return ListTile(
      leading: CircleAvatar(child: Text(_initial(stat.trainerName))),
      title: Text(stat.trainerName),
      subtitle: Text(
        '회원 ${stat.memberCount}명 · 완료 ${stat.doneCount}회 · 노쇼 $noShowText',
        style: theme.textTheme.bodySmall,
      ),
      trailing: Text(
        '${won.format(stat.revenue)}원',
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  /// 아바타에 넣을 머리글자(이름 첫 글자). 빈 이름이면 '?'.
  String _initial(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed.substring(0, 1);
  }
}

// =====================================================================
// 3. 만료 임박 회원
// =====================================================================

class _ExpiringSection extends StatelessWidget {
  const _ExpiringSection({required this.expiring});

  final List<AdminContractRow> expiring;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('만료 임박 회원'),
        const SizedBox(height: 4),
        Text(
          '잔여 3회 이하 또는 만료 14일 이내 — 재등록 권유 대상',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (expiring.isEmpty)
          const _MutedRow('만료 임박 회원이 없습니다.')
        else
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < expiring.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _ExpiringTile(row: expiring[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _ExpiringTile extends StatelessWidget {
  const _ExpiringTile({required this.row});

  final AdminContractRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 만료일은 한국어 요일 초기화(intl) 없이 안전한 ASCII 포맷으로(CLAUDE.md).
    final endText = row.endDate == null
        ? '만료일 미정'
        : '만료 ${DateFormat('yyyy-MM-dd').format(row.endDate!)}';
    final trainer = row.trainerName ?? '담당 미지정';

    // 잔여 0 이하는 위험 강조(소진 완료).
    final isUrgent = row.remainingSessions <= 0;
    final remainColor =
        isUrgent ? theme.colorScheme.error : theme.colorScheme.primary;

    return ListTile(
      title: Text(row.memberName),
      subtitle: Text(
        '$trainer · $endText',
        style: theme.textTheme.bodySmall,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '잔여 ${row.remainingSessions}회',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: remainColor,
            ),
          ),
          Text(
            '${row.usedSessions}/${row.totalSessions}',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// 공용 소품
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

/// 비어있음/안내용 흐린 한 줄.
class _MutedRow extends StatelessWidget {
  const _MutedRow(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

/// 센터에 데이터가 전혀 없을 때(계약 0건) 안내.
class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          '아직 이 센터에 등록된 계약이 없습니다.\n'
          '트레이너가 회원·계약을 등록하면 지표가 채워집니다.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}

