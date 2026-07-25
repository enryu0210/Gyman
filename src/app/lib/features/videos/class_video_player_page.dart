/// 재생기 + 시점 지적 배선 (L2) — 트레이너/회원 공용 진입점.
///
/// **왜 별도 래퍼인가:**
///   [ClassVideoPlayer] 는 Supabase/Riverpod 을 모르는 순수 재생기라는 계약을 지킨다
///   (그 파일 상단 주석). 마킹 조회·추가·삭제라는 *데이터* 책임은 여기로 모아,
///   트레이너 화면과 회원 화면이 같은 배선을 재사용하게 한다.
///
/// **역할 차이는 [canAnnotate] 하나:**
///   true(트레이너) → 코멘트 추가·삭제 가능. false(회원) → 읽기 전용.
///   실제 권한은 앱이 아니라 RLS(0038)가 강제한다 — 이 플래그는 UI 표시용일 뿐이다.
///
/// 진입: `Navigator.push(MaterialPageRoute(... ClassVideoPlayerPage(...)))`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/class_video_mark.dart';
import 'add_video_mark_dialog.dart';
import 'class_video_player.dart';
import 'video_mark_providers.dart';

class ClassVideoPlayerPage extends ConsumerWidget {
  const ClassVideoPlayerPage({
    super.key,
    required this.videoId,
    required this.url,
    required this.title,
    this.canAnnotate = false,
  });

  /// 대상 영상 (class_videos.id) — 마킹 조회 키.
  final String videoId;

  /// 단기 서명 URL(호출 측이 발급해 전달).
  final String url;

  final String title;

  /// 트레이너 시점이면 true — 코멘트 추가·삭제 UI 노출.
  final bool canAnnotate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 마킹은 부가 정보라 로딩·에러로 재생을 막지 않는다 — 실패해도 영상은 나온다.
    final marks = ref.watch(marksForVideoProvider(videoId)).value ?? const [];

    return ClassVideoPlayer(
      url: url,
      title: title,
      marks: marks,
      onAddMarkAt: canAnnotate ? (pos) => _addMark(context, pos) : null,
      onDeleteMark: canAnnotate ? (mark) => _deleteMark(context, ref, mark) : null,
    );
  }

  /// 현재 지점에 코멘트 추가. 저장했으면 true — 재생기가 그 지점에 머무를지 판단한다.
  Future<bool> _addMark(BuildContext context, Duration position) async {
    final ok = await showAddVideoMarkDialog(
      context,
      videoId: videoId,
      position: position,
    );
    if (ok == true && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('코멘트를 남겼습니다.')));
    }
    return ok == true;
  }

  /// 마킹 삭제 — 되돌릴 수 없으므로 확인을 받는다.
  Future<void> _deleteMark(
    BuildContext context,
    WidgetRef ref,
    ClassVideoMark mark,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('코멘트 삭제'),
        content: Text('${mark.timeLabel} 지점의 코멘트를 삭제하시겠습니까?'),
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
        .read(videoMarkControllerProvider.notifier)
        .delete(id: mark.id, videoId: videoId);

    if (!context.mounted) return;
    final state = ref.read(videoMarkControllerProvider);
    final err = state.error;
    final msg = !state.hasError
        ? '삭제했습니다.'
        : (err is StateError ? err.message : '삭제에 실패했습니다.');
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }
}
