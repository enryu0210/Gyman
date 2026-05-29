/// 수업(sessions) + 수업 기록(session_records) 두 테이블의 read/write wrapper.
///
/// **트랜잭션 정책 (중요):**
///   Supabase JS/Dart SDK 는 다중 테이블 트랜잭션을 직접 지원하지 않는다.
///   따라서 [createDoneSession] 은 다음 순서로 처리한다:
///     1) sessions INSERT (status=done, recorded_at=now)
///     2) session_records INSERT (방금 만든 session_id)
///   2)가 실패하면 1)을 [softDeleteSession] 으로 되돌린다 (보상 트랜잭션).
///   "수업은 있는데 기록은 없는" 데이터 깨짐을 방지.
///
///   더 안전한 방식은 SQL RPC 함수로 묶는 것이지만, 베타 단계에서는 코드 가독성 우선.
///   회원 늘어나면 RPC 로 이전.
///
/// **잔여 횟수 정책:**
///   sessions INSERT/UPDATE 시 pt_contracts 의 used_sessions 캐시를 갱신하지 않는다.
///   `v_contract_status` view 가 sessions 를 직접 카운트해서 잔여 횟수를 만든다.
///   즉, 본 repository 가 sessions 만 건드리면 view 의 잔여 횟수가 자동으로 따라옴.
///   (계약/잔여 표시 측은 contractStatusForMemberProvider 를 invalidate)
///
/// 참고: docs/develop_plan.md §4 Phase 1.4, src/supabase/migrations/0005_*.sql.
library;

// supabase_flutter 가 export 하는 auth `Session` 과 도메인 `Session` 이름 충돌 →
// SDK 의 인증 `Session` 을 가린다 (본 파일에서는 인증 세션을 안 쓰므로 안전).
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../../../domain/deduction_rule.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/session.dart';
import '../../../domain/models/session_record.dart';

// =====================================================================
// SessionStatus ↔ DB ENUM 문자열 변환
// =====================================================================

/// PG ENUM `session_status` 값 (snake_case) ↔ Dart [SessionStatus].
///
/// 한 곳에 모아둔 이유: 다른 repository(예: 회원 조회)에서 status 를 필터링할
/// 일이 생기면 같은 함수 재사용 — 양쪽이 어긋나는 버그를 막는다.
SessionStatus _statusFromDb(String raw) {
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
      // DB ENUM 에 새 값이 들어왔다면 명시적으로 실패 — 조용한 데이터 손상 방지.
      throw StateError('알 수 없는 session_status 값: $raw');
  }
}

String _statusToDb(SessionStatus status) {
  switch (status) {
    case SessionStatus.requested:
      return 'requested';
    case SessionStatus.scheduled:
      return 'scheduled';
    case SessionStatus.done:
      return 'done';
    case SessionStatus.noShow:
      return 'no_show';
    case SessionStatus.canceled:
      return 'canceled';
    case SessionStatus.lateCancel:
      return 'late_cancel';
  }
}

// =====================================================================
// 신규 수업 기록 입력 객체
// =====================================================================

/// "수업 완료 + 기록" 등록 시 한 번에 받는 입력.
///
/// 본 단계(1.4)는 *과거에 진행된 수업을 즉시 기록* 하는 경로만 지원.
/// 즉 status 는 항상 [SessionStatus.done] 으로 고정되며 예약 → 완료 전이는
/// Phase 1.6(예약 캘린더)에서 별도 메서드로 다룬다.
class NewSessionRecordInput {
  /// 차감 대상 계약 ID — 어떤 계약에서 1회 빠지는지 결정.
  final String contractId;

  /// 수업이 진행된 시각.
  final DateTime scheduledAt;

  /// 운동 종목 리스트 (빈 리스트 허용 — 컨디션만 기록할 수 있음).
  final List<Exercise> exercises;

  /// 컨디션 코드(good/normal/bad 권장) 또는 자유 텍스트. null 가능.
  final String? condition;

