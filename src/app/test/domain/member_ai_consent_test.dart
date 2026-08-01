/// 회원 AI 사용 동의(`Member.aiConsent`) 기본값·보존 규칙 테스트.
///
/// **왜 이 값에만 테스트를 붙이나:**
///   `aiConsent` 는 켜지는 순간 회원의 수업 기록·인바디가 외부 LLM 으로 나가는
///   스위치다. 다른 필드는 잘못되면 화면이 비지만, 이 필드는 잘못된 방향(false→true)
///   으로 틀리면 동의 없이 개인정보가 전송된다. 그래서 "모르면 false" 라는
///   fail-closed 방향을 회귀 테스트로 고정한다. (develop_plan.md §6)
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/domain/models/member.dart';

void main() {
  Member buildMember({bool? aiConsent, bool? optOut}) {
    return Member(
      id: 'm-1',
      name: '홍길동',
      createdAt: DateTime(2026, 1, 1),
      aiConsent: aiConsent ?? false,
      aiConsentMemberOptout: optOut ?? false,
    );
  }

  group('Member.aiConsent — fail-closed 기본값', () {
    test('명시하지 않으면 동의 없음(false)으로 시작한다', () {
      final member = Member(
        id: 'm-1',
        name: '홍길동',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(member.aiConsent, isFalse);
    });

    test('true 로 만들면 그대로 유지된다', () {
      expect(buildMember(aiConsent: true).aiConsent, isTrue);
    });
  });

  group('Member.copyWith — 동의 값 보존', () {
    test('다른 필드만 바꾸면 기존 동의가 유지된다', () {
      final consented = buildMember(aiConsent: true);

      final renamed = consented.copyWith(name: '김철수');

      // 이름 수정 같은 무관한 변경이 동의를 조용히 꺼뜨리면 안 된다.
      expect(renamed.name, '김철수');
      expect(renamed.aiConsent, isTrue);
    });

    test('동의를 명시적으로 철회(false)할 수 있다', () {
      final consented = buildMember(aiConsent: true);

      final revoked = consented.copyWith(aiConsent: false);

      expect(revoked.aiConsent, isFalse);
    });

    test('동의 없는 회원에 무관한 변경을 해도 켜지지 않는다', () {
      final notConsented = buildMember(aiConsent: false);

      final updated = notConsented.copyWith(goal: '체중감량');

      expect(updated.goal, '체중감량');
      expect(updated.aiConsent, isFalse);
    });
  });

  // 마이그레이션 0040 — 회원 거부권.
  //
  // aiConsentEffective 는 **DB 생성 컬럼 ai_consent_effective 와 같은 식**이어야
  // 한다. 어긋나면 "화면엔 허용인데 서버가 막는다"(또는 그 반대)가 되므로,
  // 진리표를 통째로 고정한다.
  group('Member.aiConsentEffective — 회원 거부가 항상 이긴다 (0040)', () {
    test('트레이너 동의 O + 회원 거부 X → 전송 허용', () {
      expect(buildMember(aiConsent: true, optOut: false).aiConsentEffective,
          isTrue);
    });

    test('트레이너 동의 O + 회원 거부 O → 차단 (거부가 우선)', () {
      expect(buildMember(aiConsent: true, optOut: true).aiConsentEffective,
          isFalse);
    });

    test('트레이너 동의 X + 회원 거부 X → 차단', () {
      expect(buildMember(aiConsent: false, optOut: false).aiConsentEffective,
          isFalse);
    });

    test('트레이너 동의 X + 회원 거부 O → 차단', () {
      expect(buildMember(aiConsent: false, optOut: true).aiConsentEffective,
          isFalse);
    });

    test('거부는 기본값이 아니다 — 명시하지 않으면 거부하지 않은 상태', () {
      final member = Member(
        id: 'm-1',
        name: '홍길동',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(member.aiConsentMemberOptout, isFalse);
      // 단, aiConsent 가 기본 false 라 실효값은 여전히 차단(fail-closed).
      expect(member.aiConsentEffective, isFalse);
    });

    test('copyWith 로 거부만 켜도 트레이너 동의 기록은 남는다', () {
      final consented = buildMember(aiConsent: true);

      final refused = consented.copyWith(aiConsentMemberOptout: true);

      // 두 값은 별개의 사실 — 회원이 거부해도 "동의를 받았다"는 기록은 지우지 않는다.
      expect(refused.aiConsent, isTrue);
      expect(refused.aiConsentMemberOptout, isTrue);
      expect(refused.aiConsentEffective, isFalse);
    });

    test('거부를 철회하면 다시 허용된다', () {
      final refused = buildMember(aiConsent: true, optOut: true);

      final restored = refused.copyWith(aiConsentMemberOptout: false);

      expect(restored.aiConsentEffective, isTrue);
    });

    test('이름 수정 같은 무관한 변경이 거부를 조용히 풀지 않는다', () {
      final refused = buildMember(aiConsent: true, optOut: true);

      final renamed = refused.copyWith(name: '김철수');

      expect(renamed.name, '김철수');
      expect(renamed.aiConsentMemberOptout, isTrue);
      expect(renamed.aiConsentEffective, isFalse);
    });
  });
}
