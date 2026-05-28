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

    // v_contract_status 는 RLS 가 없지만 베이스 테이블(pt_contracts, sessions) RLS 가
    // 그대로 적용 → 본인 행만 노출. end_date / member 이름은 view 에 없어서 inner join.
    final rows = await _client.from('v_contract_status').select('''
          contract_id, member_id, total_sessions, used_sessions,
          remaining_sessions, start_date, end_date,
          pt_contracts!inner(
            id,
            member_profiles!inner(id, name)
          )
        ''');

    final items = <RenewalAlertItem>[];
    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      final endDateRaw = r['end_date'] as String?;
      final endDate =
          endDateRaw == null ? null : DateTime.tryParse(endDateRaw);
      final total = (r['total_sessions'] as num).toInt();
      // COUNT() 결과는 bigint → num.toInt(). 직접 `as int` 면 view 조회 시 런타임 오류.
      final used = (r['used_sessions'] as num).toInt();
      final remaining = (r['remaining_sessions'] as num).toInt();
      final level = RenewalCalculator.getAlertLevelFromCounts(
        total: total,
        used: used,
        remaining: remaining,
        endDate: endDate,
        now: reference,
      );

      final contract = r['pt_contracts'] as Map<String, dynamic>;
      final member = contract['member_profiles'] as Map<String, dynamic>;

      items.add(RenewalAlertItem(
        contractId: r['contract_id'] as String,
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
