/// 회원 홈 화면 — 오늘의 운동 중심 (UI 1차 개편 §3.3).
///
/// 라우트: `/member/home` (회원 셸의 첫 번째 탭)
///
/// **정보 우선순위 (계획서 §3.3 — 잔여 횟수보다 운동 경험을 먼저):**
///   1. 다음 PT 또는 오늘의 운동   — [_TodayHeroSection]
///   2. 트레이너 메시지 또는 안내   — [_InboxCard] (있을 때만)
///   3. 이번 주 운동 현황          — [_WeeklyActivityCard]
///   4. 최근 변화 요약             — [_RecentChangeCard] (측정이 있을 때만)
///   5. 계약 잔여 횟수와 보조 메뉴  — [_RemainingCard] · [_MenuCard]
///
/// 개편 전에는 잔여 횟수가 상단이었고 출석 스트릭이 화면 유일의 볼트 블록이었다.
/// 회원이 앱을 여는 이유는 "오늘 운동을 어떻게 하지"이지 "몇 회 남았지"가 아니라서
/// 순서를 뒤집었다. 잔여 횟수는 사라지지 않고 히어로의 부제로도 한 번 더 보인다.
///
/// **볼트 라임 강조는 화면에 하나(§4.1).** 누가 가져갈지는 상황이 정한다 —
/// 오늘 수업이 남았으면 히어로가, 그렇지 않으면 격자의 "셀프 운동 기록"이 가져간다
/// (판정은 `MemberHomeFocus.takesVoltAccent`).
///
/// 모두 **읽기 전용**(회원은 본인 데이터를 보기만). 조회/권한 분리는 repository + RLS가
/// 담당하고, 본 화면은 provider 의 AsyncValue 를 로딩/에러/데이터로 분기해 그린다.
///
/// 날짜 표기는 `intl` 한국어 로케일 대신 `core/util/date_format_ko.dart` 수동 포맷 사용
/// (프로젝트 지침 — main.dart 가 initializeDateFormatting 미호출).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/util/date_format_ko.dart';
import '../../../core/widgets/app_menu_grid.dart';
import '../../../core/widgets/async_state_views.dart';
import '../../../domain/body_change_summary.dart';
import '../../../domain/member_home_focus.dart';
import '../../../domain/weekly_activity.dart';
import '../attendance/member_attendance_providers.dart';
import '../attendance/member_attendance_repository.dart';
import '../chat/member_chat_providers.dart';
import '../notices/member_notices_providers.dart';
import '../notices/member_notices_repository.dart';
import '../notifications/pt_reminder_providers.dart';
import 'member_home_repository.dart';
import 'member_home_providers.dart';

class MemberHomeScreen extends ConsumerStatefulWidget {
  const MemberHomeScreen({super.key});

  @override
  ConsumerState<MemberHomeScreen> createState() => _MemberHomeScreenState();
}

class _MemberHomeScreenState extends ConsumerState<MemberHomeScreen> {
  @override
  void initState() {
    super.initState();
    // 홈 진입 시 다가올 예약 기준으로 PT 알림 재동기화 — 트레이너가 승인한 예약
    // (requested→scheduled)을 푸시 없이 이 시점에 반영한다. 실패해도 무해(fire&forget).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(ptReminderLeadProvider.notifier).resync();
    });
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(memberHomeSummaryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('내 PT'),
        actions: [
          IconButton(
            tooltip: '설정',
            icon: const Icon(Icons.settings_outlined),
            // 설정(문의·약관·탈퇴·로그아웃)으로 push — 뒤로가기로 홈 복귀.
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: summary.when(
        loading: () => const AppLoadingView(),
        error: (err, _) => AppErrorView(
          onRetry: () => ref.invalidate(memberHomeSummaryProvider),
        ),
        data: (data) => RefreshIndicator(
          // 당겨서 새로고침 — 트레이너가 예약을 추가하면 다시 받아온다.
          onRefresh: () async {
            ref.invalidate(memberHomeSummaryProvider);
            ref.invalidate(memberUnreadTotalProvider);
            ref.invalidate(myNoticesProvider);
            ref.invalidate(attendanceDataProvider);
            // 새로고침 시 알림도 최신 예약 기준으로 재동기화.
            await ref.read(ptReminderLeadProvider.notifier).resync();
          },
          child: _HomeBody(data: data),
        ),
      ),
    );
  }
}

