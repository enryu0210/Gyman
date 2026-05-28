/// 회원 관리 Riverpod providers + Add/EditMemberController.
///
/// **흐름:**
///   - [membersListProvider]         : 트레이너 본인이 볼 수 있는 회원 목록
///   - [memberByIdProvider]          : 회원 1명 상세 (.family — id 별로 분리 캐시)
///   - [memberRepositoryProvider]    : Supabase 호출 wrapper
///   - [addMemberControllerProvider] : 추가 액션 + 로딩/에러 상태
///   - [editMemberControllerProvider]: 수정/삭제 액션 + 로딩/에러 상태
///
/// 목록·상세는 추가/수정/삭제가 성공할 때 컨트롤러가 invalidate 해서 자동 새로고침.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../domain/models/member.dart';
import '../../auth/auth_providers.dart';
import 'member_repository.dart';

/// 회원 repository provider.
/// Supabase 미설정 시 (테스트 환경 등) repository 인스턴스는 만들 수 있지만
/// 실제 호출은 [isSupabaseReadyProvider] 가드로 막힌다.
final memberRepositoryProvider = Provider<MemberRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return MemberRepository(client);
});

/// 현재 트레이너의 회원 목록.
/// Supabase 미설정/미로그인 시 빈 리스트.
final membersListProvider = FutureProvider<List<Member>>((ref) async {
  if (!ref.watch(isSupabaseReadyProvider)) return const [];
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const [];

  return ref.watch(memberRepositoryProvider).listForCurrentTrainer();
});

/// 회원 1명 상세 — id로 조회.
///
/// `.family` 사용 이유: id 별로 캐시를 따로 두기 위해. 회원 A 상세를 보고 나와도
/// 회원 B 상세 진입 시 새로 받지 않고 캐시 사용 가능, 반대로 A 수정 후 invalidate
/// 시에도 A만 다시 받는다.
///
/// 반환 값이 null이면 호출 측에서 "회원을 찾을 수 없습니다" 화면을 보여준다.
/// (삭제됐거나 RLS에서 차단된 경우)
final memberByIdProvider =
    FutureProvider.family<Member?, String>((ref, memberId) async {
  if (!ref.watch(isSupabaseReadyProvider)) return null;
  final user = ref.watch(authStateProvider).value;
  if (user == null) return null;

  return ref.watch(memberRepositoryProvider).findById(memberId);
});

/// 회원 추가 액션 컨트롤러.
///
/// state = `AsyncValue<void>`:
///   - isLoading : 저장 중 (다이얼로그 버튼 비활성)
///   - hasError  : 실패 (SnackBar로 메시지)
///   - data null : 유휴/성공
class AddMemberController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {
    // 유휴 상태
  }

  /// 회원 추가. 성공 시 [membersListProvider] 무효화 → 목록 자동 새로고침.
  Future<void> addMember(NewMemberInput input) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(memberRepositoryProvider).addMember(input);
      // 목록 갱신 — 다음 watch에서 새로 조회
      ref.invalidate(membersListProvider);
    });
  }
}

final addMemberControllerProvider =
    AutoDisposeAsyncNotifierProvider<AddMemberController, void>(
  AddMemberController.new,
);

/// 회원 수정/삭제 액션 컨트롤러.
///
/// AddMemberController 와 분리한 이유: 두 액션이 동시에 진행될 일은 거의 없지만,
/// "수정 다이얼로그가 떠 있는 동안 다른 곳에서 추가가 진행 중" 같은 상태 충돌을
/// 컨트롤러 분리로 자연스럽게 회피. UI 측 isLoading 표시도 명확해짐.
///
/// 성공 시 영향 받는 provider:
///   - [memberByIdProvider]: 해당 회원만 invalidate
///   - [membersListProvider]: 목록 정렬/표시값(이름) 변경 가능 → 전체 invalidate
class EditMemberController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {
    // 유휴 상태
  }

  /// 회원 정보 수정. 성공 시 상세/목록 provider 무효화.
  Future<void> updateMember({
    required String memberId,
    required UpdateMemberInput input,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref
          .read(memberRepositoryProvider)
          .updateMember(memberId, input);
      ref.invalidate(memberByIdProvider(memberId));
      ref.invalidate(membersListProvider);
    });
  }

  /// 회원 soft delete. 성공 시 상세/목록 provider 무효화.
  /// 호출 측은 보통 확인 다이얼로그 통과 후 부르고, 성공하면 이전 화면(목록)으로 pop.
  Future<void> softDelete(String memberId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(memberRepositoryProvider).softDelete(memberId);
      ref.invalidate(memberByIdProvider(memberId));
      ref.invalidate(membersListProvider);
    });
  }
}

final editMemberControllerProvider =
    AutoDisposeAsyncNotifierProvider<EditMemberController, void>(
  EditMemberController.new,
);
