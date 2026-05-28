/// 회원 상세 화면 (Phase 1.2-B).
///
/// 라우트: `/trainer/members/:id`
///
/// **Phase 1.2-B 범위 (지금):**
///   - 회원 기본 정보 (이름/연락처/생년월일/등록일) 표시
///   - 목적/배경/부상이력/체형/생활패턴 표시
///   - 매핑 상태(앱 가입 여부) 표시
///   - 수정 다이얼로그 진입
///   - soft delete (확인 다이얼로그 후)
///
/// **추후 단계에서 채워질 섹션 (placeholder만 둠):**
///   - 현재 계약 / 잔여 횟수  → Phase 1.3
///   - 최근 수업 5건           → Phase 1.4
///   - 트레이너 전용 메모     → Phase 1.10 + AI-C
///   - 변화 추이 그래프       → Phase 2 (S1)
///
/// 와이어프레임 출처: docs/wireframes/04_member_card.md 화면 4.2.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/member.dart';
import 'edit_member_dialog.dart';
import 'member_providers.dart';

class MemberDetailScreen extends ConsumerWidget {
  const MemberDetailScreen({super.key, required this.memberId});

  /// 라우트 path parameter — `/trainer/members/:id` 의 `:id`.
  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberAsync = ref.watch(memberByIdProvider(memberId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('회원 상세'),
        actions: [
          // 메뉴는 회원이 로드된 경우에만 보이게
          memberAsync.maybeWhen(
            data: (member) => member == null
                ? const SizedBox.shrink()
                : _DetailMenu(member: member),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: memberAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(
          error: e,
          onRetry: () => ref.invalidate(memberByIdProvider(memberId)),
        ),
        data: (member) {
          if (member == null) {
            return const _NotFoundView();
          }
          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(memberByIdProvider(memberId)),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _HeaderCard(member: member),
                const SizedBox(height: 16),
                _PlaceholderCard(
                  icon: Icons.check_circle_outline,
                  title: '현재 계약',
                  message: 'Phase 1.3에서 PT 계약 등록과 잔여 횟수 표시가 추가됩니다.',
                ),
                const SizedBox(height: 16),
                _ProfileCard(member: member),
                const SizedBox(height: 16),
                _PlaceholderCard(
                  icon: Icons.lock_outline,
                  title: '트레이너 전용 메모',
                  message: 'Phase 1.10에서 트레이너 메모와 AI 초안 검수가 추가됩니다.',
                ),
                const SizedBox(height: 16),
                _PlaceholderCard(
                  icon: Icons.fitness_center,
                  title: '최근 수업',
                  message: 'Phase 1.4에서 수업 기록과 함께 표시됩니다.',
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// =====================================================================
// 상단 헤더 카드 — 이름/매핑 상태/연락처/등록일
// =====================================================================

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.member});
  final Member member;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: colors.primaryContainer,
              child: Text(
                member.name.isNotEmpty ? member.name.characters.first : '?',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: colors.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(member.name, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (member.isLinkedToAuth)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: Icon(
                            Icons.check_circle,
                            size: 16,
                            color: Colors.green,
                          ),
                          label: const Text('앱 가입 완료'),
                          labelStyle: const TextStyle(fontSize: 12),
                        )
                      else
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: const Text('앱 미가입'),
                          labelStyle: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                          backgroundColor: colors.surfaceContainerHighest,
                          side: BorderSide.none,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if ((member.phone ?? '').isNotEmpty)
                    _IconLine(icon: Icons.phone, text: member.phone!),
                  if (member.birthDate != null)
                    _IconLine(
                      icon: Icons.cake_outlined,
                      text: _formatBirth(member.birthDate!),
                    ),
                  _IconLine(
                    icon: Icons.event_outlined,
                    text: '등록일: ${_formatDate(member.createdAt)}',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "1992-03-14 (만 34세)" 형태로 포맷.
  /// intl 패키지가 의존성에 잡혀 있어 별도 utility 미사용.
  String _formatBirth(DateTime birth) {
    final age = _calculateAge(birth, DateTime.now());
    final ymd = DateFormat('yyyy-MM-dd').format(birth);
    return '$ymd (만 $age세)';
  }

  /// 만 나이 계산. 생일이 지났는지로 1 차감.
  static int _calculateAge(DateTime birth, DateTime today) {
    var age = today.year - birth.year;
    final beforeBirthday = (today.month < birth.month) ||
        (today.month == birth.month && today.day < birth.day);
    if (beforeBirthday) age -= 1;
    return age;
  }

  String _formatDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
}

class _IconLine extends StatelessWidget {
  const _IconLine({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: colors.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// 프로필 카드 — 목적/경험/부상이력/체형/생활패턴 (회원도 볼 수 있는 영역)
// =====================================================================

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.member});
  final Member member;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final fields = <(String, String?)>[
      ('운동 목적', member.goal),
      ('운동 경험', member.experience),
      ('부상 이력', member.injuryHistory),
      ('체형 특징', member.bodyFeatures),
      ('생활 패턴', member.lifestyle),
    ];

    final hasAny = fields.any((f) => (f.$2 ?? '').trim().isNotEmpty);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.flag_outlined, size: 18, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '목적 / 배경',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Tooltip(
                  message: '회원 본인도 자신의 카드에서 볼 수 있는 정보',
                  child: Icon(
                    Icons.info_outline,
                    size: 16,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!hasAny)
              Text(
                '입력된 정보가 없습니다. 오른쪽 위 메뉴에서 [수정]으로 채워보세요.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              )
            else
              ...fields
                  .where((f) => (f.$2 ?? '').trim().isNotEmpty)
                  .map((f) => _FieldRow(label: f.$1, value: f.$2!)),
          ],
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Phase 1.2-B 시점에 비어 있는 섹션용 placeholder
// =====================================================================

class _PlaceholderCard extends StatelessWidget {
  const _PlaceholderCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: colors.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// AppBar 메뉴 — 수정 / 삭제
// =====================================================================

class _DetailMenu extends ConsumerWidget {
  const _DetailMenu({required this.member});
  final Member member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_DetailMenuAction>(
      tooltip: '메뉴',
      onSelected: (action) async {
        switch (action) {
          case _DetailMenuAction.edit:
            final updated = await showEditMemberDialog(context, member);
            if (updated == true && context.mounted) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(content: Text('회원 정보가 수정되었습니다.')),
                );
            }
          case _DetailMenuAction.delete:
            final confirmed = await _confirmDelete(context, member.name);
            if (confirmed != true || !context.mounted) return;

            await ref
                .read(editMemberControllerProvider.notifier)
                .softDelete(member.id);

            if (!context.mounted) return;
            final state = ref.read(editMemberControllerProvider);
            if (state.hasError) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(
                      state.error?.toString() ?? '삭제에 실패했습니다.',
                    ),
                  ),
                );
              return;
            }
            // 성공 — 목록으로 돌아감
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(content: Text('${member.name} 회원이 삭제되었습니다.')),
              );
            context.pop();
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: _DetailMenuAction.edit,
          child: ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('수정'),
            dense: true,
          ),
        ),
        PopupMenuItem(
          value: _DetailMenuAction.delete,
          child: ListTile(
            leading: Icon(Icons.delete_outline, color: Colors.red),
            title: Text('삭제', style: TextStyle(color: Colors.red)),
            dense: true,
          ),
        ),
      ],
    );
  }

  /// 확인 다이얼로그 — "정말 삭제" 명시. soft delete임을 안내.
  Future<bool?> _confirmDelete(BuildContext context, String name) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('회원 삭제'),
        content: Text(
          '$name 회원을 삭제하시겠습니까?\n'
          '계약/수업 기록은 보존되지만 목록과 자동 알림에서 즉시 제외됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }
}

enum _DetailMenuAction { edit, delete }

// =====================================================================
// 에러/없음 화면
// =====================================================================

class _NotFoundView extends StatelessWidget {
  const _NotFoundView();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_off_outlined, size: 64, color: colors.outline),
            const SizedBox(height: 16),
            Text(
              '회원을 찾을 수 없습니다',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '삭제됐거나 접근 권한이 없는 회원일 수 있습니다.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(
              '회원 정보를 불러오지 못했습니다',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}
