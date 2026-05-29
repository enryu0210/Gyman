/// 회원 본인 시점의 "내 수업 기록" 조회 repository (읽기 전용).
///
/// **가시성 분리 (본 제품 핵심 원칙):**
///   회원에게는 *본인 운동 내용*만 보인다. `session_records.next_memo` 는
///   "트레이너가 다음 수업에 떠올릴 단서" 라 회원에게 노출하지 않는다.
///   RLS(`records_member_read`)는 행 단위라 next_memo 컬럼까지 읽을 수 있으므로,
///   **쿼리에서 아예 select 하지 않아** 클라이언트로 전달조차 되지 않게 한다(컬럼 단위 방어).
///   → 회원은 exercises / condition / pain 만 받는다.
///
/// **본인 데이터 보장:**
///   회원 측 조회는 항상 본인 것이라 member_id 필터를 클라가 넘기지 않고
///   DB RLS(`sessions_member_read` / `records_member_read`,
///   `current_member_profile_id()` 경유)에 위임한다.
///
/// 참고: docs/develop_plan.md §4 회원 로드맵 ③(내 기록 열람),
///       src/supabase/migrations/0013(RLS), 0005(sessions/records).
library;

// supabase_flutter 의 auth `Session` 과 도메인 `Session` 이름 충돌 → SDK 측을 가린다.
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../../../domain/models/session_record.dart';

// =====================================================================
// 표시용 모델
// =====================================================================

/// "내 수업 기록" 한 건 — 수업 일시 + 운동 기록 본문.
///
/// done 수업만 조회하므로 [record] 는 보통 채워지지만, 데이터 이상(기록 누락)에
/// 대비해 nullable 로 둔다.
class MemberSessionRecord {
  final String sessionId;
  final DateTime scheduledAt;
  final SessionRecord? record;

  const MemberSessionRecord({
    required this.sessionId,
    required this.scheduledAt,
    required this.record,
  });

  bool get hasRecord => record != null;
}

// =====================================================================
// Repository
// =====================================================================

class MemberRecordsRepository {
  final SupabaseClient _client;
  MemberRecordsRepository(this._client);

  static const _sessionsTable = 'sessions';

  /// 본인의 완료(done) 수업 기록을 최신순으로 조회.
  ///
  /// next_memo 를 의도적으로 제외한 컬럼만 select — 트레이너용 메모가
  /// 회원 클라이언트로 전달되지 않게 한다.
  Future<List<MemberSessionRecord>> listMyRecords({int limit = 50}) async {
    final rows = await _client
        .from(_sessionsTable)
        .select('''
          id, scheduled_at, status,
          session_records(session_id, exercises, condition, pain, created_at, updated_at)
        ''')
        .eq('status', 'done')
        .order('scheduled_at', ascending: false)
        .limit(limit);

    return (rows as List).cast<Map<String, dynamic>>().map((r) {
      // session_records 는 1:1 이지만 PostgREST 가 List/Map 둘 다로 줄 수 있어 모두 대응.
      final raw = r['session_records'];
      SessionRecord? record;
      if (raw is Map<String, dynamic>) {
        record = SessionRecord.fromRow(raw);
      } else if (raw is List && raw.isNotEmpty) {
        record = SessionRecord.fromRow(raw.first as Map<String, dynamic>);
      }
      return MemberSessionRecord(
        sessionId: r['id'] as String,
        scheduledAt: DateTime.parse(r['scheduled_at'] as String),
        record: record,
      );
    }).toList(growable: false);
  }
}
