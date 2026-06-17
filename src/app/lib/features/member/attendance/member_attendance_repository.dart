/// 회원 출석 데이터 조회 — PT 수업(완료+예정) + 셀프 운동 기록을 모은다.
///
/// 운톡 불만 #3(출석 일주일만 조회)·#6(동기부여) 대응의 데이터 소스.
/// 출석 캘린더(PT/셀프 색 구분 + PT 시작 시간 표기)와 스트릭 배지가 공유한다.
///
/// **무엇을 가져오나:**
///   - PT(`sessions`): 완료(done) + 예정(scheduled). 캘린더에 "다가올 예약"을
///     같이 보여주려고 예정도 포함한다. PT 는 `scheduled_at`(timestamptz)이라
///     **시작 시각까지 보관**(달력 셀 시간 표기 A안).
///   - 셀프(`self_workout_logs`): `logged_at` 이 date(시각 없음)라 **날짜만** 보관.
///     → 셀프 운동은 시간 표기 없이 점 마킹만 한다.
///
/// **가시성:** member_id 필터 없이 RLS 위임 — sessions_member_read /
///   self_log_member_rw 가 본인 것만 노출(current_member_profile_id 경유).
///
/// 참고: migrations 0005(sessions)·0028(self_workout_logs), 0013(RLS).
library;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/attendance_streak_calculator.dart';

/// PT 수업 한 건 — 시작 시각 + 완료 여부.
/// 달력 셀의 시간 표기(A안)와 완료/예정 점 구분에 쓴다.
class PtEntry {
  /// 수업 시작 시각(로컬, 시간 포함).
  final DateTime at;

  /// true=완료(done), false=예정(scheduled, 아직 안 한 예약).
  final bool done;

  const PtEntry({required this.at, required this.done});
}

/// 출석한 날 모음 — PT(완료+예정, 시간 포함)와 셀프(날짜만)를 구분해서 들고 있다.
class AttendanceData {
  /// 날짜(시각 제거) → 그날 PT 수업 목록(완료+예정, 시각 오름차순).
  /// 시간 표기·점 마킹·바텀시트가 공유.
  final Map<DateTime, List<PtEntry>> ptByDay;

  /// 셀프 운동이 있은 날(셀프는 시간 미저장 → 날짜만).
  final Set<DateTime> selfDays;

  const AttendanceData({required this.ptByDay, required this.selfDays});

  static const empty = AttendanceData(ptByDay: {}, selfDays: {});

  /// 스트릭 계산용 — **실제 출석(완료 PT + 셀프)만**. 예정 PT 는 아직 안 했으니 제외.
  Set<DateTime> get allDays => {
        for (final entry in ptByDay.entries)
          if (entry.value.any((p) => p.done)) entry.key,
        ...selfDays,
      };

  /// 그날 PT 목록(시각 오름차순). 없으면 빈 리스트.
  List<PtEntry> ptOn(DateTime day) =>
      ptByDay[AttendanceStreakCalculator.dateOnly(day)] ?? const [];

  bool hasSelf(DateTime day) =>
      selfDays.contains(AttendanceStreakCalculator.dateOnly(day));

  /// 달력에서 앞으로 이동 가능한 마지막 달 — 가장 늦은 **예정 PT** 가 있는 달
  /// (없으면 이번 달). 미래로 무한정 넘기는 건 막되, 잡혀 있는 예약은 다 보이게.
  DateTime get latestMonthWithSchedule {
    final now = DateTime.now();
    var max = DateTime(now.year, now.month);
    for (final entries in ptByDay.values) {
      for (final p in entries) {
        if (p.done) continue;
        final m = DateTime(p.at.year, p.at.month);
        if (m.isAfter(max)) max = m;
      }
    }
    return max;
  }
}

class MemberAttendanceRepository {
  final SupabaseClient _client;
  MemberAttendanceRepository(this._client);

  /// 본인 출석 전체(PT 완료+예정, 셀프)를 조회.
  Future<AttendanceData> fetchAttendance() async {
    // 두 테이블을 병렬 조회 — 서로 의존 없음.
    final results = await Future.wait([
      _client
          .from('sessions')
          .select('scheduled_at, status')
          .inFilter('status', ['done', 'scheduled']),
      _client.from('self_workout_logs').select('logged_at'),
    ]);

    final ptByDay = <DateTime, List<PtEntry>>{};
    for (final r in (results[0] as List).cast<Map<String, dynamic>>()) {
      final dt = parseSessionTimestamp(r['scheduled_at']);
      if (dt == null) continue;
      final day = AttendanceStreakCalculator.dateOnly(dt);
      final done = r['status'] == 'done';
      (ptByDay[day] ??= []).add(PtEntry(at: dt, done: done));
    }
    // 각 날짜의 PT 를 시각 오름차순으로 — 셀의 "가장 이른 시간" 표기·시트 정렬용.
    for (final list in ptByDay.values) {
      list.sort((a, b) => a.at.compareTo(b.at));
    }

    final selfDays = <DateTime>{};
    for (final r in (results[1] as List).cast<Map<String, dynamic>>()) {
      final dt = parseSessionTimestamp(r['logged_at']);
      if (dt != null) selfDays.add(AttendanceStreakCalculator.dateOnly(dt));
    }

    return AttendanceData(ptByDay: ptByDay, selfDays: selfDays);
  }

  /// 서버 타임스탬프(scheduled_at: timestamptz / logged_at: date)를 파싱한다.
  ///
  /// **`.toLocal()` 을 호출하지 않는 게 핵심.** 이 앱은 수업 시각을 "벽시계 그대로"
  /// 다루는 컨벤션이다 — 쓰기(`session_repository`)가 로컬 시각을 offset 없는 naive
  /// ISO 로 보내 Postgres 가 UTC 로 적재하고, 다른 모든 읽기 화면(records/home/
  /// progress)도 `DateTime.parse` 만 하고 toLocal 을 안 한다. 여기서 toLocal 을
  /// 부르면 timestamptz 가 +09:00 밀려 **오후 2시가 23시로** 표시된다(이 버그의 원인).
  /// 다른 read repo 와 동일하게 둬서 화면 간 시각 표기를 일치시킨다.
  ///
  /// offset 있는 문자열(`...+00:00`)은 `isUtc=true` 인 DateTime 이 되고, 그 .hour/.day
  /// 가 곧 적재된 벽시계 값이라 시간 표기·날짜 그룹핑 모두 정확하다.
  @visibleForTesting
  static DateTime? parseSessionTimestamp(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }
}
