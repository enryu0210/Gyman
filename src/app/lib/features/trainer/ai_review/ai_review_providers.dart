/// AI 검수 Riverpod providers + MessageReviewController (Phase 1.9).
///
/// **흐름:**
///   - [aiReviewRepositoryProvider]        : Supabase wrapper
///   - [pendingMessagesProvider]           : 검수 대상(draft+approved) 리스트
///   - [pendingMessageReviewCountProvider] : 홈 배지용 draft 건수 (파생)
///   - [messageReviewControllerProvider]   : 승인/취소/수정/일괄승인 액션
///
/// 액션 성공 시 [pendingMessagesProvider] 만 invalidate — 영향 범위 최소화.
/// (CLAUDE.md UI/Riverpod 패턴)
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../domain/models/enums.dart';
import '../../auth/auth_providers.dart';
import 'ai_review_repository.dart';

final aiReviewRepositoryProvider = Provider<AiReviewRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return AiReviewRepository(client);
});

/// 검수 대상 메시지(draft + approved) 리스트. 발송 예정 빠른 순.
final pendingMessagesProvider =
    FutureProvider<List<MessageDraft>>((ref) async {
  if (!ref.watch(isSupabaseReadyProvider)) return const [];
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const [];

  return ref.watch(aiReviewRepositoryProvider).listPendingMessages();
});

/// 홈 "AI 검수 N건" 배지용 — 검수 대기(draft) 건수만 센다.
///
/// 별도 count 쿼리 대신 [pendingMessagesProvider] 결과에서 파생.
/// 베타 규모(트레이너 1명·소수 회원)에선 전체 로드 비용이 무시할 수준.
final pendingMessageReviewCountProvider = Provider<int>((ref) {
  final async = ref.watch(pendingMessagesProvider);
  return async.maybeWhen(
    data: (list) =>
        list.where((m) => m.status.isPendingReview).length,
    orElse: () => 0,
  );
});

/// 검수 액션 컨트롤러.
///
/// state = `AsyncValue<void>`:
///   - isLoading : 처리 중
///   - hasError  : 실패 (호출 측이 SnackBar)
///   - data null : 유휴/성공
///
/// 메서드명에 `update` 금지 규칙(CLAUDE.md) 때문에 수정은 `editContent`.
class MessageReviewController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {
    // 유휴 상태
  }

  Future<void> approve(String id) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(aiReviewRepositoryProvider).approve(id);
      ref.invalidate(pendingMessagesProvider);
    });
  }

  Future<void> approveMany(List<String> ids) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(aiReviewRepositoryProvider).approveMany(ids);
      ref.invalidate(pendingMessagesProvider);
    });
  }

  Future<void> cancel(String id) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(aiReviewRepositoryProvider).cancel(id);
      ref.invalidate(pendingMessagesProvider);
    });
  }

  /// 발송(앱 내 전달). 승인된 건을 sent 로 전이 → 회원 "받은 안내"에 노출.
  Future<void> markSent(String id) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(aiReviewRepositoryProvider).markSent(id);
      ref.invalidate(pendingMessagesProvider);
    });
  }

  Future<void> editContent({
    required String id,
    required String content,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref
          .read(aiReviewRepositoryProvider)
          .editContent(id: id, content: content);
      ref.invalidate(pendingMessagesProvider);
    });
  }
}

final messageReviewControllerProvider =
    AutoDisposeAsyncNotifierProvider<MessageReviewController, void>(
  MessageReviewController.new,
);