/// 데이터가 도착한 뒤의 본문 — 우선순위 순서대로 섹션을 쌓는다.
class _HomeBody extends StatelessWidget {
  const _HomeBody({required this.data});
  final MemberHomeSummary data;

  @override
  Widget build(BuildContext context) {
    // 히어로 분기와 "이 화면의 볼트를 누가 가져가는가"를 한 번에 정한다.
    final focus = buildMemberHomeFocus(
      todaySessions: data.todaySessions,
      nextSession: data.nextSession,
      now: DateTime.now(),
    );
    final change = buildBodyChangeSummary(data.recentMeasurements);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _GreetingHeader(name: data.memberName),
        const SizedBox(height: 16),
        // ① 오늘의 운동 / 다음 PT
        _TodayHeroSection(focus: focus, summary: data),
        // ② 트레이너 메시지·안내 (없으면 스스로 사라진다)
        const _InboxCard(),
        const SizedBox(height: 16),
        // ③ 이번 주 운동 현황
        const _WeeklyActivityCard(),
        // ④ 최근 변화 요약 (측정 없으면 스스로 사라진다)
        _RecentChangeCard(change: change),
        const SizedBox(height: 16),
        // ⑤ 잔여 횟수 + 보조 메뉴
        _RemainingCard(summary: data),
        const SizedBox(height: 16),
        _MenuCard(highlightSelfLog: !focus.takesVoltAccent),
      ],
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
    final theme = Theme.of(context);
    // 이름 조회 실패(빈 문자열) 시엔 호칭만.
    final greeting = name.isEmpty ? '안녕하세요' : '$name님, 안녕하세요';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formatKoreanDateHeader(DateTime.now()),
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          greeting,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// =====================================================================
// ① 오늘의 운동 / 다음 PT — 히어로
// =====================================================================

/// 상황별로 모습이 갈리는 최상단 카드.
///
/// 오늘 수업이 진행 중이거나 남아 있으면 **볼트 블록**(오늘의 주인공), 그 밖에는
/// 차분한 카드로 알리기만 한다. 예약이 아예 없을 때만 카드 안에 볼트 버튼
/// ("예약 신청")을 둔다 — 예약이 없다는 사실 자체를 라임으로 축하하듯 칠하면
/// 메시지가 뒤집히기 때문에 블록은 쓰지 않는다.
class _TodayHeroSection extends StatelessWidget {
  const _TodayHeroSection({required this.focus, required this.summary});

  final MemberHomeFocus focus;
  final MemberHomeSummary summary;

