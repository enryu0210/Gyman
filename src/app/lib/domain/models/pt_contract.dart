/// PT 계약 — 잔여 횟수의 원천이 되는 도메인 객체.
///
/// **불변 객체(immutable)로 설계한 이유:**
///   - 계산기(`RemainingSessionsCalculator`, `RenewalCalculator`)가 같은 입력에
///     항상 같은 출력을 내야 단위 테스트와 분쟁 시 재계산이 가능하다.
///   - 상태 변경은 새 인스턴스 생성으로 (copyWith) — 디버깅 시 "언제 바뀌었는지"
///     추적이 쉬워진다.
///
/// **`usedSessions` / `remainingSessions` 캐시 컬럼이 없는 이유:**
///   sessions 리스트가 진실의 원천. 캐시 두면 동기화 버그 → 매출 분쟁.
///   data_model.md §2.2 `pt_contracts` 주석과 동일한 원칙.
library;

class PtContract {
  /// 계약 ID (Supabase에서 uuid).
  final String id;

  /// 회원 ID (member_profiles.user_id).
  final String memberId;

  /// 트레이너 ID (trainer_profiles.user_id).
  final String trainerId;

  /// 센터 ID. NULL 가능 (개인 트레이너 등).
  final String? centerId;

  /// 총 등록 횟수. CHECK 제약상 > 0.
  final int totalSessions;

  /// 계약 시작일.
  final DateTime startDate;

  /// 계약 종료일. NULL 가능 (만료일 미정 — 횟수 다 쓸 때까지).
  final DateTime? endDate;

  /// 가격 (원 단위). NULL 가능 (현장 결제 등).
  final int? price;

  /// 자유 메모 (특이사항, 결제 방식 등).
  final String? memo;

  /// 계약 생성 시각.
  final DateTime createdAt;

  /// soft delete 시각. NULL이면 활성 계약.
  final DateTime? deletedAt;

  const PtContract({
    required this.id,
    required this.memberId,
    required this.trainerId,
    required this.totalSessions,
    required this.startDate,
    required this.createdAt,
    this.centerId,
    this.endDate,
    this.price,
    this.memo,
    this.deletedAt,
  });

  /// 활성 계약 여부 (soft delete 안 됨).
  bool get isActive => deletedAt == null;

  /// 일부 필드만 바꾼 새 인스턴스 생성.
  /// 불변 객체에서 상태 변경을 표현하는 표준 패턴.
  PtContract copyWith({
    String? id,
    String? memberId,
    String? trainerId,
    String? centerId,
    int? totalSessions,
    DateTime? startDate,
    DateTime? endDate,
    int? price,
    String? memo,
    DateTime? createdAt,
    DateTime? deletedAt,
  }) {
    return PtContract(
      id: id ?? this.id,
      memberId: memberId ?? this.memberId,
      trainerId: trainerId ?? this.trainerId,
      centerId: centerId ?? this.centerId,
      totalSessions: totalSessions ?? this.totalSessions,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      price: price ?? this.price,
      memo: memo ?? this.memo,
      createdAt: createdAt ?? this.createdAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PtContract &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          memberId == other.memberId &&
          trainerId == other.trainerId &&
          centerId == other.centerId &&
          totalSessions == other.totalSessions &&
          startDate == other.startDate &&
          endDate == other.endDate &&
          price == other.price &&
          memo == other.memo &&
          createdAt == other.createdAt &&
          deletedAt == other.deletedAt;

  @override
  int get hashCode => Object.hash(
        id,
        memberId,
        trainerId,
        centerId,
        totalSessions,
        startDate,
        endDate,
        price,
        memo,
        createdAt,
        deletedAt,
      );

  @override
  String toString() =>
      'PtContract(id: $id, member: $memberId, total: $totalSessions, '
      'start: $startDate, end: $endDate, deleted: $deletedAt)';
}
