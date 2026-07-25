/// 회원 체형 제약 모델 단위 테스트 (L1-a — docs/design_movement_coaching.md).
///
/// **왜 이 항목들을 고정하는가:**
///   이 모델은 의료 인접 정보를 다룬다. 특히 [ConditionSource]는 "의료기관 진단"과
///   "트레이너 관찰"을 가르는 법적 안전선이라(설계 §5), 알 수 없는 값이 실수로
///   "진단"으로 표시되는 회귀를 테스트로 막는다.
///
///   표시명은 카탈로그가 **잠정 목록**이라(설계 §8.1) 앞으로 항목이 바뀐다.
///   이미 저장된 행이 그때 빈 칸으로 깨지지 않는지도 함께 고정한다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/domain/models/member_condition.dart';

/// 테스트용 행 생성 헬퍼 — 필수 키만 채우고 나머지는 개별 테스트가 덮어쓴다.
Map<String, dynamic> row({
  String code = 'scoliosis',
  String? label,
  String? source = 'medical',
  String? memberNote,
  Object? trainerNote = _absent,
  Object? active = _absent,
}) {
  return {
    'id': 'c1',
    'member_id': 'm1',
    'code': code,
    'label': label,
    'source': source,
    'member_note': memberNote,
    // _absent 면 키 자체를 넣지 않는다 — 회원 측 부분 select 상황 재현.
    if (!identical(trainerNote, _absent)) 'trainer_note': trainerNote,
    if (!identical(active, _absent)) 'active': active,
    'recorded_by': 't1',
    'created_at': '2026-07-25T10:00:00Z',
    'updated_at': '2026-07-25T10:00:00Z',
  };
}

/// "이 키는 아예 없음"을 나타내는 센티널.
const _absent = Object();

/// 최소 필드로 도메인 객체 생성 — payload 테스트용.
MemberCondition make({
  String code = 'scoliosis',
  String? label,
  ConditionSource source = ConditionSource.trainerObservation,
  String? memberNote,
  String? trainerNote,
}) {
  final now = DateTime(2026, 7, 25);
  return MemberCondition(
    id: 'new',
    memberId: 'm1',
    code: code,
    label: label,
    source: source,
    memberNote: memberNote,
    trainerNote: trainerNote,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('ConditionSource.fromCode — 법적 안전선', () {
    test('정확한 코드는 그대로 매핑된다', () {
      expect(ConditionSource.fromCode('medical'), ConditionSource.medical);
      expect(
        ConditionSource.fromCode('trainer_observation'),
        ConditionSource.trainerObservation,
      );
    });

    test('모르는 값·null 은 "관찰"로 흡수한다 (진단으로 승격 금지)', () {
      // 알 수 없는 값을 "의료기관 진단"으로 표시하면 근거 없는 권위를 부여하게 된다.
      // 모호할 땐 약한 주장 쪽이 안전하다.
      expect(
        ConditionSource.fromCode(null),
        ConditionSource.trainerObservation,
      );
      expect(
        ConditionSource.fromCode('self_diagnosed'),
        ConditionSource.trainerObservation,
      );
      expect(ConditionSource.fromCode(''), ConditionSource.trainerObservation);
    });

    test('관찰 설명 문구에 "진단 아님"이 드러난다', () {
      expect(ConditionSource.trainerObservation.description, contains('진단'));
    });
  });

  group('displayName', () {
    test('카탈로그 코드는 표시명으로 바뀐다', () {
      expect(MemberCondition.fromRow(row(code: 'scoliosis')).displayName, '척추측만');
      expect(
        MemberCondition.fromRow(row(code: 'anterior_pelvic_tilt')).displayName,
        '골반 전방경사',
      );
    });

    test('custom 은 자유 입력 label 을 쓴다', () {
      final c = MemberCondition.fromRow(
        row(code: 'custom', label: '우측 발목 가동범위 제한'),
      );
      expect(c.displayName, '우측 발목 가동범위 제한');
    });

    test('custom 인데 label 이 비면 "기타"로 폴백한다', () {
      expect(
        MemberCondition.fromRow(row(code: 'custom', label: null)).displayName,
        '기타',
      );
      expect(
        MemberCondition.fromRow(row(code: 'custom', label: '   ')).displayName,
        '기타',
      );
    });

    test('카탈로그에 없는 코드는 원문을 그대로 보여준다 (빈 칸으로 안 깨짐)', () {
      // 카탈로그가 잠정 목록이라(§8.1) 항목이 지워질 수 있다. 이미 저장된 행이
      // 그때 이름 없는 항목으로 표시되면 트레이너가 무슨 기록인지 알 수 없다.
      expect(
        MemberCondition.fromRow(row(code: 'legacy_code')).displayName,
        'legacy_code',
      );
    });
  });

  group('fromRow — 부분 select 방어', () {
    test('trainer_note 키가 아예 없어도 깨지지 않고 null 이 된다', () {
      // 회원 측 조회(L1-b)는 trainer_note 를 SELECT 에서 제외한다 —
      // 그때 키 자체가 없는 Map 이 들어온다.
      final c = MemberCondition.fromRow(row());
      expect(c.trainerNote, isNull);
    });

    test('active 키가 없으면 true 로 본다', () {
      expect(MemberCondition.fromRow(row()).active, isTrue);
    });

    test('active=false 는 그대로 반영된다', () {
      expect(MemberCondition.fromRow(row(active: false)).active, isFalse);
    });

    test('isMedical 은 출처에 따라 갈린다', () {
      expect(MemberCondition.fromRow(row(source: 'medical')).isMedical, isTrue);
      expect(
        MemberCondition.fromRow(row(source: 'trainer_observation')).isMedical,
        isFalse,
      );
    });
  });

  group('toInsertPayload', () {
    test('custom 이 아니면 label 을 버린다 (표시명 중복 방지)', () {
      final p = make(code: 'scoliosis', label: '엉뚱한 값').toInsertPayload();
      expect(p['code'], 'scoliosis');
      expect(p['label'], isNull);
    });

    test('custom 이면 label 을 보낸다 (공백 제거)', () {
      final p = make(code: 'custom', label: '  발목 제한  ').toInsertPayload();
      expect(p['label'], '발목 제한');
    });

    test('빈 메모는 null 로 정규화된다', () {
      // 빈 문자열이 저장되면 "메모 있음"으로 오판해 UI 에 빈 줄이 생긴다.
      final p = make(memberNote: '   ', trainerNote: '').toInsertPayload();
      expect(p['member_note'], isNull);
      expect(p['trainer_note'], isNull);
    });

    test('출처는 DB 코드 문자열로 나간다', () {
      final p = make(source: ConditionSource.medical).toInsertPayload();
      expect(p['source'], 'medical');
    });

    test('payload 에 severity 가 없다 (의료 판단 필드 미도입)', () {
      // "중등도 측만증" 같은 표현은 의료 판단이라 스키마·모델 어디에도 두지 않는다.
      expect(make().toInsertPayload().containsKey('severity'), isFalse);
    });
  });

  group('ConditionCatalog', () {
    test('custom 항목이 카탈로그에 포함돼 있다', () {
      expect(ConditionCatalog.find(ConditionCatalog.customCode), isNotNull);
    });

    test('코드가 중복되지 않는다', () {
      final codes = ConditionCatalog.items.map((e) => e.code).toList();
      expect(codes.toSet().length, codes.length);
    });

    test('labelOf 는 모르는 코드에 원문을 돌려준다', () {
      expect(ConditionCatalog.labelOf('nope'), 'nope');
    });
  });
}
