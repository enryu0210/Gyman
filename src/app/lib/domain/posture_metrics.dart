/// 자세 키포인트 → 참고 수치 계산 (체형 분석 A단계).
/// docs/design_body_analysis.md §1.3 · §2.3
///
/// **⚠ 이건 진단 도구가 아니다.** 2D 단일 사진 키포인트는 카메라 거리·각도·옷·자세
///   흔들림에 민감하다. 그래서 여기서 뽑는 건 "트레이너가 눈으로 확인할 출발점"이지
///   결론이 아니다. 회원 노출은 **트레이너 코멘트가 달린 뒤에만** 열린다
///   (RLS `assess_member_read_after_review` — 이 계산의 한계를 덮는 안전장치).
///
/// **왜 좌우 비교만 하나:** 절대 각도(거북목 전방이동량 등)는 카메라 위치에 따라
///   통째로 흔들린다. 반면 **좌우 차이**는 그 전역 오차가 서로 상쇄돼 2D 에서 가장
///   신뢰도가 높다. 베타 범위를 어깨/골반 높이차로 고정한 이유(§0.2).
///
/// **ML Kit 비의존:** 입력은 [PoseSnapshot] 이라는 순수 Dart 구조다. ML Kit 은 아직
///   도입 전이고(B단계), 도입 후에도 어댑터가 이 구조로 변환해 넘긴다. 덕분에 계산은
///   지금 단위 테스트로 전부 고정할 수 있다(develop_plan §5.1).
library;

import 'dart:math' as math;

/// 분석에 쓰는 랜드마크.
///
/// **좌/우는 "피사체 기준"이다** — ML Kit 규약과 같다. 정면 사진에서 피사체의
/// 왼쪽 어깨는 *이미지상 오른쪽*에 나타난다. 이 혼동이 좌우 판정을 뒤집는 흔한
/// 버그 원인이라, 어댑터가 ML Kit 라벨을 그대로 옮기게 두고 여기서 뒤집지 않는다.
enum PoseLandmarkType {
  leftShoulder,
  rightShoulder,
  leftHip,
  rightHip,
}

/// 키포인트 1개 — 정규화 좌표(0~1) + 신뢰도.
///
/// 좌표계는 **이미지 좌표**: x 는 오른쪽으로, **y 는 아래로** 증가한다.
/// 따라서 y 가 작을수록 화면에서 위(=높이 있음)다.
class PoseKeypoint {
  /// 가로 위치 0~1 (이미지 너비 기준 정규화).
  final double x;

  /// 세로 위치 0~1 (이미지 높이 기준 정규화). **아래로 갈수록 큼.**
  final double y;

  /// 검출 신뢰도 0~1. 낮으면 그 지표는 계산하지 않는다.
  final double likelihood;

  const PoseKeypoint({
    required this.x,
    required this.y,
    this.likelihood = 1.0,
  });
}

/// 사진 1장에서 뽑은 키포인트 묶음.
///
/// **이미지 크기를 함께 받는 이유:** 좌표가 정규화(0~1)라 가로/세로가 서로 다른
/// 스케일이다. 그대로 각도를 재면 세로로 긴 사진에서 기울기가 과장된다.
/// 저장은 해상도 독립적으로(정규화), 계산은 픽셀 공간에서 — 그래서 둘 다 받는다.
class PoseSnapshot {
  final Map<PoseLandmarkType, PoseKeypoint> points;

  /// 원본 이미지 픽셀 크기.
  final int imageWidth;
  final int imageHeight;

  const PoseSnapshot({
    required this.points,
    required this.imageWidth,
    required this.imageHeight,
  });

  PoseKeypoint? operator [](PoseLandmarkType type) => points[type];
}

/// 신체 좌우.
enum BodySide {
  left('left', '왼쪽'),
  right('right', '오른쪽');

  const BodySide(this.code, this.label);
  final String code;
  final String label;
}

/// 지표 판정.
///
/// **경고 등급이 아니라 "확인이 필요한가"다.** 진단 표현을 쓰지 않기 위해
/// good/bad 대신 ok/watch 로 둔다(설계 §0.2 — "라운드숄더입니다" ✗).
enum PostureFlag {
  /// 기준 이내.
  ok('ok', '기준 이내'),

  /// 기준 초과 — 트레이너 확인 권장.
  watch('watch', '확인 권장'),

  /// 계산 불가(키포인트 신뢰도 부족·촬영 각도 문제). **0 으로 채우지 않는다.**
  insufficient('insufficient', '측정 불가');

  const PostureFlag(this.code, this.label);
  final String code;
  final String label;
}

/// 측정 항목.
enum PostureMetricKey {
  /// 좌우 어깨 높이차(수평 대비 기울기, 도).
  shoulderTilt('shoulder_tilt_deg', '어깨 높이차', PoseLandmarkType.leftShoulder,
      PoseLandmarkType.rightShoulder),

  /// 좌우 골반 높이차(수평 대비 기울기, 도).
  pelvisTilt('pelvis_tilt_deg', '골반 높이차', PoseLandmarkType.leftHip,
      PoseLandmarkType.rightHip);

  const PostureMetricKey(this.code, this.label, this.leftPoint, this.rightPoint);

  /// `ai_result.metrics[].key` 에 저장되는 값.
  final String code;

  /// UI 표시명. **부위 이름만** — 상태명(라운드숄더 등)을 쓰지 않는다.
  final String label;

  final PoseLandmarkType leftPoint;
  final PoseLandmarkType rightPoint;
}

/// 계산 결과 1건.
class PostureMetric {
  final PostureMetricKey key;

