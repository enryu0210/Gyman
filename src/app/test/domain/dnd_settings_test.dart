import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/domain/models/dnd_settings.dart';

/// DndSettings 단위 테스트 — 특히 자정 넘김 구간.
void main() {
  DateTime at(int h, int m) => DateTime(2026, 6, 1, h, m);

  group('isActiveAt — 비활성/미설정', () {
    test('enabled=false 면 항상 false', () {
      const s = DndSettings(enabled: false, startMinute: 0, endMinute: 1439);
      expect(s.isActiveAt(at(3, 0)), isFalse);
    });
    test('시작/끝 미설정이면 false', () {
      const s = DndSettings(enabled: true);
      expect(s.isActiveAt(at(3, 0)), isFalse);
    });
    test('start==end 는 빈 구간 → false', () {
      const s = DndSettings(enabled: true, startMinute: 600, endMinute: 600);
      expect(s.isActiveAt(at(10, 0)), isFalse);
    });
  });

  group('isActiveAt — 같은 날 구간 (09:00~18:00)', () {
    const s = DndSettings(enabled: true, startMinute: 9 * 60, endMinute: 18 * 60);
    test('구간 안', () => expect(s.isActiveAt(at(12, 0)), isTrue));
    test('시작 경계 포함', () => expect(s.isActiveAt(at(9, 0)), isTrue));
    test('끝 경계 제외', () => expect(s.isActiveAt(at(18, 0)), isFalse));
    test('구간 전', () => expect(s.isActiveAt(at(8, 59)), isFalse));
    test('구간 후', () => expect(s.isActiveAt(at(18, 1)), isFalse));
  });

  group('isActiveAt — 자정 넘김 구간 (22:00~08:00)', () {
    const s = DndSettings(enabled: true, startMinute: 22 * 60, endMinute: 8 * 60);
    test('밤(23:00) 활성', () => expect(s.isActiveAt(at(23, 0)), isTrue));
    test('새벽(02:00) 활성', () => expect(s.isActiveAt(at(2, 0)), isTrue));
    test('시작 경계(22:00) 포함', () => expect(s.isActiveAt(at(22, 0)), isTrue));
    test('끝 경계(08:00) 제외', () => expect(s.isActiveAt(at(8, 0)), isFalse));
    test('낮(12:00) 비활성', () => expect(s.isActiveAt(at(12, 0)), isFalse));
    test('끝 직전(07:59) 활성', () => expect(s.isActiveAt(at(7, 59)), isTrue));
  });

  group('fromRow / toUpdatePayload', () {
    test("'HH:mm:ss' 파싱 → 분", () {
      final s = DndSettings.fromRow({
        'dnd_enabled': true,
        'dnd_start': '22:00:00',
        'dnd_end': '08:30:00',
      });
      expect(s.enabled, isTrue);
      expect(s.startMinute, 22 * 60);
      expect(s.endMinute, 8 * 60 + 30);
    });

    test('payload 는 HH:mm 문자열', () {
      const s = DndSettings(
          enabled: true, startMinute: 22 * 60, endMinute: 8 * 60 + 5);
      final p = s.toUpdatePayload();
      expect(p['dnd_enabled'], isTrue);
      expect(p['dnd_start'], '22:00');
      expect(p['dnd_end'], '08:05');
    });

    test('미설정은 null 보존', () {
      final s = DndSettings.fromRow({
        'dnd_enabled': false,
        'dnd_start': null,
        'dnd_end': null,
      });
      expect(s.startMinute, isNull);
      expect(s.endMinute, isNull);
      expect(s.isConfigured, isFalse);
    });

    test('잘못된 형식은 null', () {
      final s = DndSettings.fromRow({
        'dnd_enabled': true,
        'dnd_start': 'bad',
        'dnd_end': '25:99',
      });
      expect(s.startMinute, isNull);
      expect(s.endMinute, isNull);
    });
  });

  test('rangeLabel', () {
    const s = DndSettings(enabled: true, startMinute: 22 * 60, endMinute: 8 * 60);
    expect(s.rangeLabel, '22:00 ~ 08:00');
  });
}
