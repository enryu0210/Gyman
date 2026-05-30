/// 회원 홈 화면 — 다음 수업 + 잔여 횟수 (Phase 2 회원 로드맵 ②).
///
/// 라우트: `/member/home`
///
/// **표시 영역:**
///   1. 인사말 — 회원 이름
///   2. 다음 수업 카드 — 가장 가까운 예약(없으면 안내 문구)
///   3. 잔여 횟수 카드 — 전체 합계 + 계약별 내역
///
/// 모두 **읽기 전용**(회원은 본인 데이터를 보기만). 데이터 조회/권한 분리는
/// repository + RLS 가 담당하고, 본 화면은 [memberHomeSummaryProvider] 의
/// AsyncValue 를 로딩/에러/데이터로 분기해 그린다.
///
/// 날짜 표기는 `intl`의 한국어 로케일(initializeDateFormatting 미호출)에 의존하지
/// 않도록 수동 포맷 헬퍼를 사용한다(프로젝트 지침).
///
/// 와이어프레임 출처: docs/develop_plan.md §3.2 /member/home.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/util/date_format_ko.dart';
import '../../../domain/models/session.dart';
import '../../auth/auth_providers.dart';
import 'member_home_repository.dart';
import 'member_home_providers.dart';

class MemberHomeScreen extends ConsumerWidget {
  const MemberHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(memberHomeSummaryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('내 PT'),
        actions: [
          IconButton(
            tooltip: '로그아웃',
            icon: const Icon(Icons.logout),
            onPressed: () =>
                ref.read(signInControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: summary.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _ErrorView(
          onRetry: () => ref.invalidate(memberHomeSummaryProvider),
        ),
        data: (data) => RefreshIndicator(
          // 당겨서 새로고침 — 트레이너가 예약을 추가하면 다시 받아온다.
          onRefresh: () async => ref.invalidate(memberHomeSummaryProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _GreetingHeader(name: data.memberName),
              const SizedBox(height: 16),
              _NextSessionCard(session: data.nextSession),
              const SizedBox(height: 16),
              _RemainingCard(summary: data),
              const SizedBox(height: 16),
              const _MenuCard(),
            ],
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// 메뉴 — 회원 기능 진입
// =====================================================================

/// 회원 하위 화면 진입 카드.
class _MenuCard extends StatelessWidget {
  const _MenuCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      // 드릴인은 push — 형제 최상위 라우트여도 뒤로가기가 생긴다.
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.event_note_outlined),
            title: const Text('예약 신청'),
            subtitle: const Text('원하는 시간에 수업 신청하기'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/member/booking'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.fitness_center),
            title: const Text('내 수업 기록'),
            subtitle: const Text('지난 수업의 운동 내용 보기'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/member/records'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.show_chart),
            title: const Text('변화 추이'),
            subtitle: const Text('중량·인바디 변화 그래프 보기'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/member/records/progress'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.campaign_outlined),
            title: const Text('받은 안내'),
            subtitle: const Text('트레이너가 보낸 안내 보기'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/member/notices'),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// 인사말
// =====================================================================

class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    // 이름 조회 실패(빈 문자열) 시엔 호칭만.
    final greeting = name.isEmpty ? '안녕하세요' : '$name님, 안녕하세요';
    return Text(
      greeting,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

// =====================================================================
// 다음 수업
// =====================================================================

class _NextSessionCard extends StatelessWidget {
  const _NextSessionCard({required this.session});
  final Session? session;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.event_available, color: colors.primary),
                const SizedBox(width: 8),
                Text('다음 수업', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            if (session == null)
              Text(
                '예정된 수업이 없습니다.\n예약은 담당 트레이너에게 문의해 주세요.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              )
            else ...[
              Text(
                formatKoreanDateTime(session!.scheduledAt),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                untilLabel(session!.scheduledAt),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.primary,
                ),
              ),
              if ((session!.statusMemo ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  session!.statusMemo!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// 잔여 횟수
// =====================================================================

class _RemainingCard extends StatelessWidget {
  const _RemainingCard({required this.summary});
  final MemberHomeSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.confirmation_number_outlined,
                    color: colors.primary),
                const SizedBox(width: 8),
                Text('잔여 횟수', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            if (!summary.hasContract)
              Text(
                '등록된 PT 계약이 없습니다.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              )
            else ...[
              // 전체 합계 — 가장 크게.
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${summary.totalRemaining}',
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('회 남음', style: theme.textTheme.titleMedium),
                ],
              ),
              // 계약이 둘 이상이면 계약별 내역도 함께(소진 계약 포함).
              if (summary.contracts.length > 1) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 8),
                for (final c in summary.contracts)
                  _ContractRow(status: c),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// 계약 1건의 잔여/전체 한 줄 표시 (계약 여러 개일 때).
class _ContractRow extends StatelessWidget {
  const _ContractRow({required this.status});
  final MemberContractStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = Theme.of(context).colorScheme;
    final label =
        '${formatKoreanDate(status.startDate)} 시작 계약';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            status.isExhausted
                ? '소진 완료'
                : '${status.remainingSessions} / ${status.totalSessions}회',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: status.isExhausted ? colors.error : null,
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// 에러 표시
// =====================================================================

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
              '정보를 불러오지 못했습니다.\n잠시 후 다시 시도해 주세요.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}
