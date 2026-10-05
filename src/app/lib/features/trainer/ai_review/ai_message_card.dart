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
import 'ai_review_providers.dart';
import 'ai_review_repository.dart';

class AiMessageCard extends ConsumerStatefulWidget {
  const AiMessageCard({
    super.key,
    required this.memberId,
    required this.memberName,
  });

  final String memberId;
  final String memberName;

  @override
  ConsumerState<AiMessageCard> createState() => _AiMessageCardState();
}

class _AiMessageCardState extends ConsumerState<AiMessageCard> {
  bool _generatingCoaching = false;

  @override
  Widget build(BuildContext context) {
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
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: _generatingCoaching ? null : _onGenerateCoaching,
                icon: _generatingCoaching
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.fitness_center, size: 18),
                label: const Text('AI 코칭 가이드'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onGenerateCoaching() async {
    // 상태 반영 전 들어온 재탭도 차단해 중복 초안과 비용을 막는다.
    if (_generatingCoaching) return;
    setState(() => _generatingCoaching = true);
    try {
      await ref.read(aiReviewRepositoryProvider).generateCoachingDraft(
            memberId: widget.memberId,
          );
      if (!mounted) return;
      ref.invalidate(pendingMessagesProvider);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: const Text('AI 코칭 가이드가 검수 큐에 추가되었습니다.'),
          action: SnackBarAction(
            label: 'AI 검수',
            onPressed: () => context.push('/trainer/ai-review'),
          ),
        ));
    } on AiGenerationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      // 예상 밖의 실패도 화면에 원시 예외 대신 재시도 가능한 안내를 보여 준다.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('코칭 가이드 생성에 실패했습니다. 잠시 후 다시 시도해 주세요.')),
      );
    } finally {
      // 화면을 나간 뒤 비동기 응답이 도착해도 폐기된 상태를 수정하지 않는다.
      if (mounted) setState(() => _generatingCoaching = false);
    }
  }

  Future<void> _onGenerate(BuildContext context) async {
    final created = await showGenerateDraftDialog(
      context,
      memberId: widget.memberId,
      memberName: widget.memberName,
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
