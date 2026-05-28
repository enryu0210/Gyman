/// PT 계약(pt_contracts) repository + v_contract_status 조회 wrapper.
///
/// 본 repository는 **트레이너 시점**만 다룬다.
/// 회원 측 조회는 회원앱(Phase 2)에서 별도 repository로.
///
/// **잔여 횟수 정책 (중요):**
///   DB의 `v_contract_status` view 가 진실의 원천이다.
///   - sessions 테이블의 status 별 카운트를 SQL이 직접 합산
///   - 도메인 `RemainingSessionsCalculator` 와 동일한 식 (단위 테스트로 동치성 보장)
///   - 두 경로 결과가 다르면 매출/분쟁 직결 → 한 곳(view)에서 받는다.
///   - 도메인 계산기는 오프라인/캐시 시나리오, 단위 테스트, audit 재계산용으로 남김.
///
/// 참고: docs/data_model.md §4 v_contract_status, develop_plan.md §1 1.3.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/models/pt_contract.dart';

/// 계약 추가 시 사용하는 입력 객체.
/// 트레이너 ID는 현재 로그인 사용자(auth.uid())로 채우므로 입력에서 제외.
class NewContractInput {
  final String memberId;
  final int totalSessions;
  final DateTime startDate;
  final DateTime? endDate;
  final int? price;
  final String? memo;
  final String? centerId;

  const NewContractInput({
    required this.memberId,
    required this.totalSessions,
    required this.startDate,
    this.endDate,
    this.price,
    this.memo,
    this.centerId,
  });
}

/// v_contract_status view 의 한 행.
///
/// view 자체는 RLS 없지만, 베이스 테이블(pt_contracts, sessions) RLS가
/// 그대로 적용되므로 권한 안전. (data_model.md §4 주석)
class ContractStatusRow {
  final String contractId;
  final String memberId;
  final String trainerId;
  final int totalSessions;
  final int usedSessions;
  final int remainingSessions;
  final DateTime startDate;
  final DateTime? endDate;

  const ContractStatusRow({
    required this.contractId,
    required this.memberId,
    required this.trainerId,
    required this.totalSessions,
    required this.usedSessions,
    required this.remainingSessions,
    required this.startDate,
    this.endDate,
  });

  bool get isExhausted => remainingSessions <= 0;
}

class ContractRepository {
  final SupabaseClient _client;
  ContractRepository(this._client);

  static const _table = 'pt_contracts';
  static const _statusView = 'v_contract_status';

  // ---------------------------------------------------------------------
  // PtContract row 매핑
  // ---------------------------------------------------------------------
  static PtContract _fromRow(Map<String, dynamic> row) {
    return PtContract(
      id: row['id'] as String,
      memberId: row['member_id'] as String,
      trainerId: row['trainer_id'] as String,
      centerId: row['center_id'] as String?,
      totalSessions: row['total_sessions'] as int,
      startDate: DateTime.parse(row['start_date'] as String),
      endDate: _parseDate(row['end_date']),
      price: row['price'] as int?,
      memo: row['memo'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      deletedAt: _parseDate(row['deleted_at']),
    );
  }

  static ContractStatusRow _statusFromRow(Map<String, dynamic> row) {
    return ContractStatusRow(
      contractId: row['contract_id'] as String,
      memberId: row['member_id'] as String,
      trainerId: row['trainer_id'] as String,
      totalSessions: row['total_sessions'] as int,
      // PG COUNT()는 bigint(int64) — Dart에서는 int. 안전 변환.
      usedSessions: (row['used_sessions'] as num).toInt(),
      remainingSessions: (row['remaining_sessions'] as num).toInt(),
      startDate: DateTime.parse(row['start_date'] as String),
      endDate: _parseDate(row['end_date']),
    );
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v as String);
  }

  // ---------------------------------------------------------------------
  // 조회
  // ---------------------------------------------------------------------

  /// 회원 1명의 활성 계약 리스트 (시작일 내림차순 — 최신 계약 먼저).
  ///
  /// 활성: deleted_at IS NULL.
  /// 만료 여부(잔여 0)는 *상태 행* 으로 별도 판단 — 본 메서드는 행만 반환.
  Future<List<PtContract>> listForMember(String memberId) async {
    final rows = await _client
        .from(_table)
        .select()
        .eq('member_id', memberId)
        .filter('deleted_at', 'is', null)
        .order('start_date', ascending: false);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(_fromRow)
        .toList(growable: false);
  }

  /// 계약 상태(잔여/사용 등) 리스트 — v_contract_status view 조회.
  ///
  /// 회원별로 일괄 받아서 화면에서 contract_id로 매칭. 두 번 fetch 하는 이유는
  /// pt_contracts 의 memo/price 같은 비집계 컬럼은 view에 없기 때문.
  Future<List<ContractStatusRow>> listStatusForMember(String memberId) async {
    final rows = await _client
        .from(_statusView)
        .select()
        .eq('member_id', memberId)
        .order('start_date', ascending: false);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(_statusFromRow)
        .toList(growable: false);
  }

  // ---------------------------------------------------------------------
  // 변경
  // ---------------------------------------------------------------------

  /// 계약 1건 추가.
  ///
  /// trainer_id는 DB default(auth.uid()) ... 가 아니라 *명시적으로* 넘긴다.
  /// 베타 단계 pt_contracts.trainer_id는 default가 없고 NOT NULL이므로,
  /// 호출 측이 현재 user.id를 알고 넘겨야 함.
  Future<PtContract> addContract({
    required NewContractInput input,
    required String trainerId,
  }) async {
    final row = await _client
        .from(_table)
        .insert({
          'member_id': input.memberId,
          'trainer_id': trainerId,
          'center_id': input.centerId,
          'total_sessions': input.totalSessions,
          // date 컬럼은 YYYY-MM-DD 문자열 권장 — toIso8601String()이면 시각까지
          // 들어가 PG가 date로 캐스팅하면서 일자만 취함.
          'start_date': _formatDate(input.startDate),
          'end_date': input.endDate == null ? null : _formatDate(input.endDate!),
          'price': input.price,
          'memo': input.memo,
        })
        .select()
        .single();
    return _fromRow(row);
  }

  /// 계약 soft delete — 잔여 계산에서 제외되지만 row는 보존(매출 audit).
  Future<void> softDelete(String contractId) async {
    await _client
        .from(_table)
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', contractId);
  }

  /// YYYY-MM-DD 포맷 — date 컬럼용. intl 의존 피하려고 직접.
  static String _formatDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }
}
