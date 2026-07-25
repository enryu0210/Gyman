/// 코칭 큐 선별 로직 단위 테스트 (L1-b).
///
/// **왜 고정하는가:** 이 로직이 어긋나면 회원 화면과 트레이너 화면에 **서로 다른 큐**가
///   뜨거나, 해제한 제약의 큐가 계속 뜬다. 둘 다 신뢰를 바로 깎는 실패라
///   표시 규칙(활성만·센터 우선·정렬·상한)을 전부 못 박는다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/domain/coaching_cue.dart';
import 'package:gyman/domain/models/member_condition.dart';
import 'package:gyman/domain/movement_pattern.dart';

MemberCondition condition(String code, {bool active = true, String? label}) {
  final now = DateTime(2026, 7, 25);
  return MemberCondition(
    id: 'c_$code',
    memberId: 'm1',
    code: code,
    label: label,
    source: ConditionSource.trainerObservation,
    active: active,
    createdAt: now,
    updatedAt: now,
  );
}

CoachingRule rule(
  String code,
  MovementPattern pattern,
  CueAction action,
  String cue, {
  String? centerId,
}) {
  return CoachingRule(
    id: 'r_${code}_${pattern.code}_${centerId ?? 'seed'}',
    centerId: centerId,
    conditionCode: code,
    pattern: pattern,
    action: action,
    cue: cue,
  );
}

