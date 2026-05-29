/// 인증 관련 Riverpod provider 모음 + 로그인 액션 컨트롤러.
///
/// **구성:**
///   - [authRepositoryProvider]   : Supabase Auth 래퍼
///   - [roleRepositoryProvider]   : 역할 판정 repository
///   - [authStateProvider]        : User? 스트림 (auth 상태 변경 자동 반영)
///   - [currentRoleProvider]      : 현재 사용자 역할 (FutureProvider, user 변경 시 재계산)
///   - [signInControllerProvider] : 로그인 액션 + `AsyncValue<void>` 상태
///
/// **Supabase 미설정 환경(테스트/키 빈 상태) 대응:**
///   [Env.isSupabaseConfigured] 가 false면 인증 관련 stream/future가 즉시 null/완료를
///   반환하도록 분기. UI는 로그인 화면에 "Supabase 미설정" 안내를 띄운다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../../core/supabase/supabase_client.dart';
import '../../domain/models/enums.dart';
import 'auth_repository.dart';
import 'role_repository.dart';

/// Supabase 초기화 완료 여부.
/// 미설정 시 auth 관련 호출이 모두 안전한 기본값을 반환하도록 게이트로 사용.
final isSupabaseReadyProvider = Provider<bool>((ref) {
  return Env.isSupabaseConfigured;
});

/// 인증 repository.
/// Supabase 미설정 시에도 인스턴스는 만들지만, 내부 호출이 실패하면
/// AuthFailure로 변환되어 UI가 안전하게 표시함.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return AuthRepository(client);
});

/// 역할 판정 repository.
final roleRepositoryProvider = Provider<RoleRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return RoleRepository(client);
});

/// 현재 인증 상태 스트림.
/// Supabase 미설정 시 항상 null 발행 (로그인 화면 유지).
final authStateProvider = StreamProvider<User?>((ref) {
  if (!ref.watch(isSupabaseReadyProvider)) {
    return Stream<User?>.value(null);
  }
  return ref.watch(authRepositoryProvider).authStateChanges();
});

/// 현재 사용자 역할.
/// authStateProvider가 변할 때마다 재계산 → 로그인/로그아웃 즉시 반영.
///
/// 반환:
///   - data: UserRole? (null은 "역할 미정" — 프로필 미생성 케이스)
///   - loading: 판정 중
///   - error: DB 조회 실패
final currentRoleProvider = FutureProvider<UserRole?>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return null;
  if (!ref.watch(isSupabaseReadyProvider)) return null;

  return ref.watch(roleRepositoryProvider).getCurrentUserRole();
});

// =====================================================================
// SignInController — 로그인 액션 + 로딩/에러 상태 관리
// =====================================================================

/// 로그인 진행 상태.
///
/// AsyncNotifier 패턴: state 자체가 `AsyncValue<void>`라서 UI에서
///   - state.isLoading → 버튼 비활성 + 인디케이터
///   - state.hasError → 에러 메시지 표시
///   - 정상 완료 → authStateProvider가 user 발행 → router redirect
/// 흐름이 자연스럽다.
class SignInController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {
    // 초기 상태는 "유휴" — 아무 일도 하지 않음.
  }

  /// 이메일/비밀번호 로그인 시도.
  ///
  /// 성공 시 state = AsyncData(null), 실패 시 AsyncError(AuthFailure).
  /// 호출 측은 await 후 [AsyncValue.hasError] 확인.
  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(authRepositoryProvider);
      await repo.signInWithPassword(email: email, password: password);
    });
  }

  /// 회원 셀프 가입.
  ///
  /// 성공 시: (이메일 인증 OFF면) 즉시 로그인 → 라우터가 초대 코드 입력 화면으로,
  ///         (이메일 인증 ON이면) 인증 메일 발송 — 호출 측이 안내.
  Future<void> signUp({
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(authRepositoryProvider).signUp(
            email: email,
            password: password,
          );
    });
  }

  /// 로그아웃.
  Future<void> signOut() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(authRepositoryProvider).signOut();
    });
  }
}

/// 로그인 컨트롤러 provider.
/// AutoDispose — 로그인 화면 벗어나면 상태 폐기 (다시 들어왔을 때 깨끗한 상태).
final signInControllerProvider =
    AutoDisposeAsyncNotifierProvider<SignInController, void>(
  SignInController.new,
);
