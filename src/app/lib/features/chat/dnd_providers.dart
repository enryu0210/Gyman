/// 방해금지(DND) Riverpod providers (2.3).
///
/// - [dndRepositoryProvider]
/// - [myDndProvider]        : 트레이너 본인 설정 (설정 화면용)
/// - [peerDndProvider]      : 상대 user_id 의 DND (.family, 채팅 배너용)
/// - [dndControllerProvider]: 본인 설정 저장 액션
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_client.dart';
import '../../domain/models/dnd_settings.dart';
import '../auth/auth_providers.dart';
import 'dnd_repository.dart';

final dndRepositoryProvider = Provider<DndRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return DndRepository(client);
});

/// 트레이너 본인 DND 설정.
final myDndProvider = FutureProvider.autoDispose<DndSettings>((ref) async {
  if (!ref.watch(isSupabaseReadyProvider)) {
    return const DndSettings(enabled: false);
  }
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const DndSettings(enabled: false);
  return ref.watch(dndRepositoryProvider).loadMine();
});

/// 상대(트레이너) DND 설정 — 채팅 배너 판단용. 상대가 회원이면 null.
final peerDndProvider =
    FutureProvider.autoDispose.family<DndSettings?, String>((ref, peerUserId) {
  if (!ref.watch(isSupabaseReadyProvider)) return Future.value(null);
  return ref.watch(dndRepositoryProvider).loadForPeer(peerUserId);
});

/// 본인 DND 저장 컨트롤러. state = `AsyncValue<void>`.
class DndController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> save(DndSettings settings) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(dndRepositoryProvider).saveMine(settings);
      ref.invalidate(myDndProvider);
    });
  }
}

final dndControllerProvider =
    AutoDisposeAsyncNotifierProvider<DndController, void>(DndController.new);
