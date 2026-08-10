/// 하단 바 가운데 "기록하기" 진입 시트 (UI 1차 개편 단계 B-3).
///
/// **왜 시트인가 (계획서 §7 리스크 대응):**
///   "기록하기"만 눌렀을 때 *어느 회원의* 기록인지 앱이 알 수 없다. 그래서 지금
///   진행 중이거나 시간이 지났는데 기록이 안 된 수업을 먼저 제안하고, 해당 없으면
///   회원 선택으로 보낸다. 제안이 하나도 없을 땐 시트를 띄우지 않고 곧장 회원
///   목록으로 — 선택지가 하나뿐인 시트는 탭만 한 번 더 먹는 마찰이다.
///
/// 기존 수업(예약)을 기록할 땐 `session/:sid` 로 들어가 예약 → 완료 전이를 태운다
/// (`SessionRepository.buildRecordedSessionUpdate`). 새로 만들 땐 `session/new`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/util/date_format_ko.dart';
import '../home/today_state_chip.dart';
import '../home/trainer_today_providers.dart';

/// "기록하기" 동작 진입점.
///
/// [onPickMember] 는 회원 탭으로 전환하는 콜백 — 셸이 넘겨준다. 회원 목록은 탭
/// 루트라서 `context.push` 로 겹쳐 띄우면 같은 화면이 두 겹이 된다.
Future<void> startRecordFlow(
  BuildContext context,
  WidgetRef ref, {
  required VoidCallback onPickMember,
}) async {
  final candidates =
      ref.read(trainerTodayViewProvider).valueOrNull?.recordCandidates ??
          const <TrainerTodayItem>[];

  // 제안할 수업이 없으면 시트를 건너뛰고 바로 회원 선택으로.
  if (candidates.isEmpty) {
    onPickMember();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('기록할 회원을 선택해 주세요.')),
      );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => _StartRecordSheet(onPickMember: onPickMember),
  );
}

class _StartRecordSheet extends ConsumerWidget {
  const _StartRecordSheet({required this.onPickMember});
  final VoidCallback onPickMember;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // 시트를 열어둔 사이에 수업이 끝나 후보가 바뀔 수 있으니 watch 로 따라간다.
    final candidates =
        ref.watch(trainerTodayViewProvider).valueOrNull?.recordCandidates ??
            const <TrainerTodayItem>[];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '어떤 수업을 기록할까요?',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '진행 중이거나 기록이 남은 수업이에요.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            for (final item in candidates)
              _CandidateTile(
                item: item,
                onTap: () {
                  Navigator.of(context).pop();
                  context.push(
                    '/trainer/members/${item.memberId}'
                    '/session/${item.slot.sessionId}',
                  );
                },
              ),
            const Divider(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.groups_outlined, color: colors.onSurface),
              title: const Text('다른 회원 기록하기'),
              subtitle: const Text('회원 목록에서 선택'),
              trailing: Icon(Icons.chevron_right, color: colors.outline),
              onTap: () {
                Navigator.of(context).pop();
                onPickMember();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 제안 수업 한 줄 — 시간 · 회원명 · 상태.
class _CandidateTile extends StatelessWidget {
  const _CandidateTile({required this.item, required this.onTap});

  final TrainerTodayItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(
        width: 52,
        child: Text(
          formatHm(item.scheduledAt),
          style: theme.textTheme.titleSmall,
        ),
      ),
      title: Text(item.memberName, overflow: TextOverflow.ellipsis),
      subtitle: item.memo == null
          ? null
          : Text(
              item.memo!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
      trailing: TodayStateChip(state: item.state),
      onTap: onTap,
    );
  }
}
