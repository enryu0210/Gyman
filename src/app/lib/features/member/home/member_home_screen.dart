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

import '../../../core/theme/app_theme.dart';
import '../../../core/util/date_format_ko.dart';
import '../../../core/widgets/app_menu_grid.dart';
import '../../../core/widgets/async_state_views.dart';
import '../../../domain/models/session.dart';
import '../attendance/member_attendance_providers.dart';
import '../chat/member_chat_providers.dart';
import '../notices/member_notices_providers.dart';
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
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _GreetingHeader(name: data.memberName),
              const SizedBox(height: 16),
              const _StreakCard(),
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
// 출석 스트릭 배지 (동기부여 — 운톡 불만 #6)
// =====================================================================

/// "이번 달 N일 출석 🔥 + 연속 N일" 배지. 탭하면 출석 달력으로.
///
/// 데이터 로딩 전엔 0일로 잠깐 보이지만 곧 채워진다(별도 로딩 표시는 과함).
class _StreakCard extends ConsumerWidget {
  const _StreakCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(attendanceStatsProvider);
    final theme = Theme.of(context);

    // 스트릭은 앱의 "에너지 한 방" 요소 — 라이트/다크 상관없이 볼트 라임 블록으로
    // 고정한다. 라임 위 글씨/아이콘은 대비 규칙상 항상 잉크색([AppTheme.onVolt]).
    return Material(
      color: AppTheme.volt,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/member/attendance'),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              const Icon(Icons.bolt, size: 30, color: AppTheme.onVolt),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '이번 달 ${stats.thisMonthCount}일 운동했어요',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.onVolt,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      stats.currentStreak > 0
                          ? '${stats.currentStreak}일 연속 출석 중!'
                          : '오늘 운동하고 출석을 이어가 보세요',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.onVolt.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: AppTheme.onVolt.withValues(alpha: 0.55),
              ),
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

/// 회원 하위 화면 진입 격자 — "바로가기".
///
/// 대표 액션인 "예약 신청"만 볼트 강조 타일([AppMenuItem.highlight])로 두어
/// 시선을 모으고, 나머지는 카드 톤 타일로 균일하게.
class _MenuCard extends ConsumerWidget {
  const _MenuCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadChats = ref.watch(memberUnreadCountProvider);
    final unreadNotices = ref.watch(unreadNoticeCountProvider);

    // 드릴인은 push — 형제 최상위 라우트여도 뒤로가기가 생긴다.
    final items = <AppMenuItem>[
      AppMenuItem(
        // "예약 신청" = 원하는 시간대를 잡는 행위 → 달력에 체크가 붙는 event_available.
        icon: Icons.event_available_outlined,
        label: '예약 신청',
        highlight: true, // 회원의 대표 액션 — 유일한 볼트 강조.
        onTap: () => context.push('/member/booking'),
      ),
      AppMenuItem(
        // PT 수업 기록 = 웨이트 → 덤벨(피트니스 전용 아이콘).
        icon: Icons.fitness_center,
        label: '내 수업 기록',
        onTap: () => context.push('/member/records'),
      ),
      AppMenuItem(
        icon: Icons.calendar_month_outlined,
        label: '출석 달력',
        onTap: () => context.push('/member/attendance'),
      ),
      AppMenuItem(
        icon: Icons.edit_note_outlined,
        label: '셀프 운동 기록',
        onTap: () => context.push('/member/self-log'),
      ),
      AppMenuItem(
        // 변화 "추이" = 우상향 성장 → show_chart(밋밋한 꺾은선)보다 trending_up 이 의도가 분명.
        icon: Icons.trending_up,
        label: '변화 추이',
        onTap: () => context.push('/member/records/progress'),
      ),
      AppMenuItem(
        icon: Icons.chat_bubble_outline,
        label: '트레이너와 채팅',
        badgeCount: unreadChats,
        onTap: () async {
          await context.push('/member/chat');
          // 채팅에서 돌아오면 읽음 처리됐을 수 있으니 배지 갱신.
          ref.invalidate(memberUnreadTotalProvider);
        },
      ),
      AppMenuItem(
        // 영상은 "촬영"(videocam)이 아니라 "재생/시청" → play_circle.
        icon: Icons.play_circle_outline,
        label: '내 수업 영상',
        onTap: () => context.push('/member/videos'),
      ),
      AppMenuItem(
        // 트레이너가 보낸 안내 = 알림함 → megaphone(마케팅 클리셰) 대신 notifications.
        icon: Icons.notifications_outlined,
        label: '받은 안내',
        badgeCount: unreadNotices,
        onTap: () async {
          await context.push('/member/notices');
          // 안내를 읽고 돌아오면 안읽음 배지 갱신(목록에서 파생).
          ref.invalidate(myNoticesProvider);
        },
      ),
      AppMenuItem(
        icon: Icons.help_outline,
        label: '자주 묻는 질문',
        onTap: () => context.push('/member/faq'),
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
      style: Theme.of(
        context,
      ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
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
                Icon(Icons.event_available, color: colors.onSurfaceVariant),
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
              const SizedBox(height: 6),
              // "3일 뒤" 등 남은 시간 = 라임 배지(채우기 + 잉크 글씨).
              // 라이트/다크 동일하게 보이고, 대비 규칙(라임=fill 전용)을 지킨다.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.volt,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  untilLabel(session!.scheduledAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.onVolt,
                  ),
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
// 에러 표시
// =====================================================================
