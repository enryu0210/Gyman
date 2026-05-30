/// 재등록 알림(Renewal Alert) repository — Phase 1.7.
///
/// 트레이너 본인의 *모든 활성 계약* 을 한 번에 조회해서, 각 계약에 대해
/// [RenewalCalculator.getAlertLevelFromCounts] 로 알림 단계를 판정한다.
///
/// **왜 v_contract_status 를 쓰나:**
///   - 잔여/사용 횟수는 view 가 이미 SQL 단에서 집계 → 클라이언트가 sessions 를
///     계약별로 모두 fetch 할 필요 없음 (계약 N개 × 평균 M개 세션 비용 회피)
///   - DB 와 도메인 계산식이 한 곳에서 통일됨 (잔여 횟수 정합성 정책: CLAUDE.md)
///   - 페이스 기반 예상 만료일은 본 메서드 범위 밖 — 회원 상세에서 정밀 표시 시
///     별도 fetch 후 [RenewalCalculator.estimateExpiryDate] 사용
///
/// **회원 이름 조인:**
///   pt_contracts → member_profiles inner join. RLS 가 본인 계약/회원만 노출.
///
/// 참고: docs/develop_plan.md §4 Phase 1.7,
///       src/supabase/migrations/0011_triggers_views.sql.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/models/enums.dart';
import '../../../domain/renewal_calculator.dart';

/// 알림 카드 1개에 필요한 데이터 묶음.
///
/// contract / member 메타 + view 집계 + 계산된 알림 단계.
/// 화면은 본 객체만 받으면 카드 한 줄을 그릴 수 있다.
class RenewalAlertItem {
  final String contractId;
  final String memberId;
  final String memberName;
  final int totalSessions;
  final int usedSessions;
  final int remainingSessions;
  final DateTime startDate;
  final DateTime? endDate;
  final RenewalAlertLevel level;

  const RenewalAlertItem({
    required this.contractId,
    required this.memberId,
    required this.memberName,
    required this.totalSessions,
    required this.usedSessions,
    required this.remainingSessions,
    required this.startDate,
    required this.endDate,
    required this.level,
  });

  /// 단계 우선순위 정렬용 (큰 값일수록 위에).
  ///
  /// expiring(3) > fiveLeft(2) > half(1) > none(0).
  /// 같은 단계 내에서는 remaining 적은 순 + endDate 빠른 순으로 추가 정렬.
  int get priority {
    switch (level) {
      case RenewalAlertLevel.expiring:
        return 3;
      case RenewalAlertLevel.fiveLeft:
        return 2;
      case RenewalAlertLevel.half:
        return 1;
      case RenewalAlertLevel.none:
        return 0;
    }
  }
}

class RenewalAlertRepository {
  final SupabaseClient _client;
  RenewalAlertRepository(this._client);

  /// 현재 트레이너의 모든 활성 계약 + 알림 단계.
  ///
  /// 정렬: 단계 우선순위 desc → remaining asc → endDate asc nulls last.
  /// 호출 측이 알림 단계별로 그룹화하기 쉽도록 본 메서드가 최종 정렬까지 책임.
  Future<List<RenewalAlertItem>> listForCurrentTrainer({DateTime? now}) async {
    final reference = now ?? DateTime.now();

    // 1) 트레이너 본인 활성 계약 + 회원명.
    //    pt_contracts 의 트레이너 RLS 가 적용되어 본인 계약만 노출되고, 회원명은
    //    member_id → member_profiles(id) FK 로 임베드한다.
    //    ⚠️ view(v_contract_status)에 직접 pt_contracts 를 임베드하면 PostgREST 가
    //    view-테이블 관계를 찾지 못해 조회가 실패한다(view 엔 FK 가 없음). 그래서
    //    계약 테이블을 1차 소스로 쓰고, 잔여 횟수만 아래에서 view 로 따로 가져온다.
    //
    //    "활성" 조건은 두 가지를 모두 만족해야 한다:
    //      - 계약이 살아 있음(pt_contracts.deleted_at IS NULL)
    //      - 회원이 살아 있음(member_profiles.deleted_at IS NULL)
    //    회원을 soft-delete 하면 그 계약은 더 이상 재등록 대상이 아니므로, 임베드한
    //    member_profiles 의 deleted_at 으로도 걸러 "활성 계약 N건" 집계에서 제외한다.
    //    (!inner 라 임베드 테이블 필터가 부모 계약 행까지 함께 제한한다.)
    final contractRows = await _client
        .from('pt_contracts')
        .select('''
          id, member_id, total_sessions, start_date, end_date,
          member_profiles!inner(id, name)
        ''')
        .filter('deleted_at', 'is', null)
        .filter('member_profiles.deleted_at', 'is', null);

    final contracts = (contractRows as List).cast<Map<String, dynamic>>();
    if (contracts.isEmpty) return const [];

    // 2) 잔여/사용 횟수 — 위에서 얻은(이미 RLS 통과한) 계약 id 로 한정해 view 조회.
    final contractIds =
        contracts.map((r) => r['id'] as String).toList(growable: false);
    final statusRows = await _client
        .from('v_contract_status')
        .select('contract_id, used_sessions, remaining_sessions')
        .inFilter('contract_id', contractIds);
    final statusById = <String, Map<String, dynamic>>{
      for (final r in (statusRows as List).cast<Map<String, dynamic>>())
        r['contract_id'] as String: r,
    };

    // 3) 병합 + 알림 단계 계산.
    final items = <RenewalAlertItem>[];
    for (final r in contracts) {
      final contractId = r['id'] as String;
      final member = r['member_profiles'] as Map<String, dynamic>;
      final endDateRaw = r['end_date'] as String?;
      final endDate =
          endDateRaw == null ? null : DateTime.tryParse(endDateRaw);
      final total = (r['total_sessions'] as num).toInt();
      // COUNT() 결과는 bigint → num.toInt(). 직접 `as int` 면 view 조회 시 런타임 오류.
      // 세션이 0건이어도 view 행은 존재(used=0/remaining=total). 혹시 누락 시 폴백.
      final status = statusById[contractId];
      final used =
          status == null ? 0 : (status['used_sessions'] as num).toInt();
      final remaining = status == null
          ? total
          : (status['remaining_sessions'] as num).toInt();
      final level = RenewalCalculator.getAlertLevelFromCounts(
        total: total,
        used: used,
        remaining: remaining,
        endDate: endDate,
        now: reference,
      );

      items.add(RenewalAlertItem(
        contractId: contractId,
        memberId: member['id'] as String,
        memberName: member['name'] as String,
        totalSessions: total,
        usedSessions: used,
        remainingSessions: remaining,
        startDate: DateTime.parse(r['start_date'] as String),
        endDate: endDate,
        level: level,
      ));
    }

    items.sort((a, b) {
      final p = b.priority.compareTo(a.priority);
      if (p != 0) return p;
      final r = a.remainingSessions.compareTo(b.remainingSessions);
      if (r != 0) return r;
      // endDate null 은 가장 뒤로 — "만료일 미정" 은 시급성 낮음
      if (a.endDate == null && b.endDate == null) return 0;
      if (a.endDate == null) return 1;
      if (b.endDate == null) return -1;
      return a.endDate!.compareTo(b.endDate!);
    });

    return items;
  }
}