  /// 통증/특이사항.
  final String? pain;

  /// 다음 수업용 메모.
  final String? nextMemo;

  const NewSessionRecordInput({
    required this.contractId,
    required this.scheduledAt,
    required this.exercises,
    this.condition,
    this.pain,
    this.nextMemo,
  });
}

/// 예약(미래 수업) 생성 시 입력. status 는 항상 scheduled.
class NewBookingInput {
  final String contractId;
  final DateTime scheduledAt;

  /// 예약 메모 — 회원 요청사항 등. status_memo 컬럼에 저장.
  final String? memo;

  const NewBookingInput({
    required this.contractId,
    required this.scheduledAt,
    this.memo,
  });
}

/// 기존 수업 기록 수정 시 사용. session_id 는 메서드 인자로 별도 전달.
class UpdateSessionRecordInput {
  final DateTime scheduledAt;
  final List<Exercise> exercises;
  final String? condition;
  final String? pain;
  final String? nextMemo;

  const UpdateSessionRecordInput({
    required this.scheduledAt,
    required this.exercises,
    this.condition,
    this.pain,
    this.nextMemo,
  });
}

// =====================================================================
// 트레이너 화면 표시용 결합 모델 — Session + (선택) SessionRecord
// =====================================================================

/// "최근 수업" 리스트 카드 1개에 필요한 데이터.
///
/// Session 만 있어도 (예: 노쇼) 카드를 그릴 수 있고,
/// SessionRecord 가 있으면 종목 수/볼륨을 함께 보여준다.
class SessionWithRecord {
  final Session session;
  final SessionRecord? record;

  const SessionWithRecord({required this.session, this.record});

  bool get hasRecord => record != null;
}

// =====================================================================
// SessionRepository
// =====================================================================

class SessionRepository {
  final SupabaseClient _client;
  SessionRepository(this._client);

  static const _sessionsTable = 'sessions';
  static const _recordsTable = 'session_records';

  // ---------------------------------------------------------------------
  // 행 매핑
  // ---------------------------------------------------------------------
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

