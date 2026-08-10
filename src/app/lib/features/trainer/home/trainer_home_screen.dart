/// 트레이너 홈 화면 — 일일 업무 흐름 중심 (UI 1차 개편 단계 B).
///
/// 라우트: `/trainer/home` (트레이너 셸의 첫 번째 탭)
///
/// **정보 우선순위(ui_renewal_phase1_plan.md §3.2):**
///   1. 다음 수업        — 지금 무엇을 준비해야 하는가
///   2. 오늘의 타임라인   — 하루가 어떻게 흘러가는가
///   3. 처리할 일        — 승인·검수·안읽음·기록 대기
///   4. 재등록 주의 회원
///   5. 보조 바로가기
///
/// **개편 전과의 차이:** 예전 홈은 처리 대기 *총량* 이 첫 화면이었고 회원/예약/채팅
/// 진입점이 격자로 모여 있었다. 그 진입점들은 하단 탭으로 옮겨갔으므로 격자에는
/// 탭에 없는 것(AI 검수·관리자 대시보드)만 남는다 — 같은 기능을 두 번 놓지 않는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/util/clock_providers.dart';
import '../../../core/util/date_format_ko.dart';
import '../../../core/widgets/app_menu_grid.dart';
import '../../../domain/today_schedule.dart';
import '../../auth/auth_providers.dart';
import '../ai_review/ai_review_providers.dart';
import '../chat/trainer_chat_providers.dart';
import '../contract/contract_providers.dart';
import '../renewal/renewal_alert_providers.dart';
import '../renewal/renewal_alerts_card.dart';
import '../session_log/session_providers.dart';
import 'today_state_chip.dart';
import 'trainer_today_providers.dart';

/// 타임라인에 한 번에 펼쳐 보여줄 최대 줄 수.
///
/// 작은 화면에서 다음 수업 카드 + 타임라인이 과밀해지지 않게 당일 핵심만 보이고,
/// 나머지는 "전체 일정"으로 넘긴다(계획서 §7 정보 밀도 리스크 대응).
const _kTimelinePreviewCount = 4;

class TrainerHomeScreen extends ConsumerWidget {
  const TrainerHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(nowProvider);

    // 앱을 켜둔 채 자정을 넘기면 "오늘" 조회 결과가 어제 것이 된다 → 날짜 키가
    // 바뀌는 순간 다시 불러온다. (안 하면 아침에 어제 수업이 "기록 대기"로 뜬다)
    ref.listen<String>(todayKeyProvider, (_, _) {
      ref.invalidate(trainerBookingsProvider(TrainerBookingRange.today));
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(formatKoreanDateHeader(now)),
        actions: [
          IconButton(
            tooltip: '설정',
            icon: const Icon(Icons.settings_outlined),
            // 설정(문의·약관·로그아웃)으로 push — 뒤로가기로 홈 복귀.
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refreshAll(ref),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: const [
            _TodaySummaryLine(),
            SizedBox(height: 14),
            _FocusSection(),
            SizedBox(height: 20),
            _TodoSection(),
            SizedBox(height: 20),
            RenewalAlertsCard(),
            SizedBox(height: 20),
            _SecondaryShortcuts(),
          ],
        ),
      ),
    );
  }

  /// 당겨서 새로고침 — 홈이 보여주는 모든 소스를 한 번에 다시 불러온다.
  static void _refreshAll(WidgetRef ref) {
    ref.invalidate(trainerBookingsProvider(TrainerBookingRange.today));
    ref.invalidate(trainerPendingRequestsProvider);
    ref.invalidate(trainerUnreadTotalProvider);
    ref.invalidate(pendingMessagesProvider);
    ref.invalidate(trainerRenewalAlertsProvider);
  }
}

// =====================================================================
// 1) 요약 한 줄 — "오늘 수업 3건 · 처리할 일 5건"
// =====================================================================

class _TodaySummaryLine extends ConsumerWidget {
  const _TodaySummaryLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = ref.watch(trainerTodayViewProvider).valueOrNull;
    final todoCount = ref.watch(_todoTotalProvider);

    final sessionCount = today?.items.length ?? 0;
    final parts = <String>[
      if (sessionCount > 0) '오늘 수업 $sessionCount건',
      if (todoCount > 0) '처리할 일 $todoCount건',
    ];

    return Text(
      parts.isEmpty ? '오늘은 밀린 일 없이 깔끔해요' : parts.join(' · '),
      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
    );
  }
}

