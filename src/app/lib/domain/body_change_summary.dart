/// 최근 인바디 변화 요약 — **순수 도메인 로직** (Flutter 의존 0).
///
/// 회원 홈 정보 우선순위 ④ "최근 변화 요약"(계획서 §3.3)의 계산부.
/// 홈은 그래프를 그리지 않고 "가장 최근 측정값 + 직전 대비 증감" 한 줄만 보여준다
/// (전체 추이는 `/member/records/progress`).
///
/// **왜 지표마다 따로 직전 값을 찾는가:**
///   인바디는 상황에 따라 일부 항목만 측정된다(`BodyMeasurement` 세 지표가 모두
///   nullable 인 이유). 측정 회차 단위로 "직전 회차"를 잡으면, 체중만 잰 회차가 끼는
///   순간 체지방 비교가 통째로 사라진다. 지표별로 값이 있는 마지막 두 시점을 각각
///   찾아야 회원이 실제로 잰 것만큼 비교가 보인다.
///
/// **증감을 좋다/나쁘다로 판정하지 않는다:**
///   체중 -1kg 이 감량 회원에겐 성과지만 증량 회원에겐 반대다. 목표는 자유 텍스트
///   (`member_profiles.goal`)라 기계적으로 읽을 수 없고, 잘못 판정하면 앱이 회원의
///   몸에 대해 틀린 평가를 내리는 셈이 된다. 도메인은 **부호와 크기만** 돌려주고,
///   화면도 증감을 성패 색(빨강/초록)으로 칠하지 않는다(리포 의료 안전선).
library;

import 'models/body_measurement.dart';

/// 지표 하나의 "최근값 + 직전 대비 변화".
class MetricChange {
  const MetricChange({
    required this.latest,
    required this.latestAt,
    required this.previous,
    required this.previousAt,
  });

  /// 가장 최근에 측정된 값.
  final double latest;

  /// 그 값을 측정한 날.
  final DateTime latestAt;

  /// 이 지표를 그 전에 측정한 값. 비교할 과거가 없으면 null.
  final double? previous;

  /// 직전 측정일. [previous] 와 함께 null 이거나 함께 값이 있다.
  final DateTime? previousAt;

  /// 직전 대비 변화량(부호 유지). 비교 대상이 없으면 null.
  double? get delta => previous == null ? null : latest - previous!;

  /// 비교할 과거 측정이 있는가(첫 측정이면 false — "첫 기록"으로 표시).
  bool get hasComparison => previous != null;
}

/// 세 지표의 변화 묶음.
class BodyChangeSummary {
  const BodyChangeSummary({
    required this.weightKg,
    required this.bodyFatPct,
    required this.skeletalMuscleKg,
  });

  /// 체중(kg). 한 번도 측정되지 않았으면 null.
  final MetricChange? weightKg;

  /// 체지방률(%).
  final MetricChange? bodyFatPct;

  /// 골격근량(kg).
  final MetricChange? skeletalMuscleKg;

  static const empty = BodyChangeSummary(
    weightKg: null,
    bodyFatPct: null,
    skeletalMuscleKg: null,
  );

  /// 값이 있는 지표들(화면이 순서대로 칩을 그린다).
  // null 인 지표는 null-aware 엔트리(`?x`)로 조용히 빠진다(린트 use_null_aware_elements).
  List<MetricChange> get metrics => [
        ?weightKg,
        ?bodyFatPct,
        ?skeletalMuscleKg,
      ];

  /// 보여줄 게 하나도 없는가 — true 면 홈에서 카드 자체를 그리지 않는다
  /// (빈 카드를 세워 두면 아직 측정 안 한 회원의 홈만 길어진다).
  bool get isEmpty => metrics.isEmpty;

  /// 세 지표 중 가장 최근 측정일 — 카드 부제("8월 10일 측정")용.
  DateTime? get latestMeasuredAt {
    DateTime? latest;
    for (final m in metrics) {
      if (latest == null || m.latestAt.isAfter(latest)) latest = m.latestAt;
    }
    return latest;
  }
}

/// 인바디 측정 목록 → 지표별 최근/직전 요약.
///
/// [measurements] 정렬 상태를 신뢰하지 않고 내부에서 측정일 오름차순으로 정렬한다
/// (같은 날 두 번 측정된 경우는 행 생성 시각으로 순서를 가른다).
BodyChangeSummary buildBodyChangeSummary(
  Iterable<BodyMeasurement> measurements,
) {
  final sorted = measurements.toList()
    ..sort((a, b) {
      final byDate = a.measuredAt.compareTo(b.measuredAt);
      if (byDate != 0) return byDate;
      return a.createdAt.compareTo(b.createdAt);
    });
  if (sorted.isEmpty) return BodyChangeSummary.empty;

  return BodyChangeSummary(
    weightKg: _changeOf(sorted, (m) => m.weightKg),
    bodyFatPct: _changeOf(sorted, (m) => m.bodyFatPct),
    skeletalMuscleKg: _changeOf(sorted, (m) => m.skeletalMuscleKg),
  );
}

/// 오름차순 목록에서 해당 지표의 값이 있는 **마지막 두 시점**을 찾는다.
/// 값이 하나뿐이면 previous 없이(첫 기록), 하나도 없으면 null.
MetricChange? _changeOf(
  List<BodyMeasurement> ascending,
  double? Function(BodyMeasurement) pick,
) {
  double? latest;
  DateTime? latestAt;
  double? previous;
  DateTime? previousAt;

  for (var i = ascending.length - 1; i >= 0; i--) {
    final v = pick(ascending[i]);
    if (v == null) continue;
    if (latest == null) {
      latest = v;
      latestAt = ascending[i].measuredAt;
      continue;
    }
    previous = v;
    previousAt = ascending[i].measuredAt;
    break;
  }

  if (latest == null) return null;
  return MetricChange(
    latest: latest,
    latestAt: latestAt!,
    previous: previous,
    previousAt: previousAt,
  );
}
