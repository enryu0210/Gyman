/// 하단 바 가운데 "기록하기" 진입 시트 (UI 1차 개편 단계 B-3).
///
/// **이 시트의 존재 이유 = 회원 탭과 목적지가 다르다.**
///   회원 탭은 *회원을 관리하는* 곳이라 회원을 누르면 회원 카드(계약·메모·인바디)로 간다.
///   기록하기는 *수업을 적는* 동작이라, 여기서 고른 것은 무엇이든 **곧장 기록 화면**으로
///   간다. 이 시트가 회원 목록으로 넘겨 버리면 두 버튼이 같은 곳으로 가는 셈이 되고,
///   기록을 시작하는 데 3탭 이상 든다(계획서 완료 기준: 두 번 이내).
///
/// **고르는 순서 (계획서 §7 리스크 대응 — "어느 회원의 기록인지 불명확"):**
///   1. 지금 기록할 수업 — 진행 중이거나 시간이 지났는데 미기록
///   2. 오늘 예정 수업   — 조금 일찍 끝났거나 미리 열어 두는 경우
///   3. 회원 검색       — 예약에 없던 수업(대체·추가 수업)
///
/// 1·2 는 기존 수업(`session/:sid`)이라 저장 시 예약 → 완료로 전이되고
/// (`SessionRepository.buildRecordedSessionUpdate`), 3 은 새 수업(`session/new`)이다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/util/date_format_ko.dart';
import '../../../core/widgets/async_state_views.dart';
import '../../../domain/models/member.dart';
import '../../../domain/today_schedule.dart';
import '../home/today_state_chip.dart';
import '../home/trainer_today_providers.dart';
import '../member/member_providers.dart';

/// "기록하기" 동작 진입점.
///
/// [onOpenMembersTab] 은 회원 탭으로 전환하는 콜백 — 셸이 넘겨준다. 등록된 회원이
/// 하나도 없을 때(신규 트레이너) 회원 추가로 보내는 **막다른 길 방지용**으로만 쓴다.
Future<void> startRecordFlow(
  BuildContext context, {
  required VoidCallback onOpenMembersTab,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    // 회원 목록까지 담아야 하므로 기본 높이(화면 절반)로는 모자란다.
    isScrollControlled: true,
    builder: (_) => _StartRecordSheet(onOpenMembersTab: onOpenMembersTab),
  );
}

/// **왜 StatefulWidget 인가 (검색 컨트롤러 소유권):**
///   컨트롤러를 바깥에서 만들어 `showModalBottomSheet(...).whenComplete(dispose)` 로
///   정리하면 안 된다 — 그 future 는 `Navigator.pop()` 시점에 완료되는데, 시트는
///   **닫히는 애니메이션 동안 아직 살아서 리빌드**된다. 그 리빌드에서 TextField 가
///   이미 dispose 된 컨트롤러에 리스너를 붙이려다 터지고, 실패한 빌드가
///   Duplicate GlobalKeys · `_dependents.isEmpty` 같은 2차 예외를 줄줄이 만든다(실측).
///   State 가 소유하면 dispose 는 요소가 실제로 unmount 될 때(=애니메이션 종료 후)만 돈다.
///
///   build 안에서 만들지 않는다는 원래 취지(리빌드해도 한글 IME 조합 유지)는
///   State 가 그대로 지킨다 — initState 에서 한 번만 만들기 때문.
class _StartRecordSheet extends StatefulWidget {
  const _StartRecordSheet({required this.onOpenMembersTab});

  final VoidCallback onOpenMembersTab;

  @override
  State<_StartRecordSheet> createState() => _StartRecordSheetState();
}

class _StartRecordSheetState extends State<_StartRecordSheet> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);

    return ConstrainedBox(
      // 화면을 다 덮지 않게 — 뒤가 비쳐야 시트라는 게 읽힌다.
      constraints: BoxConstraints(maxHeight: media.size.height * 0.78),
      child: Padding(
        // 검색 키보드가 올라와도 입력칸이 가리지 않게.
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                '수업 기록 시작',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            // 오늘 수업 + 회원 검색을 한 스크롤에 담는다. 검색 결과가 길어져도
            // 위쪽 오늘 수업이 잘리지 않고 함께 올라간다.
            Flexible(
              child: _SheetBody(
                searchCtrl: _searchCtrl,
                onOpenMembersTab: widget.onOpenMembersTab,
              ),
            ),
            SizedBox(height: media.padding.bottom + 8),
          ],
        ),
      ),
    );
  }
}

class _SheetBody extends ConsumerWidget {
  const _SheetBody({required this.searchCtrl, required this.onOpenMembersTab});

  final TextEditingController searchCtrl;
  final VoidCallback onOpenMembersTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 시트를 열어둔 사이에 수업이 끝나 상태가 바뀔 수 있으니 watch 로 따라간다.
    final today = ref.watch(trainerTodayViewProvider).valueOrNull;
    final membersAsync = ref.watch(membersListProvider);

