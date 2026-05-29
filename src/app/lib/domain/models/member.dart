/// 회원 도메인 모델.
///
/// **v0.2 (마이그레이션 0013) 이후:**
///   - [id] 가 PK — 회원 식별의 기준
///   - [userId] 는 nullable — 회원이 앱 가입 전엔 NULL
///   - 트레이너가 회원 정보만 먼저 등록 → 회원 가입 후 매핑 흐름
///
/// 도메인 모델이므로 Supabase/Flutter 의존 0. JSON 변환은
/// `features/trainer/member/member_repository.dart` 가 담당한다.
///
/// 참고: docs/data_model.md §2.2 member_profiles.
library;

class Member {
  /// 회원 ID (member_profiles.id). 항상 존재.
  final String id;

  /// 매핑된 Supabase Auth 사용자 ID. NULL이면 아직 앱 가입 안 한 회원.
  final String? userId;

  /// 소속 센터 ID. NULL 가능 (개인 트레이너 회원 등).
  final String? centerId;

  /// 회원 이름. UI 표시의 기본키.
  final String name;

  final String? phone;
  final DateTime? birthDate;

  /// 운동 목적 (예: "체중감량", "근육량 증가").
  final String? goal;

  /// 운동 경험.
  final String? experience;

  /// 부상 이력.
  final String? injuryHistory;

  /// 체형 특징.
  final String? bodyFeatures;

  /// 생활 패턴 (식습관, 수면 등).
  final String? lifestyle;

  /// 운동 가능 시간대 (JSON).
  /// 예: [{"day":"mon","from":"19:00","to":"21:00"}, ...]
  final List<Map<String, dynamic>>? availableTimes;

  /// 초대 코드 — 회원이 앱 가입 후 본인 계정에 이 프로필을 연결할 때 입력.
  /// 트레이너가 회원에게 전달. 연결 완료(userId != null) 후엔 표시 불필요.
  final String? inviteCode;

  final DateTime createdAt;
  final DateTime? deletedAt;

  const Member({
    required this.id,
    required this.name,
    required this.createdAt,
    this.userId,
    this.centerId,
    this.phone,
    this.birthDate,
    this.goal,
    this.experience,
    this.injuryHistory,
    this.bodyFeatures,
    this.lifestyle,
    this.availableTimes,
    this.inviteCode,
    this.deletedAt,
  });

  /// 회원이 앱 가입 후 매핑된 상태인지.
  /// UI에서 "앱 미가입" 배지를 보일지 결정.
  bool get isLinkedToAuth => userId != null;

  /// 활성 회원인지 (soft delete 안 됨).
  bool get isActive => deletedAt == null;

  Member copyWith({
    String? id,
    String? userId,
    String? centerId,
    String? name,
    String? phone,
    DateTime? birthDate,
    String? goal,
    String? experience,
    String? injuryHistory,
    String? bodyFeatures,
    String? lifestyle,
    List<Map<String, dynamic>>? availableTimes,
    String? inviteCode,
    DateTime? createdAt,
    DateTime? deletedAt,
  }) {
    return Member(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      centerId: centerId ?? this.centerId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      birthDate: birthDate ?? this.birthDate,
      goal: goal ?? this.goal,
      experience: experience ?? this.experience,
      injuryHistory: injuryHistory ?? this.injuryHistory,
      bodyFeatures: bodyFeatures ?? this.bodyFeatures,
      lifestyle: lifestyle ?? this.lifestyle,
      availableTimes: availableTimes ?? this.availableTimes,
      inviteCode: inviteCode ?? this.inviteCode,
      createdAt: createdAt ?? this.createdAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Member && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'Member(id: $id, name: $name, linked: $isLinkedToAuth, deleted: $deletedAt)';
}