  @override
  Widget build(BuildContext context) {
    // 잔여 횟수는 히어로의 부제로도 한 번 보여 준다 — 순서상 아래로 내려간 정보라
    // "몇 회 남았더라"를 확인하려고 스크롤하지 않게.
    final remainingLabel =
        summary.hasContract ? '잔여 ${summary.totalRemaining}회' : null;

    return switch (focus.kind) {
      MemberFocusKind.inProgress => _VoltHeroCard(
          overline: '지금 수업 중',
          headline: focus.at == null ? '수업 중' : '${formatHm(focus.at!)} PT',
          caption: remainingLabel,
        ),
      MemberFocusKind.todayUpcoming => _VoltHeroCard(
          overline: '오늘 수업',
          headline: focus.at == null ? '오늘 수업' : '${formatHm(focus.at!)} PT',
          // 남은 시간은 라임 블록 위 잉크 글씨로 이미 대비가 확보된다.
          badge: focus.at == null ? null : untilLabel(focus.at!),
          caption: remainingLabel,
        ),
      MemberFocusKind.awaitingApproval => _PlainHeroCard(
          icon: Icons.hourglass_empty,
          overline: '승인 대기',
          headline: focus.at == null
              ? '예약 신청을 확인 중이에요'
              : '${formatKoreanDateHeader(focus.at!)} ${formatHm(focus.at!)}',
          message: '트레이너가 확인하면 예약이 확정돼요.',
          caption: remainingLabel,
        ),
      MemberFocusKind.todayDone => _PlainHeroCard(
          icon: Icons.check_circle_outline,
          overline: '오늘 수업 완료',
          headline: '오늘 운동을 마쳤어요',
          message: _upNextMessage(focus),
          caption: remainingLabel,
          actionLabel: '수업 기록 보기',
          // 기록 상세는 목록 화면의 시트라 딥링크가 없다 → 기록 탭 루트로 이동
          // (탭 루트는 go, 드릴인은 push — shipped.md §3.8).
          onAction: (context) => context.go('/member/records'),
        ),
      MemberFocusKind.todayFinished => _PlainHeroCard(
          icon: Icons.check_circle_outline,
          overline: '오늘 수업 종료',
          headline: '오늘 운동을 마쳤어요',
          message: '트레이너가 기록을 정리하면 기록 탭에서 볼 수 있어요.'
              '${_upNextSuffix(focus)}',
          caption: remainingLabel,
        ),
      MemberFocusKind.future => _PlainHeroCard(
          icon: Icons.event_available,
          overline: '다음 수업',
          headline: focus.at == null
              ? '예정된 수업'
              : '${formatKoreanDateHeader(focus.at!)} ${formatHm(focus.at!)}',
          badge: focus.at == null ? null : untilLabel(focus.at!),
          caption: remainingLabel,
        ),
      MemberFocusKind.none => _PlainHeroCard(
          icon: Icons.event_busy_outlined,
          overline: '예정된 수업 없음',
          headline: '다음 수업을 잡아 볼까요?',
          message: '예약을 신청하면 트레이너가 확인 후 확정해 드려요.',
          caption: remainingLabel,
          actionLabel: '예약 신청',
          // 예약이 없을 때는 이게 이 화면의 대표 행동 → 유일한 볼트 강조.
          onAction: (context) => context.push('/member/booking'),
          emphasizeAction: true,
        ),
    };
  }

  /// 오늘 수업이 끝난 뒤 붙이는 "다음은 언제" 한 줄.
  static String _upNextMessage(MemberHomeFocus focus) {
    final next = focus.upNextAt;
    if (next == null) return '다음 예약이 잡히면 여기에서 알려드릴게요.';
    return '다음 수업은 ${formatKoreanDateHeader(next)} ${formatHm(next)}예요.';
  }

  /// 기록 대기 문구 뒤에 덧붙이는 다음 수업 안내(없으면 빈 문자열).
  static String _upNextSuffix(MemberHomeFocus focus) {
    final next = focus.upNextAt;
    if (next == null) return '';
    return '\n다음 수업은 ${formatKoreanDateHeader(next)} ${formatHm(next)}예요.';
  }
}

/// 볼트 라임 블록 히어로 — 오늘 수업이 진행 중이거나 남아 있을 때만.
///
/// 라임 위 글씨/아이콘은 대비 규칙상 항상 잉크색([AppTheme.onVolt]). 라이트/다크
/// 어느 쪽에서도 같은 모습이라 "오늘의 주인공" 자리가 흔들리지 않는다.
class _VoltHeroCard extends StatelessWidget {
  const _VoltHeroCard({
    required this.overline,
    required this.headline,
    this.badge,
    this.caption,
  });

