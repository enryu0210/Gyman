/// 자세 참고 수치 계산 단위 테스트 (체형 분석 A단계).
///
/// **왜 지금 고정하는가:** ML Kit 은 아직 도입 전(B단계)이지만 계산은 순수 Dart 라
///   지금 전부 검증할 수 있다. 여기서 틀리면 **회원에게 틀린 신체 수치**가 가고,
///   그건 이 제품에서 가장 되돌리기 어려운 실수다.
///
/// 특히 못 박는 것:
///   1. 정규화 좌표 → 픽셀 변환(세로로 긴 사진에서 각도 과장 방지)
///   2. 좌/우 판정(피사체 기준 — 이미지 좌우와 반대라 뒤집히기 쉽다)
///   3. **못 재는 경우를 0 으로 채우지 않는다**(0 = 완벽히 수평, null = 못 쟀음)
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/domain/posture_metrics.dart';

/// 어깨 두 점만 넣은 스냅샷 헬퍼. 기본 이미지는 1000x1000(정사각 → 왜곡 없음).
PoseSnapshot shoulders({
  required double leftX,
  required double leftY,
  required double rightX,
  required double rightY,
  double likelihood = 1.0,
  int width = 1000,
  int height = 1000,
}) {
  return PoseSnapshot(
    imageWidth: width,
    imageHeight: height,
    points: {
      PoseLandmarkType.leftShoulder:
          PoseKeypoint(x: leftX, y: leftY, likelihood: likelihood),
      PoseLandmarkType.rightShoulder:
          PoseKeypoint(x: rightX, y: rightY, likelihood: likelihood),
    },
  );
}

PostureMetric shoulderMetric(PoseSnapshot s) =>
    PostureMetricsCalculator.computeOne(s, PostureMetricKey.shoulderTilt);

