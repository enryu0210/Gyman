/// CenterRules JSON 직렬화 단위 테스트 — Phase 3.2 (C2).
///
/// 규정은 노쇼율/차감 해석에 영향을 줄 수 있어 직렬화 깨짐이 곤란 → 라운드트립과
/// 방어적 파싱을 고정한다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/domain/models/center_rules.dart';

void main() {
  group('CenterRules.fromJson', () {
    test('정상 JSON 파싱', () {
      final r = CenterRules.fromJson({
        'late_cancel_hours': 24,
        'no_show_deduct': true,
        'late_arrival_minutes': 15,
      });
      expect(r.lateCancelHours, 24);
      expect(r.noShowDeduct, isTrue);
      expect(r.lateArrivalMinutes, 15);
    });

    test('빈 JSON → 기본값(노쇼 차감 true, 나머지 null)', () {
      final r = CenterRules.fromJson({});
      expect(r.lateCancelHours, isNull);
      expect(r.noShowDeduct, isTrue);
      expect(r.lateArrivalMinutes, isNull);
    });

    test('no_show_deduct=false 반영', () {
      final r = CenterRules.fromJson({'no_show_deduct': false});
      expect(r.noShowDeduct, isFalse);
    });

    test('숫자가 문자열로 와도 int 로 정규화', () {
      final r = CenterRules.fromJson({'late_cancel_hours': '12'});
      expect(r.lateCancelHours, 12);
    });

    test('이상한 타입은 null 로 흘려보냄(터지지 않음)', () {
      final r = CenterRules.fromJson({
        'late_cancel_hours': 'abc',
        'no_show_deduct': 'yes', // bool 아님 → 기본 true
      });
      expect(r.lateCancelHours, isNull);
      expect(r.noShowDeduct, isTrue);
    });
  });

  group('CenterRules.toJson', () {
    test('null 숫자 항목은 키를 빼고, no_show_deduct 는 항상 포함', () {
      const r = CenterRules(noShowDeduct: false);
      expect(r.toJson(), {'no_show_deduct': false});
    });

    test('라운드트립 — toJson → fromJson 동일', () {
      const r = CenterRules(
        lateCancelHours: 24,
        noShowDeduct: false,
        lateArrivalMinutes: 10,
      );
      final back = CenterRules.fromJson(r.toJson());
      expect(back.lateCancelHours, 24);
      expect(back.noShowDeduct, isFalse);
      expect(back.lateArrivalMinutes, 10);
    });
  });

  group('CenterRules.copyWith', () {
    test('일부만 교체', () {
      const r = CenterRules(lateCancelHours: 24, lateArrivalMinutes: 15);
      final updated = r.copyWith(noShowDeduct: false);
      expect(updated.lateCancelHours, 24);
      expect(updated.noShowDeduct, isFalse);
      expect(updated.lateArrivalMinutes, 15);
    });

    test('clear 플래그로 null 화', () {
      const r = CenterRules(lateCancelHours: 24);
      final cleared = r.copyWith(clearLateCancelHours: true);
      expect(cleared.lateCancelHours, isNull);
    });
  });
}
