/// 트레이너의 회원 목록 화면.
///
/// /trainer/members 경로. AppBar에 로그아웃, FAB로 회원 추가 다이얼로그.
/// 매핑 안 된 회원(앱 미가입)은 회색 배지로 표시 — UI에서 즉시 구분 가능.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/async_state_views.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/member.dart';
import '../../auth/auth_providers.dart';
import '../renewal/renewal_alert_providers.dart';
import '../renewal/renewal_alert_repository.dart';
import '../renewal/renewal_alerts_card.dart';
import 'add_member_dialog.dart';
import 'member_providers.dart';

class MemberListScreen extends ConsumerWidget {
  const MemberListScreen({super.key});

  /// 회원 id → 가장 높은 알림 단계. none 인 회원은 맵에서 빠짐.
  /// 알림 데이터가 아직 로딩 중이면 빈 맵 — 회원 카드는 알림 chip 없이 표시.
  static Map<String, RenewalAlertLevel> _maxLevelByMember(
    List<RenewalAlertItem> alerts,
  ) {
    final out = <String, RenewalAlertLevel>{};
    for (final a in alerts) {
      if (a.level == RenewalAlertLevel.none) continue;
      final cur = out[a.memberId];
      if (cur == null || a.priority > _priorityOf(cur)) {
        out[a.memberId] = a.level;
      }
    }
    return out;
  }

  static int _priorityOf(RenewalAlertLevel l) {
    switch (l) {
      case RenewalAlertLevel.expiring:
        return 3;
      case RenewalAlertLevel.fiveLeft:
        return 2;
      case RenewalAlertLevel.half:
        return 1;
      case RenewalAlertLevel.none:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(membersListProvider);
    final alerts = ref.watch(trainerRenewalAlertsProvider);
    final levelByMember = _maxLevelByMember(alerts.valueOrNull ?? const []);

    return Scaffold(
      appBar: AppBar(
        title: const Text('회원 목록'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(membersListProvider),
          ),
          IconButton(
            tooltip: '로그아웃',
            icon: const Icon(Icons.logout),
            onPressed: () =>
                ref.read(signInControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final added = await showAddMemberDialog(context);
          if (added == true && context.mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(content: Text('회원이 추가되었습니다.')));
          }
        },
        icon: const Icon(Icons.person_add),
        label: const Text('회원 추가'),
      ),
      body: members.when(
        loading: () => const AppLoadingView(),
        error: (e, _) => AppErrorView(
          message: '목록을 불러오지 못했습니다.',
          detail: e.toString(),
          onRetry: () => ref.invalidate(membersListProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const AppEmptyView(
              icon: Icons.group_outlined,
              title: '등록된 회원이 없습니다',
              message: '오른쪽 아래 [회원 추가] 버튼으로 시작하세요.\n'
                  '회원이 아직 앱을 깔지 않았어도 정보만 먼저 입력할 수 있습니다.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(membersListProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
              itemCount: list.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) => _MemberTile(
                member: list[i],
                alertLevel: levelByMember[list[i].id],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member, this.alertLevel});
  final Member member;

  /// 회원이 가진 계약 중 가장 높은 알림 단계. null/none 이면 chip 안 그림.
  final RenewalAlertLevel? alertLevel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: colors.primaryContainer,
        child: Text(
          member.name.isNotEmpty ? member.name.characters.first : '?',
          style: TextStyle(color: colors.onPrimaryContainer),
        ),
      ),
      title: Row(
        children: [
          Flexible(child: Text(member.name, overflow: TextOverflow.ellipsis)),
          if (alertLevel != null && alertLevel != RenewalAlertLevel.none) ...[
            const SizedBox(width: 6),
            _AlertBadge(level: alertLevel!),
          ],
        ],
      ),
      subtitle: Row(
        children: [
          if (member.goal != null && member.goal!.isNotEmpty)
            Flexible(
              child: Text(
                member.goal!,
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            Text(
              '목적 미입력',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
        ],
      ),
      trailing: member.isLinkedToAuth
          ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
          : Tooltip(
              message: '회원이 아직 앱에 가입하지 않음',
              child: Chip(
                visualDensity: VisualDensity.compact,
                label: const Text('앱 미가입'),
                labelStyle: TextStyle(
                  fontSize: 11,
                  color: colors.onSurfaceVariant,
                ),
                backgroundColor: colors.surfaceContainerHighest,
                side: BorderSide.none,
              ),
            ),
      // Phase 1.2-B — 상세 화면(MemberDetailScreen)으로 이동.
      // go_router의 push: 뒤로가기 시 목록으로 자연스럽게 돌아간다.
      onTap: () => context.push('/trainer/members/${member.id}'),
    );
  }
}

/// 회원 행에 붙는 작은 알림 배지 — 홈 카드와 동일한 색/라벨 톤.
class _AlertBadge extends StatelessWidget {
  const _AlertBadge({required this.level});
  final RenewalAlertLevel level;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = renewalAlertStyle(level, colors);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: style.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 11, color: style.fg),
          const SizedBox(width: 3),
          Text(
            style.label,
            style: TextStyle(
              fontSize: 10,
              color: style.fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

