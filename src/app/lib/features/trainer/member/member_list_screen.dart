/// 트레이너의 회원 목록 화면.
///
/// /trainer/members 경로. AppBar에 로그아웃, FAB로 회원 추가 다이얼로그.
/// 매핑 안 된 회원(앱 미가입)은 회색 배지로 표시 — UI에서 즉시 구분 가능.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/member.dart';
import '../../auth/auth_providers.dart';
import 'add_member_dialog.dart';
import 'member_providers.dart';

class MemberListScreen extends ConsumerWidget {
  const MemberListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(membersListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('회원 목록'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(membersListProvider),
          ),
          IconButton(
            tooltip: '로그아웃',
            icon: const Icon(Icons.logout),
            onPressed: () =>
                ref.read(signInControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final added = await showAddMemberDialog(context);
          if (added == true && context.mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(content: Text('회원이 추가되었습니다.')));
          }
        },
        icon: const Icon(Icons.person_add),
        label: const Text('회원 추가'),
      ),
      body: members.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(
          error: e,
          onRetry: () => ref.invalidate(membersListProvider),
        ),
        data: (list) {
          if (list.isEmpty) return const _EmptyView();
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(membersListProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
              itemCount: list.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) => _MemberTile(member: list[i]),
            ),
          );
        },
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member});
  final Member member;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: colors.primaryContainer,
        child: Text(
          member.name.isNotEmpty ? member.name.characters.first : '?',
          style: TextStyle(color: colors.onPrimaryContainer),
        ),
      ),
      title: Text(member.name),
      subtitle: Row(
        children: [
          if (member.goal != null && member.goal!.isNotEmpty)
            Flexible(
              child: Text(
                member.goal!,
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            Text(
              '목적 미입력',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
        ],
      ),
      trailing: member.isLinkedToAuth
          ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
          : Tooltip(
              message: '회원이 아직 앱에 가입하지 않음',
              child: Chip(
                visualDensity: VisualDensity.compact,
                label: const Text('앱 미가입'),
                labelStyle: TextStyle(
                  fontSize: 11,
                  color: colors.onSurfaceVariant,
                ),
                backgroundColor: colors.surfaceContainerHighest,
                side: BorderSide.none,
              ),
            ),
      // 상세 화면은 1.2-B에서 — 일단 탭은 비활성
      onTap: null,
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.group_outlined, size: 64, color: colors.outline),
            const SizedBox(height: 16),
            Text(
              '등록된 회원이 없습니다',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '오른쪽 아래 [회원 추가] 버튼으로 시작하세요.\n'
              '회원이 아직 앱을 깔지 않았어도 정보만 먼저 입력할 수 있습니다.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
              '목록을 불러오지 못했습니다',
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
