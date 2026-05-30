/// 인바디 측정 Riverpod providers + 액션 컨트롤러 (Phase 2 2.2, S1).
///
/// - [bodyMeasurementRepositoryProvider]
/// - [measurementsForMemberProvider] : 회원 1명의 측정 리스트 (.family)
/// - [bodyMeasurementControllerProvider] : 추가/삭제 액션 (`AsyncValue<void>`)
///
/// 액션 성공 시 해당 회원의 [measurementsForMemberProvider] 만 invalidate.
/// SnackBar 는 호출 측(카드)이, 컨트롤러는 상태만 — UI/Riverpod 패턴(CLAUDE.md).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../domain/models/body_measurement.dart';
import '../../auth/auth_providers.dart';
import 'body_measurement_repository.dart';

final bodyMeasurementRepositoryProvider =
    Provider<BodyMeasurementRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return BodyMeasurementRepository(client);
});

/// 회원 1명의 인바디 측정 기록(최신 먼저).
final measurementsForMemberProvider =
    FutureProvider.family<List<BodyMeasurement>, String>((ref, memberId) async {
  if (!ref.watch(isSupabaseReadyProvider)) return const [];
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const [];
  return ref.watch(bodyMeasurementRepositoryProvider).listForMember(memberId);
});

/// 측정 추가/삭제 컨트롤러. state = `AsyncValue<void>`.
class BodyMeasurementController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// 측정 1건 추가. recorded_by 는 현재 로그인 트레이너 user_id.
  Future<void> add({
    required String memberId,
    required BodyMeasurement measurement,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = ref.read(authStateProvider).value;
      if (user == null) {
        throw StateError('로그인이 필요합니다.');
      }
      await ref.read(bodyMeasurementRepositoryProvider).add(
            measurement: measurement,
            recordedBy: user.id,
          );
      ref.invalidate(measurementsForMemberProvider(memberId));
    });
  }

  Future<void> delete({required String id, required String memberId}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(bodyMeasurementRepositoryProvider).delete(id);
      ref.invalidate(measurementsForMemberProvider(memberId));
    });
  }
}

final bodyMeasurementControllerProvider =
    AutoDisposeAsyncNotifierProvider<BodyMeasurementController, void>(
  BodyMeasurementController.new,
);
