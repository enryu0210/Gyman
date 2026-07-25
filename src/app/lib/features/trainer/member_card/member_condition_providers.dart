/// 회원 체형 제약 Riverpod providers + 액션 컨트롤러 (L1-a).
///
/// - [memberConditionRepositoryProvider]
/// - [conditionsForMemberProvider] : 회원 1명의 제약 리스트 (.family)
/// - [memberConditionControllerProvider] : 등록/해제/삭제 액션 (`AsyncValue<void>`)
///
/// 액션 성공 시 해당 회원의 [conditionsForMemberProvider] 만 invalidate.
/// SnackBar 는 호출 측(카드)이, 컨트롤러는 상태만 — UI/Riverpod 패턴(CLAUDE.md).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../domain/models/member_condition.dart';
import '../../auth/auth_providers.dart';
import 'member_condition_repository.dart';

final memberConditionRepositoryProvider =
    Provider<MemberConditionRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return MemberConditionRepository(client);
});

/// 회원 1명의 체형 제약(활성 먼저, 최근 등록 먼저).
final conditionsForMemberProvider =
    FutureProvider.family<List<MemberCondition>, String>((ref, memberId) async {
  if (!ref.watch(isSupabaseReadyProvider)) return const [];
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const [];
  return ref.watch(memberConditionRepositoryProvider).listForMember(memberId);
});

/// 제약 등록/해제/삭제 컨트롤러. state = `AsyncValue<void>`.
class MemberConditionController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// 제약 1건 등록. recorded_by 는 현재 로그인 트레이너 user_id.
  Future<void> add({
    required String memberId,
    required MemberCondition condition,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = ref.read(authStateProvider).value;
      if (user == null) {
        throw StateError('로그인이 필요합니다.');
      }
      await ref.read(memberConditionRepositoryProvider).add(
            condition: condition,
            recordedBy: user.id,
          );
      ref.invalidate(conditionsForMemberProvider(memberId));
    });
  }

  /// 해제(active=false) / 재적용(active=true). 삭제와 달리 이력이 남는다.
  ///
  /// 메서드명에 `update` 를 쓰지 않는 이유: `AutoDisposeAsyncNotifier.update` 와
  /// 시그니처가 충돌해 invalid_override 가 난다(CLAUDE.md).
  Future<void> changeActive({
    required String id,
    required String memberId,
    required bool active,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref
          .read(memberConditionRepositoryProvider)
          .setActive(id: id, active: active);
      ref.invalidate(conditionsForMemberProvider(memberId));
    });
  }

  Future<void> delete({required String id, required String memberId}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(memberConditionRepositoryProvider).delete(id);
      ref.invalidate(conditionsForMemberProvider(memberId));
    });
  }
}

final memberConditionControllerProvider =
    AutoDisposeAsyncNotifierProvider<MemberConditionController, void>(
  MemberConditionController.new,
);
