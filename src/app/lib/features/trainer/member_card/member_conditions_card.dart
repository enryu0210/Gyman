/// 회원 상세 "체형 특이사항" 카드 (L1-a — docs/design_movement_coaching.md).
///
/// 구성:
///   - 상단: [기록 추가] 버튼
///   - 본문: 등록된 제약 목록(항목명 + 출처 배지 + 메모). 해제/재적용/삭제.
///
/// **가시성이 항목마다 다르다:**
///   회원은 항목명·출처·"회원에게 보일 설명"까지 본다. "트레이너 전용 메모"는
///   회원 측 조회에서 select 되지 않아 보이지 않는다(자물쇠 아이콘으로 구분 표시).
///
/// **왜 이걸 입력하는가(트레이너에게 보여줄 이유):**
///   여기 등록된 제약이 나중에 동작 패턴별 큐로 연결되어(L1-b), 회원이 혼자 운동할 때
///   해당 동작에서 자동으로 주의사항이 뜬다. 지금은 등록·조회까지.
///
/// 추가/해제/삭제는 [memberConditionControllerProvider] 경유. SnackBar 는 본 카드가,
/// 컨트롤러는 상태만 — UI/Riverpod 패턴(CLAUDE.md).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/member_condition.dart';
import 'add_member_condition_dialog.dart';
import 'member_condition_providers.dart';

class MemberConditionsCard extends ConsumerWidget {
  const MemberConditionsCard({super.key, required this.memberId});

  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final async = ref.watch(conditionsForMemberProvider(memberId));
    final busy = ref.watch(memberConditionControllerProvider).isLoading;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.accessibility_new_outlined,
                    size: 18, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('체형 특이사항', style: theme.textTheme.titleMedium),
                ),
                Tooltip(
                  message: '회원도 볼 수 있습니다 (트레이너 전용 메모 제외)',
                  child: Icon(Icons.visibility_outlined,
                      size: 16, color: colors.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: busy ? null : () => _add(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('기록 추가'),
              ),
            ),
            const SizedBox(height: 4),
            async.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('특이사항을 불러오지 못했습니다.\n$e',
                    style: theme.textTheme.bodySmall),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '등록된 특이사항이 없습니다. 측만증·골반 경사처럼 운동을 조정해야 하는 항목을 '
                      '기록해 두면, 회원이 혼자 운동할 때 해당 동작에서 주의사항을 안내할 수 있습니다.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final c in list)
                      _ConditionTile(memberId: memberId, condition: c),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final ok = await showAddMemberConditionDialog(context, memberId: memberId);
    if (ok == true && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('특이사항이 기록되었습니다.')));
    }
  }
}

/// 제약 1건 행 — 항목명 + 출처 배지 + 메모 + 액션 메뉴.
class _ConditionTile extends ConsumerWidget {
  const _ConditionTile({required this.memberId, required this.condition});

  final String memberId;
  final MemberCondition condition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final c = condition;

    // 해제된 항목은 흐리게 — 목록에는 남기되 현재 유효하지 않음을 즉시 구분.
    final dim = !c.active;
    final titleColor = dim ? colors.onSurfaceVariant : colors.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      c.displayName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                        decoration: dim ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    _SourceBadge(source: c.source),
                    if (dim)
                      Text(
                        '해제됨',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                  ],
                ),
                if (c.memberNote != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    c.memberNote!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
                if (c.trainerNote != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lock_outline,
                          size: 14, color: colors.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          c.trainerNote!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          _ActionMenu(memberId: memberId, condition: condition),
        ],
      ),
    );
  }
}

/// 해제/재적용 · 삭제 메뉴.
class _ActionMenu extends ConsumerWidget {
  const _ActionMenu({required this.memberId, required this.condition});

  final String memberId;
  final MemberCondition condition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = condition.active;
    return PopupMenuButton<String>(
      tooltip: '관리',
      icon: const Icon(Icons.more_vert, size: 20),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'toggle',
          child: Row(
            children: [
              Icon(active ? Icons.pause_circle_outline : Icons.play_circle_outline,
                  size: 18),
              const SizedBox(width: 8),
              Text(active ? '해제' : '다시 적용'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 18),
              SizedBox(width: 8),
              Text('삭제'),
            ],
          ),
        ),
      ],
      onSelected: (v) {
        if (v == 'toggle') {
          _toggle(context, ref);
        } else if (v == 'delete') {
          _confirmDelete(context, ref);
        }
      },
    );
  }

  /// 해제/재적용 — 이력이 남으므로 확인 없이 바로 처리(되돌리기 쉬움).
  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    final next = !condition.active;
    await ref.read(memberConditionControllerProvider.notifier).changeActive(
          id: condition.id,
          memberId: memberId,
          active: next,
        );
    if (!context.mounted) return;
    _showResult(
      context,
      ref,
      okMessage: next ? '다시 적용했습니다.' : '해제했습니다.',
      failMessage: '처리에 실패했습니다.',
    );
  }

  /// 삭제는 되돌릴 수 없으므로 확인 + "해제" 대안을 함께 안내.
  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('특이사항 삭제'),
        content: Text(
          '"${condition.displayName}" 기록을 삭제하시겠습니까?\n\n'
          '이력을 남기려면 삭제 대신 [해제]를 사용하세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await ref
        .read(memberConditionControllerProvider.notifier)
        .delete(id: condition.id, memberId: memberId);

    if (!context.mounted) return;
    _showResult(
      context,
      ref,
      okMessage: '삭제했습니다.',
      failMessage: '삭제에 실패했습니다.',
    );
  }

  /// 컨트롤러 상태를 읽어 성공/실패 SnackBar 를 띄운다.
  ///
  /// repository 가 중복 등록 등을 [StateError] 로 바꿔 던지므로, 그 메시지는
  /// 그대로 보여주고 그 외 예외는 일반 문구로 감싼다(raw 예외 노출 금지 — CLAUDE.md).
  void _showResult(
    BuildContext context,
    WidgetRef ref, {
    required String okMessage,
    required String failMessage,
  }) {
    final state = ref.read(memberConditionControllerProvider);
    final err = state.error;
    final msg = !state.hasError
        ? okMessage
        : (err is StateError ? err.message : failMessage);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }
}

/// 출처 배지 — "의료기관 진단"과 "트레이너 관찰"을 한눈에 구분(§5 안전선).
///
/// 하드코딩 Material shade 대신 [ColorScheme] 역할색만 쓴다 — 다크 테마에서
/// 밝은 블록으로 깨지는 것을 피하기 위함(CLAUDE.md 재등록 알림 사례).
class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.source});
  final ConditionSource source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isMedical = source == ConditionSource.medical;

    return Tooltip(
      message: source.description,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            // 진단 이력만 테두리로 한 단계 강조 — 근거의 무게가 다르므로.
            color: isMedical ? colors.outline : Colors.transparent,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isMedical
                  ? Icons.local_hospital_outlined
                  : Icons.visibility_outlined,
              size: 12,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              source.label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