  static DateTime? _parseTimestamp(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v as String);
  }

  // ---------------------------------------------------------------------
  // 조회
  // ---------------------------------------------------------------------

  /// 회원 1명의 최근 수업 [limit] 건을 진행 일시 내림차순으로 반환.
  ///
  /// pt_contracts 와 inner join 해야 회원 단위로 가져올 수 있음 — Supabase 표현으로는
  /// `select('*, pt_contracts!inner(member_id)')` 후 `.eq('pt_contracts.member_id', ...)`.
  /// RLS 가 트레이너 본인 계약만 노출하므로 다른 트레이너의 회원 수업은 안 보임.
  ///
  /// 반환은 sessions + (있다면) session_records 결합. 노쇼/취소는 record 가 null.
  Future<List<SessionWithRecord>> listRecentForMember(
    String memberId, {
    int limit = 20,
  }) async {
    // sessions + 부모 계약(member_id 매칭용) + 자식 session_records 까지 한 번에.
    // 결과 모양: { ...sessions컬럼, pt_contracts: {member_id}, session_records: {...}|null }
    final rows = await _client
        .from(_sessionsTable)
        .select('''
          id, contract_id, scheduled_at, status, recorded_at,
          recorded_by_trainer_id, status_memo, created_at,
          pt_contracts!inner(member_id),
          session_records(*)
        ''')
        .eq('pt_contracts.member_id', memberId)
        .order('scheduled_at', ascending: false)
        .limit(limit);

    final list = <SessionWithRecord>[];
    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      final session = _sessionFromRow(r);
      // session_records 는 one-to-one 이지만 PostgREST 가 List 로 반환할 수 있어 둘 다 대응.
      final rec = r['session_records'];
      SessionRecord? record;
      if (rec is Map<String, dynamic>) {
        record = SessionRecord.fromRow(rec);
      } else if (rec is List && rec.isNotEmpty) {
        record = SessionRecord.fromRow(rec.first as Map<String, dynamic>);
      }
      list.add(SessionWithRecord(session: session, record: record));
    }
    return list;
  }

  /// 수업 1건 + 기록을 id 로 조회.
  /// 기록 화면 진입 시 사용. 노쇼 등 기록 없는 수업이면 [SessionWithRecord.record] = null.
  Future<SessionWithRecord?> findById(String sessionId) async {
    final row = await _client
        .from(_sessionsTable)
        .select('*, session_records(*)')
        .eq('id', sessionId)
        .maybeSingle();
    if (row == null) return null;

    final session = _sessionFromRow(row);
    final rec = row['session_records'];
    SessionRecord? record;
    if (rec is Map<String, dynamic>) {
      record = SessionRecord.fromRow(rec);
    } else if (rec is List && rec.isNotEmpty) {
      record = SessionRecord.fromRow(rec.first as Map<String, dynamic>);
    }
    return SessionWithRecord(session: session, record: record);
  }

  // ---------------------------------------------------------------------
  // 변경 — 트랜잭션 보상 패턴
  // ---------------------------------------------------------------------

  /// 수업 완료 + 기록을 한 번에 생성.
  ///
  /// 순서:
  ///   1) sessions INSERT (status=done, recorded_at=now, recorded_by=trainerId)
  ///   2) session_records INSERT
  ///
  /// 1)은 성공했는데 2)가 실패하면 1) row 를 즉시 hard delete 로 되돌린다.
  /// (sessions 는 soft delete 컬럼이 없음 — 데이터 모델 §2.2 참조)
  ///
  /// 반환: 방금 만들어진 (Session + SessionRecord).
  Future<SessionWithRecord> createDoneSession({
    required NewSessionRecordInput input,
    required String trainerId,
  }) async {
    final now = DateTime.now().toIso8601String();

    // 1) sessions INSERT
    final sessionRow = await _client
        .from(_sessionsTable)
        .insert({
          'contract_id': input.contractId,
          'scheduled_at': input.scheduledAt.toIso8601String(),
          'status': _statusToDb(SessionStatus.done),
          'recorded_at': now,
          'recorded_by_trainer_id': trainerId,
        })
        .select()
        .single();
    final session = _sessionFromRow(sessionRow);

    // 2) session_records INSERT — 실패 시 1) 보상.
    try {
      final recordRow = await _client
          .from(_recordsTable)
          .insert({
            'session_id': session.id,
            'exercises': input.exercises
                .map((e) => e.toJson())
                .toList(growable: false),
            'condition': input.condition,
            'pain': input.pain,
            'next_memo': input.nextMemo,
          })
          .select()
          .single();
      final record = SessionRecord.fromRow(recordRow);
      return SessionWithRecord(session: session, record: record);
    } catch (e) {
      // 보상: sessions row 제거. delete 자체가 또 실패할 수 있지만,
      // 그 경우엔 원본 에러를 잃지 않도록 try/catch 로 묻고 재throw.
      try {
        await _client.from(_sessionsTable).delete().eq('id', session.id);
      } catch (_) {
        // 보상 실패는 로깅만 하고 원본 에러를 우선 노출.
        // (운영에서는 Sentry/Crashlytics 로 알람을 보내야 함 — Phase 2 검토)
      }
      rethrow;
    }
  }

  /// 기존 수업 기록을 수정. sessions(scheduled_at) + session_records 양쪽 갱신.
  ///
  /// status 는 변경하지 않는다 — 노쇼/취소 전이는 1.6 의 markStatus 메서드로.
  Future<SessionWithRecord> updateRecord({
    required String sessionId,
    required UpdateSessionRecordInput input,
  }) async {
    // 수업 일시 변경
    final sessionRow = await _client
        .from(_sessionsTable)
        .update({
          'scheduled_at': input.scheduledAt.toIso8601String(),
        })
        .eq('id', sessionId)
        .select()
        .single();
    final session = _sessionFromRow(sessionRow);

    // 기록 본문 갱신. upsert 로 처리 — done 인데 record 가 없는 비정상 케이스(보상 실패 등)
    // 에서도 새로 만들어줘서 자기 치유.
    final recordRow = await _client.from(_recordsTable).upsert({
      'session_id': sessionId,
      'exercises': input.exercises
          .map((e) => e.toJson())
          .toList(growable: false),
      'condition': input.condition,
      'pain': input.pain,
      'next_memo': input.nextMemo,
    }).select().single();
    final record = SessionRecord.fromRow(recordRow);

    return SessionWithRecord(session: session, record: record);
  }

  /// 수업 1건 삭제.
  ///
  /// session_records 는 FK ON DELETE CASCADE 로 함께 사라짐 (0005 마이그레이션).
  /// 잔여 횟수는 view 가 자동 재계산.
  Future<void> deleteSession(String sessionId) async {
    await _client.from(_sessionsTable).delete().eq('id', sessionId);
  }

  // ---------------------------------------------------------------------
  // 예약(미래 수업) — Phase 1.6
  // ---------------------------------------------------------------------

  /// 미래 수업 예약 1건을 생성. status=scheduled.
  ///
  /// scheduled 상태는 잔여 횟수에서 차감되지 않으므로 (v_contract_status 가
  /// done/no_show/late_cancel 만 카운트), 본 호출은 "잔여 횟수를 잡아두는" 효과는 없다.
  /// 잔여 부족 경고는 UI 단에서.
  Future<Session> createScheduledSession({
    required NewBookingInput input,
    required String trainerId,
  }) async {
    final row = await _client
        .from(_sessionsTable)
        .insert({
          'contract_id': input.contractId,
          'scheduled_at': input.scheduledAt.toIso8601String(),
          'status': _statusToDb(SessionStatus.scheduled),
          // recorded_at / recorded_by_trainer_id 는 done 처리 시점에 채움.
          // 예약 단계엔 NULL — 누가 예약을 잡았는지는 audit 가 필요해지면 별도 컬럼/테이블.
          'status_memo': input.memo,
        })
        .select()
        .single();
    return _sessionFromRow(row);
  }

  /// 예약된 수업의 상태를 변경.
  ///
  /// 호출 시점에 따라 동작이 다르다:
  ///   - status = done  : 본 메서드 대신 [updateRecord] 또는 [createDoneSession] 흐름 사용
  ///                      (record 본문이 함께 있어야 의미 있음). 본 메서드는 차단함.
  ///   - status = noShow / canceled / lateCancel : status 만 변경, record 는 손대지 않음.
  ///                                                노쇼/지각취소는 차감, 정상취소는 미차감.
  ///   - status = scheduled : 잘못된 처리를 되돌리는 경우. 허용은 하되 호출 측이 신중해야 함.
  ///
  /// [memo] 가 null 이면 status_memo 컬럼은 손대지 않음 (기존 메모 유지).
  /// 빈 문자열을 명시하면 비움.
  Future<Session> markStatus({
    required String sessionId,
    required SessionStatus status,
    String? memo,
  }) async {
    if (status == SessionStatus.done) {
      throw ArgumentError(
        'done 전이는 본 메서드로 처리하지 않습니다. updateRecord/createDoneSession 사용.',
      );
    }
    final update = <String, dynamic>{
      'status': _statusToDb(status),
    };
    if (memo != null) {
      update['status_memo'] = memo.isEmpty ? null : memo;
    }
    final row = await _client
        .from(_sessionsTable)
        .update(update)
        .eq('id', sessionId)
        .select()
        .single();
    return _sessionFromRow(row);
  }

  /// 취소 처리 — 정책에 따라 정상취소 / 지각취소 자동 분류.
  ///
  /// [DeductionRule.classifyCancellation] 으로 [SessionStatus] 결정 후 [markStatus] 위임.
  /// 분쟁 시 재계산 가능하도록 분류 로직이 도메인 순수 함수로 분리되어 있다.
  Future<Session> cancelSession({
    required String sessionId,
    required DateTime scheduledAt,
    required DateTime cancelAt,
    String? memo,
    DeductionPolicy policy = DeductionPolicy.defaultPolicy,
  }) async {
    final status = DeductionRule.classifyCancellation(
      scheduledAt: scheduledAt,
      cancelAt: cancelAt,
      policy: policy,
    );
    return markStatus(sessionId: sessionId, status: status, memo: memo);
  }

  // ---------------------------------------------------------------------
  // 트레이너 본인 예약 리스트 — Phase 1.6 booking_screen
  // ---------------------------------------------------------------------

  /// 트레이너 본인의 모든 sessions 를 기간 범위로 조회 (회원 정보 포함).
  ///
  /// 회원 이름이 카드에 필요해서 member_profiles 까지 inner join.
  /// pt_contracts → member_profiles 두 단계 — supabase select 표현으로:
  ///   `pt_contracts!inner(trainer_id, member_id, member_profiles!inner(name))`
  /// RLS 가 본인 계약만 노출 — 다른 트레이너 데이터는 어차피 안 옴.
  ///
  /// 정렬: scheduled_at 오름차순 — 오늘이 위로.
  Future<List<TrainerBookingRow>> listForCurrentTrainerBetween({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await _client
        .from(_sessionsTable)
        .select('''
          id, contract_id, scheduled_at, status, recorded_at,
          recorded_by_trainer_id, status_memo, created_at,
          pt_contracts!inner(
            id, member_id,
            member_profiles!inner(id, name)
          )
        ''')
        .gte('scheduled_at', from.toIso8601String())
        .lt('scheduled_at', to.toIso8601String())
        .order('scheduled_at');

    return (rows as List).cast<Map<String, dynamic>>().map((r) {
      final session = _sessionFromRow(r);
      final contract = r['pt_contracts'] as Map<String, dynamic>;
      final member = contract['member_profiles'] as Map<String, dynamic>;
      return TrainerBookingRow(
        session: session,
        memberId: member['id'] as String,
        memberName: member['name'] as String,
      );
    }).toList(growable: false);
  }

  /// 트레이너 본인 앞으로 들어온 **승인 대기(requested)** 신청 전체 (날짜 무관).
  ///
  /// 회원이 신청한 예약은 미래 어느 날짜로든 잡힐 수 있어, 예약 화면의 날짜 범위
  /// chip 으로는 놓칠 수 있다. 그래서 신청은 범위와 별개로 한 곳에 모아 보여준다.
  /// RLS(sessions_trainer_rw)가 본인 계약 수업만 노출하므로 다른 트레이너 신청은 안 옴.
  ///
  /// 정렬: 신청한 수업 일시 오름차순(가까운 일정 먼저).
  Future<List<TrainerBookingRow>> listPendingRequestsForCurrentTrainer() async {
    final rows = await _client
        .from(_sessionsTable)
        .select('''
          id, contract_id, scheduled_at, status, recorded_at,
          recorded_by_trainer_id, status_memo, created_at,
          pt_contracts!inner(
            id, member_id,
            member_profiles!inner(id, name)
          )
        ''')
        .eq('status', _statusToDb(SessionStatus.requested))
        .order('scheduled_at');

    return (rows as List).cast<Map<String, dynamic>>().map((r) {
      final session = _sessionFromRow(r);
      final contract = r['pt_contracts'] as Map<String, dynamic>;
      final member = contract['member_profiles'] as Map<String, dynamic>;
      return TrainerBookingRow(
        session: session,
        memberId: member['id'] as String,
        memberName: member['name'] as String,
      );
    }).toList(growable: false);
  }
}

/// 트레이너 예약 화면 1행 표시용 — Session + 회원 표시명.
class TrainerBookingRow {
  final Session session;
  final String memberId;
  final String memberName;

  const TrainerBookingRow({
    required this.session,
    required this.memberId,
    required this.memberName,
  });
}
