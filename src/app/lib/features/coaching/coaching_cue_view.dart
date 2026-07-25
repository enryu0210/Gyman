/// 코칭 큐 표시 위젯 — 회원/트레이너 공용 (L1-b).
/// docs/design_movement_coaching.md
///
/// **공용인 이유:** 같은 제약·같은 운동이면 회원 화면과 트레이너 화면에 **같은 큐**가
///   떠야 한다. 화면별로 그리면 문구·정렬이 갈라진다(공용 `ChatScreen`·`ClassVideoPlayer`
///   와 같은 역할 분리).
///
/// **표시 원칙(설계 §5·§9):**
///   - 왜 뜨는지를 항상 같이 보여준다 — 근거 제약명을 칩으로. 이유 없는 지시는
///     무시되거나 불안을 준다.
///   - 진단·처방 톤 금지. `modify` 는 "트레이너가 안내한 대체 동작"으로 주체가 트레이너.
///   - 통증은 언제나 트레이너/의료기관 확인으로 안내를 닫는다.
///
/// 하드코딩 Material shade 대신 [ColorScheme] 역할색만 쓴다 — 다크 테마에서
/// 밝은 블록으로 깨지는 것을 피하기 위함(CLAUDE.md).
library;

import 'package:flutter/material.dart';

import '../../domain/coaching_cue.dart';

class CoachingCueView extends StatelessWidget {
  const CoachingCueView({
    super.key,
    required this.cues,
    this.title = '체형 특이사항 안내',
    this.showDetail = false,
  });

  /// 표시할 큐(이미 [CoachingCueSelector] 로 선별·정렬된 것).
  final List<CoachingCue> cues;

  /// 섹션 제목.
  final String title;

  /// 트레이너용 상세(`detail`)까지 펼칠지. 회원 화면은 false.
  final bool showDetail;

  @override
  Widget build(BuildContext context) {
    // 큐가 없으면 자리도 차지하지 않는다 — 종목을 못 알아본 경우가 흔하고,
    // 그때 빈 박스가 남으면 "뭔가 로딩 중"처럼 보인다.
    if (cues.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    // 대체 권장이 하나라도 있으면 통증 안내 문구를 덧붙인다.
    final hasModify = cues.any((c) => c.action == CueAction.modify);

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.accessibility_new_outlined,
                  size: 16, color: colors.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ),
              Tooltip(
                message: '트레이너가 기록한 체형 특이사항에 따라 표시됩니다',
                child: Icon(Icons.info_outline,
                    size: 14, color: colors.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final cue in cues)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _CueRow(cue: cue, showDetail: showDetail),
            ),
          if (hasModify)
            Text(
              '통증이 있으면 무리하지 말고 트레이너에게 알려주세요.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

/// 큐 1건 — 성격 아이콘 + 문구 + 근거 제약명.
class _CueRow extends StatelessWidget {
  const _CueRow({required this.cue, required this.showDetail});

  final CoachingCue cue;
  final bool showDetail;

  /// 큐 성격별 아이콘. 이모지 대신 Material 라인 아이콘(디자인 시스템).
  IconData get _icon => switch (cue.action) {
        CueAction.modify => Icons.change_circle_outlined,
        CueAction.caution => Icons.warning_amber_outlined,
        CueAction.focus => Icons.lightbulb_outline,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    // 대체 권장만 한 단계 강조 — 나머지는 같은 톤으로 두어 과잉 경고를 피한다.
    final iconColor =
        cue.action == CueAction.modify ? colors.error : colors.onSurfaceVariant;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(_icon, size: 16, color: iconColor),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(cue.cue, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
              // 근거 — "왜 이게 뜨는지"를 항상 같이 보여준다.
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _MetaChip(text: cue.conditionLabel),
                  _MetaChip(text: cue.action.label),
                ],
              ),
              if (showDetail && cue.detail != null) ...[
                const SizedBox(height: 4),
                Text(
                  cue.detail!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Text(
        text,
        style: theme.textTheme.labelSmall
            ?.copyWith(color: colors.onSurfaceVariant),
      ),
    );
  }
}
