/// PT 계약 관련 Riverpod providers + AddContractController.
///
/// **흐름:**
///   - [contractRepositoryProvider]      : Supabase wrapper
///   - [contractsForMemberProvider]      : 회원 1명의 활성 계약 리스트 (.family)
///   - [contractStatusForMemberProvider] : 회원 1명의 계약 상태(잔여 등) 리스트 (.family)
///   - [addContractControllerProvider]   : 등록 액션 + 로딩/에러
///
/// 추가/삭제 시 두 list provider 모두 invalidate — 화면이 항상 일관됨.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../domain/models/pt_contract.dart';
import '../../auth/auth_providers.dart';
import 'contract_repository.dart';

final contractRepositoryProvider = Provider<ContractRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return ContractRepository(client);
});

/// 회원 1명의 활성 계약 리스트.
/// 시작일 내림차순 (최신 먼저).
final contractsForMemberProvider =
    FutureProvider.family<List<PtContract>, String>((ref, memberId) async {
  if (!ref.watch(isSupabaseReadyProvider)) return const [];
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const [];

  return ref.watch(contractRepositoryProvider).listForMember(memberId);
});

/// 회원 1명의 계약 상태(잔여/사용 등) 리스트. v_contract_status 조회.
///
/// **분리 이유:**
///   `contractsForMemberProvider` 는 pt_contracts 행을 그대로 받아 가격/메모 등을 본다.
///   잔여 횟수는 sessions 와의 조인 결과라 view 한 번 더 받는 게 단순함.
///   sessions 변경 시(1.4 이후) 이 provider만 invalidate 해서 잔여만 갱신 가능.
final contractStatusForMemberProvider =
    FutureProvider.family<List<ContractStatusRow>, String>(
        (ref, memberId) async {
  if (!ref.watch(isSupabaseReadyProvider)) return const [];
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const [];

  return ref.watch(contractRepositoryProvider).listStatusForMember(memberId);
});

/// 계약 추가/삭제 액션 컨트롤러.
///
/// state = `AsyncValue<void>`:
///   - isLoading : 저장 중
///   - hasError  : 실패 (SnackBar)
///   - data null : 유휴/성공
class AddContractController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {
    // 유휴 상태
  }

  /// 계약 추가. 성공 시 회원별 계약/상태 provider 모두 invalidate.
  Future<void> addContract(NewContractInput input) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = ref.read(authStateProvider).value;
      if (user == null) {
        throw StateError('로그인이 필요합니다. 로그아웃 후 다시 시도해 주세요.');
      }
      await ref.read(contractRepositoryProvider).addContract(
            input: input,
            trainerId: user.id,
          );
      ref.invalidate(contractsForMemberProvider(input.memberId));
      ref.invalidate(contractStatusForMemberProvider(input.memberId));
    });
  }

  /// 계약 soft delete. memberId는 invalidate 대상 결정용.
  Future<void> softDelete({
    required String contractId,
    required String memberId,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(contractRepositoryProvider).softDelete(contractId);
      ref.invalidate(contractsForMemberProvider(memberId));
      ref.invalidate(contractStatusForMemberProvider(memberId));
    });
  }
}

final addContractControllerProvider =
    AutoDisposeAsyncNotifierProvider<AddContractController, void>(
  AddContractController.new,
);
