/// 수업 영상 Riverpod providers + 액션 컨트롤러 (S 시리즈).
///
/// - [classVideoRepositoryProvider]
/// - [videosForMemberProvider]    : 회원 1명의 영상 리스트 (.family)
/// - [classVideoSignedUrlProvider]: object key → 재생용 서명 URL (.family)
/// - [classVideoControllerProvider]: 업로드/삭제 액션 (`AsyncValue<void>`)
///
/// 액션 성공 시 해당 회원의 [videosForMemberProvider] 만 invalidate.
/// SnackBar 는 호출 측(카드/화면)이, 컨트롤러는 상태만 — UI/Riverpod 패턴(CLAUDE.md).
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../domain/models/class_video.dart';
import '../../auth/auth_providers.dart';
import 'class_video_repository.dart';

final classVideoRepositoryProvider = Provider<ClassVideoRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return ClassVideoRepository(client);
});

/// 회원 1명의 수업 영상(최신 먼저). 트레이너 측 카드용.
final videosForMemberProvider =
    FutureProvider.family<List<ClassVideo>, String>((ref, memberId) async {
  if (!ref.watch(isSupabaseReadyProvider)) return const [];
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const [];
  return ref.watch(classVideoRepositoryProvider).listForMember(memberId);
});

/// object key → 재생용 단기 서명 URL. 탭한 영상에 대해서만 발급.
/// autoDispose: 재생기를 닫으면 URL 캐시도 정리.
final classVideoSignedUrlProvider =
    FutureProvider.autoDispose.family<String, String>((ref, storagePath) {
  return ref.watch(classVideoRepositoryProvider).signedVideoUrl(storagePath);
});

/// 영상 업로드/삭제 컨트롤러. state = `AsyncValue<void>`.
class ClassVideoController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// 영상 1건 업로드. uploaded_by 는 현재 로그인 트레이너 user_id.
  Future<void> upload({
    required String memberId,
    required File file,
    String? title,
    int? durationSec,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = ref.read(authStateProvider).value;
      if (user == null) {
        throw StateError('로그인이 필요합니다.');
      }
      await ref.read(classVideoRepositoryProvider).upload(
            memberId: memberId,
            file: file,
            uploadedBy: user.id,
            title: title,
            durationSec: durationSec,
          );
      ref.invalidate(videosForMemberProvider(memberId));
    });
  }

  /// 영상 1건 삭제(메타 + 파일).
  Future<void> remove({
    required String id,
    required String storagePath,
    required String memberId,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref
          .read(classVideoRepositoryProvider)
          .delete(id: id, storagePath: storagePath);
      ref.invalidate(videosForMemberProvider(memberId));
    });
  }
}

final classVideoControllerProvider =
    AutoDisposeAsyncNotifierProvider<ClassVideoController, void>(
  ClassVideoController.new,
);
