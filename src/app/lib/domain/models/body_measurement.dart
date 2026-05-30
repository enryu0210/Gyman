/// 인바디(체성분) 수치 측정 1건. body_measurements 테이블의 1행과 1:1 대응.
///
/// **body_assessments(사진/AI 분석)와 다른 모델인 이유:**
///   인바디는 기기로 측정한 *객관적 수치*(체중/체지방률/골격근량)라 트레이너 검수
///   게이트 없이 회원에게 바로 노출된다. 사진 기반 체형 분석(Phase 4)과 책임이 다르므로
///   테이블·모델을 분리한다(0023 마이그레이션 주석 참조).
///
/// **세 지표가 모두 nullable 인 이유:**
///   인바디 기기/측정 상황에 따라 일부 항목만 잴 수 있다(예: 체중만). 빠진 값은
///   추이 그래프에서 그 시점만 건너뛴다 — 0으로 채우면 가짜 하락처럼 보이기 때문.
///
/// 불변 객체로 둔 이유는 [SessionRecord] / [PtContract] 와 동일 — 표시 일관성.
library;

class BodyMeasurement {
  /// 측정 기록 PK.
  final String id;

  /// 대상 회원 (member_profiles.id).
  final String memberId;

  /// 체중 (kg). 미측정이면 null.
  final double? weightKg;

  /// 체지방률 (%). 미측정이면 null.
  final double? bodyFatPct;

  /// 골격근량 (kg). 미측정이면 null.
  final double? skeletalMuscleKg;

  /// 측정일 (시각 없이 날짜 단위).
  final DateTime measuredAt;

  /// 기록한 트레이너 user_id. 계정 삭제 등으로 비어 있을 수 있어 nullable.
  final String? recordedBy;

  /// 행 생성 시각.
  final DateTime createdAt;

  const BodyMeasurement({
    required this.id,
    required this.memberId,
    required this.measuredAt,
    required this.createdAt,
    this.weightKg,
    this.bodyFatPct,
    this.skeletalMuscleKg,
  }) : recordedBy = null;

  /// recordedBy 까지 포함한 전체 생성자 — [fromRow] 전용.
  const BodyMeasurement._full({
    required this.id,
    required this.memberId,
    required this.measuredAt,
    required this.createdAt,
    required this.weightKg,
    required this.bodyFatPct,
    required this.skeletalMuscleKg,
    required this.recordedBy,
  });

  /// 측정 항목이 하나도 없는(전부 null) 빈 기록인지 — 입력 검증/표시용.
  bool get isEmpty =>
      weightKg == null && bodyFatPct == null && skeletalMuscleKg == null;

  /// body_measurements 행 → 도메인 객체.
  ///
  /// PG numeric 은 SDK 가 num(int/double) 또는 String 으로 줄 수 있어 [_toDouble] 로 흡수.
  /// measured_at 은 `YYYY-MM-DD` date 문자열, created_at 은 ISO8601 timestamptz.
  factory BodyMeasurement.fromRow(Map<String, dynamic> row) {
    return BodyMeasurement._full(
      id: row['id'] as String,
      memberId: row['member_id'] as String,
      weightKg: _toDouble(row['weight_kg']),
      bodyFatPct: _toDouble(row['body_fat_pct']),
      skeletalMuscleKg: _toDouble(row['skeletal_muscle_kg']),
      measuredAt: DateTime.parse(row['measured_at'] as String),
      recordedBy: row['recorded_by'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  /// INSERT payload. id/created_at 은 DB 기본값, recorded_by 는 호출 측에서 주입.
  /// measured_at 은 시각이 섞이지 않게 `YYYY-MM-DD` 문자열로 보낸다(CLAUDE.md date 지침).
  Map<String, dynamic> toInsertPayload() => {
        'member_id': memberId,
        'weight_kg': weightKg,
        'body_fat_pct': bodyFatPct,
        'skeletal_muscle_kg': skeletalMuscleKg,
        'measured_at': _dateOnly(measuredAt),
      };

  /// numeric/text/num 어느 형태로 와도 double 로. 빈 값/파싱 실패는 null.
  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  /// DateTime → `YYYY-MM-DD`.
  static String _dateOnly(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  @override
  String toString() => 'BodyMeasurement($measuredAt, '
      'w:$weightKg, fat:$bodyFatPct, muscle:$skeletalMuscleKg)';
}