  final String overline;
  final String headline;
  final String? badge;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onVoltMuted = AppTheme.onVolt.withValues(alpha: 0.72);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.volt,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                overline,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: onVoltMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 8),
                // 라임 위에서는 흰 배경 대신 잉크 반투명 필 — 라임끼리 겹치면 안 읽힌다.
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.onVolt.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badge!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.onVolt,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(
            headline,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: AppTheme.onVolt,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 6),
            Text(
              caption!,
              style: theme.textTheme.bodyMedium?.copyWith(color: onVoltMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// 차분한 카드 히어로 — 알리기만 하면 되는 상황(완료·대기·다음 수업·예약 없음).
class _PlainHeroCard extends StatelessWidget {
  const _PlainHeroCard({
    required this.icon,
    required this.overline,
    required this.headline,
    this.message,
    this.badge,
    this.caption,
    this.actionLabel,
    this.onAction,
    this.emphasizeAction = false,
  });

  final IconData icon;
  final String overline;
  final String headline;
  final String? message;
  final String? badge;
  final String? caption;
  final String? actionLabel;

  /// `BuildContext` 를 받는 이유 — 라우팅에 필요.
  final void Function(BuildContext context)? onAction;

  /// true 면 볼트 채우기 버튼(화면 유일 강조), false 면 테두리 버튼.
  final bool emphasizeAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: colors.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  overline,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 8),
                  // 남은 시간 = 라임 채우기 + 잉크 글씨(라임은 fill 전용 규칙).
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.volt,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badge!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.onVolt,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Text(
              headline,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
            if (caption != null) ...[
              const SizedBox(height: 6),
              Text(
                caption!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: emphasizeAction
                    ? FilledButton(
                        onPressed: () => onAction!(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.volt,
                          foregroundColor: AppTheme.onVolt,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(actionLabel!),
                      )
                    : OutlinedButton(
                        onPressed: () => onAction!(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(actionLabel!),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// ② 트레이너 메시지·안내
// =====================================================================

/// 안 읽은 채팅·안내가 있을 때만 나타나는 카드.
///
/// **하단 탭에도 배지가 있는데 왜 홈에 또 두나:** 탭 배지는 숫자만 알려 준다. 특히
/// 받은 안내는 "내 정보" 탭 안쪽에 있어 무엇이 왔는지 열어 보기 전엔 모른다. 여기서는
/// 안내 **제목/내용 한 줄**까지 보여 줘, 열지 말지를 홈에서 판단할 수 있게 한다.
/// 읽을 게 없으면 카드 자체가 사라지므로 평소 홈이 길어지지 않는다.
class _InboxCard extends ConsumerWidget {
  const _InboxCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadChats = ref.watch(memberUnreadCountProvider);
    final notices = ref.watch(myNoticesProvider).valueOrNull ?? const [];
    final unreadNotices =
        notices.where((n) => !n.isRead).toList(growable: false);

    if (unreadChats == 0 && unreadNotices.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        child: Column(
          children: [
            if (unreadChats > 0)
              _InboxRow(
                icon: Icons.chat_bubble_outline,
                title: '트레이너 메시지 $unreadChats건',
                subtitle: '읽지 않은 대화가 있어요.',
                // 채팅은 탭 루트 → go(셸 위에 같은 화면을 겹쳐 쌓지 않는다).
                onTap: () => context.go('/member/chat'),
              ),
            if (unreadChats > 0 && unreadNotices.isNotEmpty)
              const Divider(height: 1, indent: 16, endIndent: 16),
            if (unreadNotices.isNotEmpty)
              _InboxRow(
                icon: Icons.campaign_outlined,
                title: unreadNotices.length == 1
                    ? memberNoticeLabel(unreadNotices.first.triggerType)
                    : '새 안내 ${unreadNotices.length}건',
                subtitle: unreadNotices.first.content,
                // 받은 안내 목록은 드릴인 화면 → push(뒤로가기로 홈 복귀).
                onTap: () => context.push('/member/notices'),
              ),
          ],
        ),
      ),
    );
  }
}

class _InboxRow extends StatelessWidget {
  const _InboxRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: colors.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// ③ 이번 주 운동 현황
// =====================================================================

/// 월~일 7칸 도트 + "이번 주 N일 · 연속 N일". 탭하면 출석 달력으로.
///
/// 개편 전 스트릭 배지가 이 자리의 볼트 블록이었는데, 오늘 수업 히어로와 강조가
/// 둘로 갈렸다(§4.1 위반). 강조는 히어로에 넘기고 여기서는 카드 톤으로 내려앉되,
/// "이번 달 N일"보다 한 주 단위로 바꿔 지금 주의 리듬이 보이게 했다.
class _WeeklyActivityCard extends ConsumerWidget {
  const _WeeklyActivityCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final attendance = ref.watch(attendanceDataProvider).valueOrNull;
    final stats = ref.watch(attendanceStatsProvider);

    // 데이터 도착 전엔 빈 주(모두 미운동)로 그린다 — 카드 크기가 흔들리지 않게.
    final week = buildWeeklyActivity(
      workoutDays: attendance?.allDays ?? const <DateTime>{},
      plannedPtDays: _plannedDays(attendance),
      now: DateTime.now(),
    );

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        // 출석 달력은 "일정" 탭 루트 → go.
        onTap: () => context.go('/member/attendance'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '이번 주 ${week.workoutCount}일 운동했어요',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                stats.currentStreak > 0
                    ? '${stats.currentStreak}일 연속 출석 중'
                    : '오늘 운동하고 출석을 이어가 보세요',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final day in week.days) _WeekDot(day: day),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 아직 안 한 예정 PT 가 있는 날 — 출석 달력과 **같은 원자료**에서 뽑는다.
  /// (달력엔 예정 PT 가 표시되는데 홈 주간 도트엔 없으면 같은 주가 달라 보인다.)
  static Set<DateTime> _plannedDays(AttendanceData? attendance) {
    if (attendance == null) return const <DateTime>{};
    return {
      for (final entry in attendance.ptByDay.entries)
        if (entry.value.any((pt) => !pt.done)) entry.key,
    };
  }
}

/// 요일 한 칸 — 도트 + 요일 글자.
///
/// 색만으로 판단시키지 않는다(§4.1): 요일 글자가 항상 함께 있고, 오늘은 글자를 굵게
/// 해서 색맹 사용자도 위치를 잃지 않는다.
class _WeekDot extends StatelessWidget {
  const _WeekDot({required this.day});
  final WeeklyDay day;

  static const _labels = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    // 운동한 날 = 볼트 채우기(라임은 fill 전용), 예정 = 테두리만, 나머지 = 옅은 면.
    final Color fill;
    final Border? border;
    if (day.workedOut) {
      fill = AppTheme.volt;
      border = null;
    } else if (day.hasPlannedPt) {
      fill = Colors.transparent;
      border = Border.all(color: colors.outline, width: 1.5);
    } else {
      fill = colors.onSurface.withValues(alpha: 0.07);
      border = null;
    }

    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: border,
          ),
          alignment: Alignment.center,
          child: day.workedOut
              ? const Icon(Icons.check, size: 16, color: AppTheme.onVolt)
              : null,
        ),
        const SizedBox(height: 6),
        Text(
          _labels[day.date.weekday - 1],
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: day.isToday ? FontWeight.w800 : FontWeight.w500,
            color: day.isToday ? colors.onSurface : colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// =====================================================================
// ④ 최근 변화 요약
// =====================================================================

/// 최근 인바디 측정값과 직전 대비 증감. 측정이 없으면 카드를 그리지 않는다.
///
/// **증감을 성패 색으로 칠하지 않는다.** 체중 -1kg 은 감량 회원에겐 성과지만 증량
/// 회원에겐 반대다. 앱이 회원의 몸을 평가하지 않도록 부호와 숫자만 중립적으로 적는다
/// (도메인 `body_change_summary.dart` 주석 참조).
class _RecentChangeCard extends StatelessWidget {
  const _RecentChangeCard({required this.change});
  final BodyChangeSummary change;

  @override
  Widget build(BuildContext context) {
    if (change.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final measuredAt = change.latestMeasuredAt;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          // 전체 추이 그래프는 드릴인 → push.
          onTap: () => context.push('/member/records/progress'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '최근 변화',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (measuredAt != null)
                      Text(
                        '${formatKoreanDateHeader(measuredAt)} 측정',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (change.weightKg != null)
                      Expanded(
                        child: _MetricTile(
                          label: '체중',
                          unit: 'kg',
                          metric: change.weightKg!,
                        ),
                      ),
                    if (change.bodyFatPct != null)
                      Expanded(
                        child: _MetricTile(
                          label: '체지방률',
                          unit: '%',
                          metric: change.bodyFatPct!,
                        ),
                      ),
                    if (change.skeletalMuscleKg != null)
                      Expanded(
                        child: _MetricTile(
                          label: '골격근량',
                          unit: 'kg',
                          metric: change.skeletalMuscleKg!,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 지표 한 칸 — 라벨 / 값 / 증감.
class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.unit,
    required this.metric,
  });

  final String label;
  final String unit;
  final MetricChange metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final delta = metric.delta;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              _format(metric.latest),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              unit,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          // 비교할 과거가 없으면 "첫 기록" — 0으로 적으면 변화가 없었던 것처럼 읽힌다.
          delta == null ? '첫 기록' : _formatDelta(delta),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  /// 소수 첫째 자리까지(인바디 표기 관행). 정수면 소수점을 안 붙인다.
  static String _format(double v) {
    final rounded = (v * 10).round() / 10;
    return rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(1);
  }

  /// 증감은 부호를 항상 붙인다(+0.5 / -1.2). 반올림 결과가 0이면 "변화 없음".
  static String _formatDelta(double delta) {
    final rounded = (delta * 10).round() / 10;
    if (rounded == 0) return '변화 없음';
    final sign = rounded > 0 ? '+' : '';
    return '$sign${_format(rounded)}';
  }
}

// =====================================================================
// ⑤ 잔여 횟수
// =====================================================================

class _RemainingCard extends StatelessWidget {
  const _RemainingCard({required this.summary});
  final MemberHomeSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    // 전체 계약 총량(게이지 분모). 0이면 게이지 생략(0으로 나누기 방지).
    final totalAll = summary.contracts.fold<int>(
      0,
      (sum, c) => sum + c.totalSessions,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.confirmation_number_outlined,
                  color: colors.onSurfaceVariant,
                ),
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
              // 소진 진행 게이지 — 채움은 볼트 라임(fill), 트랙은 옅은 중립.
              if (totalAll > 0) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: (summary.totalRemaining / totalAll).clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: colors.onSurface.withValues(alpha: 0.08),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppTheme.volt,
                    ),
                  ),
                ),
              ],
              // 계약이 둘 이상이면 계약별 내역도 함께(소진 계약 포함).
              if (summary.contracts.length > 1) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 8),
                for (final c in summary.contracts) _ContractRow(status: c),
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
    final label = '${formatKoreanDate(status.startDate)} 시작 계약';
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
// 보조 메뉴
// =====================================================================

/// 회원 하위 화면 진입 격자 — "바로가기".
///
/// 하단 탭으로 옮겨간 것(예약·수업 기록·채팅·영상·안내·FAQ)은 격자에서 뺐다 —
/// 같은 기능을 두 곳에 두면 어느 쪽이 정답인지 매번 고민하게 된다. 여기 남긴 건
/// 탭 루트가 아니라 **한 단계 더 들어가야 닿는 것**들이다.
class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.highlightSelfLog});

  /// 히어로가 볼트를 안 가져갔을 때만 true — 화면당 강조 1개(§4.1)를 지키려고
  /// 상위(`_HomeBody`)가 계산해 내려 준다.
  final bool highlightSelfLog;

  @override
  Widget build(BuildContext context) {
    final items = <AppMenuItem>[
      AppMenuItem(
        icon: Icons.edit_note_outlined,
        label: '셀프 운동 기록',
        highlight: highlightSelfLog,
        onTap: () => context.push('/member/self-log'),
      ),
      AppMenuItem(
        // 변화 "추이" = 우상향 성장 → show_chart(밋밋한 꺾은선)보다 trending_up 이 의도가 분명.
        icon: Icons.trending_up,
        label: '변화 추이',
        onTap: () => context.push('/member/records/progress'),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '바로가기',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 12),
        AppMenuGrid(items: items),
      ],
    );
  }
}
