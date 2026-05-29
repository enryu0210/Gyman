/// 회원 본인 시점의 "예약 신청" repository (회원 로드맵 ⑤).
///
/// **권한 모델 (RLS 위임):**
///   회원은 본인 계약에 한해서만 예약을 신청(requested)할 수 있고, 미승인 신청만
///   철회(DELETE)할 수 있다. 클라가 member_id 를 넘기지 않고 DB RLS 가 처리한다.
///     - INSERT : sessions_member_request_insert (status='requested' + 본인 계약, 0022)
///     - DELETE : sessions_member_cancel_request (본인 'requested' 만, 0022)
///     - SELECT : sessions_member_read (본인 계약 수업 전체, 0013)
///     - 계약   : v_contract_status security_invoker (본인 행만, 0018)
///   → 확정 예약(scheduled) 직접 생성은 RLS 가 막는다. 승인은 트레이너만.
///
/// **신청은 잔여 횟수를 차감하지 않는다** — v_contract_status 가 requested 를
///   카운트하지 않으므로(0021), 신청만으로 잔여가 줄지 않는다. 표시용 경고만 한다.
///
/// 참고: docs/develop_plan.md §4 회원 로드맵 ⑤,
///       src/supabase/migrations/0021(enum)·0022(RLS).
library;

// supabase_flutter 의 auth `Session` 과 도메인 `Session` 이름 충돌 → SDK 측을 가린다.
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../../../domain/models/enums.dart';
import '../../../domain/models/session.dart';

// =====================================================================
// 표시용 모델
// =====================================================================

/// 예약 신청 시 회원이 고를 수 있는 계약 1건 (v_contract_status 한 행).
///
/// 잔여 0이어도 신청 자체는 허용(트레이너가 새 계약 등 판단) — 화면에서 안내만 한다.
class BookableContract {
  final String contractId;
  final int totalSessions;
  final int remainingSessions;
  final DateTime startDate;
  final DateTime? endDate;

  const BookableContract({
    required this.contractId,
    required this.totalSessions,
    required this.remainingSessions,
    required this.startDate,
    this.endDate,
  });

  bool get isExhausted => remainingSessions <= 0;
}

// =====================================================================
// Repository
// =====================================================================

class MemberBookingRepository {
  final SupabaseClient _client;
  MemberBookingRepository(this._client);

  static const _sessionsTable = 'sessions';
  static const _statusView = 'v_contract_status';

  /// 신청 가능한 본인 계약 목록(최신 시작일 순).
  Future<List<BookableContract>> listBookableContracts() async {
    final rows = await _client
        .from(_statusView)
        .select()
        .order('start_date', ascending: false);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(_contractFromRow)
        .toList(growable: false);
  }

  /// 본인의 신청(requested) + 확정(scheduled) 예약을 일시 오름차순으로 조회.
  ///
  /// 완료/취소된 수업은 "내 수업 기록" 영역이 담당하므로 여기선 제외한다.
  /// (RLS 가 본인 계약 수업만 노출하므로 member_id 필터 불필요)
  Future<List<Session>> listMyBookings() async {
    final rows = await _client
        .from(_sessionsTable)
        .select()
        .inFilter('status', const ['requested', 'scheduled'])
        .order('scheduled_at', ascending: true);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(_sessionFromRow)
        .toList(growable: false);
  }

  /// 예약 신청 1건 생성 (status=requested).
  ///
  /// 확정이 아니라 "신청"이다 — 트레이너 승인 후에야 scheduled 가 된다.
  Future<Session> requestBooking({
    required String contractId,
    required DateTime scheduledAt,
    String? memo,
  }) async {
    final row = await _client
        .from(_sessionsTable)
        .insert({
          'contract_id': contractId,
          'scheduled_at': scheduledAt.toIso8601String(),
          'status': 'requested',
          'status_memo': memo,
        })
        .select()
        .single();
    return _sessionFromRow(row);
  }

  /// 본인이 낸 신청(requested)을 철회 — 행 삭제.
  ///
  /// RLS 가 status='requested' 인 본인 계약 수업만 삭제 허용하므로, 이미 승인되어
  /// scheduled 가 된 예약은 여기서 못 지운다(0건 영향). 그 경우 트레이너에게 문의.
  Future<void> cancelRequest(String sessionId) async {
    await _client.from(_sessionsTable).delete().eq('id', sessionId);
  }

  // ---------------------------------------------------------------------
  // 행 매핑
  // ---------------------------------------------------------------------

  static BookableContract _contractFromRow(Map<String, dynamic> row) {
    return BookableContract(
      contractId: row['contract_id'] as String,
      totalSessions: row['total_sessions'] as int,
      // PG COUNT()는 bigint → num 경유 변환(직접 as int 시 view 조회 타입오류).
      remainingSessions: (row['remaining_sessions'] as num).toInt(),
      startDate: DateTime.parse(row['start_date'] as String),
      endDate: _parseDate(row['end_date']),
    );
  }

  static Session _sessionFromRow(Map<String, dynamic> row) {
    return Session(
      id: row['id'] as String,
      contractId: row['contract_id'] as String,
      scheduledAt: DateTime.parse(row['scheduled_at'] as String),
      status: _statusFromDb(row['status'] as String),
      recordedAt: _parseTimestamp(row['recorded_at']),
      recordedByTrainerId: row['recorded_by_trainer_id'] as String?,
      statusMemo: row['status_memo'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  static SessionStatus _statusFromDb(String raw) {
    switch (raw) {
      case 'requested':
        return SessionStatus.requested;
      case 'scheduled':
        return SessionStatus.scheduled;
      case 'done':
        return SessionStatus.done;
      case 'no_show':
        return SessionStatus.noShow;
      case 'canceled':
        return SessionStatus.canceled;
      case 'late_cancel':
        return SessionStatus.lateCancel;
      default:
        throw StateError('알 수 없는 session_status 값: $raw');
    }
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v as String);
  }

  static DateTime? _parseTimestamp(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v as String);
  }
}
