/// 관리자 센터 설정 Riverpod provider + 액션 컨트롤러 — Phase 3.2 (C2).
///
/// - [centerSettingsRepositoryProvider] : repository
/// - [centerSettingsProvider]           : 설정 데이터(규정+FAQ) FutureProvider
/// - [centerSettingsControllerProvider] : 저장/추가/수정/삭제 액션 + 로딩·에러 상태
///
/// 액션 성공 시 [centerSettingsProvider] 만 invalidate. SnackBar 는 호출 화면이.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../domain/models/center_rules.dart';
import 'center_settings_repository.dart';

final centerSettingsRepositoryProvider =
    Provider<CenterSettingsRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return CenterSettingsRepository(client);
});

/// 센터 설정 데이터(규정 + FAQ).
final centerSettingsProvider =
    FutureProvider.autoDispose<CenterSettings>((ref) async {
  return ref.watch(centerSettingsRepositoryProvider).loadSettings();
});

// =====================================================================
// 액션 컨트롤러 — 규정 저장 / FAQ 추가·수정·삭제
// =====================================================================

/// 상태는 `AsyncValue<void>` — 호출 화면이 isLoading/hasError 를 그대로 분기.
///
/// 메서드명에 `update` 를 쓰지 않음(AutoDisposeAsyncNotifier.update 시그니처 충돌,
/// CLAUDE.md). 동사+명사로: saveRules / addFaq / editFaq / deleteFaq.
class CenterSettingsController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  CenterSettingsRepository get _repo =>
      ref.read(centerSettingsRepositoryProvider);

  /// 규정 저장.
  Future<void> saveRules(String centerId, CenterRules rules) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _repo.updateRules(centerId, rules);
      ref.invalidate(centerSettingsProvider);
    });
  }

  Future<void> addFaq({
    required String question,
    required String answer,
    int sortOrder = 0,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _repo.addFaq(
        question: question,
        answer: answer,
        sortOrder: sortOrder,
      );
      ref.invalidate(centerSettingsProvider);
    });
  }

  Future<void> editFaq({
    required String id,
    required String question,
    required String answer,
    required int sortOrder,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _repo.editFaq(
        id: id,
        question: question,
        answer: answer,
        sortOrder: sortOrder,
      );
      ref.invalidate(centerSettingsProvider);
    });
  }

  Future<void> deleteFaq(String id) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _repo.deleteFaq(id);
      ref.invalidate(centerSettingsProvider);
    });
  }
}

final centerSettingsControllerProvider =
    AutoDisposeAsyncNotifierProvider<CenterSettingsController, void>(
  CenterSettingsController.new,
);
