/// 셀프 운동 기록 Riverpod providers + 액션 컨트롤러 (S4 / Phase 2.5).
///
/// - [selfWorkoutLogRepositoryProvider] : repository 인스턴스(공용)
/// - [mySelfLogsProvider]               : 회원 본인 기록 목록(회원 화면용)
/// - [selfLogsForMemberProvider]        : 특정 회원 기록 목록(.family, 트레이너 카드용)
/// - [selfLogControllerProvider]        : 작성/수정/삭제 액션(`AsyncValue<void>`)
///
/// 작성/수정/삭제는 회원만 수행하므로 컨트롤러 성공 시 회원 뷰만 invalidate 한다.
/// **출석 달력·스트릭도 셀프 기록에서 파생**되므로([attendanceDataProvider] 가
/// self_workout_logs 를 함께 조회) 셀프 기록을 바꾸면 [mySelfLogsProvider] 뿐
/// 아니라 [attendanceDataProvider] 도 같이 무효화해야 한다. 안 그러면 홈 스트릭
/// 카드가 attendanceData 를 계속 watch 해 살려둔 캐시 때문에 새 기록이 달력/배지에
/// 안 뜬다(달력 미반영 버그). SnackBar 는 호출 측, 컨트롤러는 상태만(UI/Riverpod 패턴).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_client.dart';
import '../../domain/models/self_workout_log.dart';
import '../auth/auth_providers.dart';
import '../member/attendance/member_attendance_providers.dart';
import 'self_log_repository.dart';

final selfWorkoutLogRepositoryProvider =
    Provider<SelfWorkoutLogRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return SelfWorkoutLogRepository(client);
});

/// 회원 본인의 셀프 기록 목록(최신 먼저).
final mySelfLogsProvider =
    FutureProvider.autoDispose<List<SelfWorkoutLog>>((ref) async {
  if (!ref.watch(isSupabaseReadyProvider)) return const [];
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const [];
  return ref.watch(selfWorkoutLogRepositoryProvider).listMine();
});

/// 트레이너가 보는 특정 회원의 셀프 기록 목록(.family — 회원별 캐시 분리).
final selfLogsForMemberProvider =
    FutureProvider.family<List<SelfWorkoutLog>, String>((ref, memberId) async {
  if (!ref.watch(isSupabaseReadyProvider)) return const [];
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const [];
  return ref.watch(selfWorkoutLogRepositoryProvider).listForMember(memberId);
});

/// 셀프 기록 작성/수정/삭제 컨트롤러. state = `AsyncValue<void>`.
class SelfLogController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> add(SelfWorkoutLog log) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(selfWorkoutLogRepositoryProvider).create(log);
      _invalidateViews();
    });
  }

  /// 기록 수정. 메서드명에 'update' 금지 규칙(AsyncNotifier.update 충돌) → editLog.
  Future<void> editLog(String id, SelfWorkoutLog log) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(selfWorkoutLogRepositoryProvider).update(id, log);
      _invalidateViews();
    });
  }

  Future<void> remove(String id) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(selfWorkoutLogRepositoryProvider).delete(id);
      _invalidateViews();
    });
  }

  /// 셀프 기록 변경 후 영향받는 회원 뷰를 함께 무효화.
  /// 목록 + **출석 달력·스트릭**(attendanceData 가 self_workout_logs 를 함께 집계).
  void _invalidateViews() {
    ref.invalidate(mySelfLogsProvider);
    ref.invalidate(attendanceDataProvider);
  }
}

final selfLogControllerProvider =
    AutoDisposeAsyncNotifierProvider<SelfLogController, void>(
  SelfLogController.new,
);
