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
import '../../../domain/deduction_rule.dart';
import '../../../domain/models/enums.dart';
import '../../auth/auth_providers.dart';
import '../contract/contract_providers.dart';
import '../renewal/renewal_alert_providers.dart';
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

/// 트레이너 본인 예약 리스트 범위 — 예약 화면(/trainer/booking) 의 chip 필터.
enum TrainerBookingRange { today, tomorrow, thisWeek, nextWeek }

extension TrainerBookingRangeBounds on TrainerBookingRange {
  /// 현재 시각 기준 [from, to) 반환. to 는 exclusive.
  ///
  /// 주의: from/to 는 *로컬 자정* 기준으로 잘라서 Supabase 에 ISO8601 로 전달된다.
  /// scheduled_at 컬럼은 timestamptz 라 서버가 알아서 비교 — 클라이언트가 UTC 변환할 필요 없음.
  (DateTime from, DateTime to) bounds(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (this) {
      case TrainerBookingRange.today:
        return (today, today.add(const Duration(days: 1)));
      case TrainerBookingRange.tomorrow:
        final t = today.add(const Duration(days: 1));
        return (t, t.add(const Duration(days: 1)));
      case TrainerBookingRange.thisWeek:
        // 월요일 시작 (Dart weekday: Mon=1 .. Sun=7)
        final monday = today.subtract(Duration(days: today.weekday - 1));
        return (monday, monday.add(const Duration(days: 7)));
      case TrainerBookingRange.nextWeek:
        final monday = today.subtract(Duration(days: today.weekday - 1));
        final nextMon = monday.add(const Duration(days: 7));
        return (nextMon, nextMon.add(const Duration(days: 7)));
    }
  }

  String get label {
    switch (this) {
      case TrainerBookingRange.today:
        return '오늘';
      case TrainerBookingRange.tomorrow:
        return '내일';
      case TrainerBookingRange.thisWeek:
        return '이번 주';
      case TrainerBookingRange.nextWeek:
        return '다음 주';
    }
  }
}

/// 트레이너 본인의 예약/완료 수업 리스트 — 화면 chip 으로 범위 선택.
///
/// .family 키가 enum 이라 chip 변경 시 자동 분리 캐시.
final trainerBookingsProvider = FutureProvider.family<
    List<TrainerBookingRow>, TrainerBookingRange>((ref, range) async {
  if (!ref.watch(isSupabaseReadyProvider)) return const [];
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const [];

  final (from, to) = range.bounds(DateTime.now());
  return ref
      .watch(sessionRepositoryProvider)
      .listForCurrentTrainerBetween(from: from, to: to);
});

/// 트레이너 앞으로 들어온 승인 대기(requested) 신청 전체 (날짜 무관).
///
/// 예약 화면 상단 "승인 대기" 섹션 + 트레이너 홈 배지에서 함께 watch.
final trainerPendingRequestsProvider =
    FutureProvider.autoDispose<List<TrainerBookingRow>>((ref) async {
  if (!ref.watch(isSupabaseReadyProvider)) return const [];
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const [];

  return ref
      .watch(sessionRepositoryProvider)
      .listPendingRequestsForCurrentTrainer();
});

