/// 회원 본인 시점의 홈 화면 데이터 조회 repository (읽기 전용).
///
/// **트레이너 repository와 분리한 이유:**
///   트레이너 측(`contract_repository`, `session_repository`)은 "담당 회원을
///   memberId로 지정해 조회"하는 반면, 회원 측은 **항상 본인 데이터만** 본다.
///   본인 식별은 클라가 직접 넘기지 않고 DB RLS(`current_member_profile_id()`)가
///   처리하므로, 쿼리에 member_id 필터를 두지 않아도 본인 행만 돌아온다.
///     - v_contract_status : security_invoker=true(0018)라 base RLS 그대로 적용
///     - sessions          : sessions_member_read 정책이 본인 계약 수업만 노출
///   → 다른 회원 데이터가 섞일 여지가 없다(2차 방어로 코드도 단순해짐).
///
/// **반환 모델:**
///   화면이 필요로 하는 것만 담은 [MemberHomeSummary] 하나로 합쳐 돌려준다.
///   (잔여 횟수 합계 + 계약별 내역 + 다음 예약 수업)
///
/// 참고: docs/develop_plan.md §4 회원 로드맵 ②(회원 홈),
///       src/supabase/migrations/0013(RLS)·0018(view security_invoker).
library;

// supabase_flutter 가 export 하는 auth `Session` 과 도메인 `Session` 이름 충돌 →
// SDK 측 인증 `Session` 을 가린다(본 파일은 인증 세션을 쓰지 않음).
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../../../domain/models/enums.dart';
import '../../../domain/models/session.dart';

// =====================================================================
// 표시용 모델
// =====================================================================

/// 회원 1명의 계약 1건 상태 — v_contract_status view 한 행.
///
/// 잔여 횟수의 진실의 원천은 항상 이 view(트레이너 측과 동일 식). 회원 앱은
/// 읽기만 하므로 도메인 계산기 대신 view 값을 그대로 신뢰한다.
class MemberContractStatus {
  final String contractId;
  final int totalSessions;
  final int usedSessions;
  final int remainingSessions;
  final DateTime startDate;
  final DateTime? endDate;

  const MemberContractStatus({
    required this.contractId,
    required this.totalSessions,
    required this.usedSessions,
    required this.remainingSessions,
    required this.startDate,
    this.endDate,
  });

  /// 횟수를 모두 소진했는가(잔여 0 이하).
  bool get isExhausted => remainingSessions <= 0;
}

/// 회원 홈 화면이 한 번에 그리는 데 필요한 데이터 묶음.
class MemberHomeSummary {
  /// 회원 표시명(인사말용). 프로필 조회 실패 시 빈 문자열.
  final String memberName;

  /// 다가오는 예약 수업 중 가장 가까운 1건. 없으면 null.
  final Session? nextSession;

  /// 활성 계약별 상태(최신 시작일 순). 빈 리스트면 "등록된 계약 없음".
  final List<MemberContractStatus> contracts;

  const MemberHomeSummary({
    required this.memberName,
    required this.nextSession,
    required this.contracts,
  });

  /// 전체 계약을 합산한 잔여 횟수. 음수 방지를 위해 0 미만은 0으로 본다.
  int get totalRemaining {
    final sum = contracts.fold<int>(0, (acc, c) => acc + c.remainingSessions);
    return sum < 0 ? 0 : sum;
  }

  /// 표시할 계약이 하나라도 있는가.
  bool get hasContract => contracts.isNotEmpty;
}

// =====================================================================
// Repository
// =====================================================================

class MemberHomeRepository {
  final SupabaseClient _client;
  MemberHomeRepository(this._client);

  static const _memberTable = 'member_profiles';
  static const _statusView = 'v_contract_status';
  static const _sessionsTable = 'sessions';

  /// 홈 화면 데이터 한 번에 로드.
  ///
  /// 세 쿼리를 병렬로 던져 라운드트립 지연을 줄인다. 셋 다 RLS로 본인 데이터만
  /// 돌아오므로 별도 member_id 필터가 필요 없다.
  Future<MemberHomeSummary> loadSummary() async {
    final results = await Future.wait([
      _fetchMemberName(),
      _fetchContractStatuses(),
      _fetchNextSession(),
    ]);

    return MemberHomeSummary(
      memberName: results[0] as String,
      contracts: results[1] as List<MemberContractStatus>,
      nextSession: results[2] as Session?,
    );
  }

  // ---------------------------------------------------------------------
  // 개별 조회
  // ---------------------------------------------------------------------

  /// 본인 회원 프로필의 이름. member_self_rw RLS로 본인 1행만 조회.
  Future<String> _fetchMemberName() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return '';
    final row = await _client
        .from(_memberTable)
        .select('name')
        .eq('user_id', userId)
        .maybeSingle();
    return (row?['name'] as String?) ?? '';
  }

  /// 본인 계약 상태 리스트(시작일 내림차순 — 최신 계약 먼저).
  Future<List<MemberContractStatus>> _fetchContractStatuses() async {
    final rows = await _client
        .from(_statusView)
        .select()
        .order('start_date', ascending: false);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(_statusFromRow)
        .toList(growable: false);
  }

  /// 다가오는 예약 수업 중 가장 가까운 1건.
  ///
  /// 조건: status=scheduled(아직 진행 전) + scheduled_at >= 지금.
  /// RLS가 본인 계약 수업만 노출하므로 계약 join 없이 안전하게 조회.
  Future<Session?> _fetchNextSession() async {
    final nowIso = DateTime.now().toIso8601String();
    final row = await _client
        .from(_sessionsTable)
        .select()
        .eq('status', 'scheduled')
        .gte('scheduled_at', nowIso)
        .order('scheduled_at', ascending: true)
        .limit(1)
        .maybeSingle();
    if (row == null) return null;
    return _sessionFromRow(row);
  }

  // ---------------------------------------------------------------------
  // 행 매핑
  // ---------------------------------------------------------------------

  static MemberContractStatus _statusFromRow(Map<String, dynamic> row) {
    return MemberContractStatus(
      contractId: row['contract_id'] as String,
      totalSessions: row['total_sessions'] as int,
      // PG COUNT()는 bigint → Dart num 경유 변환(직접 as int 시 view에서 타입오류).
      usedSessions: (row['used_sessions'] as num).toInt(),
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

  /// PG ENUM session_status → 도메인 enum. 본 화면은 scheduled만 조회하지만,
  /// 알 수 없는 값이 오면 조용히 넘기지 않고 명시적으로 실패시킨다.
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
