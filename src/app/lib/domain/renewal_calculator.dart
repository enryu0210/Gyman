/// 재등록 시점 계산 — 트레이너 홈의 "재등록 알림" 카드와 자동 안내 메시지 트리거.
///
/// **왜 도메인 로직인가:**
///   "5회 남았을 때 알린다" "곧 만료할 때 알린다" 같은 판정 기준이 매출과 직결.
///   기준이 한 곳에 모여있어야 변경(예: 3회로 조정) 시 한 줄만 수정하고
///   테스트 한 번 돌리면 검증된다.
///
/// **만료일 추정 방식 (estimateExpiryDate):**
///   - 차감된 세션의 첫 시각 ~ 현재까지 경과 일수 기준
///   - 페이스 = 차감 횟수 / 경과 주 수 (주당 차감 횟수)
///   - 남은 주 = 잔여 횟수 / 페이스
///   - 예상 만료일 = 현재 + 남은 주
///   - end_date가 명시되어 있으면 둘 중 빠른 날 반환
///
/// **신뢰성 보장:**
///   - 활동 기간 < 7일 OR 차감 0회 → null 반환 (페이스 추정 신뢰도 부족)
///   - 호출 측은 null 시 "데이터 부족" 메시지 표시
///
/// 참고: docs/develop_plan.md §2.3, §4 1.7,
///       docs/data_model.md §2.1 renewal_alert_level.
library;

import 'models/enums.dart';
import 'models/pt_contract.dart';
import 'models/session.dart';
import 'remaining_sessions.dart';

class RenewalCalculator {
  /// 페이스 계산을 신뢰하려면 최소 이만큼 활동 기간이 있어야 함.
  /// 1주 = 한 주에 1번씩이라도 본 셈. 더 짧으면 페이스가 들쭉날쭉.
  static const _minActivityDays = 7;

  /// "5회 남음" 알림 임계값.
  /// 트레이너가 재등록 권유 대화를 자연스럽게 시작할 수 있는 횟수.
  static const _fiveLeftThreshold = 5;

  /// "곧 만료" 알림 임계값 (7일).
  /// data_model.md §2.1 renewal_alert_level enum 주석과 일치.
  static const _expiringWindowDays = 7;

