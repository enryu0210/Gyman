/// 트레이너 대화 목록 / 안읽음 배지 providers (S2 / 2.3).
///
/// - [trainerChatRepositoryProvider]
/// - [trainerConversationsProvider] : 대화 목록 (FutureProvider, 화면에서 새로고침)
/// - [trainerUnreadTotalProvider]   : 안읽음 총합 FutureProvider
/// - [trainerUnreadCountProvider]   : 위를 int 로 평탄화(홈 배지용, 로딩/에러 시 0)
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../auth/auth_providers.dart';
import 'trainer_chat_repository.dart';

final trainerChatRepositoryProvider = Provider<TrainerChatRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return TrainerChatRepository(client);
});

/// 트레이너 본인의 대화 목록(최근 메시지순).
final trainerConversationsProvider =
    FutureProvider.autoDispose<List<TrainerConversation>>((ref) async {
  if (!ref.watch(isSupabaseReadyProvider)) return const [];
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const [];
  return ref.watch(trainerChatRepositoryProvider).listConversations();
});

/// 안읽음 총합(FutureProvider). 홈 진입 때마다 가볍게 재조회.
final trainerUnreadTotalProvider =
    FutureProvider.autoDispose<int>((ref) async {
  if (!ref.watch(isSupabaseReadyProvider)) return 0;
  final user = ref.watch(authStateProvider).value;
  if (user == null) return 0;
  return ref.watch(trainerChatRepositoryProvider).unreadTotal();
});

/// 홈 배지용 — 로딩/에러 시 0 으로 폴백(배지를 안 띄움).
final trainerUnreadCountProvider = Provider.autoDispose<int>((ref) {
  return ref.watch(trainerUnreadTotalProvider).maybeWhen(
        data: (n) => n,
        orElse: () => 0,
      );
});