void main() {
  group('기울기 크기', () {
    test('완전 수평이면 0도이고 ok 다', () {
      // 정면 사진에서 피사체의 왼쪽 어깨는 이미지상 오른쪽(x가 큼)에 온다.
      final m = shoulderMetric(shoulders(
        leftX: 0.6,
        leftY: 0.30,
        rightX: 0.4,
        rightY: 0.30,
      ));
      expect(m.valueDeg, closeTo(0, 0.001));
      expect(m.flag, PostureFlag.ok);
      expect(m.higherSide, isNull); // 완전 수평 → 높은 쪽 없음
    });

    test('45도 기울기를 45도로 잰다', () {
      // dx = 0.2*1000 = 200px, dy = 0.2*1000 = 200px → 45도
      final m = shoulderMetric(shoulders(
        leftX: 0.6,
        leftY: 0.30,
        rightX: 0.4,
        rightY: 0.50,
      ));
      expect(m.valueDeg, closeTo(45, 0.001));
    });

    test('기준(2도) 초과면 watch, 이내면 ok', () {
      // dx=200px 기준으로 dy 를 조절해 임계 주변을 확인.
      final under = shoulderMetric(shoulders(
        leftX: 0.6, leftY: 0.30, rightX: 0.4, rightY: 0.303, // ~0.86도
      ));
      expect(under.flag, PostureFlag.ok);

      final over = shoulderMetric(shoulders(
        leftX: 0.6, leftY: 0.30, rightX: 0.4, rightY: 0.32, // ~5.7도
      ));
      expect(over.flag, PostureFlag.watch);
      expect(over.valueDeg! > PostureMetricsCalculator.watchThresholdDeg, isTrue);
    });

    test('좌우 순서를 바꿔도 크기는 같다 (부호 뒤집힘에 안 흔들림)', () {
      final a = shoulderMetric(shoulders(
        leftX: 0.6, leftY: 0.30, rightX: 0.4, rightY: 0.35,
      ));
      final b = shoulderMetric(shoulders(
        leftX: 0.4, leftY: 0.30, rightX: 0.6, rightY: 0.35,
      ));
      expect(a.valueDeg, closeTo(b.valueDeg!, 0.001));
    });
  });

  group('종횡비 보정', () {
    test('세로로 긴 사진에서 각도가 과장되지 않는다', () {
      // 정규화 좌표만 보면 dx=0.2, dy=0.2 라 45도처럼 보이지만,
      // 실제 픽셀은 dx=0.2*1000=200, dy=0.2*2000=400 → 63.4도가 맞다.
      final m = shoulderMetric(shoulders(
        leftX: 0.6,
        leftY: 0.30,
        rightX: 0.4,
        rightY: 0.50,
        width: 1000,
        height: 2000,
      ));
      expect(m.valueDeg, closeTo(63.435, 0.01));
      // 보정을 빠뜨렸다면 45도가 나왔을 것.
      expect(m.valueDeg, isNot(closeTo(45, 1)));
    });
  });

  group('좌우 판정 — 피사체 기준', () {
    test('y 가 작은 쪽(화면 위)이 높은 쪽이다', () {
      final m = shoulderMetric(shoulders(
        leftX: 0.6, leftY: 0.28, rightX: 0.4, rightY: 0.32,
      ));
      expect(m.higherSide, BodySide.left);
    });

    test('반대 경우도 맞게 잡는다', () {
      final m = shoulderMetric(shoulders(
        leftX: 0.6, leftY: 0.32, rightX: 0.4, rightY: 0.28,
      ));
      expect(m.higherSide, BodySide.right);
    });

    test('이미지상 위치가 아니라 랜드마크 라벨을 따른다', () {
      // 왼쪽 어깨가 이미지상 "왼쪽"(x 작음)에 있어도 — 뒷모습 촬영 등 —
      // 높이 판정은 라벨 기준이어야 한다.
      final m = shoulderMetric(shoulders(
        leftX: 0.4, leftY: 0.28, rightX: 0.6, rightY: 0.32,
      ));
      expect(m.higherSide, BodySide.left);
    });
  });

  group('측정 불가 — 0 으로 채우지 않는다', () {
    test('키포인트가 없으면 insufficient + value null', () {
      final s = PoseSnapshot(
        imageWidth: 1000,
        imageHeight: 1000,
        points: const {},
      );
      final m = shoulderMetric(s);
      expect(m.flag, PostureFlag.insufficient);
      expect(m.valueDeg, isNull); // 0 이 아니라 null 이어야 한다
      expect(m.note, isNotNull);
    });

    test('신뢰도가 낮으면 재지 않는다', () {
      final m = shoulderMetric(shoulders(
        leftX: 0.6, leftY: 0.30, rightX: 0.4, rightY: 0.35,
        likelihood: 0.2,
      ));
      expect(m.flag, PostureFlag.insufficient);
      expect(m.valueDeg, isNull);
    });

    test('옆으로 돌아 좌우가 겹치면 재지 않는다', () {
      // dx 가 이미지 너비의 5% 미만 → 각도가 요동치는 구간이라 측정 포기.
      final m = shoulderMetric(shoulders(
        leftX: 0.51, leftY: 0.30, rightX: 0.49, rightY: 0.34,
      ));
      expect(m.flag, PostureFlag.insufficient);
      expect(m.note, contains('정면'));
    });

    test('이미지 크기가 0이면 재지 않는다', () {
      final m = shoulderMetric(shoulders(
        leftX: 0.6, leftY: 0.30, rightX: 0.4, rightY: 0.35,
        width: 0,
      ));
      expect(m.flag, PostureFlag.insufficient);
    });
  });

  group('compute — 베타 범위 전체', () {
    test('어깨·골반 두 지표를 항상 돌려준다', () {
      final s = PoseSnapshot(
        imageWidth: 1000,
        imageHeight: 1000,
        points: {
          PoseLandmarkType.leftShoulder:
              const PoseKeypoint(x: 0.6, y: 0.30),
          PoseLandmarkType.rightShoulder:
              const PoseKeypoint(x: 0.4, y: 0.32),
          PoseLandmarkType.leftHip: const PoseKeypoint(x: 0.57, y: 0.60),
          PoseLandmarkType.rightHip: const PoseKeypoint(x: 0.43, y: 0.60),
        },
      );
      final metrics = PostureMetricsCalculator.compute(s);
      expect(metrics, hasLength(2));
      expect(metrics.map((m) => m.key.code),
          containsAll(['shoulder_tilt_deg', 'pelvis_tilt_deg']));
      // 골반은 수평 → ok
      final pelvis =
          metrics.firstWhere((m) => m.key == PostureMetricKey.pelvisTilt);
      expect(pelvis.flag, PostureFlag.ok);
    });

    test('일부 키포인트만 있어도 나머지는 insufficient 로 채워 나온다', () {
      final metrics = PostureMetricsCalculator.compute(shoulders(
        leftX: 0.6, leftY: 0.30, rightX: 0.4, rightY: 0.30,
      ));
      final pelvis =
          metrics.firstWhere((m) => m.key == PostureMetricKey.pelvisTilt);
      expect(pelvis.flag, PostureFlag.insufficient);
    });
  });

  group('표현 — 단정하지 않는다', () {
    test('지표 이름에 상태명(라운드숄더 등)이 없다', () {
      for (final key in PostureMetricKey.values) {
        expect(key.label, isNot(contains('숄더')));
        expect(key.label, isNot(contains('측만')));
      }
    });

    test('describe 는 사실 + 방향만 말한다', () {
      final m = shoulderMetric(shoulders(
        leftX: 0.6, leftY: 0.28, rightX: 0.4, rightY: 0.32,
      ));
      final text = m.describe();
      expect(text, contains('어깨 높이차'));
      expect(text, contains('왼쪽이 높음'));
    });

    test('측정 불가면 사유를 함께 알려준다', () {
      final m = shoulderMetric(shoulders(
        leftX: 0.51, leftY: 0.30, rightX: 0.49, rightY: 0.34,
      ));
      expect(m.describe(), contains('측정 불가'));
    });
  });

  group('toJson — ai_result.metrics 직렬화', () {
    test('설계 §2.3 구조로 나간다', () {
      final m = shoulderMetric(shoulders(
        leftX: 0.6, leftY: 0.28, rightX: 0.4, rightY: 0.32,
      ));
      final json = m.toJson();
      expect(json['key'], 'shoulder_tilt_deg');
      expect(json['flag'], 'watch');
      expect(json['higher_side'], 'left');
      expect(json['ref'], '±2');
      expect(json['value'], isA<double>());
    });

    test('측정 불가는 value 가 null 로 나간다', () {
      final m = shoulderMetric(shoulders(
        leftX: 0.6, leftY: 0.30, rightX: 0.4, rightY: 0.35,
        likelihood: 0.1,
      ));
      final json = m.toJson();
      expect(json['value'], isNull);
      expect(json['flag'], 'insufficient');
      expect(json['note'], isNotNull);
    });
  });
}
