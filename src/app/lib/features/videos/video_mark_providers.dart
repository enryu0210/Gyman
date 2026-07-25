/// 영상 시점 지적 Riverpod providers + 액션 컨트롤러 (L2).
///
/// - [videoMarkRepositoryProvider]
/// - [marksForVideoProvider]      : 영상 1개의 마킹 (.family, 시점 오름차순)
/// - [videoMarkControllerProvider] : 추가/삭제 액션 (`AsyncValue<void>`)
///
/// 액션 성공 시 해당 영상의 [marksForVideoProvider] 만 invalidate.
/// SnackBar 는 호출 측이, 컨트롤러는 상태만 — UI/Riverpod 패턴(CLAUDE.md).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_client.dart';
import '../../domain/models/class_video_mark.dart';
import '../auth/auth_providers.dart';
import 'video_mark_repository.dart';

final videoMarkRepositoryProvider = Provider<VideoMarkRepository>((ref) {
  return VideoMarkRepository(ref.watch(supabaseClientProvider));
});

/// 영상 1개의 마킹(시점 오름차순).
final marksForVideoProvider =
    FutureProvider.family<List<ClassVideoMark>, String>((ref, videoId) async {
  if (!ref.watch(isSupabaseReadyProvider)) return const [];
  if (ref.watch(authStateProvider).value == null) return const [];
  return ref.watch(videoMarkRepositoryProvider).listForVideo(videoId);
});

/// 마킹 추가/삭제 컨트롤러. state = `AsyncValue<void>`.
class VideoMarkController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> add({required ClassVideoMark mark}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = ref.read(authStateProvider).value;
      if (user == null) {
        throw StateError('로그인이 필요합니다.');
      }
      await ref
          .read(videoMarkRepositoryProvider)
          .add(mark: mark, createdBy: user.id);
      ref.invalidate(marksForVideoProvider(mark.videoId));
    });
  }

  Future<void> delete({required String id, required String videoId}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(videoMarkRepositoryProvider).delete(id);
      ref.invalidate(marksForVideoProvider(videoId));
    });
  }
}

final videoMarkControllerProvider =
    AutoDisposeAsyncNotifierProvider<VideoMarkController, void>(
  VideoMarkController.new,
);
