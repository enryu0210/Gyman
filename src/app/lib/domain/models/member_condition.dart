/// 회원 체형 제약/특이사항 1건. `member_conditions` 테이블의 1행과 1:1 대응.
/// (동작 습관·체형 제약 코칭 L1 — docs/design_movement_coaching.md §3.1)
///
/// **이 모델이 존재하는 이유:**
///   "측만증이라 편측 부하는 대칭 종목으로", "골반 전방경사라 오버헤드에서 허리 주의"
///   같은 판단은 지금 트레이너 머릿속에만 있다. 회원이 혼자 운동하는 순간 사라진다.
///   이 모델은 그 판단을 구조화해, 회원이 해당 동작을 만나는 시점에 다시 꺼내쓰게 한다.
///
/// **⚠ 앱은 상태를 판정하지 않는다 (설계 §5 의료·법적 안전선):**
///   측만증 판정은 X-ray 판독의 영역이고, 트레이너도 의료인이 아니라 진단 권한이 없다.
///   그래서 [source] 로 "의료기관 진단"과 "트레이너 관찰"을 반드시 구분하고,
///   경중(severity)은 아예 모델에 두지 않는다 — "중등도 측만증"은 의료 판단이기 때문.
///   앱의 역할은 *등록된 판단을 나르는 것*이지 판단하는 것이 아니다.
///
/// **가시성:** [memberNote]는 회원에게 보이지만 [trainerNote]는 트레이너 전용이다.
///   PG RLS 는 행 단위라 컬럼을 못 가리므로, 회원 측 조회는 SELECT 목록에서
///   trainer_note 를 제외하는 컬럼 단위 방어로 막는다(`next_memo` 와 같은 기존 패턴).
library;

/// 제약 정보의 출처 — 진단인가 관찰인가.
///
/// 이 구분이 흐려지면 앱이 "진단"을 하는 것처럼 읽혀 법적 문제가 된다.
/// DB CHECK 제약(0036)으로도 강제되며, UI 표기도 서로 다르게 한다.
enum ConditionSource {
  /// 의료기관 진단 이력 — 회원이 제출한 내용을 트레이너가 옮겨 적은 것.
  medical('medical', '의료기관 진단', '회원이 제출한 진단 이력'),

  /// 트레이너 관찰 소견 — **진단이 아니다.**
  trainerObservation(
      'trainer_observation', '트레이너 관찰', '수업 중 관찰한 소견 (진단 아님)');

  const ConditionSource(this.code, this.label, this.description);

  /// DB 에 저장되는 값.
  final String code;

  /// UI 표시명.
  final String label;

  /// UI 보조 설명 — 진단/관찰 혼동을 막는 문구.
  final String description;

  /// DB 문자열 → enum. 모르는 값은 더 보수적인 쪽(관찰)으로 흡수한다.
  ///
  /// 왜 관찰이 기본인가: 알 수 없는 값을 "의료기관 진단"으로 표시하면
  /// 근거 없는 권위를 부여하게 된다. 모호할 땐 약한 주장 쪽이 안전하다.
  static ConditionSource fromCode(String? raw) {
    return ConditionSource.values.firstWhere(
      (s) => s.code == raw,
      orElse: () => ConditionSource.trainerObservation,
    );
  }
}

/// 제약 코드 카탈로그 1항목 — 코드와 표시명 매핑.
class ConditionCodeInfo {
  /// DB 에 저장되는 코드.
  final String code;

  /// UI 표시명.
  final String label;

  /// 트레이너가 고를 때 참고할 한 줄 설명.
  final String hint;

  const ConditionCodeInfo({
    required this.code,
    required this.label,
    required this.hint,
  });
}

/// 제약 코드 카탈로그.
///
/// **⚠ 잠정 목록이다 (설계 §8.1).** 실제 목록은 트레이너와 함께 "실제로 쓰는 것만"
/// 추려서 확정해야 한다. DB 는 code 를 text 로 들고 있어 항목 추가·삭제에
/// 마이그레이션이 필요 없다 — 이 리스트만 고치면 된다.
class ConditionCatalog {
  const ConditionCatalog._();

  /// 직접 입력용 코드. 이 코드일 때만 `label` 자유 입력을 쓴다.
  static const customCode = 'custom';

  static const items = <ConditionCodeInfo>[
    ConditionCodeInfo(
      code: 'scoliosis',
      label: '척추측만',
      hint: '좌우 비대칭 부하 주의 — 진단은 의료기관',
    ),
    ConditionCodeInfo(
      code: 'anterior_pelvic_tilt',
      label: '골반 전방경사',
      hint: '허리 과신전 주의 (오버헤드·힌지 동작)',
    ),
    ConditionCodeInfo(
      code: 'posterior_pelvic_tilt',
      label: '골반 후방경사',
      hint: '스쿼트 하단 말림(butt wink) 주의',
    ),
    ConditionCodeInfo(
      code: 'rounded_shoulder',
      label: '라운드 숄더',
      hint: '수평 밀기 편중 주의, 당기기 보강',
    ),
    ConditionCodeInfo(
      code: 'forward_head',
      label: '거북목',
      hint: '경추 중립 큐 필요',
    ),
    ConditionCodeInfo(
      code: 'knee_valgus',
      label: '무릎 모임',
      hint: '스쿼트·런지에서 무릎이 안쪽으로 말림',
    ),
    ConditionCodeInfo(
      code: 'flat_foot',
      label: '평발',
      hint: '발 아치·체중 분산 큐 필요',
    ),
    ConditionCodeInfo(
      code: 'shoulder_impingement',
      label: '어깨 충돌증후군',
      hint: '수직 밀기 각도 조정 필요',
    ),
    ConditionCodeInfo(
      code: customCode,
      label: '직접 입력',
      hint: '목록에 없는 항목을 직접 적습니다',
    ),
  ];

