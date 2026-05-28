/// 수업 기록(session_log) Riverpod providers + Save/EditSessionController.
///
/// **흐름:**
///   - [sessionRepositoryProvider]         : Supabase wrapper
///   - [recentSessionsForMemberProvider]   : 회원 1명의 최근 수업 리스트 (.family)
///   - [sessionDetailProvider]             : 수업 1건 + 기록 (.family)
///   - [saveSessionControllerProvider]     : 신규/수정/삭제 액션 컨트롤러
///
/// **invalidation 정책:**
///   수업이 새로 생기거나 사라지면 잔여 횟수 view 결과도 바뀌므로
///   [contractStatusForMemberProvider] 까지 함께 invalidate.
///   계약 메타(pt_contracts) 자체는 안 바뀌니 [contractsForMemberProvider] 는 그대로.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../auth/auth_providers.dart';
import '../contract/contract_providers.dart';
import 'session_repository.dart';

final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return SessionRepository(client);
});

/// 회원 1명의 최근 수업 (최대 [limit] 건, 진행 일시 내림차순).
///
/// .family 로 memberId 별 분리 캐시. 다른 회원 상세 진입 시 새로 fetch.
/// 본 화면(회원 상세)에서는 5건 정도면 충분 — 기본값 [limit]=20 은 향후 확장 여지.
final recentSessionsForMemberProvider =
    FutureProvider.family<List<SessionWithRecord>, String>(
        (ref, memberId) async {
  if (!ref.watch(isSupabaseReadyProvider)) return const [];
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const [];

  return ref
      .watch(sessionRepositoryProvider)
      .listRecentForMember(memberId, limit: 20);
});

/// 수업 1건 상세. 수정 화면 진입 시 사용.
final sessionDetailProvider =
    FutureProvider.family<SessionWithRecord?, String>((ref, sessionId) async {
  if (!ref.watch(isSupabaseReadyProvider)) return null;
  final user = ref.watch(authStateProvider).value;
  if (user == null) return null;

  return ref.watch(sessionRepositoryProvider).findById(sessionId);
});

/// 신규/수정/삭제 액션 컨트롤러.
///
/// state = `AsyncValue<void>`:
///   - isLoading : 저장 중 (버튼 비활성)
///   - hasError  : 실패 (SnackBar)
///   - data null : 유휴/성공
class SaveSessionController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {
    // 유휴 상태
  }

  /// 수업 완료 + 기록을 한 번에 저장.
  ///
  /// 성공 시 영향 받는 provider 를 invalidate:
  ///   - recentSessionsForMemberProvider(memberId) : 최근 수업 리스트
  ///   - contractStatusForMemberProvider(memberId) : 잔여 횟수 (view 재조회)
  ///   - sessionDetailProvider(id) : 새 id 는 캐시가 없으니 invalidate 불필요
  Future<void> createDone({
    required NewSessionRecordInput input,
    required String memberId,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = ref.read(authStateProvider).value;
      if (user == null) {
        throw StateError('로그인이 필요합니다. 로그아웃 후 다시 시도해 주세요.');
      }
      await ref.read(sessionRepositoryProvider).createDoneSession(
            input: input,
            trainerId: user.id,
          );
      ref.invalidate(recentSessionsForMemberProvider(memberId));
      ref.invalidate(contractStatusForMemberProvider(memberId));
    });
  }

  /// 기존 수업 기록 수정.
  ///
  /// 계약은 바꾸지 않는다고 가정 — 화면에서도 잠금. 그래야 잔여 횟수 정합성 유지.
  ///
  /// 메서드명이 `editRecord` 인 이유: 부모 [AsyncNotifierBase] 가 `update` 라는
  /// 다른 시그니처의 메서드를 이미 가지고 있어서 단순 `update` 로 두면 잘못된 override 가 됨.
  Future<void> editRecord({
    required String sessionId,
    required UpdateSessionRecordInput input,
    required String memberId,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(sessionRepositoryProvider).updateRecord(
            sessionId: sessionId,
            input: input,
          );
      ref.invalidate(sessionDetailProvider(sessionId));
      ref.invalidate(recentSessionsForMemberProvider(memberId));
      // 일시(scheduled_at) 만 바뀌어도 잔여 횟수 자체는 동일하지만, view 결과의
      // 정렬/표시값이 일관되도록 함께 invalidate.
      ref.invalidate(contractStatusForMemberProvider(memberId));
    });
  }

  /// 수업 1건 삭제 — session_records 도 ON DELETE CASCADE 로 함께 사라짐.
  /// 잔여 횟수 1회 복구된다 (done 이었던 수업이 사라지므로).
  Future<void> delete({
    required String sessionId,
    required String memberId,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(sessionRepositoryProvider).deleteSession(sessionId);
      ref.invalidate(sessionDetailProvider(sessionId));
      ref.invalidate(recentSessionsForMemberProvider(memberId));
      ref.invalidate(contractStatusForMemberProvider(memberId));
    });
  }
}

final saveSessionControllerProvider =
    AutoDisposeAsyncNotifierProvider<SaveSessionController, void>(
  SaveSessionController.new,
);
