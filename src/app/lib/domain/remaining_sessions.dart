/// 잔여 횟수 / 사용 횟수 계산.
///
/// **본 모듈이 "진실의 원천":**
///   DB `pt_contracts`에 used_sessions 캐시를 두지 않은 이유와 동일 — 한 곳에서만
///   계산하면 동기화 버그가 원천 차단된다. DB의 `v_contract_status` view도
///   본 모듈과 같은 식을 사용한다 (sql 0011_triggers_views).
///
/// 참고: docs/data_model.md §2.2 (캐시 컬럼 미보유), §4.2 (DB view),
///       docs/develop_plan.md §5.1 remaining_sessions_test.
library;

import 'models/enums.dart';
import 'models/pt_contract.dart';
import 'models/session.dart';

/// 계약 1건의 횟수 집계 결과.
///
/// UI에서 "10회 중 4회 사용, 6회 남음 (노쇼 1, 당일취소 1)" 같은 표시에 사용.
class ContractStatus {
  final int total;
  final int used;
  final int remaining;

  /// 세부 분류 — UI/대시보드에서 사유별 카운트 표시.
  final int doneCount;
  final int noShowCount;
  final int lateCancelCount;
  final int canceledCount;
  final int scheduledCount;

  /// 회원이 신청만 하고 트레이너 미승인 상태(requested)인 건수.
  /// 잔여 횟수엔 영향 없음 — 대시보드/디버깅용. 기본 0 (구버전 생성 호환).
  final int requestedCount;

  const ContractStatus({
    required this.total,
    required this.used,
    required this.remaining,
    required this.doneCount,
    required this.noShowCount,
    required this.lateCancelCount,
    required this.canceledCount,
    required this.scheduledCount,
    this.requestedCount = 0,
  });

  /// 만료(잔여 0) 여부.
  bool get isExhausted => remaining <= 0;

  @override
  String toString() => 'ContractStatus(total: $total, used: $used, '
      'remaining: $remaining, done: $doneCount, noShow: $noShowCount, '
      'lateCancel: $lateCancelCount, canceled: $canceledCount, '
      'scheduled: $scheduledCount, requested: $requestedCount)';
}

class RemainingSessionsCalculator {
  /// 계약과 그 계약에 속한 세션 리스트로부터 [ContractStatus]를 계산한다.
  ///
  /// **방어 동작:**
  ///   - sessions에 다른 contract_id가 섞여 있으면 자동 필터링
  ///     (호출 측에서 미리 거르는 게 정상이지만, 도메인이 안전 우선)
  ///   - 잔여가 음수가 되면 0으로 클램프 (트레이너가 과기록한 데이터 오류 케이스)
  ///
  /// 예시:
  ///   - total 10, done 4, noShow 1, lateCancel 1 → used 6, remaining 4
  ///   - total 10, canceled 3 (정상취소만) → used 0, remaining 10
  ///   - total 10, done 12 (과기록) → used 12, remaining 0 (음수 차단)
  static ContractStatus calculate(
    PtContract contract,
    List<Session> sessions,
  ) {
    // 다른 계약의 세션이 섞여 들어와도 무시 — 잘못된 합산 방지.
    final mine = sessions.where((s) => s.contractId == contract.id);

    var done = 0;
    var noShow = 0;
    var lateCancel = 0;
    var canceled = 0;
    var scheduled = 0;
    var requested = 0;

    for (final s in mine) {
      switch (s.status) {
        case SessionStatus.done:
          done++;
          break;
        case SessionStatus.noShow:
          noShow++;
          break;
        case SessionStatus.lateCancel:
          lateCancel++;
          break;
        case SessionStatus.canceled:
          canceled++;
          break;
        case SessionStatus.scheduled:
          scheduled++;
          break;
        case SessionStatus.requested:
          requested++;
          break;
      }
    }

    final used = done + noShow + lateCancel;
    // 음수 방지 — 데이터 오류 시에도 화면이 깨지지 않게.
    final remaining = (contract.totalSessions - used).clamp(0, contract.totalSessions);

    return ContractStatus(
      total: contract.totalSessions,
      used: used,
      remaining: remaining,
      doneCount: done,
      noShowCount: noShow,
      lateCancelCount: lateCancel,
      canceledCount: canceled,
      scheduledCount: scheduled,
      requestedCount: requested,
    );
  }

  /// 잔여 횟수만 빠르게 — UI에서 숫자 하나만 필요한 경우.
  static int remaining(PtContract contract, List<Session> sessions) =>
      calculate(contract, sessions).remaining;
}
