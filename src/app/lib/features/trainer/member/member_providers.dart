/// 회원 관리 Riverpod providers + AddMemberController.
///
/// **흐름:**
///   - [membersListProvider] : 트레이너 본인이 볼 수 있는 회원 목록 (FutureProvider)
///   - [memberRepositoryProvider] : Supabase 호출 wrapper
///   - [addMemberControllerProvider] : 추가 액션 + 로딩/에러 상태
///
/// 목록은 트레이너가 회원을 추가하거나 매핑할 때 자동 갱신되도록
/// AddMemberController가 성공 시 [membersListProvider]를 invalidate 한다.
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
