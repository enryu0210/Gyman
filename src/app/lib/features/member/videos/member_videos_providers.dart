/// 회원 "수업 영상" Riverpod providers (읽기 전용, S 시리즈).
///
/// - [memberVideosRepositoryProvider] : repository 인스턴스
/// - [myVideosProvider]               : 본인 영상 리스트 FutureProvider
/// - [memberVideoSignedUrlProvider]   : object key → 재생용 서명 URL (.family)
///
/// 새로고침은 `ref.invalidate(myVideosProvider)` 로(당겨서 새로고침/재시도).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../domain/models/class_video.dart';
import 'member_videos_repository.dart';

final memberVideosRepositoryProvider =
    Provider<MemberVideosRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return MemberVideosRepository(client);
});

/// 본인 수업 영상 리스트(최신 먼저).
final myVideosProvider =
    FutureProvider.autoDispose<List<ClassVideo>>((ref) async {
  return ref.watch(memberVideosRepositoryProvider).listMyVideos();
});

/// object key → 재생용 단기 서명 URL. 탭한 영상에 대해서만 발급.
final memberVideoSignedUrlProvider =
    FutureProvider.autoDispose.family<String, String>((ref, storagePath) {
  return ref.watch(memberVideosRepositoryProvider).signedVideoUrl(storagePath);
});
