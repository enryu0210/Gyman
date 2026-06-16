/// 관리자 대시보드(C1) 데이터 조회 + 집계 repository (읽기 전용).
///
/// **데이터 소스:** `v_admin_contract_overview` view 한 개(0030).
///   계약 1건 = 1행. security_invoker=true 라 0029 admin RLS 가 그대로 적용돼
///   **본인 센터 계약만** 돌아온다 → 쿼리에 center_id 필터를 두지 않아도 안전
///   (회원 홈 repository 와 동일한 "RLS 가 범위를 좁힌다" 패턴).
///
/// **집계는 Dart 에서:**
///   잔여/사용 횟수·매출 같은 매출 직결 수치는 이미 view(=v_contract_status 재사용)
///   에서 통일된 식으로 계산돼 내려온다. 여기서는 그 행들을 group/sum 해서
///   센터 요약·트레이너별 성과·만료 임박 목록 세 묶음으로만 변환한다.
///   (SQL GROUP BY 를 또 만들지 않은 이유: 화면이 쓰는 grain 이 3종이라 한 view 를
///    클라에서 나눠 쓰는 편이 단순하고, 매출 중복 합산 위험도 per-contract grain 이
///    원천 차단한다.)
///
/// 참고: docs/develop_plan.md §4 Phase 3.1-B,
///       src/supabase/migrations/0029(admin RLS)·0030(view).
library;

import 'package:supabase_flutter/supabase_flutter.dart';

// =====================================================================
// 원본 행 모델 — view 한 행
// =====================================================================

/// `v_admin_contract_overview` 한 행 = 계약 1건의 대시보드용 스냅샷.
class AdminContractRow {
  final String contractId;
  final String memberId;
  final String memberName;
  final String trainerId;

  /// 트레이너명. 계약의 트레이너가 (탈퇴 등으로) 안 잡히면 null.
  final String? trainerName;

  final int totalSessions;

  /// 차감된 수업 총합(done + no_show + late_cancel) = 노쇼율 분모.
  final int usedSessions;
  final int remainingSessions;

  final DateTime startDate;
  final DateTime? endDate;

  /// 계약 금액(원). 미입력이면 null → 매출 합산에서 0 취급.
  final int? price;

  final int doneCount;
  final int noShowCount;

  const AdminContractRow({
    required this.contractId,
    required this.memberId,
    required this.memberName,
    required this.trainerId,
    required this.trainerName,
    required this.totalSessions,
    required this.usedSessions,
    required this.remainingSessions,
    required this.startDate,
    required this.endDate,
    required this.price,
    required this.doneCount,
    required this.noShowCount,
  });

  /// 잔여 횟수가 남아있고 만료되지 않은 "진행 중" 계약인가.
  bool isActiveOn(DateTime today) {
    if (remainingSessions <= 0) return false;
    if (endDate != null && endDate!.isBefore(today)) return false;
    return true;
  }

  /// 재등록 권유가 필요한 "만료 임박" 계약인가.
  ///
  /// 기준(둘 중 하나라도): 잔여 [lowRemaining]회 이하 / 만료일이 [soonDays]일 이내.
  bool isExpiring(DateTime today, {int lowRemaining = 3, int soonDays = 14}) {
    final lowOnSessions = remainingSessions <= lowRemaining;
    final soonByDate = endDate != null &&
        !endDate!.isBefore(today) &&
        endDate!.isBefore(today.add(Duration(days: soonDays + 1)));
    return lowOnSessions || soonByDate;
  }
}

// =====================================================================
// 집계 결과 모델
// =====================================================================

/// 센터 전체 요약 카드 4종.
class AdminCenterSummary {
  /// 진행 중 계약(잔여>0·미만료)을 가진 회원 수(중복 제거).
  final int activeMemberCount;

  /// 진행 중 계약 수.
  final int activeContractCount;

  /// 누적 매출(모든 계약 price 합).
  final int totalRevenue;

