/// 트레이너 전용 메모 Riverpod providers + MemberNoteController (Phase 1.10).
///
/// - [memberNoteRepositoryProvider]
/// - [notesForMemberProvider]   : 회원 1명의 메모 리스트 (.family, 초안+확정)
/// - [memberNoteControllerProvider] : 생성/확정/수정/삭제/수동추가 액션
///
/// 액션 성공 시 해당 회원의 [notesForMemberProvider] 만 invalidate.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../auth/auth_providers.dart';
import 'member_note_repository.dart';

final memberNoteRepositoryProvider = Provider<MemberNoteRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return MemberNoteRepository(client);
});

/// 회원 1명의 트레이너 전용 메모(초안+확정). 최신 먼저.
final notesForMemberProvider =
    FutureProvider.family<List<MemberNote>, String>((ref, memberId) async {
  if (!ref.watch(isSupabaseReadyProvider)) return const [];
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const [];
  return ref.watch(memberNoteRepositoryProvider).listForMember(memberId);
});

/// 메모 액션 컨트롤러. state = `AsyncValue<void>`.
///
/// 생성([generate])은 실패 사유를 호출 측이 분기해야 해서 [AiGenerationException]
/// 을 그대로 rethrow — 호출 측(카드)이 catch 해서 폴백 SnackBar 를 띄운다.
class MemberNoteController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// AI 메모 초안 생성. 성공 시 noteId 반환, 실패 시 예외 rethrow(폴백 UX 용).
  Future<String> generate({required String memberId, String? sessionId}) async {
    state = const AsyncLoading();
    try {
      final id = await ref
          .read(memberNoteRepositoryProvider)
          .generateMemoDraft(memberId: memberId, sessionId: sessionId);
      ref.invalidate(notesForMemberProvider(memberId));
      state = const AsyncData(null);
      return id;
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow; // 호출 측이 code 별 폴백 처리
    }
  }

  Future<void> confirm({required String id, required String memberId}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(memberNoteRepositoryProvider).confirm(id);
      ref.invalidate(notesForMemberProvider(memberId));
    });
  }

  Future<void> editContent({
    required String id,
    required String memberId,
    required String content,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref
          .read(memberNoteRepositoryProvider)
          .editContent(id: id, content: content);
      ref.invalidate(notesForMemberProvider(memberId));
    });
  }

  Future<void> delete({required String id, required String memberId}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(memberNoteRepositoryProvider).delete(id);
      ref.invalidate(notesForMemberProvider(memberId));
    });
  }

  Future<void> addManual({
    required String memberId,
    required String content,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = ref.read(authStateProvider).value;
      if (user == null) {
        throw StateError('로그인이 필요합니다.');
      }
      await ref.read(memberNoteRepositoryProvider).addManual(
            memberId: memberId,
            content: content,
            trainerId: user.id,
          );
      ref.invalidate(notesForMemberProvider(memberId));
    });
  }
}

final memberNoteControllerProvider =
    AutoDisposeAsyncNotifierProvider<MemberNoteController, void>(
  MemberNoteController.new,
);
