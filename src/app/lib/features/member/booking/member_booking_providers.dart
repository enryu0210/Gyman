/// 회원 예약 신청 화면용 Riverpod provider + 액션 컨트롤러 (회원 로드맵 ⑤).
///
/// - [memberBookingRepositoryProvider] : repository 인스턴스
/// - [memberBookableContractsProvider] : 신청 가능한 본인 계약 목록
/// - [myBookingsProvider]              : 본인 신청(requested)+확정(scheduled) 목록
/// - [memberBookingControllerProvider] : 신청/철회 액션 컨트롤러
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../domain/models/session.dart';
import 'member_booking_repository.dart';

final memberBookingRepositoryProvider =
    Provider<MemberBookingRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return MemberBookingRepository(client);
});

/// 신청 가능한 본인 계약 목록.
final memberBookableContractsProvider =
    FutureProvider.autoDispose<List<BookableContract>>((ref) async {
  return ref.watch(memberBookingRepositoryProvider).listBookableContracts();
});

/// 본인 신청+확정 예약 목록.
final myBookingsProvider =
    FutureProvider.autoDispose<List<Session>>((ref) async {
  return ref.watch(memberBookingRepositoryProvider).listMyBookings();
});

/// 예약 신청/철회 액션 컨트롤러.
///
/// state = `AsyncValue<void>`: isLoading(처리 중) / hasError(실패) / null(유휴·성공).
/// SnackBar 는 호출 측이 띄우고, 컨트롤러는 상태만 관리(프로젝트 UI 패턴).
class MemberBookingController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {
    // 유휴 상태
  }

  /// 예약 신청.
  ///
  /// 성공 시 본인 예약 목록을 invalidate. 신청은 잔여를 차감하지 않으므로
  /// 홈의 잔여/다음수업(scheduled)에는 영향이 없어 별도 갱신 불필요.
  Future<void> request({
    required String contractId,
    required DateTime scheduledAt,
    String? memo,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(memberBookingRepositoryProvider).requestBooking(
            contractId: contractId,
            scheduledAt: scheduledAt,
            memo: memo,
          );
      ref.invalidate(myBookingsProvider);
    });
  }

  /// 신청 철회.
  Future<void> withdraw(String sessionId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(memberBookingRepositoryProvider).cancelRequest(sessionId);
      ref.invalidate(myBookingsProvider);
    });
  }
}

final memberBookingControllerProvider =
    AutoDisposeAsyncNotifierProvider<MemberBookingController, void>(
  MemberBookingController.new,
);