  /// 예상 만료일 계산.
  ///
  /// 반환 규칙:
  ///   - 차감 0회 → null
  ///   - 첫 차감 ~ now 경과 일수 < [_minActivityDays] → null
  ///   - 잔여 횟수 0 → now 반환 (이미 만료)
  ///   - end_date가 명시되어 있으면 (estimated, end_date) 중 빠른 날
  ///
  /// 예시 (now = 2026-02-01):
  ///   - total 10, done 8, 첫 done 2026-01-01 → 1달간 8회 → 주당 2회 →
  ///     잔여 2회 / 2회 = 1주 → 만료 예상 2026-02-08
  ///   - end_date = 2026-02-05 가 있으면 → 2026-02-05 (더 빠르므로)
  ///
  /// [now]는 테스트 결정성을 위한 주입점. 미지정 시 DateTime.now().
  static DateTime? estimateExpiryDate(
    PtContract contract,
    List<Session> sessions, {
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final status = RemainingSessionsCalculator.calculate(contract, sessions);

    if (status.remaining <= 0) {
      // 이미 만료. end_date가 더 가까우면 그것을, 아니면 now.
      return _earliest(reference, contract.endDate);
    }

    // 자기 계약 + 차감된 세션만 추리기
    final deducted = sessions
        .where((s) => s.contractId == contract.id && s.isDeducted)
        .toList();

    if (deducted.isEmpty) {
      // 페이스 추정 불가. end_date가 있으면 그거라도 반환.
      return contract.endDate;
    }

    // 첫 차감 시각 ~ 현재까지 경과 (페이스의 분모)
    deducted.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final firstDeducted = deducted.first.scheduledAt;
    final elapsedDays = reference.difference(firstDeducted).inDays;

    if (elapsedDays < _minActivityDays) {
      // 신뢰할 만한 페이스가 안 나옴. end_date로 폴백.
      return contract.endDate;
    }

    // 주당 차감 횟수 (예: 4주 동안 8회 → 2.0)
    final perWeek = deducted.length / (elapsedDays / 7.0);
    // 남은 주 수 (예: 잔여 4회 / 2.0 = 2주)
    final remainingWeeks = status.remaining / perWeek;
    final estimated = reference.add(
      Duration(days: (remainingWeeks * 7).round()),
    );

    return _earliest(estimated, contract.endDate);
  }

  /// 재등록 알림 단계 판정.
  ///
  /// 우선순위 (높음→낮음): expiring > fiveLeft > half > none
  /// 한 계약이 여러 조건을 만족해도 가장 높은 단계 하나만 반환.
  ///
  /// 기준:
  ///   - expiring: 잔여 0 OR (예상 만료일 또는 end_date가 7일 이내)
  ///   - fiveLeft: 잔여 횟수 ≤ 5
  ///   - half: 사용 횟수 ≥ 총 횟수의 절반 (정확히 절반 포함)
  ///   - none: 그 외
  ///
  /// 예시 (total 10, now = 2026-02-01):
  ///   - used 0 → none
  ///   - used 5 → half
  ///   - used 6, remaining 4 → fiveLeft (5회 이하 임계 — fiveLeft가 half보다 우선)
  ///   - end_date = 2026-02-05 (4일 후), remaining 8 → expiring (가장 우선)
  static RenewalAlertLevel getAlertLevel(
    PtContract contract,
    List<Session> sessions, {
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final status = RemainingSessionsCalculator.calculate(contract, sessions);

    // 1) expiring 판정 — 가장 강한 신호
    if (status.remaining <= 0) {
      return RenewalAlertLevel.expiring;
    }
    final estimated = estimateExpiryDate(contract, sessions, now: reference);
    if (estimated != null) {
      final daysUntil = estimated.difference(reference).inDays;
      if (daysUntil <= _expiringWindowDays) {
        return RenewalAlertLevel.expiring;
      }
    }

    // 2) fiveLeft 판정
    if (status.remaining <= _fiveLeftThreshold) {
      return RenewalAlertLevel.fiveLeft;
    }

    // 3) half 판정 — 절반 정확히 포함
    // (used*2 >= total) 형태로 비교 — int 나눗셈 절상/절하 이슈 회피
    if (status.used * 2 >= contract.totalSessions) {
      return RenewalAlertLevel.half;
    }

    return RenewalAlertLevel.none;
  }

  /// [getAlertLevel] 의 가벼운 변종 — 세션 리스트가 없이 *집계값* 만으로 판정.
  ///
  /// 트레이너 본인의 *모든* 활성 계약을 한 번에 분류할 때 사용한다 (홈 알림 카드).
  /// 세션 리스트를 N개 계약 × 평균 M개씩 fetch 하는 비용을 피한다.
  ///
  /// 차이:
  ///   - 페이스 기반 추정 만료일은 *계산하지 않음*. expiring 판정은
  ///     `remaining == 0` 또는 `endDate ≤ 7일 이내` 둘만 본다.
  ///   - 회원 상세에서 "예상 만료 2026-02-08" 같은 정밀 표시가 필요할 땐 본 메서드 대신
  ///     [estimateExpiryDate] / [getAlertLevel] 사용.
  ///
  /// 예시 (총 10회 기준):
  ///   - used 0 → none
  ///   - used 5 → half
  ///   - used 6, remaining 4 → fiveLeft
  ///   - remaining 8, endDate = 3일 후 → expiring
  ///   - remaining 0 → expiring
  static RenewalAlertLevel getAlertLevelFromCounts({
    required int total,
    required int used,
    required int remaining,
    DateTime? endDate,
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();

    if (remaining <= 0) return RenewalAlertLevel.expiring;
    if (endDate != null) {
      final daysUntil = endDate.difference(reference).inDays;
      if (daysUntil <= _expiringWindowDays) {
        return RenewalAlertLevel.expiring;
      }
    }
    if (remaining <= _fiveLeftThreshold) return RenewalAlertLevel.fiveLeft;
    if (used * 2 >= total) return RenewalAlertLevel.half;
    return RenewalAlertLevel.none;
  }

  /// 두 날짜 중 빠른 날 반환 (둘 다 있을 때). b가 null이면 a 반환.
  static DateTime _earliest(DateTime a, DateTime? b) {
    if (b == null) return a;
    return a.isBefore(b) ? a : b;
  }
}