  /// 기울기 크기(도, 0 이상). 계산 불가면 null — **0 과 구분해야 한다**
  /// (0 은 "완벽히 수평", null 은 "못 쟀다").
  final double? valueDeg;

  /// 더 높은 쪽(피사체 기준). 완전 수평이거나 계산 불가면 null.
  final BodySide? higherSide;

  final PostureFlag flag;

  /// 계산 불가 사유(사용자 안내용). 정상 계산 시 null.
  final String? note;

  const PostureMetric({
    required this.key,
    required this.flag,
    this.valueDeg,
    this.higherSide,
    this.note,
  });

  /// 사람이 읽는 한 줄. **단정하지 않는다** — 사실 + 기준만 말한다.
  String describe() {
    if (valueDeg == null) return '${key.label}: ${flag.label}${note == null ? '' : ' ($note)'}';
    final v = valueDeg!.toStringAsFixed(1);
    if (higherSide == null) return '${key.label} $v도 (좌우 차이 거의 없음)';
    return '${key.label} $v도 — ${higherSide!.label}이 높음';
  }

  /// `ai_result.metrics[]` 항목으로 직렬화(설계 §2.3 구조).
  Map<String, dynamic> toJson() => {
        'key': key.code,
        'value': valueDeg,
        'higher_side': higherSide?.code,
        'ref': '±${PostureMetricsCalculator.watchThresholdDeg.toStringAsFixed(0)}',
        'flag': flag.code,
        if (note != null) 'note': note,
      };

  @override
  String toString() => 'PostureMetric(${key.code}, $valueDeg, ${flag.code})';
}

/// 키포인트 → 참고 수치.
class PostureMetricsCalculator {
  const PostureMetricsCalculator._();

  /// 이 값을 넘으면 `watch`(트레이너 확인 권장).
  ///
  /// ±2도는 2D 스크리닝에서 흔히 쓰는 보수적 기준이다. **의학적 컷오프가 아니라
  /// "눈으로 한 번 볼 만한가"의 문턱**이며, 실사용 후 트레이너와 조정할 값이다.
  static const watchThresholdDeg = 2.0;

  /// 키포인트 신뢰도 하한. 미만이면 그 지표는 계산하지 않는다.
  static const minLikelihood = 0.5;

  /// 두 점의 가로 간격이 이미지 너비의 이 비율 미만이면 계산하지 않는다.
  ///
  /// **왜 필요한가:** 피사체가 옆으로 돌면 좌우 어깨가 겹쳐 보이고, 그때 각도는
  /// 아주 작은 픽셀 차이에 요동친다(45도가 나오기도 한다). 정면 촬영이 아니면
  /// 아예 안 재는 편이 안전하다 — 틀린 수치보다 없는 수치.
  static const minSeparationRatio = 0.05;

  /// 스냅샷에서 베타 범위 지표 전부 계산.
  static List<PostureMetric> compute(PoseSnapshot snapshot) {
    return List.unmodifiable([
      for (final key in PostureMetricKey.values) computeOne(snapshot, key),
    ]);
  }

  /// 지표 1개 계산.
  static PostureMetric computeOne(PoseSnapshot snapshot, PostureMetricKey key) {
    final left = snapshot[key.leftPoint];
    final right = snapshot[key.rightPoint];

    if (left == null || right == null) {
      return PostureMetric(
        key: key,
        flag: PostureFlag.insufficient,
        note: '키포인트를 찾지 못했습니다',
      );
    }
    if (left.likelihood < minLikelihood || right.likelihood < minLikelihood) {
      return PostureMetric(
        key: key,
        flag: PostureFlag.insufficient,
        note: '검출 신뢰도가 낮습니다',
      );
    }
    if (snapshot.imageWidth <= 0 || snapshot.imageHeight <= 0) {
      return PostureMetric(
        key: key,
        flag: PostureFlag.insufficient,
        note: '이미지 크기를 알 수 없습니다',
      );
    }

    // 정규화 좌표 → 픽셀 좌표. 가로/세로 스케일이 달라 이 변환 없이는 각도가 왜곡된다.
    final leftX = left.x * snapshot.imageWidth;
    final leftY = left.y * snapshot.imageHeight;
    final rightX = right.x * snapshot.imageWidth;
    final rightY = right.y * snapshot.imageHeight;

    final dx = (rightX - leftX).abs();
    final dy = (rightY - leftY).abs();

    // 정면이 아니면(좌우가 겹치면) 각도가 요동친다 → 측정 포기.
    if (dx < snapshot.imageWidth * minSeparationRatio) {
      return PostureMetric(
        key: key,
        flag: PostureFlag.insufficient,
        note: '정면으로 다시 촬영해 주세요',
      );
    }

    // 수평선과 이룬 각(항상 0~90도).
    //
    // 방향 벡터가 아니라 절대값으로 재는 이유: 정면 사진에서 피사체의 왼쪽 어깨는
    // 이미지상 오른쪽에 오므로 dx 의 부호가 뒤집힌다. 부호를 그대로 쓰면 atan2 가
    // 180도 근처를 돌려준다. 크기와 "어느 쪽이 높은가"를 나눠서 구하는 게 안전하다.
    final degrees = math.atan2(dy, dx) * 180 / math.pi;

    // y 는 아래로 증가 → 값이 작은 쪽이 화면에서 위(=높음).
    final BodySide? higher;
    if (leftY == rightY) {
      higher = null;
    } else {
      higher = leftY < rightY ? BodySide.left : BodySide.right;
    }

    return PostureMetric(
      key: key,
      valueDeg: degrees,
      higherSide: higher,
      flag: degrees > watchThresholdDeg ? PostureFlag.watch : PostureFlag.ok,
    );
  }
}
