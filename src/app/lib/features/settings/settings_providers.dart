/// 설정 기능 provider + 액션 컨트롤러.
///
/// - [settingsRepositoryProvider] : 문의/동의/탈퇴 repository
/// - [inquiryControllerProvider]  : 문의 전송 액션
/// - [deleteAccountControllerProvider] : 회원 탈퇴 액션(성공 시 로그아웃까지)
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_client.dart';
import '../auth/auth_providers.dart';
import 'settings_repository.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(supabaseClientProvider));
});

// =====================================================================
// 문의 전송
// =====================================================================

/// 문의 전송 컨트롤러. 성공/실패 상태만 들고, SnackBar 는 호출자가 띄운다.
class InquiryController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> submit(String message) async {
    state = const AsyncLoading();
    // 작성 시점 역할 라벨(참고용) — 실패해도 문의는 보냄.
    final role = await ref.read(currentRoleProvider.future);
    state = await AsyncValue.guard(() async {
      await ref
          .read(settingsRepositoryProvider)
          .submitInquiry(message: message, role: role?.name);
    });
  }
}

final inquiryControllerProvider =
    AutoDisposeAsyncNotifierProvider<InquiryController, void>(
  InquiryController.new,
);

// =====================================================================
// 회원 탈퇴
// =====================================================================

/// 회원 탈퇴 컨트롤러. 서버 익명화·계정 삭제 성공 시 곧바로 로그아웃 →
/// 라우터가 /login 으로 보낸다.
class DeleteAccountController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> deleteAccount({required String reason, String? detail}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref
          .read(settingsRepositoryProvider)
          .deleteAccount(reason: reason, detail: detail);
      // 서버에서 계정이 삭제됐으니 로컬 세션도 비운다.
      await ref.read(authRepositoryProvider).signOut();
    });
  }
}

final deleteAccountControllerProvider =
    AutoDisposeAsyncNotifierProvider<DeleteAccountController, void>(
  DeleteAccountController.new,
);
