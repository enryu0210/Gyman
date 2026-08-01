/// 회원 본인 AI 사용 동의 providers + 액션 컨트롤러 (legal_docs_gap_check.md A-2).
///
/// - [memberAiConsentRepositoryProvider] : repository 인스턴스
/// - [myAiConsentProvider]               : 회원 본인의 동의 상태
/// - [memberAiConsentControllerProvider] : 거부 토글 액션(`AsyncValue<void>`)
///
/// SnackBar 는 호출 측이, 컨트롤러는 상태만 (UI/Riverpod 패턴).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../auth/auth_providers.dart';
import 'member_ai_consent_repository.dart';

final memberAiConsentRepositoryProvider =
    Provider<MemberAiConsentRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return MemberAiConsentRepository(client);
});

/// 회원 본인의 AI 동의 상태. 미연결(프로필 없음)이면 null.
final myAiConsentProvider =
    FutureProvider.autoDispose<MemberAiConsentState?>((ref) async {
  if (!ref.watch(isSupabaseReadyProvider)) return null;
  final user = ref.watch(authStateProvider).value;
  if (user == null) return null;
  return ref.watch(memberAiConsentRepositoryProvider).fetchMine();
});

/// 거부 토글 액션.
///
/// 메서드명에 `update` 를 쓰지 않는다 — `AsyncNotifier.update` 와 시그니처가
/// 충돌해 invalid_override 가 된다(앱 지침).
class MemberAiConsentController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// [optOut] true = AI 사용 거부, false = 거부 철회.
  Future<void> changeOptOut(bool optOut) async {
    state = const AsyncValue<void>.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(memberAiConsentRepositoryProvider).setOptOut(optOut);
      ref.invalidate(myAiConsentProvider);
    });
  }
}

final memberAiConsentControllerProvider =
    AutoDisposeAsyncNotifierProvider<MemberAiConsentController, void>(
  MemberAiConsentController.new,
);
