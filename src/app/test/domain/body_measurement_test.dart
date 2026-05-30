import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/domain/models/body_measurement.dart';

/// BodyMeasurement 단위 테스트.
///
/// **검증 포인트:**
///   - PG numeric 이 num/String 어느 형태로 와도 double 로 흡수
///   - 미측정(null) 항목 보존 — 0으로 채우지 않음(가짜 추이 방지)
///   - INSERT payload 의 measured_at 이 시각 없는 `YYYY-MM-DD`
///   - isEmpty 판정
void main() {
  group('BodyMeasurement.fromRow', () {
    test('numeric 이 num 으로 올 때', () {
      final m = BodyMeasurement.fromRow({
        'id': 'm1',
        'member_id': 'mem1',
        'weight_kg': 72.5,
        'body_fat_pct': 18.3,
        'skeletal_muscle_kg': 33.1,
        'measured_at': '2026-03-01',
        'recorded_by': 'tr1',
        'created_at': '2026-03-01T09:00:00.000Z',
      });
      expect(m.weightKg, 72.5);
      expect(m.bodyFatPct, 18.3);
      expect(m.skeletalMuscleKg, 33.1);
      expect(m.measuredAt, DateTime(2026, 3, 1));
      expect(m.recordedBy, 'tr1');
    });

    test('numeric 이 String 으로 와도 double 로 파싱', () {
      final m = BodyMeasurement.fromRow({
        'id': 'm1',
        'member_id': 'mem1',
        'weight_kg': '70.0',
        'body_fat_pct': '20',
        'skeletal_muscle_kg': null,
        'measured_at': '2026-03-01',
        'recorded_by': null,
        'created_at': '2026-03-01T09:00:00.000Z',
      });
      expect(m.weightKg, 70.0);
      expect(m.bodyFatPct, 20.0);
      expect(m.skeletalMuscleKg, isNull);
      expect(m.recordedBy, isNull);
    });

    test('미측정 항목은 null 로 보존(0으로 채우지 않음)', () {
      final m = BodyMeasurement.fromRow({
        'id': 'm1',
        'member_id': 'mem1',
        'weight_kg': 70.0,
        'body_fat_pct': null,
        'skeletal_muscle_kg': null,
        'measured_at': '2026-03-01',
        'recorded_by': null,
        'created_at': '2026-03-01T09:00:00.000Z',
      });
      expect(m.weightKg, 70.0);
      expect(m.bodyFatPct, isNull);
      expect(m.skeletalMuscleKg, isNull);
      expect(m.isEmpty, isFalse);
    });
  });

  group('isEmpty', () {
    test('세 지표 모두 null 이면 empty', () {
      final m = BodyMeasurement(
        id: 'm1',
        memberId: 'mem1',
        measuredAt: _fixedDate,
        createdAt: _fixedDate,
      );
      expect(m.isEmpty, isTrue);
    });
  });

  group('toInsertPayload', () {
    test('measured_at 은 시각 없는 YYYY-MM-DD', () {
      final m = BodyMeasurement(
        id: 'ignored',
        memberId: 'mem1',
        weightKg: 72.5,
        measuredAt: DateTime(2026, 3, 1, 14, 30), // 시각이 섞여 있어도
        createdAt: _fixedDate,
      );
      final payload = m.toInsertPayload();
      expect(payload['measured_at'], '2026-03-01'); // 날짜만
      expect(payload['weight_kg'], 72.5);
      expect(payload['body_fat_pct'], isNull);
      expect(payload.containsKey('id'), isFalse); // DB 기본값
    });

    test('한 자리 월/일은 0 패딩', () {
      final m = BodyMeasurement(
        id: 'ignored',
        memberId: 'mem1',
        weightKg: 70,
        measuredAt: DateTime(2026, 1, 5),
        createdAt: _fixedDate,
      );
      expect(m.toInsertPayload()['measured_at'], '2026-01-05');
    });
  });
}

final _fixedDate = DateTime(2026, 3, 1);