/// 승인 대기 신청 건수 — 트레이너 홈 "예약" 배지용.
/// 로딩/에러 시엔 0 으로 폴백(배지를 안 띄움).
final trainerPendingRequestCountProvider = Provider.autoDispose<int>((ref) {
  return ref.watch(trainerPendingRequestsProvider).maybeWhen(
        data: (list) => list.length,
        orElse: () => 0,
      );
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
      _invalidateBookings();
    });
  }

  /// 기존 수업 기록 수정/완료 처리.
  ///
  /// 계약은 바꾸지 않는다고 가정 — 화면에서도 잠금. 그래야 잔여 횟수 정합성 유지.
  /// [previousStatus] 가 done 이 아니면 저장 시 done 으로 전이된다(예약→완료 버그 수정).
  /// 전이되면 잔여 횟수가 바뀌므로 contractStatus 도 함께 invalidate(기존과 동일).
  ///
  /// 메서드명이 `editRecord` 인 이유: 부모 [AsyncNotifierBase] 가 `update` 라는
  /// 다른 시그니처의 메서드를 이미 가지고 있어서 단순 `update` 로 두면 잘못된 override 가 됨.
  Future<void> editRecord({
    required String sessionId,
    required UpdateSessionRecordInput input,
    required String memberId,
    required SessionStatus previousStatus,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = ref.read(authStateProvider).value;
      if (user == null) {
        throw StateError('로그인이 필요합니다. 로그아웃 후 다시 시도해 주세요.');
      }
      await ref.read(sessionRepositoryProvider).updateRecord(
            sessionId: sessionId,
            input: input,
            trainerId: user.id,
            previousStatus: previousStatus,
          );
      ref.invalidate(sessionDetailProvider(sessionId));
      ref.invalidate(recentSessionsForMemberProvider(memberId));
      // 일시(scheduled_at) 만 바뀌어도 잔여 횟수 자체는 동일하지만, view 결과의
      // 정렬/표시값이 일관되도록 함께 invalidate.
      ref.invalidate(contractStatusForMemberProvider(memberId));
      _invalidateBookings();
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
      _invalidateBookings();
    });
  }

  // -------------------------------------------------------------------
  // Phase 1.6 — 예약 / 상태 전이
  // -------------------------------------------------------------------

  /// 예약 1건 생성 (status=scheduled). 잔여 횟수에는 영향 없음.
  Future<void> createScheduled({
    required NewBookingInput input,
    required String memberId,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = ref.read(authStateProvider).value;
      if (user == null) {
        throw StateError('로그인이 필요합니다. 로그아웃 후 다시 시도해 주세요.');
      }
      await ref.read(sessionRepositoryProvider).createScheduledSession(
            input: input,
            trainerId: user.id,
          );
      ref.invalidate(recentSessionsForMemberProvider(memberId));
      // scheduled 는 차감 안 되지만, view 결과의 정렬/표시는 동일하게 유지.
      ref.invalidate(contractStatusForMemberProvider(memberId));
      _invalidateBookings();
    });
  }

  /// 예약 상태 변경 (done 은 별도 흐름 — 수업 기록 화면 진입).
  ///
  /// 노쇼/지각취소 → 잔여 차감, 정상취소/예약복원 → 미차감. view 가 자동 재계산.
  Future<void> changeStatus({
    required String sessionId,
    required SessionStatus status,
    required String memberId,
    String? memo,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(sessionRepositoryProvider).markStatus(
            sessionId: sessionId,
            status: status,
            memo: memo,
          );
      ref.invalidate(sessionDetailProvider(sessionId));
      ref.invalidate(recentSessionsForMemberProvider(memberId));
      ref.invalidate(contractStatusForMemberProvider(memberId));
      _invalidateBookings();
    });
  }

  /// 취소 — 정책에 따라 자동 분류(canceled / lateCancel) 후 적용.
  /// 호출 시점 = 취소 시각 (DateTime.now()) 이라 시간대 의존 분류가 자연스럽게 들어감.
  Future<void> cancel({
    required String sessionId,
    required DateTime scheduledAt,
    required String memberId,
    String? memo,
    DeductionPolicy policy = DeductionPolicy.defaultPolicy,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(sessionRepositoryProvider).cancelSession(
            sessionId: sessionId,
            scheduledAt: scheduledAt,
            cancelAt: DateTime.now(),
            memo: memo,
            policy: policy,
          );
      ref.invalidate(sessionDetailProvider(sessionId));
      ref.invalidate(recentSessionsForMemberProvider(memberId));
      ref.invalidate(contractStatusForMemberProvider(memberId));
      _invalidateBookings();
    });
  }

  // -------------------------------------------------------------------
  // 회원 예약 신청(requested) 승인/거절 — 회원 로드맵 ⑤
  // -------------------------------------------------------------------

  /// 회원 신청(requested)을 승인 → 확정(scheduled).
  ///
  /// markStatus 가 requested→scheduled 전이를 처리. 잔여 횟수에는 영향 없음
  /// (둘 다 미차감). 승인 후 신청 목록/예약 목록을 함께 갱신.
  Future<void> approveRequest({
    required String sessionId,
    required String memberId,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(sessionRepositoryProvider).markStatus(
            sessionId: sessionId,
            status: SessionStatus.scheduled,
          );
      ref.invalidate(recentSessionsForMemberProvider(memberId));
      _invalidateBookings();
    });
  }

  /// 회원 신청(requested)을 **일시 변경 후 승인** → 새 시간으로 확정(scheduled).
  ///
  /// 회원이 시간 여유를 준 경우(예: "오전에도 괜찮아요") 트레이너가 시간을 조정해
  /// 바로 확정한다. 잔여 횟수에는 영향 없음(requested·scheduled 둘 다 미차감).
  Future<void> approveRequestWithReschedule({
    required String sessionId,
    required DateTime newScheduledAt,
    required String memberId,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(sessionRepositoryProvider).approveWithReschedule(
            sessionId: sessionId,
            newScheduledAt: newScheduledAt,
          );
      ref.invalidate(recentSessionsForMemberProvider(memberId));
      _invalidateBookings();
    });
  }

  /// 회원 신청(requested)을 거절 → 행 삭제.
  ///
  /// 거절은 흔적을 남기지 않고 신청을 제거한다(베타 단순화). 회원 화면에서도
  /// 해당 신청이 사라진다. 거절 사유 전달은 별도 채널(채팅/안내) — 후속 과제.
  Future<void> rejectRequest({
    required String sessionId,
    required String memberId,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(sessionRepositoryProvider).deleteSession(sessionId);
      ref.invalidate(recentSessionsForMemberProvider(memberId));
      _invalidateBookings();
    });
  }

  /// 트레이너 본인 예약 리스트 4개 범위 + 재등록 알림 일괄 invalidate.
  ///
  /// session 변동은 잔여 횟수에 영향 → 알림 단계도 바뀔 수 있음. 어느 회원의 어느
  /// 계약인지 매번 따져서 부분 invalidate 하는 것보다 전체 갱신이 단순/안전.
  /// 캐시 크기가 작아 부담 없음.
  void _invalidateBookings() {
    for (final r in TrainerBookingRange.values) {
      ref.invalidate(trainerBookingsProvider(r));
    }
    ref.invalidate(trainerPendingRequestsProvider);
    ref.invalidate(trainerRenewalAlertsProvider);
  }
}

final saveSessionControllerProvider =
    AutoDisposeAsyncNotifierProvider<SaveSessionController, void>(
  SaveSessionController.new,
);