  /// 노쇼율(0.0~1.0). 차감 수업이 0이면 0.
  final double noShowRate;

  const AdminCenterSummary({
    required this.activeMemberCount,
    required this.activeContractCount,
    required this.totalRevenue,
    required this.noShowRate,
  });
}

/// 트레이너 1명의 성과 한 줄.
class AdminTrainerStat {
  final String trainerId;
  final String trainerName;

  /// 담당 회원 수(중복 제거).
  final int memberCount;

  /// 완료한 수업 수(done).
  final int doneCount;

  /// 담당 계약 매출 합.
  final int revenue;

  /// 노쇼율(0.0~1.0).
  final double noShowRate;

  const AdminTrainerStat({
    required this.trainerId,
    required this.trainerName,
    required this.memberCount,
    required this.doneCount,
    required this.revenue,
    required this.noShowRate,
  });
}

/// 대시보드 한 화면이 필요로 하는 데이터 묶음.
class AdminDashboardData {
  final AdminCenterSummary summary;

  /// 트레이너별 성과(매출 내림차순).
  final List<AdminTrainerStat> trainerStats;

  /// 만료 임박 계약(잔여 적은 순 → 만료일 가까운 순).
  final List<AdminContractRow> expiring;

  const AdminDashboardData({
    required this.summary,
    required this.trainerStats,
    required this.expiring,
  });

  /// 센터에 계약 데이터가 하나도 없는가(빈 상태 안내용).
  bool get isEmpty => trainerStats.isEmpty && expiring.isEmpty;
}

// =====================================================================
// Repository
// =====================================================================

class AdminDashboardRepository {
  final SupabaseClient _client;
  AdminDashboardRepository(this._client);

  static const _overviewView = 'v_admin_contract_overview';

  /// view 컬럼 — 추가 시 매핑/모델과 함께 갱신할 것(_columns 동기화 원칙).
  static const _columns =
      'contract_id, member_id, member_name, trainer_id, trainer_name, '
      'total_sessions, used_sessions, remaining_sessions, '
      'start_date, end_date, price, done_count, no_show_count';

  /// 대시보드 데이터 로드 → 집계까지 한 번에.
  Future<AdminDashboardData> loadDashboard() async {
    final rows = await _fetchRows();
    return aggregate(rows, DateTime.now());
  }

  /// view 행들을 화면용 세 묶음으로 집계(순수 함수 — Supabase 의존 없음).
  ///
  /// 매출/노쇼율 같은 매출 직결 수치라 **단위 테스트 대상**(CLAUDE.md §5.1).
  /// [now] 를 주입받아(만료 임박/활성 판정의 "오늘") 테스트에서 시점을 고정한다.
  static AdminDashboardData aggregate(
    List<AdminContractRow> rows,
    DateTime now,
  ) {
    final today = _dateOnly(now);
    return AdminDashboardData(
      summary: _buildSummary(rows, today),
      trainerStats: _buildTrainerStats(rows),
      expiring: _buildExpiring(rows, today),
    );
  }

  // ---------------------------------------------------------------------
  // 조회
  // ---------------------------------------------------------------------

  Future<List<AdminContractRow>> _fetchRows() async {
    final rows = await _client
        .from(_overviewView)
        .select(_columns)
        .order('start_date', ascending: false);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(_fromRow)
        .toList(growable: false);
  }

  // ---------------------------------------------------------------------
  // 집계
  // ---------------------------------------------------------------------

  /// 센터 요약 4종.
  static AdminCenterSummary _buildSummary(
    List<AdminContractRow> rows,
    DateTime today,
  ) {
    final activeMembers = <String>{};
    var activeContracts = 0;
    var totalRevenue = 0;
    var totalNoShow = 0;
    var totalDeducted = 0; // 노쇼율 분모(used_sessions 합)

    for (final r in rows) {
      totalRevenue += r.price ?? 0;
      totalNoShow += r.noShowCount;
      totalDeducted += r.usedSessions;
      if (r.isActiveOn(today)) {
        activeContracts++;
        activeMembers.add(r.memberId);
      }
    }

    return AdminCenterSummary(
      activeMemberCount: activeMembers.length,
      activeContractCount: activeContracts,
      totalRevenue: totalRevenue,
      noShowRate: totalDeducted == 0 ? 0 : totalNoShow / totalDeducted,
    );
  }

