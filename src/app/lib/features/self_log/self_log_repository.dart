/// 회원 셀프 운동 기록 read/write wrapper (S4 / Phase 2.5).
///
/// **가시성(RLS 0028 위임):**
///   - 회원   : 본인 기록 rw — [listMine]/[create]/[update]/[delete].
///     클라가 member_id 를 넘기지 않는다(INSERT 는 DB DEFAULT, 조회는 RLS 가 본인만).
///   - 트레이너: 담당 회원 기록 read-only — [listForMember].
///
/// 한 테이블을 양 역할이 쓰므로 repository 는 공용 features/self_log/ 에 둔다
/// (chat 과 동일한 공용 위치 패턴). 작성 UI 는 회원 전용, 읽기 카드는 트레이너 전용.
///
/// 참고: docs/develop_plan.md §4 Phase 2 2.5, src/supabase/migrations/0028.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/self_workout_log.dart';

class SelfWorkoutLogRepository {
  final SupabaseClient _client;
  SelfWorkoutLogRepository(this._client);

  static const _table = 'self_workout_logs';
  static const _columns = 'id, member_id, logged_at, workout, note, created_at';

  /// 회원 본인의 기록 — 날짜 내림차순(최신 먼저).
  /// member_id 필터 없이 RLS(self_log_member_rw)가 본인 것만 노출한다.
  Future<List<SelfWorkoutLog>> listMine() async {
    final rows = await _client
        .from(_table)
        .select(_columns)
        .order('logged_at', ascending: false)
        .order('created_at', ascending: false);
    return _mapRows(rows);
  }

  /// 트레이너가 보는 특정 회원의 기록 — 날짜 내림차순.
  /// RLS(self_log_trainer_read)가 담당 회원만 노출한다.
  Future<List<SelfWorkoutLog>> listForMember(String memberId) async {
    final rows = await _client
        .from(_table)
        .select(_columns)
        .eq('member_id', memberId)
        .order('logged_at', ascending: false)
        .order('created_at', ascending: false);
    return _mapRows(rows);
  }

  /// 기록 1건 추가(회원). member_id 는 DB DEFAULT(current_member_profile_id())가 채운다.
  Future<void> create(SelfWorkoutLog log) async {
    await _client.from(_table).insert(log.toInsertPayload());
  }

  /// 기록 1건 수정(회원 본인). RLS 가 남의 기록 수정은 막는다(0건 영향).
  Future<void> update(String id, SelfWorkoutLog log) async {
    await _client.from(_table).update(log.toUpdatePayload()).eq('id', id);
  }

  /// 기록 1건 삭제(회원 본인, 하드 삭제).
  Future<void> delete(String id) async {
    await _client.from(_table).delete().eq('id', id);
  }

  static List<SelfWorkoutLog> _mapRows(dynamic rows) {
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(SelfWorkoutLog.fromRow)
        .toList(growable: false);
  }
}
