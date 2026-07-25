/// 체형 분석 모델 단위 테스트 (체형 분석 A단계).
///
/// **가장 중요한 것:** [BodyAssessment.isVisibleToMember] 가 RLS
///   (`assess_member_read_after_review`)와 **같은 조건**을 유지하는지.
///   이 게이트가 2D 키포인트 정확도 한계(설계 §1.3)를 덮는 안전장치라,
///   앱 쪽이 먼저 새면 DB 가 막아도 UX 상 "AI가 단정한" 화면이 잠깐 뜬다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/domain/models/body_assessment.dart';
import 'package:gyman/domain/posture_metrics.dart';

BodyAssessment assessment({
  String? trainerComment,
  Map<String, dynamic>? aiResult,
  Map<BodyPhotoView, String> photos = const {},
}) {
  return BodyAssessment(
    id: 'a1',
    memberId: 'm1',
    photos: photos,
    aiResult: aiResult,
    trainerComment: trainerComment,
    assessedAt: DateTime(2026, 7, 25),
  );
}

void main() {
  group('회원 노출 게이트 (RLS 미러)', () {
    test('트레이너 코멘트가 없으면 회원에게 안 보인다', () {
      expect(assessment().isVisibleToMember, isFalse);
      expect(assessment().needsReview, isTrue);
    });

    test('공백만 있는 코멘트도 노출 금지 (RLS 의 trim 조건과 동일)', () {
      expect(assessment(trainerComment: '   ').isVisibleToMember, isFalse);
      expect(assessment(trainerComment: '\n\t').isVisibleToMember, isFalse);
    });

    test('코멘트가 채워지면 노출된다', () {
      final a = assessment(trainerComment: '어깨 높이차는 생활습관 영향으로 보입니다.');
      expect(a.isVisibleToMember, isTrue);
      expect(a.needsReview, isFalse);
    });

    test('AI 결과가 아무리 풍부해도 코멘트 없이는 안 보인다', () {
      final a = assessment(
        aiResult: {
          'engine': 'mlkit_pose',
          'metrics': [
            {'key': 'shoulder_tilt_deg', 'value': 3.1, 'flag': 'watch'},
          ],
        },
      );
      expect(a.isVisibleToMember, isFalse);
    });
  });

  group('metrics 역직렬화', () {
    test('저장된 수치를 도메인 타입으로 되살린다', () {
      final a = assessment(aiResult: {
        'metrics': [
          {
            'key': 'shoulder_tilt_deg',
            'value': 3.1,
            'higher_side': 'left',
            'flag': 'watch',
          },
        ],
      });
      final m = a.metrics.single;
      expect(m.key, PostureMetricKey.shoulderTilt);
      expect(m.valueDeg, 3.1);
      expect(m.higherSide, BodySide.left);
      expect(m.flag, PostureFlag.watch);
    });

    test('모르는 key 항목은 건너뛴다 (정체불명 수치 미표시)', () {
      final a = assessment(aiResult: {
        'metrics': [
          {'key': 'neck_angle_deg', 'value': 12.0, 'flag': 'ok'},
          {'key': 'pelvis_tilt_deg', 'value': 1.0, 'flag': 'ok'},
        ],
      });
      expect(a.metrics, hasLength(1));
      expect(a.metrics.single.key, PostureMetricKey.pelvisTilt);
    });

    test('모르는 flag 는 insufficient 로 흡수한다 (없는 안심 금지)', () {
      // 알 수 없는 값을 'ok(기준 이내)' 로 보여주면 근거 없는 안심을 준다.
      final a = assessment(aiResult: {
        'metrics': [
          {'key': 'shoulder_tilt_deg', 'value': 3.1, 'flag': 'excellent'},
        ],
      });
      expect(a.metrics.single.flag, PostureFlag.insufficient);
    });

    test('ai_result 가 없거나 형식이 깨져도 빈 목록', () {
      expect(assessment().metrics, isEmpty);
      expect(assessment(aiResult: {'metrics': 'nope'}).metrics, isEmpty);
      expect(assessment(aiResult: {}).metrics, isEmpty);
    });

    test('숫자가 문자열로 와도 흡수한다', () {
      final a = assessment(aiResult: {
        'metrics': [
          {'key': 'shoulder_tilt_deg', 'value': '3.5', 'flag': 'watch'},
        ],
      });
      expect(a.metrics.single.valueDeg, 3.5);
    });
  });

  group('Storage 경로 규칙', () {
    test('첫 세그먼트가 member_id 다 (Storage RLS 권한 키)', () {
      final path = BodyAssessment.photoPath(
        memberId: 'mem-uuid',
        assessmentId: 'as-uuid',
        view: BodyPhotoView.front,
      );
      expect(path, 'mem-uuid/as-uuid/front.jpg');
      expect(path.split('/').first, 'mem-uuid');
    });

    test('뷰별로 파일명이 갈린다', () {
      String p(BodyPhotoView v) => BodyAssessment.photoPath(
          memberId: 'm', assessmentId: 'a', view: v);
      expect(p(BodyPhotoView.side), endsWith('side.jpg'));
      expect(p(BodyPhotoView.back), endsWith('back.jpg'));
    });
  });

  group('photos 파싱', () {
    test('jsonb 맵을 뷰별 경로로 읽는다', () {
      final a = BodyAssessment.fromRow({
        'id': 'a1',
        'member_id': 'm1',
        'photos': {'front': 'm1/a1/front.jpg', 'back': 'm1/a1/back.jpg'},
        'ai_result': null,
        'trainer_comment': null,
        'assessed_at': '2026-07-25T10:00:00Z',
        'recorded_by': 't1',
      });
      expect(a.photos[BodyPhotoView.front], 'm1/a1/front.jpg');
      expect(a.photos[BodyPhotoView.back], 'm1/a1/back.jpg');
      expect(a.photos[BodyPhotoView.side], isNull);
    });

    test('모르는 키·빈 값은 버린다', () {
      final a = BodyAssessment.fromRow({
        'id': 'a1',
        'member_id': 'm1',
        'photos': {'front': '', 'top': 'x.jpg', 'side': 'ok.jpg'},
        'ai_result': null,
        'trainer_comment': null,
        'assessed_at': '2026-07-25T10:00:00Z',
        'recorded_by': null,
      });
      expect(a.photos, hasLength(1));
      expect(a.photos[BodyPhotoView.side], 'ok.jpg');
    });
  });

  group('INSERT payload', () {
    test('trainer_comment 를 보내지 않는다 (항상 미검수로 시작)', () {
      // 등록 시점에 코멘트가 같이 들어가면 검수 게이트를 건너뛰게 된다.
      final payload = assessment(
        trainerComment: '실수로 채워진 값',
        photos: {BodyPhotoView.front: 'm1/a1/front.jpg'},
      ).toInsertPayload();

      expect(payload.containsKey('trainer_comment'), isFalse);
      expect(payload['member_id'], 'm1');
      expect(payload['photos'], {'front': 'm1/a1/front.jpg'});
    });
  });

  group('buildAiResult — 감사 정보', () {
    test('엔진·버전을 남긴다 (LLM 이 없어 프롬프트 추적이 불가하므로)', () {
      final result = BodyAssessment.buildAiResult(
        engine: 'mlkit_pose',
        engineVersion: '0.13.0',
        capturedAt: DateTime.utc(2026, 7, 25, 1, 2, 3),
        metrics: const [
          PostureMetric(
            key: PostureMetricKey.shoulderTilt,
            valueDeg: 3.1,
            higherSide: BodySide.left,
            flag: PostureFlag.watch,
          ),
        ],
      );

      expect(result['engine'], 'mlkit_pose');
      expect(result['engine_version'], '0.13.0');
      expect(result['captured_at'], '2026-07-25T01:02:03.000Z');
      expect((result['metrics'] as List), hasLength(1));
      // views 를 안 넘기면 키 자체가 없다.
      expect(result.containsKey('views'), isFalse);
    });

    test('왕복(build → fromRow → metrics)이 값을 보존한다', () {
      final built = BodyAssessment.buildAiResult(
        engine: 'mlkit_pose',
        engineVersion: '0.13.0',
        capturedAt: DateTime.utc(2026, 7, 25),
        metrics: const [
          PostureMetric(
            key: PostureMetricKey.pelvisTilt,
            valueDeg: 1.2,
            higherSide: BodySide.right,
            flag: PostureFlag.ok,
          ),
        ],
      );

      final a = assessment(aiResult: built);
      final m = a.metrics.single;
      expect(m.key, PostureMetricKey.pelvisTilt);
      expect(m.valueDeg, 1.2);
      expect(m.higherSide, BodySide.right);
      expect(m.flag, PostureFlag.ok);
      expect(a.engineLabel, 'mlkit_pose 0.13.0');
    });
  });
}
