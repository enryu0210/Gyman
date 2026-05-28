/// 즐겨찾기 종목(trainer_favorite_exercises) 관련 Riverpod providers + controller.
///
/// **흐름:**
///   - [favoriteExerciseRepositoryProvider] : Supabase wrapper
///   - [favoriteExercisesProvider]          : 현재 트레이너의 즐겨찾기 리스트
///   - [favoriteExerciseControllerProvider] : 추가/삭제 액션 + 로딩/에러
///
/// 액션 성공 시 [favoriteExercisesProvider] 만 invalidate — 다른 화면과의 cross-effect 없음.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../auth/auth_providers.dart';
import 'favorite_exercise_repository.dart';

final favoriteExerciseRepositoryProvider =
    Provider<FavoriteExerciseRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return FavoriteExerciseRepository(client);
});

/// 현재 트레이너의 즐겨찾기 리스트. 로그아웃/미설정 시 빈 리스트.
final favoriteExercisesProvider =
    FutureProvider<List<FavoriteExercise>>((ref) async {
  if (!ref.watch(isSupabaseReadyProvider)) return const [];
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const [];

  return ref.watch(favoriteExerciseRepositoryProvider).listForCurrentTrainer();
});

/// 즐겨찾기 추가/삭제 액션 컨트롤러.
///
/// state = `AsyncValue<void>`:
///   - isLoading : 저장/삭제 중 (버튼 비활성)
///   - hasError  : 실패 (SnackBar)
///   - data null : 유휴/성공
class FavoriteExerciseController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {
    // 유휴 상태
  }

  /// 즐겨찾기 추가. UNIQUE 위반 등 에러는 state.hasError 로 노출.
  Future<void> add(String name) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(favoriteExerciseRepositoryProvider).addFavorite(name);
      ref.invalidate(favoriteExercisesProvider);
    });
  }

  Future<void> delete(String id) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(favoriteExerciseRepositoryProvider).deleteFavorite(id);
      ref.invalidate(favoriteExercisesProvider);
    });
  }
}

final favoriteExerciseControllerProvider =
    AutoDisposeAsyncNotifierProvider<FavoriteExerciseController, void>(
  FavoriteExerciseController.new,
);
