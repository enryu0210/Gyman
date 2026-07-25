/// 체형 분석 1건. `body_assessments` 테이블의 1행과 1:1 대응.
/// docs/design_body_analysis.md §2
///
/// **핵심 안전 규칙:** AI/수치는 **트레이너 코멘트가 달린 뒤에만** 회원에게 보인다.
///   DB 는 RLS(`assess_member_read_after_review`)로 강제하고, 앱은 같은 규칙을
///   [isVisibleToMember] 로 들고 있어 화면이 실수로 앞질러 보여주지 않게 한다
///   (`NotificationStatus.isVisibleToMember` 와 같은 이중 방어 패턴).
///
/// **`body_measurements`(0023, 인바디 수치)와 다른 이유:** 인바디는 기기가 잰
///   객관적 수치라 검수 없이 회원에게 바로 간다. 여기는 사진 + 추정 수치라
///   해석이 필요하다 — 그래서 게이트가 붙는다.
library;

import '../posture_metrics.dart';

/// 촬영 뷰. object key 와 `ai_result.views` 키로 그대로 쓰인다(ASCII 고정).
enum BodyPhotoView {
  front('front', '정면'),
  side('side', '측면'),
  back('back', '후면');

  const BodyPhotoView(this.code, this.label);
  final String code;
  final String label;

  static BodyPhotoView? fromCode(String? raw) {
    for (final v in BodyPhotoView.values) {
      if (v.code == raw) return v;
    }
    return null;
  }
}

/// 체형 분석 1건.
class BodyAssessment {
  final String id;

  /// 대상 회원 (member_profiles.id).
  final String memberId;

  /// 뷰 → Storage object key. 사진을 안 남긴 뷰는 키가 없다.
  final Map<BodyPhotoView, String> photos;

  /// 온디바이스 분석 산출물(설계 §2.3 구조). 미분석이면 null.
  final Map<String, dynamic>? aiResult;

  /// 트레이너 코멘트. **비어 있으면 회원에게 안 보인다**(RLS 게이트).
  final String? trainerComment;

  final DateTime assessedAt;

  /// 촬영·등록한 트레이너 user_id (0039). 계정 삭제 시 null.
  final String? recordedBy;

  const BodyAssessment({
    required this.id,
    required this.memberId,
    required this.photos,
    required this.assessedAt,
    this.aiResult,
    this.trainerComment,
    this.recordedBy,
  });

  /// 회원에게 노출 가능한가 — **RLS 와 같은 조건**을 앱에서도 들고 있는다.
  ///
  /// 이 한 줄이 2D 키포인트 정확도 한계(설계 §1.3)를 덮는 안전장치다.
  /// 수치만으로는 절대 회원에게 가지 않는다.
  bool get isVisibleToMember {
    final c = trainerComment?.trim() ?? '';
    return c.isNotEmpty;
  }

  /// 검수 대기중(분석은 됐는데 코멘트가 없음) — 트레이너 큐 표시용.
  bool get needsReview => !isVisibleToMember;

