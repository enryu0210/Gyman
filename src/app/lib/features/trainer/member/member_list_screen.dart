/// 트레이너의 회원 목록 화면.
///
/// /trainer/members 경로. AppBar에 로그아웃, FAB로 회원 추가 다이얼로그.
///
/// **디자인(리포 루트 `DESIGN.md` 준수):**
///   - 세로 `ListTile` 나열(=설정 화면 같은 밋밋함) 대신 **카드 타일 목록**.
///     타일 톤은 홈 메뉴 격자와 동일한 [AppTheme.menuTileSurface]/[AppTheme.menuTileBorder]
///     — 다크에서 배경(canvas)에 묻히지 않게 한 단계 밝은 표면 + 또렷한 경계로 띄운다.
///   - 상단 요약 스트립에 "전체 회원 / 관리 필요"를 큰 숫자로(트레이너의 핵심 =
///     재등록 관리라, 관리 필요 건수가 있으면 `error` 색으로 시선을 끈다).
///   - 앱 미가입 회원만 회색 칩으로 노출("예외에 집중"). 가입 완료는 정상 상태라
///     별도 표식을 두지 않는다 — 초록 체크(팔레트 밖 색·다크 함정)를 걷어냈다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
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
            icon: const Icon(Icons.logout_outlined),
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
        icon: const Icon(Icons.person_add_alt_1),
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
          // index 0 = 요약 스트립, 이후 = 회원 카드. builder 로 지연 생성(큰 목록 대비).
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(membersListProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: list.length + 1,
              // 요약 아래는 여유(16), 카드 사이는 촘촘히(10).
              separatorBuilder: (_, i) => SizedBox(height: i == 0 ? 16 : 10),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return _ListSummary(
                    total: list.length,
                    needAttention: levelByMember.length,
                  );
                }
                final member = list[i - 1];
                return _MemberCard(
                  member: member,
                  alertLevel: levelByMember[member.id],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// =====================================================================
// 요약 스트립 — 전체 회원 수 / 관리 필요 수 (큰 숫자, DESIGN.md)
// =====================================================================

/// 목록 맨 위 요약 — "얼마나 있고, 그중 몇이 손이 필요한가"를 큰 숫자 둘로.
///
/// 관리 필요(재등록 알림 있는 회원)는 트레이너의 핵심 작업이라, 0보다 크면
/// `error` 색으로 눈에 띄게 한다. 0이면 중립색으로 담백하게.
class _ListSummary extends StatelessWidget {
  const _ListSummary({required this.total, required this.needAttention});

  final int total;
  final int needAttention;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.menuTileSurface(theme.brightness),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.menuTileBorder(theme.brightness)),
      ),
      child: Row(
        children: [
          _SummaryStat(
            label: '전체 회원',
            value: total,
            valueColor: colors.onSurface,
          ),
          Container(
            width: 1,
            height: 34,
            margin: const EdgeInsets.symmetric(horizontal: 18),
            color: AppTheme.menuTileBorder(theme.brightness),
          ),
          _SummaryStat(
            label: '관리 필요',
            value: needAttention,
            // 손이 필요한 회원이 있으면 붉게, 없으면 담담하게.
            valueColor:
                needAttention > 0 ? colors.error : colors.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final int value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$value',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.0,
            color: valueColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// =====================================================================
// 회원 카드 — 아바타 + 이름/알림 + 목적, 탭하면 상세로 드릴인
// =====================================================================

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.member, this.alertLevel});
  final Member member;

  /// 회원이 가진 계약 중 가장 높은 알림 단계. null/none 이면 chip 안 그림.
  final RenewalAlertLevel? alertLevel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasGoal = (member.goal ?? '').trim().isNotEmpty;
    final showAlert =
        alertLevel != null && alertLevel != RenewalAlertLevel.none;

    return Material(
      color: AppTheme.menuTileSurface(theme.brightness),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // Phase 1.2-B — 상세 화면으로 push: 뒤로가기로 목록 복귀(CLAUDE.md go_router 지침).
        onTap: () => context.push('/trainer/members/${member.id}'),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: AppTheme.menuTileBorder(theme.brightness)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: colors.primaryContainer,
                child: Text(
                  member.name.isNotEmpty ? member.name.characters.first : '?',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 이름 + (있으면) 재등록 알림 배지.
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            member.name,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (showAlert) ...[
                          const SizedBox(width: 6),
                          _AlertBadge(level: alertLevel!),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    // 목적 + (미가입이면) 회색 칩 + (AI 동의 시) 강조 칩.
                    // 가입 완료는 정상이라 무표식. AI는 반대로 "동의(옵트인)"만
                    // 표식 — 미동의가 기본이라 미동의를 다 칠하면 노이즈고,
                    // 트레이너가 알고 싶은 건 "AI 켜진 회원이 누구냐"이므로.
                    Row(
                      children: [
                        if (!member.isLinkedToAuth) ...[
                          const _UnlinkedChip(),
                          const SizedBox(width: 6),
                        ],
                        if (member.aiConsent) ...[
                          const _AiConsentChip(),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            hasGoal ? member.goal! : '목적 미입력',
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                              fontStyle:
                                  hasGoal ? FontStyle.normal : FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, size: 20, color: colors.outline),
            ],
          ),
        ),
      ),
    );
  }
}

/// 앱 미가입 회원 표식 — 손이 필요한 "예외"라 회색 칩으로만 노출.
class _UnlinkedChip extends StatelessWidget {
  const _UnlinkedChip();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '앱 미가입',
        style: TextStyle(
          fontSize: 10.5,
          color: colors.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// AI 사용 동의 회원 표식 — 동의한(옵트인) 회원만 강조색 칩으로 노출.
///
/// 미동의가 기본이라 미동의는 무표식(다 칠하면 노이즈). "이 회원에게 AI를
/// 쓸 수 있다"는 신호가 트레이너에게 실질 정보 — 상세 헤더 배지와 짝을 이룬다.
/// 색은 상세 헤더와 동일하게 primary(라이트=잉크/다크=볼트, 자동 대비).
class _AiConsentChip extends StatelessWidget {
  const _AiConsentChip();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.smart_toy_outlined, size: 11, color: colors.primary),
          const SizedBox(width: 3),
          Text(
            'AI',
            style: TextStyle(
              fontSize: 10.5,
              color: colors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
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