    // 오늘 기록 대상 후보 — 이미 끝났거나(완료·취소·노쇼) 승인 전인 신청은 뺀다.
    // 승인 대기는 기록이 아니라 승인이 먼저라 여기 두면 잘못된 길로 안내하게 된다.
    final todayItems = <TrainerTodayItem>[
      ...?today?.recordCandidates,
      ...?today?.items.where((i) => i.state == TodaySessionState.upcoming),
    ];

    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      children: [
        if (todayItems.isNotEmpty) ...[
          const _SheetSectionLabel('오늘 수업'),
          for (final item in todayItems)
            _TodaySessionRow(
              item: item,
              onTap: () => _closeThenGo(
                context,
                '/trainer/members/${item.memberId}'
                '/session/${item.slot.sessionId}',
              ),
            ),
          const Divider(height: 28),
        ],
        const _SheetSectionLabel('예약에 없는 수업 기록'),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: TextField(
            controller: searchCtrl,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: '회원 이름 검색',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
          ),
        ),
        membersAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: AppLoadingView(),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: AppInlineError(
              message: '회원 목록을 불러오지 못했습니다.',
              onRetry: () => ref.invalidate(membersListProvider),
            ),
          ),
          data: (members) {
            if (members.isEmpty) {
              return _EmptyMembersHint(onOpenMembersTab: () {
                Navigator.of(context).pop();
                onOpenMembersTab();
              });
            }
            // 타이핑에 반응하는 건 이 목록뿐 — 시트 전체를 setState 로 다시 그리면
            // 무겁고 한글 IME 조합에도 불리하다(CLAUDE.md UI 패턴).
            return ValueListenableBuilder<TextEditingValue>(
              valueListenable: searchCtrl,
              builder: (context, value, _) {
                final filtered = _filterMembers(members, value.text);
                if (filtered.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: Text(
                      '"${value.text.trim()}" 와 일치하는 회원이 없습니다.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final m in filtered)
                      _MemberRow(
                        member: m,
                        // 새 수업 — 기록 화면이 계약 선택·일시 기본값을 채운다.
                        onTap: () => _closeThenGo(
                          context,
                          '/trainer/members/${m.id}/session/new',
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }

  /// 시트를 닫고 목적지로 이동.
  ///
  /// 라우터를 **pop 하기 전에** 잡아 둔다 — pop 뒤의 context 는 곧 사라질 요소를
  /// 가리켜서, 그 context 로 InheritedWidget(GoRouter)을 다시 찾는 건 안전하지 않다.
  static void _closeThenGo(BuildContext context, String location) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push(location);
  }

  /// 이름 부분일치(대소문자 무시). 검색어가 비면 전체.
  static List<Member> _filterMembers(List<Member> members, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return members;
    return members
        .where((m) => m.name.toLowerCase().contains(q))
        .toList(growable: false);
  }
}

// =====================================================================
// 행 위젯들
// =====================================================================

/// 오늘 수업 한 줄 — 시간 · 회원명(메모) · 상태.
class _TodaySessionRow extends StatelessWidget {
  const _TodaySessionRow({required this.item, required this.onTap});

  final TrainerTodayItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: SizedBox(
        width: 46,
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
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
      trailing: TodayStateChip(state: item.state),
      onTap: onTap,
    );
  }
}

/// 회원 한 줄 — 누르면 새 수업 기록 화면으로 직행.
class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.onTap});

  final Member member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasGoal = (member.goal ?? '').trim().isNotEmpty;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: colors.primaryContainer,
        child: Text(
          member.name.isNotEmpty ? member.name.characters.first : '?',
          style: theme.textTheme.titleSmall?.copyWith(
            color: colors.onPrimaryContainer,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      title: Text(member.name, overflow: TextOverflow.ellipsis),
      subtitle: hasGoal
          ? Text(
              member.goal!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            )
          : null,
      trailing: Icon(Icons.edit_note_outlined, color: colors.outline),
      onTap: onTap,
    );
  }
}

/// 회원이 하나도 없을 때 — 안내만 하고 끝내지 않고 회원 추가로 이어 준다.
/// (막다른 길 금지 원칙 — shipped.md 운톡 대응)
class _EmptyMembersHint extends StatelessWidget {
  const _EmptyMembersHint({required this.onOpenMembersTab});
  final VoidCallback onOpenMembersTab;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '등록된 회원이 없습니다.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onOpenMembersTab,
            icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
            label: const Text('회원 추가하러 가기'),
          ),
        ],
      ),
    );
  }
}

/// 시트 안 섹션 라벨.
class _SheetSectionLabel extends StatelessWidget {
  const _SheetSectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