void main() {
  group('select — 기본 매칭', () {
    test('제약 × 패턴이 맞으면 큐가 나온다', () {
      final cues = CoachingCueSelector.select(
        conditions: [condition('anterior_pelvic_tilt')],
        rules: [
          rule('anterior_pelvic_tilt', MovementPattern.pushVertical,
              CueAction.caution, '갈비뼈를 닫으세요'),
        ],
        patterns: {MovementPattern.pushVertical},
      );
      expect(cues, hasLength(1));
      expect(cues.first.cue, '갈비뼈를 닫으세요');
      expect(cues.first.conditionLabel, '골반 전방경사');
    });

    test('패턴이 안 맞으면 큐가 없다', () {
      final cues = CoachingCueSelector.select(
        conditions: [condition('anterior_pelvic_tilt')],
        rules: [
          rule('anterior_pelvic_tilt', MovementPattern.pushVertical,
              CueAction.caution, 'x'),
        ],
        patterns: {MovementPattern.squat},
      );
      expect(cues, isEmpty);
    });

    test('패턴을 못 알아본 경우(빈 집합) 큐가 없다', () {
      // 모르는 종목에 아무 큐나 붙이면 안 된다 — 틀린 큐보다 없는 큐.
      final cues = CoachingCueSelector.select(
        conditions: [condition('scoliosis')],
        rules: [rule('scoliosis', MovementPattern.lunge, CueAction.modify, 'x')],
        patterns: const {},
      );
      expect(cues, isEmpty);
    });

    test('제약이 없거나 규칙이 없으면 빈 목록', () {
      expect(
        CoachingCueSelector.select(
          conditions: const [],
          rules: [rule('scoliosis', MovementPattern.lunge, CueAction.modify, 'x')],
          patterns: {MovementPattern.lunge},
        ),
        isEmpty,
      );
      expect(
        CoachingCueSelector.select(
          conditions: [condition('scoliosis')],
          rules: const [],
          patterns: {MovementPattern.lunge},
        ),
        isEmpty,
      );
    });
  });

  group('활성 제약만 사용', () {
    test('해제된 제약의 큐는 뜨지 않는다', () {
      final cues = CoachingCueSelector.select(
        conditions: [condition('scoliosis', active: false)],
        rules: [
          rule('scoliosis', MovementPattern.lunge, CueAction.modify, '대체하세요')
        ],
        patterns: {MovementPattern.lunge},
      );
      expect(cues, isEmpty);
    });

    test('활성/해제가 섞이면 활성 것만', () {
      final cues = CoachingCueSelector.select(
        conditions: [
          condition('scoliosis', active: false),
          condition('knee_valgus'),
        ],
        rules: [
          rule('scoliosis', MovementPattern.lunge, CueAction.modify, '해제된 큐'),
          rule('knee_valgus', MovementPattern.lunge, CueAction.focus, '무릎 큐'),
        ],
        patterns: {MovementPattern.lunge},
      );
      expect(cues.map((c) => c.cue), ['무릎 큐']);
    });
  });

  group('센터 규칙이 공통 시드를 덮어쓴다', () {
    test('같은 (제약, 패턴)이면 센터 규칙이 이긴다', () {
      final cues = CoachingCueSelector.select(
        conditions: [condition('knee_valgus')],
        rules: [
          rule('knee_valgus', MovementPattern.squat, CueAction.focus, '공통 시드'),
          rule('knee_valgus', MovementPattern.squat, CueAction.caution, '센터 문구',
              centerId: 'center-1'),
        ],
        patterns: {MovementPattern.squat},
      );
      expect(cues, hasLength(1));
      expect(cues.first.cue, '센터 문구');
    });

    test('규칙 순서가 반대로 와도 센터 규칙이 이긴다', () {
      // 조회 순서에 의존하면 안 된다.
      final cues = CoachingCueSelector.select(
        conditions: [condition('knee_valgus')],
        rules: [
          rule('knee_valgus', MovementPattern.squat, CueAction.caution, '센터 문구',
              centerId: 'center-1'),
          rule('knee_valgus', MovementPattern.squat, CueAction.focus, '공통 시드'),
        ],
        patterns: {MovementPattern.squat},
      );
      expect(cues.first.cue, '센터 문구');
    });
  });

  group('정렬 — 주의가 필요한 것부터', () {
    test('대체 권장 → 주의 → 체크 순', () {
      final cues = CoachingCueSelector.select(
        conditions: [
          condition('a'),
          condition('b'),
          condition('c'),
        ],
        rules: [
          rule('a', MovementPattern.squat, CueAction.focus, '체크'),
          rule('b', MovementPattern.squat, CueAction.modify, '대체'),
          rule('c', MovementPattern.squat, CueAction.caution, '주의'),
        ],
        patterns: {MovementPattern.squat},
      );
      expect(cues.map((c) => c.cue), ['대체', '주의', '체크']);
    });

    test('같은 등급이면 제약 등록 순서를 지킨다', () {
      final cues = CoachingCueSelector.select(
        conditions: [condition('first'), condition('second')],
        rules: [
          rule('second', MovementPattern.squat, CueAction.focus, '두번째'),
          rule('first', MovementPattern.squat, CueAction.focus, '첫번째'),
        ],
        patterns: {MovementPattern.squat},
      );
      expect(cues.map((c) => c.cue), ['첫번째', '두번째']);
    });
  });

  group('표시 상한 — 잔소리 방지', () {
    test('기본 상한은 3개', () {
      final conditions = [
        for (var i = 0; i < 5; i++) condition('c$i'),
      ];
      final rules = [
        for (var i = 0; i < 5; i++)
          rule('c$i', MovementPattern.squat, CueAction.focus, 'cue$i'),
      ];
      final cues = CoachingCueSelector.select(
        conditions: conditions,
        rules: rules,
        patterns: {MovementPattern.squat},
      );
      expect(cues, hasLength(CoachingCueSelector.defaultLimit));
      expect(cues, hasLength(3));
    });

    test('상한을 넘겨도 가장 중요한 것이 살아남는다', () {
      final cues = CoachingCueSelector.select(
        conditions: [condition('a'), condition('b'), condition('c')],
        rules: [
          rule('a', MovementPattern.squat, CueAction.focus, '체크'),
          rule('b', MovementPattern.squat, CueAction.focus, '체크2'),
          rule('c', MovementPattern.squat, CueAction.modify, '대체'),
        ],
        patterns: {MovementPattern.squat},
        limit: 1,
      );
      expect(cues.map((c) => c.cue), ['대체']);
    });
  });

  group('CoachingRule.tryFromRow — 방어', () {
    Map<String, dynamic> row({
      String pattern = 'squat',
      String action = 'caution',
      String cue = '문구',
    }) =>
        {
          'id': 'r1',
          'center_id': null,
          'condition_code': 'knee_valgus',
          'movement_pattern': pattern,
          'action': action,
          'cue': cue,
        };

    test('정상 행은 매핑된다', () {
      final r = CoachingRule.tryFromRow(row());
      expect(r, isNotNull);
      expect(r!.pattern, MovementPattern.squat);
      expect(r.action, CueAction.caution);
      expect(r.isCenterOverride, isFalse);
    });

    test('앱이 모르는 패턴은 버린다 (엉뚱한 큐 방지)', () {
      expect(CoachingRule.tryFromRow(row(pattern: 'sprint')), isNull);
    });

    test('빈 큐 문구는 버린다', () {
      expect(CoachingRule.tryFromRow(row(cue: '   ')), isNull);
    });

    test('모르는 action 은 가장 약한 등급으로 흡수한다', () {
      // 모호할 때 강한 경고로 승격하면 과잉 경고가 되고 결국 무시당한다.
      final r = CoachingRule.tryFromRow(row(action: 'danger'));
      expect(r!.action, CueAction.focus);
    });

    test('CueAction 에 avoid(금지)가 없다 — 처방 표현 미도입', () {
      expect(CueAction.values.map((a) => a.code), isNot(contains('avoid')));
      expect(CueAction.values, hasLength(3));
    });
  });
}