/// 처리할 일 총량 — 승인 대기 + AI 검수 + 안읽은 채팅 + 기록 대기.
final _todoTotalProvider = Provider<int>((ref) {
  final int awaiting =
      ref.watch(trainerTodayViewProvider).valueOrNull?.awaitingRecordCount ?? 0;
  final int requests = ref.watch(trainerPendingRequestCountProvider);
  final int reviews = ref.watch(pendingMessageReviewCountProvider);
  final int unread = ref.watch(trainerUnreadCountProvider);
  return awaiting + requests + reviews + unread;
});

// =====================================================================
// 2) 다음 수업 + 오늘의 타임라인
// =====================================================================

class _FocusSection extends ConsumerWidget {
  const _FocusSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(trainerTodayViewProvider);

    return async.when(
      // 카드 크기에 맞춘 자리를 잡아 두어 로딩 중 화면이 덜컹거리지 않게(§4.2).
      loading: () => const _FocusSkeleton(),
      // 홈 전체를 에러로 덮지 않는다 — 아래 처리할 일/재등록은 여전히 쓸모 있다.
      error: (_, _) => const _FocusMessageCard(
        icon: Icons.cloud_off_outlined,
        title: '오늘 일정을 불러오지 못했어요',
        message: '아래로 당겨 새로고침해 주세요.',
      ),
      data: (view) {
        final focus = view.focus;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (focus != null)
              _NextSessionCard(item: focus)
            else if (view.isEmpty)
              _FocusMessageCard(
                icon: Icons.event_available_outlined,
                title: '오늘 예정된 수업이 없어요',
                message: '회원 목록에서 예약을 잡을 수 있어요.',
                actionLabel: '회원 선택해 예약 잡기',
                onAction: () => context.go('/trainer/members'),
              )
            else
              _FocusMessageCard(
                icon: Icons.check_circle_outline,
                title: '오늘 수업을 모두 마쳤어요',
                message: '수업 ${view.doneCount}건 완료 · 남은 수업 없음',
              ),
            if (view.items.isNotEmpty) ...[
              const SizedBox(height: 18),
              _TodayTimeline(view: view),
            ],
          ],
        );
      },
    );
  }
}

/// 다음 수업(또는 진행 중 수업) 카드 — 잉크 블록(트레이너의 "집중" 요소).
///
/// 잉크 배경은 라이트/다크 공통. 다크에선 배경(canvas)과 명도가 가까워 경계가
/// 흐려지므로 얇은 볼트 테두리로 분리한다(라임 테두리는 다크 배경에서만 안전).
class _NextSessionCard extends ConsumerWidget {
  const _NextSessionCard({required this.item});
  final TrainerTodayItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const onInk = AppTheme.onInk;
    final onInkMuted = onInk.withValues(alpha: 0.60);

