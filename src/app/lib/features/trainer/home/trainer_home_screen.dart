/// 트레이너 홈 화면 (Phase 1.7 단계).
///
/// 라우트: `/trainer/home`
///
/// **표시 영역:**
///   1. 오늘 할 일 히어로 — 처리 대기(승인·검수·채팅) 총량을 한 숫자로 (동기부여)
///   2. 재등록 알림 카드 (1.7) — 회원 우선순위 한눈에
///   3. 빠른 진입 — 회원 목록 / 예약 / AI 검수 / 채팅
///
/// **이후 단계에서 추가될 영역 (계획):**
///   - "오늘의 수업" 카드 — 트레이너 본인 오늘 일정 (1.7~1.8 보강)
///
/// 와이어프레임 출처: docs/wireframes/02_trainer_home.md.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/util/date_format_ko.dart';
import '../../../core/widgets/app_menu_grid.dart';
import '../../../core/widgets/bento_layout.dart';
import '../../auth/auth_providers.dart';
import '../ai_review/ai_review_providers.dart';
import '../chat/trainer_chat_providers.dart';
import '../renewal/renewal_alerts_card.dart';
import '../session_log/session_providers.dart';

class TrainerHomeScreen extends ConsumerWidget {
  const TrainerHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('트레이너 홈'),
        actions: [
          IconButton(
            tooltip: '설정',
            icon: const Icon(Icons.settings_outlined),
            // 설정(문의·약관·로그아웃)으로 push — 뒤로가기로 홈 복귀.
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          BentoGrid(
            // 업무 우선순위와 바로가기의 밀도를 같은 벤토 규칙으로 맞춥니다.
            items: [
              const BentoGridItem(columnSpan: 2, child: _TodayBriefingHero()),
              const BentoGridItem(columnSpan: 2, child: RenewalAlertsCard()),
              BentoGridItem(columnSpan: 2, child: _QuickActionsCard()),
            ],
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// 오늘 할 일 히어로 (잉크 블록 — 트레이너 "집중" 요소, DESIGN.md)
// =====================================================================

/// 처리 대기 작업(승인 대기 · AI 검수 · 안읽은 채팅)을 하나의 큰 숫자로 모아
/// "오늘 내 접시에 뭐가 얼마나 있나"를 한눈에 보여주는 히어로.
///
/// 총량(큰 숫자)에 더해, 항목별 칩은 **탭하면 그 처리 화면으로 바로 이동**한다
/// — 밀린 걸 보고 아래 격자에서 타일을 따로 찾을 필요 없이 히어로에서 바로 처리.
/// (아래 [_QuickActionsCard] 는 대기 여부와 무관한 상시 진입점이라 역할이 겹치지 않음.)
///
/// **디자인:** DESIGN.md "잉크 블록"(near-black 배경 + 흰 글씨 + 라임 강조 수치).
/// 잉크 배경은 라이트/다크 공통으로 두되, 다크에선 배경(canvas)과 명도가 가까워
/// 경계가 흐려지므로 얇은 볼트 테두리로 분리한다(라임 테두리는 다크 배경에서만 안전).
class _TodayBriefingHero extends ConsumerWidget {
  const _TodayBriefingHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final pendingReview = ref.watch(pendingMessageReviewCountProvider);
    final pendingRequests = ref.watch(trainerPendingRequestCountProvider);
    final unreadChats = ref.watch(trainerUnreadCountProvider);
    final total = pendingReview + pendingRequests + unreadChats;

    // 잉크 위 글씨는 항상 밝은 계열 — 라이트/다크 공통 고정.
    const onInk = Color(0xFFECEEE9);
    final onInkMuted = onInk.withValues(alpha: 0.60);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.ink,
        borderRadius: BorderRadius.circular(20),
        // 다크에서만 볼트 테두리로 canvas 와 분리(라이트는 잉크-온-라이트라 불필요).
        border: isDark
            ? Border.all(color: AppTheme.volt.withValues(alpha: 0.22))
            : null,
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 날짜 오버라인.
          Row(
            children: [
              Icon(Icons.today_outlined, size: 15, color: onInkMuted),
              const SizedBox(width: 6),
              Text(
                formatKoreanDateHeader(DateTime.now()),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: onInkMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (total == 0)
            // 밀린 게 없을 땐 격려성 문구 — 큰 숫자 대신 담백하게.
            Text(
              '밀린 일 없이 깔끔해요',
              style: theme.textTheme.titleLarge?.copyWith(
                color: onInk,
                fontWeight: FontWeight.w800,
              ),
            )
          else ...[
            // 처리 대기 총량 — 볼트 라임 큰 숫자(잉크 위라 대비 안전).
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '$total',
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: AppTheme.volt,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '건 처리 대기',
                    style: theme.textTheme.titleMedium?.copyWith(color: onInk),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 항목별 내역 — 0인 건 빼고, 있는 것만 라벨로.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (pendingRequests > 0)
                  _BriefingChip(
                    label: '예약 승인',
                    count: pendingRequests,
                    onTap: () => context.push('/trainer/booking'),
                  ),
                if (pendingReview > 0)
                  _BriefingChip(
                    label: 'AI 검수',
                    count: pendingReview,
                    onTap: () => context.push('/trainer/ai-review'),
                  ),
                if (unreadChats > 0)
                  _BriefingChip(
                    label: '안읽은 채팅',
                    count: unreadChats,
                    onTap: () => context.push('/trainer/chat'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 잉크 히어로 안의 항목별 내역 칩 — 반투명 흰 배경 위 흰 글씨.
///
/// **탭하면 해당 처리 화면으로 바로 이동**(예약 승인→예약, AI 검수→검수함 등).
/// 밀린 건 히어로에서 보이는데 처리하려면 아래 격자에서 타일을 따로 찾아야 하던
/// 마찰을 없앤다 — 트레일링 chevron 으로 눌러서 갈 수 있음을 알린다.
class _BriefingChip extends StatelessWidget {
  const _BriefingChip({
    required this.label,
    required this.count,
    required this.onTap,
  });
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const onInk = Color(0xFFECEEE9);
    return Material(
      color: onInk.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$label $count',
                style: const TextStyle(
                  color: onInk,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 3),
              Icon(
                Icons.chevron_right,
                size: 15,
                color: onInk.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 회원 목록 / 예약 / AI 검수 진입 카드.
///
/// AI 검수 행은 검수 대기 건수를 배지로 표시 — [pendingMessageReviewCountProvider].
class _QuickActionsCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingReview = ref.watch(pendingMessageReviewCountProvider);
    final pendingRequests = ref.watch(trainerPendingRequestCountProvider);
    final unreadChats = ref.watch(trainerUnreadCountProvider);
    // 트레이너 겸 관리자만 노출 — 역할 우선순위상 이런 사람은 홈이 트레이너라
    // 대시보드 자동진입이 안 돼, 여기 진입점이 유일한 통로다.
    final isAdmin = ref.watch(isAdminProvider).value ?? false;

    // 격자 타일 목록 — 관리자 겸직이면 대시보드 진입을 맨 앞에 추가.
    // push 진입이라 뒤로가기로 트레이너 홈 복귀(CLAUDE.md go_router 지침).
    final items = <AppMenuItem>[
      if (isAdmin)
        AppMenuItem(
          // "대시보드" 라벨 그대로 = 요약 패널 격자 → dashboard(권한 방패 아이콘보다 직관적).
          icon: Icons.dashboard_outlined,
          label: '관리자 대시보드',
          onTap: () => context.push('/admin/dashboard'),
        ),
      AppMenuItem(
        icon: Icons.groups_outlined,
        label: '회원 목록',
        onTap: () => context.push('/trainer/members'),
      ),
      AppMenuItem(
        icon: Icons.event_outlined,
        label: '예약',
        badgeCount: pendingRequests,
        onTap: () => context.push('/trainer/booking'),
      ),
      AppMenuItem(
        // AI 초안 "검수·승인" = 확인 도장 → 봉투(mark_email)보다 fact_check 가 행위에 맞음.
        icon: Icons.fact_check_outlined,
        label: 'AI 검수',
        badgeCount: pendingReview,
        onTap: () => context.push('/trainer/ai-review'),
      ),
      AppMenuItem(
        icon: Icons.chat_bubble_outline,
        label: '회원 채팅',
        badgeCount: unreadChats,
        onTap: () => context.push('/trainer/chat'),
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

/// 홈 섹션 구분 라벨 — 격자 위 작은 제목.
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
