import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/domain/models/session_record.dart';

/// SessionRecord / Exercise / ExerciseSet 단위 테스트.
///
/// **검증 포인트:**
///   - jsonb 직렬화/역직렬화의 *왕복 보존* (round-trip) — DB와 도메인 사이
///     데이터 손실/변형 없음
///   - 음수/null/잘못된 타입 같은 더러운 입력 방어
///   - totalVolume / totalSets 계산 정확성
///
/// 이 영역이 어긋나면 회원의 변화 추이 그래프(S1)나 잔여 횟수 카운팅이
/// 잘못된 데이터에 기반하게 됨 — 매출 분쟁 직결까진 아니지만 신뢰 직결.
void main() {
  group('ExerciseSet', () {
    test('toJson / fromJson 왕복 보존', () {
      const set = ExerciseSet(weight: 60, reps: 10);
      final json = set.toJson();
      expect(json, {'weight': 60, 'reps': 10});

      final back = ExerciseSet.fromJson(json);
      expect(back, set);
    });

    test('음수 weight/reps는 0으로 보정', () {
      final set = ExerciseSet.fromJson({'weight': -5, 'reps': -1});
      expect(set.weight, 0);
      expect(set.reps, 0);
    });

    test('PG jsonb 가 double 로 줘도 int 로 받아짐', () {
      final set = ExerciseSet.fromJson({'weight': 60.0, 'reps': 10.0});
      expect(set.weight, 60);
      expect(set.reps, 10);
    });

    test('필드 누락 시 0', () {
      final set = ExerciseSet.fromJson(const {});
      expect(set.weight, 0);
      expect(set.reps, 0);
    });
  });

  group('Exercise', () {
    test('totalVolume = sum(weight × reps)', () {
      const ex = Exercise(
        name: '스쿼트',
        sets: [
          ExerciseSet(weight: 60, reps: 10), // 600
          ExerciseSet(weight: 70, reps: 8),  // 560
          ExerciseSet(weight: 80, reps: 6),  // 480
        ],
      );
      expect(ex.totalVolume, 600 + 560 + 480);
    });

    test('빈 세트 → 볼륨 0', () {
      const ex = Exercise(name: '맨몸 스쿼트', sets: []);
      expect(ex.totalVolume, 0);
    });

    test('toJson / fromJson 왕복 보존', () {
      const ex = Exercise(
        name: '벤치프레스',
        sets: [
          ExerciseSet(weight: 50, reps: 12),
          ExerciseSet(weight: 60, reps: 10),
        ],
      );
      final json = ex.toJson();
      final back = Exercise.fromJson(json);
      expect(back, ex);
    });

    test('sets 가 List 아니거나 누락이어도 빈 리스트로 안전 처리', () {
      final ex = Exercise.fromJson({'name': '풀업'}); // sets 누락
      expect(ex.name, '풀업');
      expect(ex.sets, isEmpty);

      final ex2 = Exercise.fromJson({'name': '풀업', 'sets': 'invalid'});
      expect(ex2.sets, isEmpty);
    });

    test('name 누락 시 빈 문자열', () {
      final ex = Exercise.fromJson(const {});
      expect(ex.name, '');
      expect(ex.sets, isEmpty);
    });
  });

  group('SessionRecord', () {
    /// 베이스 row — PG 가 반환하는 형태와 동일.
    Map<String, dynamic> baseRow() => {
          'session_id': 's1',
          'exercises': [
            {
              'name': '스쿼트',
              'sets': [
                {'weight': 60, 'reps': 10},
                {'weight': 70, 'reps': 8},
              ],
            },
            {
              'name': '데드리프트',
              'sets': [
                {'weight': 100, 'reps': 5},
              ],
            },
          ],
          'condition': 'good',
          'pain': null,
          'next_memo': '다음엔 무게 5kg 증량',
          'created_at': '2026-05-28T10:00:00Z',
          'updated_at': '2026-05-28T10:15:00Z',
        };

    test('fromRow → 종목/세트 모두 복원', () {
      final rec = SessionRecord.fromRow(baseRow());
      expect(rec.sessionId, 's1');
      expect(rec.exercises.length, 2);
      expect(rec.exercises[0].name, '스쿼트');
      expect(rec.exercises[0].sets.length, 2);
      expect(rec.exercises[1].name, '데드리프트');
      expect(rec.condition, 'good');
      expect(rec.pain, isNull);
      expect(rec.nextMemo, '다음엔 무게 5kg 증량');
    });

    test('totalSets / totalVolume 합산 정확', () {
      final rec = SessionRecord.fromRow(baseRow());
      // 2 + 1 = 3 세트
      expect(rec.totalSets, 3);
      // 60*10 + 70*8 + 100*5 = 600 + 560 + 500 = 1660
      expect(rec.totalVolume, 1660);
    });

    test('exercises 가 List 가 아니어도 빈 리스트로 안전 처리', () {
      final row = baseRow()..['exercises'] = null;
      final rec = SessionRecord.fromRow(row);
      expect(rec.exercises, isEmpty);
      expect(rec.totalSets, 0);
      expect(rec.totalVolume, 0);
    });

    test('toInsertPayload 는 본문 필드만 포함 (sessionId/timestamp 제외)', () {
      final rec = SessionRecord.fromRow(baseRow());
      final payload = rec.toInsertPayload();
      expect(payload.containsKey('session_id'), isFalse);
      expect(payload.containsKey('created_at'), isFalse);
      expect(payload.containsKey('updated_at'), isFalse);
      expect(payload['condition'], 'good');
      expect(payload['pain'], isNull);
      expect(payload['next_memo'], '다음엔 무게 5kg 증량');
      expect(payload['exercises'], isA<List>());
      expect((payload['exercises'] as List).length, 2);
    });

    test('payload 왕복: toInsertPayload → fromRow 와 같은 본문 복원', () {
      final rec = SessionRecord.fromRow(baseRow());
      final payload = rec.toInsertPayload();

      // session_id/timestamp 채워서 fromRow가 받을 수 있는 형태로 재구성
      final reconstructedRow = <String, dynamic>{
        'session_id': rec.sessionId,
        'created_at': rec.createdAt.toIso8601String(),
        'updated_at': rec.updatedAt.toIso8601String(),
        ...payload,
      };
      final back = SessionRecord.fromRow(reconstructedRow);
      // 본문 필드 동치 — exercises / condition / pain / next_memo
      expect(back.exercises, rec.exercises);
      expect(back.condition, rec.condition);
      expect(back.pain, rec.pain);
      expect(back.nextMemo, rec.nextMemo);
    });
  });
}
