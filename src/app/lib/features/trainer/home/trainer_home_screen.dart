/// 트레이너 홈 화면 (Phase 1.7 단계).
///
/// 라우트: `/trainer/home`
///
/// **현재 표시 영역:**
///   1. 재등록 알림 카드 (1.7) — 회원 우선순위 한눈에
///   2. 빠른 진입 — 회원 목록 / 예약 화면
///
/// **이후 단계에서 추가될 영역 (계획):**
///   - "오늘의 수업" 카드 — 트레이너 본인 오늘 일정 (1.7~1.8 보강)
///
/// 와이어프레임 출처: docs/wireframes/02_trainer_home.md.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
            tooltip: '로그아웃',
            icon: const Icon(Icons.logout),
            onPressed: () =>
                ref.read(signInControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          const RenewalAlertsCard(),
          const SizedBox(height: 16),
          _QuickActionsCard(),
        ],
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

    return Card(
      child: Column(
        children: [
          if (isAdmin) ...[
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('관리자 대시보드'),
              subtitle: const Text('센터 요약 · 트레이너 성과 · 만료 임박'),
              trailing: const Icon(Icons.chevron_right),
              // push 진입이라 뒤로가기로 트레이너 홈 복귀(CLAUDE.md go_router 지침).
              onTap: () => context.push('/admin/dashboard'),
            ),
            const Divider(height: 1),
          ],
          ListTile(
            leading: const Icon(Icons.group),
            title: const Text('회원 목록'),
            subtitle: const Text('회원 등록·검색·상세 진입'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/trainer/members'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.event),
            title: const Text('예약'),
            subtitle: Text(
              pendingRequests > 0
                  ? '승인 대기 $pendingRequests건 · 예약/노쇼·취소 처리'
                  : '오늘/이번주 예약 · 노쇼·취소 처리',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (pendingRequests > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$pendingRequests',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () => context.push('/trainer/booking'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.mark_email_unread_outlined),
            title: const Text('AI 검수'),
            subtitle: const Text('회원 안내 메시지 초안 검수·승인'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (pendingReview > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$pendingReview',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () => context.push('/trainer/ai-review'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.chat_bubble_outline),
            title: const Text('회원 채팅'),
            subtitle: Text(
              unreadChats > 0 ? '안 읽은 메시지 $unreadChats건' : '회원과 1:1 대화',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (unreadChats > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$unreadChats',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () => context.push('/trainer/chat'),
          ),
        ],
      ),
    );
  }
}
