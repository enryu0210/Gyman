/// 회원 "내 수업 영상" 화면 (S 시리즈).
///
/// 라우트: `/member/videos`. 홈에서 context.push 로 진입(뒤로가기 생성).
///
/// 트레이너가 올린 본인 영상을 최신순으로 보고, 탭하면 공용 재생기로 재생한다.
/// 모두 **읽기 전용**(회원은 보기만). 조회/권한은 repository + RLS(0027)가 담당.
///
/// 와이어프레임 출처: docs/design_class_videos.md §5.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/util/date_format_ko.dart';
import '../../../domain/models/class_video.dart';
import '../../videos/class_video_player.dart';
import 'member_videos_providers.dart';

class MemberVideosScreen extends ConsumerWidget {
  const MemberVideosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myVideosProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('내 수업 영상')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(
          onRetry: () => ref.invalidate(myVideosProvider),
        ),
        data: (list) {
          if (list.isEmpty) return const _EmptyView();
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myVideosProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              itemCount: list.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) => _VideoTile(video: list[i]),
            ),
          );
        },
      ),
    );
  }
}

/// 영상 1건 행 — 제목 + 길이/날짜, 탭하면 재생.
class _VideoTile extends ConsumerWidget {
  const _VideoTile({required this.video});
  final ClassVideo video;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final meta = <String>[
      if (video.durationLabel != null) video.durationLabel!,
      formatKoreanDate(video.createdAt),
    ].join(' · ');

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: colors.primaryContainer,
        child: Icon(Icons.play_arrow, color: colors.onPrimaryContainer),
      ),
      title: Text(video.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(meta, style: theme.textTheme.bodySmall),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _play(context, ref),
    );
  }

  /// 서명 URL 을 발급해 공용 재생기로 이동.
  Future<void> _play(BuildContext context, WidgetRef ref) async {
    final String url;
    try {
      url =
          await ref.read(memberVideoSignedUrlProvider(video.storagePath).future);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('영상을 불러오지 못했습니다.')));
      return;
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ClassVideoPlayer(url: url, title: video.displayTitle),
    ));
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
            Icon(Icons.video_library_outlined, size: 64, color: colors.outline),
            const SizedBox(height: 16),
            Text('아직 받은 영상이 없습니다',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '트레이너가 자세/폼 체크 영상을 올리면 여기에서 볼 수 있어요.',
              textAlign: TextAlign.center,
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

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 48, color: colors.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              '영상을 불러오지 못했습니다.\n잠시 후 다시 시도해 주세요.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ),
      ),
    );
  }
}
