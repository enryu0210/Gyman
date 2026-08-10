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

  /// AI 기능(메시지/메모 초안, 재등록 멘트) 사용에 대한 회원 동의 여부.
  ///
  /// **false 가 기본이고, 그래야 한다** — 이 값이 true 여야만 Edge Function 이
  /// 회원의 수업 기록·인바디를 (이름 마스킹 후) LLM 에 보낸다. 서버가
  /// `consent_required` 로 차단하므로 클라가 못 켜면 AI 기능 전체가 막힌다.
  ///
  /// 동의 주체는 회원이고 입력 주체는 트레이너 — "회원에게 동의를 받았다"를
  /// 트레이너가 기록하는 형태(영상 업로드 동의 게이트와 같은 MVP 방식).
  /// 참고: develop_plan.md §6, 설계 §9.6.
  ///
  /// ⚠ **이 값만 보고 전송 여부를 판단하지 말 것** — [aiConsentEffective] 를 볼 것.
  final bool aiConsent;

  /// 회원 본인이 AI 사용을 거부했는지 (마이그레이션 0040).
  ///
  /// [aiConsent] 와 별개의 컬럼인 이유: 회원과 트레이너 둘 다 회원 프로필을 수정할 수
  /// 있어서, 같은 필드를 쓰면 회원이 끈 것을 트레이너가 곧바로 다시 켤 수 있다.
  /// 컬럼을 나누고 DB 트리거로 "이 값은 회원만 변경 가능"을 강제한다.
  final bool aiConsentMemberOptout;

  /// 트레이너가 "회원 본인에게 개인정보 수집·이용 동의를 받았다"고 확인한 시각
  /// (마이그레이션 0041).
  ///
  /// **NULL 인 회원이 정상적으로 존재한다** — 0041 이전에 등록된 회원은 소급
  /// 확인이 불가능해서 비워 뒀다. 신규 등록은 DB 트리거가 NULL 을 거부하므로,
  /// 여기가 NULL 이면 "옛날에 등록된 회원"이라는 뜻이다.
  ///
  /// 앱 미가입 회원은 약관에 동의할 방법 자체가 없어(계정이 없으니
  /// `user_consents` 에 행을 만들 수 없다) 이 확인이 유일한 동의 근거다.
  /// 참고: docs/legal_docs_gap_check.md §C.
  final DateTime? offlineConsentConfirmedAt;

  final DateTime createdAt;
  final DateTime? deletedAt;

  const Member({
    required this.id,
    required this.name,
    required this.createdAt,
    this.offlineConsentConfirmedAt,
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
    this.aiConsent = false,
    this.aiConsentMemberOptout = false,
    this.deletedAt,
  });

  /// **AI 전송 허용 여부의 유일한 판정 기준.**
  ///
  /// DB 의 생성 컬럼 `ai_consent_effective` 와 **같은 식**이다(0040).
  /// 서버 Edge Function 도 그 컬럼만 보고 차단하므로, 화면 표시와 실제 차단이
  /// 어긋나지 않는다. 값을 따로 받아오지 않고 여기서 계산하는 이유는
  /// 조회 컬럼 목록에서 빠져 조용히 false 가 되는 사고를 없애기 위함이다.
  ///
  /// ⚠ 이 식을 고치면 `0040` 의 생성식도 같이 고칠 것. 둘이 어긋나면
  ///    "화면엔 허용인데 서버가 막는다"(또는 그 반대)가 된다.
  bool get aiConsentEffective => aiConsent && !aiConsentMemberOptout;

  /// 회원이 앱 가입 후 매핑된 상태인지.
  /// UI에서 "앱 미가입" 배지를 보일지 결정.
  bool get isLinkedToAuth => userId != null;

  /// 활성 회원인지 (soft delete 안 됨).
  bool get isActive => deletedAt == null;

  /// 개인정보 수집·이용 동의 확인 기록이 없는 회원인지.
  ///
  /// true 면 트레이너에게 소급 확인을 요청해야 한다 — 동의 근거 없이 개인정보를
  /// 보유 중인 상태이기 때문이다. 화면에서 경고를 띄우는 판단 기준.
  bool get needsConsentConfirmation => offlineConsentConfirmedAt == null;

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
    bool? aiConsent,
    bool? aiConsentMemberOptout,
    DateTime? offlineConsentConfirmedAt,
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
      aiConsent: aiConsent ?? this.aiConsent,
      aiConsentMemberOptout:
          aiConsentMemberOptout ?? this.aiConsentMemberOptout,
      offlineConsentConfirmedAt:
          offlineConsentConfirmedAt ?? this.offlineConsentConfirmedAt,
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