  /// 저장된 참고 수치. `ai_result.metrics` 를 도메인 타입으로 되살린다.
  ///
  /// 모르는 key/flag 가 섞여 있으면(앱보다 데이터가 앞선 경우) 그 항목만 건너뛴다 —
  /// 정체불명 수치를 화면에 올리지 않는다.
  List<PostureMetric> get metrics {
    final raw = aiResult?['metrics'];
    if (raw is! List) return const [];

    final result = <PostureMetric>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final key = _metricKeyFromCode(item['key'] as String?);
      if (key == null) continue;

      result.add(PostureMetric(
        key: key,
        valueDeg: _toDouble(item['value']),
        higherSide: _sideFromCode(item['higher_side'] as String?),
        flag: _flagFromCode(item['flag'] as String?),
        note: item['note'] as String?,
      ));
    }
    return List.unmodifiable(result);
  }

  /// 분석에 쓰인 엔진 표기(감사용). 없으면 null.
  String? get engineLabel {
    final engine = aiResult?['engine'] as String?;
    if (engine == null) return null;
    final version = aiResult?['engine_version'] as String?;
    return version == null ? engine : '$engine $version';
  }

  /// Storage object key 규칙 — `{member_id}/{assessment_id}/{view}.jpg`.
  ///
  /// **첫 세그먼트가 member_id 인 게 권한 키**다(0039 Storage RLS). 한글·공백이
  /// 섞이면 정책의 uuid 캐스팅이 깨지므로 ASCII 만 들어가는 이 형식을 고정한다.
  static String photoPath({
    required String memberId,
    required String assessmentId,
    required BodyPhotoView view,
  }) =>
      '$memberId/$assessmentId/${view.code}.jpg';

  /// `ai_result` JSON 조립(설계 §2.3).
  ///
  /// **엔진·버전을 남기는 이유:** LLM 을 안 쓰므로 프롬프트 추적이 없다. 대신
  /// "어떤 엔진이 이 수치를 만들었나"를 남겨야 사후 재현·분쟁 대응이 된다
  /// (develop_plan §6 "AI 생성 콘텐츠 audit log" 취지 충족).
  static Map<String, dynamic> buildAiResult({
    required String engine,
    required String engineVersion,
    required DateTime capturedAt,
    required List<PostureMetric> metrics,
    Map<String, dynamic>? views,
  }) =>
      {
        'engine': engine,
        'engine_version': engineVersion,
        'captured_at': capturedAt.toUtc().toIso8601String(),
        // null-aware map entry — views 가 null 이면 키 자체를 넣지 않는다.
        'views': ?views,
        'metrics': [for (final m in metrics) m.toJson()],
      };

  factory BodyAssessment.fromRow(Map<String, dynamic> row) {
    return BodyAssessment(
      id: row['id'] as String,
      memberId: row['member_id'] as String,
      photos: _parsePhotos(row['photos']),
      aiResult: (row['ai_result'] as Map?)?.cast<String, dynamic>(),
      trainerComment: row['trainer_comment'] as String?,
      assessedAt: DateTime.parse(row['assessed_at'] as String),
      recordedBy: row['recorded_by'] as String?,
    );
  }

  /// INSERT payload. id/assessed_at 은 DB 기본값, recorded_by 는 호출 측 주입.
  /// `trainer_comment` 는 **보내지 않는다** — 등록 시점엔 항상 미검수 상태로 시작해야
  /// 한다(설계 §4.5). 코멘트는 검수 단계에서 별도 UPDATE.
  Map<String, dynamic> toInsertPayload() => {
        'member_id': memberId,
        'photos': {
          for (final entry in photos.entries) entry.key.code: entry.value,
        },
        'ai_result': aiResult,
      };

  /// `photos` jsonb → 뷰별 경로. 모르는 키·비문자열 값은 버린다.
  static Map<BodyPhotoView, String> _parsePhotos(dynamic raw) {
    if (raw is! Map) return const {};
    final result = <BodyPhotoView, String>{};
    raw.forEach((key, value) {
      final view = BodyPhotoView.fromCode(key as String?);
      if (view == null || value is! String || value.isEmpty) return;
      result[view] = value;
    });
    return Map.unmodifiable(result);
  }

  static PostureMetricKey? _metricKeyFromCode(String? code) {
    for (final k in PostureMetricKey.values) {
      if (k.code == code) return k;
    }
    return null;
  }

  static BodySide? _sideFromCode(String? code) {
    for (final s in BodySide.values) {
      if (s.code == code) return s;
    }
    return null;
  }

  /// 모르는 flag 는 `insufficient` 로 흡수 — 정체불명 수치를 "기준 이내(ok)"로
  /// 보여주면 없는 안심을 준다. 모호할 땐 "측정 불가" 쪽이 안전하다.
  static PostureFlag _flagFromCode(String? code) {
    for (final f in PostureFlag.values) {
      if (f.code == code) return f;
    }
    return PostureFlag.insufficient;
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  @override
  String toString() =>
      'BodyAssessment($id, photos:${photos.length}, visible:$isVisibleToMember)';
}
