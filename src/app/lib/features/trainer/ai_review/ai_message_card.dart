/// 회원 상세의 "AI 안내 메시지" 카드 (Phase 1.9 LLM 연동 진입점).
///
/// 트레이너가 이 회원에게 보낼 안내 메시지 초안을 AI 로 생성하는 진입점.
/// 버튼 → [showGenerateDraftDialog] → 성공 시 검수 큐(draft)에 적재되고,
/// SnackBar 로 "AI 검수에서 확인" 을 안내(이동 액션 제공).
///
/// 실제 생성/동의확인/마스킹/한도/폴백은 다이얼로그+Edge Function 이 담당.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'generate_draft_dialog.dart';

class AiMessageCard extends ConsumerWidget {
  const AiMessageCard({
    super.key,
    required this.memberId,
    required this.memberName,
  });

  final String memberId;
  final String memberName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_outlined, size: 18, color: colors.primary),
                const SizedBox(width: 8),
                Text(
                  'AI 안내 메시지',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '회원 특성을 반영한 안내 메시지 초안을 AI 가 작성합니다. '
              '승인 전엔 회원에게 전송되지 않습니다.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('AI 초안 생성'),
                onPressed: () => _onGenerate(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onGenerate(BuildContext context) async {
    final created = await showGenerateDraftDialog(
      context,
      memberId: memberId,
      memberName: memberName,
    );
    if (created != true || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('AI 초안이 검수 큐에 추가되었습니다.'),
          action: SnackBarAction(
            label: 'AI 검수',
            onPressed: () => context.push('/trainer/ai-review'),
          ),
        ),
      );
  }
}
