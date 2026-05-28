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
///   - AI 안내 메시지 검수 큐 (1.9)
///
/// 와이어프레임 출처: docs/wireframes/02_trainer_home.md.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_providers.dart';
import '../renewal/renewal_alerts_card.dart';

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

/// 회원 목록 / 예약 화면으로 진입하는 카드.
///
/// 1.7 시점에는 두 진입점이면 충분. 1.8 이후 AI 검수 큐 등 추가되면 행 늘림.
class _QuickActionsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.group),
            title: const Text('회원 목록'),
            subtitle: const Text('회원 등록·검색·상세 진입'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/trainer/members'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.event),
            title: const Text('예약'),
            subtitle: const Text('오늘/이번주 예약 · 노쇼·취소 처리'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/trainer/booking'),
          ),
        ],
      ),
    );
  }
}
