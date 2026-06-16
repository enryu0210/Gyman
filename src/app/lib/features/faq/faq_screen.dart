/// 자주 묻는 질문(FAQ) 화면 — S3 / Phase 2.4.
///
/// 라우트: `/member/faq` (회원 홈에서 push 진입 → 뒤로가기 생성).
///
/// **구성:**
///   - 상단 안내 배너 — "일반 가이드이며 개인차가 있으니 트레이너와 상담" 고지.
///   - 운동 상식 섹션 — [exerciseFaqs] 를 아코디언(ExpansionTile)으로 나열(정적).
///   - PT 규정 섹션 — 센터 관리자가 입력한 `center_faqs`(0031, Phase 3.2)를 DB 에서
///     조회. 비었거나 조회 실패면 "준비 중" 폴백.
///
/// 운동 상식은 정적이지만 PT 규정은 DB 기반이라 ConsumerWidget 으로 둔다.
///
/// 참고: docs/develop_plan.md §4 Phase 2.4·3.2, 도메인 모델 faq_item.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/faq_item.dart';
import 'center_faq_providers.dart';
import 'exercise_faq_data.dart';

class FaqScreen extends ConsumerWidget {
  const FaqScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policyFaqs = ref.watch(centerPolicyFaqsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('자주 묻는 질문')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          const _DisclaimerBanner(),
          const SizedBox(height: 20),
          _SectionHeader(title: FaqCategory.exercise.label),
          const SizedBox(height: 8),
          // 운동 상식 — 정적 시드를 아코디언으로.
          ...exerciseFaqs.map((faq) => _FaqTile(item: faq)),
          const SizedBox(height: 24),
          _SectionHeader(title: FaqCategory.ptPolicy.label),
          const SizedBox(height: 8),
          // PT 규정 — 센터 관리자 입력(DB). 로딩/에러/빈 결과는 폴백으로.
          policyFaqs.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
            // 미설정/네트워크 실패 등은 회원에게 굳이 에러를 노출하지 않고 안내로.
            error: (_, _) => const _ComingSoonCard(),
            data: (faqs) => faqs.isEmpty
                ? const _ComingSoonCard()
                : Column(
                    children: faqs.map((faq) => _FaqTile(item: faq)).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// 상단 고지 — 검수 없는 정적 콘텐츠임을 알림
// =====================================================================

class _DisclaimerBanner extends StatelessWidget {
  const _DisclaimerBanner();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: colors.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '일반적인 운동 가이드입니다. 몸 상태는 사람마다 다르니, '
              '통증이 있거나 자세한 상담이 필요하면 담당 트레이너에게 문의해 주세요.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSecondaryContainer,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// 섹션 제목
// =====================================================================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

// =====================================================================
// FAQ 항목 — 탭하면 펼쳐지는 아코디언
// =====================================================================

class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.item});
  final FaqItem item;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Theme(
        // ExpansionTile 펼침 시 생기는 기본 divider 라인을 없애 카드와 톤 통일.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Icon(Icons.help_outline, color: colors.primary),
          title: Text(
            item.question,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                item.answer,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      height: 1.5,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// PT 규정 — Phase 3 관리자 입력 전까지 안내
// =====================================================================

class _ComingSoonCard extends StatelessWidget {
  const _ComingSoonCard();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.lock_clock_outlined, color: colors.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '취소·환불·프로그램 규정은 센터마다 달라 준비 중입니다. '
                '궁금한 점은 담당 트레이너에게 문의해 주세요.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
