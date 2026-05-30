/// 인바디(체성분) 측정 기록 read/write wrapper (Phase 2 2.2, S1).
///
/// **가시성:** 측정 수치는 객관적 사실이라 회원도 본인 것을 바로 본다(검수 게이트 없음).
///   RLS(0023): 트레이너는 담당 회원 rw(body_meas_trainer_rw),
///   회원은 본인 read(body_meas_member_read).
///
/// 트레이너용 본 repository 는 입력/삭제/조회를 담당. 회원 측 조회는
/// features/member/progress 의 별도 repository 가 본인 시점으로 수행.
///
/// 참고: docs/develop_plan.md §4 Phase 2 2.2, src/supabase/migrations/0023.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/models/body_measurement.dart';

class BodyMeasurementRepository {
  final SupabaseClient _client;
  BodyMeasurementRepository(this._client);

  static const _table = 'body_measurements';

  /// 회원 1명의 측정 기록 — 측정일 내림차순(최신 먼저).
  /// RLS 가 트레이너 본인 담당 회원만 노출.
  Future<List<BodyMeasurement>> listForMember(String memberId) async {
    final rows = await _client
        .from(_table)
        .select(
            'id, member_id, weight_kg, body_fat_pct, skeletal_muscle_kg, measured_at, recorded_by, created_at')
        .eq('member_id', memberId)
        .order('measured_at', ascending: false);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(BodyMeasurement.fromRow)
        .toList(growable: false);
  }

  /// 측정 1건 추가. recorded_by 는 호출(컨트롤러)이 현재 트레이너 user_id 로 주입.
  /// 반환: 생성된 행 id.
  Future<String> add({
    required BodyMeasurement measurement,
    required String recordedBy,
  }) async {
    final payload = measurement.toInsertPayload()..['recorded_by'] = recordedBy;
    final row = await _client.from(_table).insert(payload).select('id').single();
    return row['id'] as String;
  }

  /// 측정 1건 삭제(하드 삭제 — 잘못 입력한 측정값 제거).
  Future<void> delete(String id) async {
    await _client.from(_table).delete().eq('id', id);
  }
}