    final isPending = item.state == TodaySessionState.pending;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.ink,
        borderRadius: BorderRadius.circular(20),
        border: isDark
            ? Border.all(color: AppTheme.volt.withValues(alpha: 0.22))
            : null,
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 오버라인 — 상태 라벨 · 시각 · 남은 시간.
          Row(
            children: [
              Text(
                _focusHeadline(item.state),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: onInkMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatHm(item.scheduledAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: onInkMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              // 아직 시작 전일 때만 남은 시간 — 시작 후엔 "곧 시작"이 오해를 부른다.
              if (item.state == TodaySessionState.upcoming ||
                  item.state == TodaySessionState.pending) ...[
                const SizedBox(width: 8),
                Text(
                  untilLabel(item.scheduledAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    // 남은 시간은 잉크 위 라임 — 어두운 배경이라 대비가 안전하다.
                    color: AppTheme.volt,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(
            item.memberName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: onInk,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          _FocusMetaLine(item: item, color: onInkMuted),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _InkOutlinedButton(
                  label: '회원 카드',
                  onTap: () =>
                      context.push('/trainer/members/${item.memberId}'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _InkPrimaryButton(
                  // 승인 대기 신청이면 기록보다 승인이 먼저다.
                  label: isPending ? '예약 승인' : '수업 기록',
                  onTap: () {
                    if (isPending) {
                      context.go('/trainer/booking');
                    } else {
                      context.push(
                        '/trainer/members/${item.memberId}'
                        '/session/${item.slot.sessionId}',
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _focusHeadline(TodaySessionState state) {
    switch (state) {
      case TodaySessionState.inProgress:
        return '진행 중';
      case TodaySessionState.pending:
        return '승인 대기';
      default:
        return '다음 수업';
    }
  }
}

/// 잉크 카드 두 번째 줄 — 잔여 횟수 + 예약 메모.
///
/// 잔여 횟수는 이 수업이 차감할 **그 계약**의 값이다(회원의 다른 계약과 섞이면
/// 숫자가 틀린다). 조회는 회원 상세가 이미 쓰는 provider 재사용 — 새 쿼리 추가 X.
/// 값이 아직 없으면 자리만 비우고 카드 자체는 즉시 그린다.
class _FocusMetaLine extends ConsumerWidget {
  const _FocusMetaLine({required this.item, required this.color});

  final TrainerTodayItem item;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final statuses =
        ref.watch(contractStatusForMemberProvider(item.memberId)).valueOrNull;

    int? remaining;
    if (statuses != null) {
      for (final s in statuses) {
        if (s.contractId == item.row.session.contractId) {
          remaining = s.remainingSessions;
          break;
        }
      }
    }

    final parts = <String>[
      // 경고 상태는 색이 아니라 문구로도 읽히게(계획서 §4.1).
      if (remaining != null) '잔여 $remaining회',
      if (item.memo != null) item.memo!,
    ];
    if (parts.isEmpty) return const SizedBox.shrink();

    return Text(
      parts.join(' · '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium?.copyWith(color: color),
    );
  }
}

/// 잉크 카드 위 보조 버튼 — 반투명 흰 테두리 + 흰 글씨.
class _InkOutlinedButton extends StatelessWidget {
  const _InkOutlinedButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.onInk,
        side: BorderSide(color: AppTheme.onInk.withValues(alpha: 0.35)),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// 잉크 카드 위 대표 버튼 — 볼트 채우기 + 잉크 글씨.
///
/// 하단 바의 "기록하기"와 색이 겹치지만 **같은 행동**(수업 기록 시작)이라 강조가
/// 분산되지 않는다. 화면당 라임 강조 1개 규칙(§4.1)의 취지에 어긋나지 않음.
class _InkPrimaryButton extends StatelessWidget {
  const _InkPrimaryButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.volt,
        foregroundColor: AppTheme.onVolt,
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// 수업이 없거나 다 끝났거나 불러오지 못했을 때의 자리 — 큰 빈 영역을 남기지 않는다.
class _FocusMessageCard extends StatelessWidget {
  const _FocusMessageCard({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.menuTileSurface(theme.brightness),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.menuTileBorder(theme.brightness)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: colors.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onAction,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// 로딩 중 자리 — 카드 크기만큼의 회색 면(스켈레톤).
class _FocusSkeleton extends StatelessWidget {
  const _FocusSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 168,
      decoration: BoxDecoration(
        color: AppTheme.menuTileSurface(theme.brightness),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.menuTileBorder(theme.brightness)),
      ),
    );
  }
}

// ─────────────────────────── 오늘의 타임라인 ───────────────────────────

class _TodayTimeline extends StatelessWidget {
  const _TodayTimeline({required this.view});
  final TrainerTodayView view;

  @override
  Widget build(BuildContext context) {
    final shown = view.items.take(_kTimelinePreviewCount).toList();
    final hidden = view.items.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel('오늘의 타임라인'),
        const SizedBox(height: 8),
        for (final item in shown) _TimelineRow(item: item),
        if (hidden > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => context.go('/trainer/booking'),
              child: Text('전체 일정 보기 (+$hidden건)'),
            ),
          ),
      ],
    );
  }
}

/// 타임라인 한 줄 — 시각 · 회원명(메모) · 상태. 탭하면 회원 카드로.
///
/// 지금 기록할 수 있는 수업(진행 중·기록 대기)에는 오른쪽에 기록 버튼을 따로 둔다
/// — 행 전체 탭과 목적지가 달라 헷갈리지 않도록 눌리는 영역을 나눈다.
class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.item});
  final TrainerTodayItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final done = item.state == TodaySessionState.done ||
        item.state == TodaySessionState.canceled;

    return InkWell(
      onTap: () => context.push('/trainer/members/${item.memberId}'),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(
                formatHm(item.scheduledAt),
                style: theme.textTheme.titleSmall?.copyWith(
                  // 끝난 일은 가라앉힌다 — 남은 일에 시선이 가도록.
                  color: done ? colors.onSurfaceVariant : colors.onSurface,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.memberName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: done ? colors.onSurfaceVariant : colors.onSurface,
                    ),
                  ),
                  if (item.memo != null)
                    Text(
                      item.memo!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TodayStateChip(state: item.state),
            if (item.slot.canRecordNow)
              IconButton(
                tooltip: '수업 기록',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_note_outlined, size: 22),
                onPressed: () => context.push(
                  '/trainer/members/${item.memberId}'
                  '/session/${item.slot.sessionId}',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// 3) 처리할 일 — 승인 · 검수 · 안읽음 · 기록 대기
// =====================================================================

/// 밀린 업무를 종류별 칩으로. 탭하면 그 처리 화면으로 바로 이동한다.
///
/// 총량 큰 숫자를 걷어낸 이유: 총량은 "얼마나 밀렸나"만 알려줄 뿐 다음 행동을
/// 못 정한다. 개편 후엔 상단 요약 줄이 총량을 맡고, 여기서는 바로 처리로 잇는다.
class _TodoSection extends ConsumerWidget {
  const _TodoSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingRequests = ref.watch(trainerPendingRequestCountProvider);
    final pendingReview = ref.watch(pendingMessageReviewCountProvider);
    final unreadChats = ref.watch(trainerUnreadCountProvider);
    final awaitingRecord =
        ref.watch(trainerTodayViewProvider).valueOrNull?.awaitingRecordCount ??
            0;

    final chips = <Widget>[
      if (pendingRequests > 0)
        _TodoChip(
          icon: Icons.pending_actions_outlined,
          label: '예약 승인',
          count: pendingRequests,
          onTap: () => context.go('/trainer/booking'),
        ),
      if (awaitingRecord > 0)
        _TodoChip(
          icon: Icons.edit_note_outlined,
          label: '수업 기록',
          count: awaitingRecord,
          // 어느 수업인지는 타임라인이 이미 보여주므로 일정 탭으로 보낸다.
          onTap: () => context.go('/trainer/booking'),
        ),
      if (pendingReview > 0)
        _TodoChip(
          // AI 검수는 하단 탭에 두지 않는다(계획서 §3.1) → 홈에서만 닿는다.
          // 대기 0건이면 이 칩은 사라지므로, 상시 진입점은 아래 바로가기 격자가 맡는다.
          icon: Icons.fact_check_outlined,
          label: 'AI 검수',
          count: pendingReview,
          onTap: () => context.push('/trainer/ai-review'),
        ),
      if (unreadChats > 0)
        _TodoChip(
          icon: Icons.chat_bubble_outline,
          label: '안읽은 채팅',
          count: unreadChats,
          onTap: () => context.go('/trainer/chat'),
        ),
    ];

    if (chips.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('처리할 일'),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: chips),
      ],
    );
  }
}

class _TodoChip extends StatelessWidget {
  const _TodoChip({
    required this.icon,
    required this.label,
    required this.count,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      color: AppTheme.menuTileSurface(theme.brightness),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: AppTheme.menuTileBorder(theme.brightness)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: colors.onSurfaceVariant),
              const SizedBox(width: 7),
              Text(
                label,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                constraints: const BoxConstraints(minWidth: 20),
                decoration: BoxDecoration(
                  color: colors.errorContainer,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: colors.onErrorContainer,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, size: 17, color: colors.outline),
            ],
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// 5) 보조 바로가기 — 하단 탭에 없는 것만
// =====================================================================

class _SecondaryShortcuts extends ConsumerWidget {
  const _SecondaryShortcuts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingReview = ref.watch(pendingMessageReviewCountProvider);
    // 트레이너 겸 관리자만 노출 — 역할 우선순위상 이런 사람은 홈이 트레이너라
    // 대시보드 자동진입이 안 돼, 여기 진입점이 유일한 통로다.
    final isAdmin = ref.watch(isAdminProvider).value ?? false;

    final items = <AppMenuItem>[
      AppMenuItem(
        // AI 초안 "검수·승인" = 확인 도장 → fact_check 가 행위에 맞음.
        icon: Icons.fact_check_outlined,
        label: 'AI 검수',
        badgeCount: pendingReview,
        onTap: () => context.push('/trainer/ai-review'),
      ),
      if (isAdmin)
        AppMenuItem(
          icon: Icons.dashboard_outlined,
          label: '관리자 대시보드',
          onTap: () => context.push('/admin/dashboard'),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('바로가기'),
        const SizedBox(height: 12),
        AppMenuGrid(items: items),
      ],
    );
  }
}

/// 홈 섹션 구분 라벨 — 섹션 위 작은 제목.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w800,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
