/// 회원 출석 데이터 조회 — PT 완료 수업 + 셀프 운동 기록의 "날짜"만 모은다.
///
/// 운톡 불만 #3(출석 일주일만 조회)·#6(동기부여) 대응의 데이터 소스.
/// 출석 캘린더(PT/셀프 색 구분)와 스트릭 배지가 공유한다.
///
/// **가벼운 조회:** 캘린더·스트릭은 "그날 출석했는가 + 종류"만 알면 되므로
///   본문(운동 내용)은 가져오지 않고 날짜 컬럼만 select 한다. 전체 기간을
///   한 번에 받아 클라에서 월 이동(캘린더 네비)을 재조회 없이 처리한다
///   (베타 회원 1인 데이터량 기준 충분).
///
/// **가시성:** member_id 필터 없이 RLS 위임 — sessions_member_read /
///   self_log_member_rw 가 본인 것만 노출(current_member_profile_id 경유).
///
/// 참고: migrations 0005(sessions)·0028(self_workout_logs), 0013(RLS).
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/attendance_streak_calculator.dart';

/// 출석한 날 집합 — PT/셀프를 구분해서 들고 있다(캘린더 색 구분용).
class AttendanceData {
  /// PT 완료(done) 수업이 있은 날(날짜 단위).
  final Set<DateTime> ptDays;

  /// 셀프 운동 기록이 있은 날(날짜 단위).
  final Set<DateTime> selfDays;

  const AttendanceData({required this.ptDays, required this.selfDays});

  static const empty = AttendanceData(ptDays: {}, selfDays: {});

  /// 스트릭 계산용 — PT·셀프 합집합(같은 날 중복은 자동 제거).
  Set<DateTime> get allDays => {...ptDays, ...selfDays};

  /// 그날 출석 종류 판정(캘린더 셀 마킹용).
  bool hasPt(DateTime day) =>
      ptDays.contains(AttendanceStreakCalculator.dateOnly(day));
  bool hasSelf(DateTime day) =>
      selfDays.contains(AttendanceStreakCalculator.dateOnly(day));
}

class MemberAttendanceRepository {
  final SupabaseClient _client;
  MemberAttendanceRepository(this._client);

  /// 본인 출석 전체(PT done + 셀프)를 날짜 집합으로 조회.
  Future<AttendanceData> fetchAttendance() async {
    // 두 테이블을 병렬 조회 — 서로 의존 없음.
    final results = await Future.wait([
      _client.from('sessions').select('scheduled_at').eq('status', 'done'),
      _client.from('self_workout_logs').select('logged_at'),
    ]);

    final ptDays = <DateTime>{};
    for (final r in (results[0] as List).cast<Map<String, dynamic>>()) {
      final v = r['scheduled_at'];
      final dt = _parse(v);
      if (dt != null) ptDays.add(AttendanceStreakCalculator.dateOnly(dt));
    }

    final selfDays = <DateTime>{};
    for (final r in (results[1] as List).cast<Map<String, dynamic>>()) {
      final v = r['logged_at'];
      final dt = _parse(v);
      if (dt != null) selfDays.add(AttendanceStreakCalculator.dateOnly(dt));
    }

    return AttendanceData(ptDays: ptDays, selfDays: selfDays);
  }

  /// scheduled_at(timestamptz)은 local 로, logged_at(date)은 그대로 파싱.
  /// 둘 다 최종적으로 dateOnly 로 정규화되므로 시각/tz 세부는 호출부가 흡수.
  static DateTime? _parse(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString())?.toLocal();
  }
}
