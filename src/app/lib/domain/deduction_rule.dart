/// 차감 규정 — "취소"가 정상 취소(canceled)인지 당일/지각 취소(lateCancel)인지 판정.
///
/// **왜 도메인 로직으로 분리하나:**
///   센터마다 정책이 다르고(예: A센터는 24시간 전, B센터는 12시간 전), 분쟁 시
///   "왜 차감됐는지" 재계산이 필요하다. UI에 묻어있으면 변경/검증 모두 어려움.
///
/// **DB와의 관계:**
///   `sessions.status` 컬럼에 최종 분류된 enum 값이 저장된다.
///   본 모듈은 "트레이너가 취소 버튼을 눌렀을 때 어떤 enum 값으로 INSERT할지"
///   결정하는 역할만 한다 — 저장 후엔 [SessionStatus.deducts] 로 차감 여부만 본다.
///
/// 참고: docs/data_model.md §2.2 sessions 차감 규칙,
///       docs/develop_plan.md §5.1 deduction_rule_test.
library;

import 'models/enums.dart';

/// 센터별 차감 정책.
///
/// 추후 `centers.rules` JSONB에서 역직렬화될 값. 현재는 코드에 상수로 시작.
class DeductionPolicy {
  /// 수업 시작 몇 시간 전까지 취소해야 정상취소로 인정되는가.
  /// 이 시간 이내에 취소 = late_cancel (차감 대상).
  final int cancelDeadlineHoursBefore;

  const DeductionPolicy({
    required this.cancelDeadlineHoursBefore,
  });

  /// 기본 정책 — 수업 24시간 전까지 취소해야 무료.
  /// 대부분의 PT 센터 표준 규정.
  static const DeductionPolicy defaultPolicy = DeductionPolicy(
    cancelDeadlineHoursBefore: 24,
  );
}

/// 차감 규정 판정 유틸 (정적 메서드만 가짐).
///
/// 인스턴스화하지 않는 이유: 정책 자체는 [DeductionPolicy]로 주입받고,
/// 판정 함수는 순수함수(같은 입력 → 같은 출력)면 충분하다.
class DeductionRule {
  /// 취소 이벤트를 [SessionStatus]로 분류한다.
  ///
  /// 규칙:
  ///   - 취소 시각이 수업 시작 [policy.cancelDeadlineHoursBefore] 시간 이상 전 → [SessionStatus.canceled]
  ///   - 그 이후 (수업 직전·당일·수업 후 취소 모두 포함) → [SessionStatus.lateCancel]
  ///
  /// 예시 (policy = 24시간 기준):
  ///   - 수업 일시: 1월 10일 19:00
  ///   - 취소 일시: 1월 9일 18:00 → 25시간 전 → canceled (정상)
  ///   - 취소 일시: 1월 9일 19:00 → 정확히 24시간 전 → canceled (경계 포함)
  ///   - 취소 일시: 1월 9일 20:00 → 23시간 전 → lateCancel (차감)
  ///   - 취소 일시: 1월 10일 18:30 → 30분 전 → lateCancel
  ///
  /// **경계 처리:** 정확히 24시간 전은 회원에게 유리한 쪽(canceled)으로.
  /// "23시간 59분 59초 전"은 차감, "정확히 24시간 0초 전"은 무료.
  /// 분쟁 시 회원 신뢰 확보 우선.
  static SessionStatus classifyCancellation({
    required DateTime scheduledAt,
    required DateTime cancelAt,
    DeductionPolicy policy = DeductionPolicy.defaultPolicy,
  }) {
    final hoursUntilSession = scheduledAt.difference(cancelAt).inSeconds / 3600.0;

    if (hoursUntilSession >= policy.cancelDeadlineHoursBefore) {
      return SessionStatus.canceled;
    }
    return SessionStatus.lateCancel;
  }

  /// 어떤 상태가 차감 대상인가 판정.
  ///
  /// [SessionStatusRule.deducts] 와 동일하지만, 본 모듈에서 한 번에 차감 규칙을
  /// 보고 싶을 때 호출 지점 일관성을 위한 래퍼.
  static bool isDeducted(SessionStatus status) => status.deducts;
}