  /// 트레이너별 성과 — trainer_id 로 묶어 합산, 매출 내림차순 정렬.
  static List<AdminTrainerStat> _buildTrainerStats(
      List<AdminContractRow> rows) {
    // trainer_id → 누적 버킷
    final byTrainer = <String, _TrainerBucket>{};

    for (final r in rows) {
      final bucket = byTrainer.putIfAbsent(
        r.trainerId,
        () => _TrainerBucket(name: r.trainerName ?? '(이름 없음)'),
      );
      bucket.members.add(r.memberId);
      bucket.doneCount += r.doneCount;
      bucket.noShowCount += r.noShowCount;
      bucket.deducted += r.usedSessions;
      bucket.revenue += r.price ?? 0;
    }

    final stats = byTrainer.entries
        .map(
          (e) => AdminTrainerStat(
            trainerId: e.key,
            trainerName: e.value.name,
            memberCount: e.value.members.length,
            doneCount: e.value.doneCount,
            revenue: e.value.revenue,
            noShowRate: e.value.deducted == 0
                ? 0
                : e.value.noShowCount / e.value.deducted,
          ),
        )
        .toList();

    // 매출 큰 순으로 — 관리자가 성과 높은 트레이너부터 보게.
    stats.sort((a, b) => b.revenue.compareTo(a.revenue));
    return stats;
  }

  /// 만료 임박 계약 — 잔여 적은 순 → 만료일 가까운 순.
  static List<AdminContractRow> _buildExpiring(
    List<AdminContractRow> rows,
    DateTime today,
  ) {
    final expiring = rows.where((r) => r.isExpiring(today)).toList();
    expiring.sort((a, b) {
      final byRemaining = a.remainingSessions.compareTo(b.remainingSessions);
      if (byRemaining != 0) return byRemaining;
      // 잔여가 같으면 만료일 가까운 순(null 만료일은 뒤로).
      final ae = a.endDate, be = b.endDate;
      if (ae == null && be == null) return 0;
      if (ae == null) return 1;
      if (be == null) return -1;
      return ae.compareTo(be);
    });
    return expiring;
  }

  // ---------------------------------------------------------------------
  // 행 매핑
  // ---------------------------------------------------------------------

  static AdminContractRow _fromRow(Map<String, dynamic> row) {
    return AdminContractRow(
      contractId: row['contract_id'] as String,
      memberId: row['member_id'] as String,
      memberName: (row['member_name'] as String?) ?? '(이름 없음)',
      trainerId: row['trainer_id'] as String,
      trainerName: row['trainer_name'] as String?,
      totalSessions: (row['total_sessions'] as num).toInt(),
      // PG COUNT()/집계는 bigint → num 경유 변환(직접 as int 시 view 에서 타입오류).
      usedSessions: (row['used_sessions'] as num).toInt(),
      remainingSessions: (row['remaining_sessions'] as num).toInt(),
      startDate: DateTime.parse(row['start_date'] as String),
      endDate: _parseDate(row['end_date']),
      price: (row['price'] as num?)?.toInt(),
      doneCount: (row['done_count'] as num).toInt(),
      noShowCount: (row['no_show_count'] as num).toInt(),
    );
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v as String);
  }

  /// 시각 성분을 떼고 날짜만 비교하기 위한 헬퍼(만료 임박 판정용).
  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}

/// 트레이너별 합산용 가변 버킷(내부 전용).
class _TrainerBucket {
  final String name;
  final Set<String> members = {};
  int doneCount = 0;
  int noShowCount = 0;
  int deducted = 0;
  int revenue = 0;

  _TrainerBucket({required this.name});
}
