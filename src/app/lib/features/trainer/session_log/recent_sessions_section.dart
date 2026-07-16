/// 회원 상세 화면의 "최근 수업" 섹션 (Phase 1.4).
///
/// 회원 1명의 최근 수업 카드 리스트 + "+ 수업 기록" 진입 버튼.
///
/// **카드 1개의 표시 항목:**
///   - 진행 일시 (yyyy-MM-dd HH:mm)
///   - 상태 배지 (완료/노쇼/취소/지각취소/예약)
///   - 종목 수 / 총 세트 (record 있을 때)
///   - 첫 두 종목명 미리보기
///   - 컨디션 이모지
///
/// 탭하면 `/trainer/members/:id/session/:sid` 로 이동해서 수정 화면 진입.
///
/// 참고: docs/wireframes/04_member_card.md 화면 4.3 "최근 수업".
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/async_state_views.dart';
import '../../../domain/models/enums.dart';
import '../booking/request_action_sheet.dart';
import '../member/member_providers.dart';
import 'add_booking_dialog.dart';
import 'booking_status_sheet.dart';
import 'session_providers.dart';
import 'session_repository.dart';

class RecentSessionsSection extends ConsumerWidget {
  const RecentSessionsSection({super.key, required this.memberId});

  /// 회원 ID — 어떤 회원의 최근 수업을 보여줄지.
  final String memberId;

  /// 화면에 표시할 최대 카드 수. 더 보려면 추후 "전체 보기" 추가.
  static const _visibleLimit = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recentSessionsForMemberProvider(memberId));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(memberId: memberId),
            const SizedBox(height: 8),
            async.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => AppInlineError(
                message: '수업 기록을 불러오지 못했습니다.',
                onRetry: () =>
                    ref.invalidate(recentSessionsForMemberProvider(memberId)),
              ),
              data: (list) {
                if (list.isEmpty) return const _EmptyView();
                final visible = list.take(_visibleLimit).toList();
                return Column(
                  children: [
                    for (final sw in visible)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: _SessionCard(memberId: memberId, sw: sw),
                      ),
                    if (list.length > _visibleLimit)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '최근 ${list.length}건 중 $_visibleLimit건만 표시',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// 헤더 — 제목 + 추가 버튼
// =====================================================================

class _Header extends ConsumerWidget {
  const _Header({required this.memberId});
  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.fitness_center, size: 18, color: colors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '최근 수업',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        TextButton.icon(
          onPressed: () async {
            final added = await showAddBookingDialog(
              context,
              memberId: memberId,
            );
            if (added == true && context.mounted) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(content: Text('예약이 등록되었습니다.')),
                );
            }
          },
          icon: const Icon(Icons.event, size: 18),
          label: const Text('예약'),
        ),
        TextButton.icon(
          onPressed: () =>
              context.push('/trainer/members/$memberId/session/new'),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('수업 기록'),
        ),
      ],
    );
  }
}

// =====================================================================
// 빈/에러
// =====================================================================

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        '아직 기록된 수업이 없습니다. 오른쪽 위 [수업 기록] 버튼으로 첫 수업을 기록해 보세요.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
      ),
    );
  }
}


// =====================================================================
// 수업 카드 1개
// =====================================================================

class _SessionCard extends ConsumerWidget {
  const _SessionCard({required this.memberId, required this.sw});

  final String memberId;
  final SessionWithRecord sw;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final s = sw.session;
    final r = sw.record;
    final fmt = DateFormat('yyyy-MM-dd HH:mm');

