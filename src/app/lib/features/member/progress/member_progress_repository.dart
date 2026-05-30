/// 회원 본인 "변화 추이" 데이터 조회 repository (읽기 전용, S1 / 2.2).
///
/// 두 가지 소스를 본인 시점으로 가져온다(RLS 위임 — member_id 필터 클라가 안 넘김):
///   1) 중량 추이: 본인 done 수업의 운동 기록(exercises) → [WorkoutEntry] 리스트.
///      `next_memo` 는 트레이너 전용이라 select 에서 제외(컬럼 단위 방어 — records ③과 동일).
///   2) 인바디 추이: 본인 body_measurements(0023 RLS body_meas_member_read).
///
/// 도메인 계산(종목별 최고중량 시계열)은 [WeightTrendCalculator] 가 담당 —
/// 본 repository 는 원천 데이터만 모아 전달한다.
///
/// 참고: docs/develop_plan.md §4 Phase 2 2.2, 0023(인바디 RLS), 0013(수업/기록 RLS).
library;

// supabase_flutter 의 auth `Session` 과 도메인 `Session` 이름 충돌 → SDK 측을 가린다.
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../../../domain/models/body_measurement.dart';
import '../../../domain/models/session_record.dart';
import '../../../domain/weight_trend.dart';

/// 변화 추이 화면이 필요로 하는 두 소스를 한 번에 담는 묶음.
class ProgressData {
  /// 중량 추이 계산 입력(수업별 운동 내용). 날짜순 정렬은 계산기가 담당.
  final List<WorkoutEntry> workouts;

  /// 인바디 측정(측정일 오름차순 — 그래프가 시간순으로 바로 그림).
  final List<BodyMeasurement> measurements;

  const ProgressData({required this.workouts, required this.measurements});

  bool get hasWeightData => workouts.isNotEmpty;
  bool get hasBodyData => measurements.isNotEmpty;
}

class MemberProgressRepository {
  final SupabaseClient _client;
  MemberProgressRepository(this._client);

  /// 본인 변화 추이 데이터(중량 + 인바디)를 함께 조회.
  Future<ProgressData> loadMyProgress({int sessionLimit = 200}) async {
    // 두 조회는 독립적이라 병렬로.
    final results = await Future.wait([
      _loadWorkouts(limit: sessionLimit),
      _loadMeasurements(),
    ]);
    return ProgressData(
      workouts: results[0] as List<WorkoutEntry>,
      measurements: results[1] as List<BodyMeasurement>,
    );
  }

  /// 본인 done 수업 + 운동 기록 → WorkoutEntry 리스트.
  /// next_memo 는 트레이너 전용이라 의도적으로 select 제외.
  Future<List<WorkoutEntry>> _loadWorkouts({required int limit}) async {
    final rows = await _client
        .from('sessions')
        .select('''
          scheduled_at, status,
          session_records(exercises)
        ''')
        .eq('status', 'done')
        .order('scheduled_at', ascending: true)
        .limit(limit);

    final entries = <WorkoutEntry>[];
    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      // session_records 는 1:1 이지만 PostgREST 가 List/Map 둘 다로 줄 수 있어 모두 대응.
      final raw = r['session_records'];
      Map<String, dynamic>? recRow;
      if (raw is Map<String, dynamic>) {
        recRow = raw;
      } else if (raw is List && raw.isNotEmpty) {
        recRow = raw.first as Map<String, dynamic>;
      }
      if (recRow == null) continue; // 기록 없는 done 수업은 추이에 무의미

      final rawExercises = recRow['exercises'];
      final exercises = (rawExercises is List)
          ? rawExercises
              .whereType<Map<String, dynamic>>()
              .map(Exercise.fromJson)
              .toList(growable: false)
          : const <Exercise>[];
      if (exercises.isEmpty) continue;

      entries.add(WorkoutEntry(
        date: DateTime.parse(r['scheduled_at'] as String),
        exercises: exercises,
      ));
    }
    return entries;
  }

  /// 본인 인바디 측정 — 측정일 오름차순.
  Future<List<BodyMeasurement>> _loadMeasurements() async {
    final rows = await _client
        .from('body_measurements')
        .select(
            'id, member_id, weight_kg, body_fat_pct, skeletal_muscle_kg, measured_at, recorded_by, created_at')
        .order('measured_at', ascending: true);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(BodyMeasurement.fromRow)
        .toList(growable: false);
  }
}
