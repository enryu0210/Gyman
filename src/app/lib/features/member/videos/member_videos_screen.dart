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
import '../../../core/widgets/async_state_views.dart';
import '../../../domain/models/class_video.dart';
import '../../videos/class_video_player_page.dart';
import '../../videos/class_video_session_link.dart';
import 'member_videos_providers.dart';

class MemberVideosScreen extends ConsumerWidget {
  const MemberVideosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myVideosProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('내 수업 영상')),
      body: async.when(
        loading: () => const AppLoadingView(),
        error: (e, _) => AppErrorView(
          message: '영상을 불러오지 못했습니다.\n잠시 후 다시 시도해 주세요.',
          onRetry: () => ref.invalidate(myVideosProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const AppEmptyView(
              icon: Icons.video_library_outlined,
              title: '아직 받은 영상이 없습니다',
              message: '트레이너가 자세/폼 체크 영상을 올리면 여기에서 볼 수 있어요.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myVideosProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
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

    // 카드 행 — 회원 측 다른 목록(내 기록·받은 안내)과 같은 카드 톤으로 통일.
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _play(context, ref),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: colors.primaryContainer,
                child: Icon(Icons.play_arrow, color: colors.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      meta,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                    // 특정 수업과 연결해 올린 영상이면 그 수업 일시도 함께 표시.
                    if (video.sessionScheduledAt != null)
                      ClassVideoSessionLink(date: video.sessionScheduledAt!),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
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
      // 회원은 트레이너가 남긴 지적을 "읽기만" 한다(canAnnotate 기본 false).
      builder: (_) => ClassVideoPlayerPage(
        videoId: video.id,
        url: url,
        title: video.displayTitle,
      ),
    ));
  }
}

