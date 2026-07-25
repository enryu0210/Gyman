/// 종목명 → 동작 패턴 매핑 단위 테스트 (L1-b).
///
/// **왜 고정하는가:** 이 매핑이 틀리면 **엉뚱한 회원에게 엉뚱한 큐**가 뜬다.
///   특히 "불가리안 스플릿 스쿼트"가 스쿼트로 잡히면 런지(편측 부하) 큐를 놓치고,
///   반대로 "로우바 스쿼트"가 로우(당기기)로 잡히면 완전히 다른 큐가 뜬다.
///   둘 다 키워드 길이 우선 규칙이 막고 있으므로 회귀 테스트로 못 박는다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/domain/movement_pattern.dart';

void main() {
  group('match — 기본 매칭', () {
    test('대표 종목이 각 패턴으로 잡힌다', () {
      expect(MovementPatternMatcher.match('스쿼트'), MovementPattern.squat);
      expect(MovementPatternMatcher.match('데드리프트'), MovementPattern.hinge);
      expect(MovementPatternMatcher.match('런지'), MovementPattern.lunge);
      expect(
        MovementPatternMatcher.match('벤치프레스'),
        MovementPattern.pushHorizontal,
      );
      expect(
        MovementPatternMatcher.match('오버헤드프레스'),
        MovementPattern.pushVertical,
      );
      expect(
        MovementPatternMatcher.match('시티드로우'),
        MovementPattern.pullHorizontal,
      );
      expect(
        MovementPatternMatcher.match('랫풀다운'),
        MovementPattern.pullVertical,
      );
      expect(MovementPatternMatcher.match('플랭크'), MovementPattern.coreCarry);
    });

    test('공백·대소문자·구분자 표기 흔들림을 흡수한다', () {
      expect(
        MovementPatternMatcher.match('Bench Press'),
        MovementPattern.pushHorizontal,
      );
      expect(
        MovementPatternMatcher.match('바벨 로우'),
        MovementPattern.pullHorizontal,
      );
      expect(
        MovementPatternMatcher.match('  바벨   스쿼트  '),
        MovementPattern.squat,
      );
    });

    test('수식어가 붙어도 잡힌다', () {
      expect(MovementPatternMatcher.match('백스쿼트'), MovementPattern.squat);
      expect(MovementPatternMatcher.match('핵스쿼트'), MovementPattern.squat);
      expect(
        MovementPatternMatcher.match('루마니안 데드리프트'),
        MovementPattern.hinge,
      );
    });

    test('모르는 종목·빈 값은 null (큐를 띄우지 않는다)', () {
      expect(MovementPatternMatcher.match('레그컬'), isNull);
      expect(MovementPatternMatcher.match('유산소'), isNull);
      expect(MovementPatternMatcher.match(''), isNull);
      expect(MovementPatternMatcher.match(null), isNull);
      expect(MovementPatternMatcher.match('   '), isNull);
    });
  });

  group('긴 키워드 우선 — 오분류 방지', () {
    test('불가리안 스플릿 스쿼트는 스쿼트가 아니라 런지다', () {
      // 편측 부하 종목이라 척추측만 회원에게 다른 큐가 붙어야 한다.
      expect(
        MovementPatternMatcher.match('불가리안 스플릿 스쿼트'),
        MovementPattern.lunge,
      );
      expect(
        MovementPatternMatcher.match('스플릿스쿼트'),
        MovementPattern.lunge,
      );
    });

    test('로우바 스쿼트는 로우(당기기)가 아니라 스쿼트다', () {
      // '로우'(2자) 보다 '스쿼트'(3자) 가 길어서 이긴다.
      expect(MovementPatternMatcher.match('로우바 스쿼트'), MovementPattern.squat);
    });

    test('체스트프레스/숄더프레스가 서로 섞이지 않는다', () {
      expect(
        MovementPatternMatcher.match('체스트프레스'),
        MovementPattern.pushHorizontal,
      );
      expect(
        MovementPatternMatcher.match('숄더프레스'),
        MovementPattern.pushVertical,
      );
      expect(
        MovementPatternMatcher.match('레그프레스'),
        MovementPattern.squat,
      );
    });
  });

  group('matchAll — 종목 칸이 여러 개일 때(트레이너 수업기록)', () {
    test('각 칸의 패턴을 모아 중복 없이 돌려준다', () {
      final result = MovementPatternMatcher.matchAll([
        '스쿼트',
        '바벨 스쿼트', // 같은 패턴 → 중복 제거
        '벤치프레스',
        '레그컬', // 모르는 종목 → 무시
        null,
      ]);
      expect(result, {MovementPattern.squat, MovementPattern.pushHorizontal});
    });

    test('전부 모르는 종목이면 빈 집합', () {
      expect(MovementPatternMatcher.matchAll(['유산소', '스트레칭']), isEmpty);
    });
  });

  group('matchAllInText — 한 칸에 여러 종목(회원 셀프기록)', () {
    test('쉼표로 나열한 종목을 모두 잡는다', () {
      final result = MovementPatternMatcher.matchAllInText('하체 - 스쿼트, 레그프레스');
      // 레그프레스도 스쿼트 계열 → 결과는 squat 하나.
      expect(result, {MovementPattern.squat});
    });

    test('구분자 없이 이어 써도 각각 잡는다 (스캔-소거)', () {
      final result = MovementPatternMatcher.matchAllInText('스쿼트 벤치프레스');
      expect(result, {MovementPattern.squat, MovementPattern.pushHorizontal});
    });

    test('긴 키워드를 소거해 짧은 것이 오탐하지 않는다', () {
      // '불가리안스플릿스쿼트' 는 런지 하나여야 한다 — 스쿼트가 같이 잡히면
      // 척추측만 회원에게 편측 부하 큐 대신 엉뚱한 큐가 섞인다.
      final result = MovementPatternMatcher.matchAllInText('불가리안 스플릿 스쿼트');
      expect(result, {MovementPattern.lunge});
    });

    test('세 종목이 섞여도 전부 잡는다', () {
      final result =
          MovementPatternMatcher.matchAllInText('데드리프트, 랫풀다운, 플랭크');
      expect(result, {
        MovementPattern.hinge,
        MovementPattern.pullVertical,
        MovementPattern.coreCarry,
      });
    });

    test('모르는 텍스트·빈 값은 빈 집합', () {
      expect(MovementPatternMatcher.matchAllInText('오늘은 쉬었음'), isEmpty);
      expect(MovementPatternMatcher.matchAllInText(''), isEmpty);
      expect(MovementPatternMatcher.matchAllInText(null), isEmpty);
    });
  });

  group('MovementPattern.fromCode — DB 값 매핑', () {
    test('DB 코드가 enum 으로 매핑된다', () {
      expect(MovementPattern.fromCode('push_vertical'),
          MovementPattern.pushVertical);
      expect(MovementPattern.fromCode('core_carry'), MovementPattern.coreCarry);
    });

    test('모르는 코드·null 은 null (그 규칙은 버려진다)', () {
      expect(MovementPattern.fromCode('squats'), isNull);
      expect(MovementPattern.fromCode(null), isNull);
    });

    test('모든 패턴 코드가 snake_case 로 유일하다 (DB CHECK 와 1:1)', () {
      final codes = MovementPattern.values.map((p) => p.code).toList();
      expect(codes.toSet().length, codes.length);
      expect(codes.length, 8);
    });
  });
}
