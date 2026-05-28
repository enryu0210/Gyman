/// 즐겨찾기 종목 관리 다이얼로그 (Phase 1.5).
///
/// 본 다이얼로그는 수업 기록 화면의 "즐겨찾기" 영역 옆 [관리] 버튼에서 진입한다.
///
/// **기능:**
///   - 즐겨찾기 리스트 표시 (현재 트레이너 본인 것만)
///   - 신규 추가 (TextField + 추가 버튼)
///   - 항목별 삭제
///
/// **단순화 선택:**
///   드래그 정렬은 향후 — 현재는 추가 순서대로 표시.
///   "수정(이름 변경)" 도 없음 → 삭제 후 다시 추가 패턴. 즐겨찾기 1개 변경 빈도가
///   낮다고 가정.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'favorite_exercise_providers.dart';
import 'favorite_exercise_repository.dart';

/// 다이얼로그 진입 함수.
Future<void> showManageFavoritesDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _ManageFavoritesDialog(),
  );
}

class _ManageFavoritesDialog extends ConsumerStatefulWidget {
  const _ManageFavoritesDialog();

  @override
  ConsumerState<_ManageFavoritesDialog> createState() =>
      _ManageFavoritesDialogState();
}

class _ManageFavoritesDialogState
    extends ConsumerState<_ManageFavoritesDialog> {
  final _nameCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _addFavorite() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    await ref.read(favoriteExerciseControllerProvider.notifier).add(name);
    if (!mounted) return;

    final state = ref.read(favoriteExerciseControllerProvider);
    if (state.hasError) {
      // UNIQUE 위반은 PostgrestException — 메시지가 길어서 사용자 친화 문구로 축약.
      final raw = state.error.toString();
      final msg = raw.contains('duplicate') || raw.contains('unique')
          ? '이미 등록된 종목입니다.'
          : raw;
      _toast(msg);
      return;
    }
    _nameCtrl.clear();
  }

  Future<void> _deleteFavorite(FavoriteExercise fav) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('즐겨찾기 삭제'),
        content: Text('"${fav.name}" 을(를) 즐겨찾기에서 삭제하시겠습니까?'),
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
    if (ok != true || !mounted) return;

    await ref
        .read(favoriteExerciseControllerProvider.notifier)
        .delete(fav.id);
    if (!mounted) return;
    final state = ref.read(favoriteExerciseControllerProvider);
    if (state.hasError) {
      _toast(state.error?.toString() ?? '삭제에 실패했습니다.');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final favAsync = ref.watch(favoriteExercisesProvider);
    final busy = ref.watch(favoriteExerciseControllerProvider).isLoading;

    return AlertDialog(
      title: const Text('즐겨찾기 종목 관리'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameCtrl,
                    enabled: !busy,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _addFavorite(),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '종목명 (예: 스쿼트)',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: busy ? null : _addFavorite,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('추가'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 8),
            SizedBox(
              height: 280,
              child: favAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text('불러오기 실패: $e'),
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          '아직 등록된 즐겨찾기가 없습니다.\n'
                          '자주 기록하는 종목 이름을 추가해 보세요.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final fav = list[i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.star, color: Colors.amber),
                        title: Text(fav.name),
                        trailing: IconButton(
                          tooltip: '삭제',
                          onPressed: busy ? null : () => _deleteFavorite(fav),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
      ],
    );
  }
}