  /// 코드로 카탈로그 항목 찾기. 없으면 null(모르는 코드 — 표시는 원문으로).
  static ConditionCodeInfo? find(String code) {
    for (final item in items) {
      if (item.code == code) return item;
    }
    return null;
  }

  /// 코드 → 표시명. 카탈로그에 없으면 코드 원문을 그대로 돌려준다.
  ///
  /// 카탈로그에서 항목을 지워도 **이미 저장된 행이 빈 칸으로 깨지지 않게** 하는
  /// 방어다. 목록이 잠정이라(§8.1) 실제로 바뀔 예정이므로 필요하다.
  static String labelOf(String code) => find(code)?.label ?? code;
}

/// 회원 체형 제약 1건.
class MemberCondition {
  /// 제약 PK.
  final String id;

  /// 대상 회원 (member_profiles.id).
  final String memberId;

  /// 제약 코드 (카탈로그 코드 또는 'custom').
  final String code;

  /// code=='custom' 일 때의 자유 입력 표시명. 그 외엔 보통 null.
  final String? label;

  /// 출처 — 진단/관찰 구분.
  final ConditionSource source;

  /// 회원에게도 보이는 설명.
  final String? memberNote;

  /// 트레이너 전용 상세. 회원 측 조회에서는 select 하지 않는다 → 항상 null.
  final String? trainerNote;

  /// 유효 여부. 해제하면 false 로 내려 이력을 보존한다(삭제하지 않음).
  final bool active;

  /// 등록한 트레이너 user_id. 계정 삭제 시 null 이 될 수 있다.
  final String? recordedBy;

  final DateTime createdAt;
  final DateTime updatedAt;

  const MemberCondition({
    required this.id,
    required this.memberId,
    required this.code,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    this.label,
    this.memberNote,
    this.trainerNote,
    this.active = true,
    this.recordedBy,
  });

  /// 화면에 쓸 이름 — custom 이면 자유 입력 label, 아니면 카탈로그 표시명.
  ///
  /// custom 인데 label 이 비어 있으면(방어) '기타'로 폴백한다.
  String get displayName {
    if (code == ConditionCatalog.customCode) {
      final t = label?.trim() ?? '';
      return t.isEmpty ? '기타' : t;
    }
    return ConditionCatalog.labelOf(code);
  }

  /// 의료기관 진단 이력인지 — UI 배지 분기용.
  bool get isMedical => source == ConditionSource.medical;

  /// member_conditions 행 → 도메인 객체.
  ///
  /// trainer_note 는 회원 측 조회에서 아예 select 되지 않으므로 키 자체가
  /// 없을 수 있다 — `as String?` 로 흡수(없으면 null).
  factory MemberCondition.fromRow(Map<String, dynamic> row) {
    return MemberCondition(
      id: row['id'] as String,
      memberId: row['member_id'] as String,
      code: row['code'] as String,
      label: row['label'] as String?,
      source: ConditionSource.fromCode(row['source'] as String?),
      memberNote: row['member_note'] as String?,
      trainerNote: row['trainer_note'] as String?,
      // 과거 행/부분 select 대비 기본 true.
      active: row['active'] as bool? ?? true,
      recordedBy: row['recorded_by'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  /// INSERT payload. id/created_at/updated_at 은 DB 기본값,
  /// recorded_by 는 호출(컨트롤러)이 현재 트레이너 user_id 로 주입한다.
  ///
  /// **빈 문자열을 null 로 정규화**하는 이유: 빈 메모가 ''로 저장되면 "메모 있음"으로
  /// 오판해 UI 에 빈 줄이 생긴다. 저장 시점에 한 번만 정리한다.
  /// label 은 custom 이 아닐 때 의미가 없으므로 버린다(중복 표시명 방지).
  Map<String, dynamic> toInsertPayload() => {
        'member_id': memberId,
        'code': code,
        'label': code == ConditionCatalog.customCode ? _blankToNull(label) : null,
        'source': source.code,
        'member_note': _blankToNull(memberNote),
        'trainer_note': _blankToNull(trainerNote),
        'active': active,
      };

  /// 공백만 있는 문자열은 null 로.
  static String? _blankToNull(String? v) {
    final t = v?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

  @override
  String toString() =>
      'MemberCondition($displayName, ${source.code}, active:$active)';
}
