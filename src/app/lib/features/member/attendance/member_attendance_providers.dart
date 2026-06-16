/// 회원 출석 provider — 캘린더(원자료)와 홈 스트릭 배지(파생)가 공유.
///
/// - [memberAttendanceRepositoryProvider] : 출석 repository
/// - [attendanceDataProvider]             : PT/셀프 출석 날짜 집합
/// - [attendanceStatsProvider]            : 연속·이번 달 출석일(스트릭 배지)
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../domain/attendance_streak_calculator.dart';
import 'member_attendance_repository.dart';

final memberAttendanceRepositoryProvider =
    Provider<MemberAttendanceRepository>((ref) {
  return MemberAttendanceRepository(ref.watch(supabaseClientProvider));
});

/// 출석 원자료(PT/셀프 날짜 집합). 캘린더가 watch, 스트릭이 파생.
final attendanceDataProvider =
    FutureProvider.autoDispose<AttendanceData>((ref) async {
  return ref.watch(memberAttendanceRepositoryProvider).fetchAttendance();
});

/// 스트릭 통계 — attendanceData 에서 도메인 계산기로 파생.
/// 데이터 로딩 전이면 empty 를 돌려줘 홈 배지가 깜빡이지 않게 한다.
final attendanceStatsProvider = Provider.autoDispose<AttendanceStats>((ref) {
  final data = ref.watch(attendanceDataProvider).value;
  if (data == null) return AttendanceStats.empty;
  return AttendanceStreakCalculator.compute(data.allDays);
});