    return InkWell(
      // 탭 동작:
      //   - done: 수업 기록 수정 화면 진입
      //   - 그 외(scheduled/noShow/canceled/lateCancel): 상태 전이 시트
      onTap: () async {
        if (s.status == SessionStatus.done) {
          context.push('/trainer/members/$memberId/session/${s.id}');
          return;
        }
        // 회원 이름은 회원 detail provider 에서 가져옴 — 이미 캐시되어 있을 가능성 높음.
        final member = await ref.read(memberByIdProvider(memberId).future);
        if (!context.mounted) return;
        final name = member?.name ?? '회원';
        // requested(승인 대기)는 승인/거절 시트, 그 외는 상태 전이 시트.
        if (s.status == SessionStatus.requested) {
          await showRequestActionSheet(
            context,
            session: s,
            memberId: memberId,
            memberName: name,
          );
        } else {
          await showBookingStatusSheet(
            context,
            session: s,
            memberId: memberId,
            memberName: name,
          );
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    fmt.format(s.scheduledAt),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                _StatusBadge(status: s.status),
              ],
            ),
            const SizedBox(height: 6),
            if (r != null) ...[
              Text(
                _exercisePreview(r.exercises.map((e) => e.name).toList()),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _MetaChip(
                    icon: Icons.list_alt,
                    text: '${r.exercises.length}종목 · ${r.totalSets}세트',
                  ),
                  if ((r.condition ?? '').isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _MetaChip(
                      icon: Icons.mood,
                      text: _conditionLabel(r.condition!),
                    ),
                  ],
                  if ((r.pain ?? '').isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _MetaChip(
                      icon: Icons.healing_outlined,
                      text: '통증 기록',
                      // 주의 톤(주황) — 다크에선 밝게, 라이트에선 진하게.
                      color: colors.brightness == Brightness.dark
                          ? const Color(0xFFFFB870)
                          : const Color(0xFFD84315),
                    ),
                  ],
                ],
              ),
            ] else
              Text(
                switch (s.status) {
                  SessionStatus.requested => '회원이 신청한 예약입니다 (승인 대기).',
                  SessionStatus.scheduled => '예약된 수업입니다 (기록 없음).',
                  _ => '기록이 비어 있습니다.',
                },
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// "스쿼트, 데드리프트 외 3개" 같은 한 줄 요약.
  static String _exercisePreview(List<String> names) {
    if (names.isEmpty) return '운동 종목 없음';
    if (names.length <= 2) return names.join(', ');
    return '${names.take(2).join(', ')} 외 ${names.length - 2}개';
  }

  static String _conditionLabel(String code) {
    switch (code) {
      case 'good':
        return '컨디션 좋음';
      case 'normal':
        return '컨디션 보통';
      case 'bad':
        return '컨디션 나쁨';
      default:
        return code; // 자유 입력 그대로
    }
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final SessionStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (label, bg, fg) = _styleFor(status, colors);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }

  static (String, Color, Color) _styleFor(
    SessionStatus s,
    ColorScheme colors,
  ) {
    // 의미색(주황/빨강 등)은 밝기별로 분기 — 라이트의 밝은 shade100 배지는 다크
    // 카드 위에서 밝은 블록으로 떠 깨지므로(재등록 알림과 동일 함정), 다크에선
    // 어두운 배경 + 밝은 글씨로 뒤집는다.
    final isDark = colors.brightness == Brightness.dark;
    switch (s) {
      case SessionStatus.requested: // 승인 대기 = 주의(앰버)
        return isDark
            ? ('승인대기', const Color(0xFF33290A), const Color(0xFFE7C15A))
            : ('승인대기', const Color(0xFFFFF0C8), const Color(0xFF8A6400));
      case SessionStatus.done:
        return ('완료', colors.primaryContainer, colors.onPrimaryContainer);
      case SessionStatus.scheduled:
        return ('예약', colors.surfaceContainerHighest, colors.onSurfaceVariant);
      case SessionStatus.noShow: // 노쇼 = 경고(빨강)
        return isDark
            ? ('노쇼', const Color(0xFF3A1D1F), const Color(0xFFFF8A8F))
            : ('노쇼', const Color(0xFFFDE7E8), const Color(0xFFC62828));
      case SessionStatus.canceled:
        return ('취소', colors.surfaceContainerHighest, colors.onSurfaceVariant);
      case SessionStatus.lateCancel: // 지각취소 = 주의(주황)
        return isDark
            ? ('지각취소', const Color(0xFF352712), const Color(0xFFFFB870))
            : ('지각취소', const Color(0xFFFFF3E0), const Color(0xFFE65100));
    }
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: c),
        const SizedBox(width: 4),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c),
        ),
      ],
    );
  }
}
