/// 동의 기록 규칙 회귀 테스트 (마이그레이션 0041 / 처리방침 제3항).
///
/// **여기서 지키려는 사고 두 가지:**
///   1. 소셜 로그인처럼 민감정보 체크박스를 안 거친 경로가 기존 동의를
///      **조용히 지우는 것** — 화면에 아무 흔적이 안 남아 발견이 늦다.
///   2. 동의 확인 기록이 없는 옛 회원을 "확인된 회원"으로 착각하는 것.
///
/// RLS·트리거 자체의 DB 강제는 0041 하단 검증 SQL 로 별도 확인한다(오프라인
/// 하네스 범위 밖). 여기서는 앱이 만들어 보내는 payload 만 고정한다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/core/config/app_info.dart';
import 'package:gyman/domain/models/member.dart';
import 'package:gyman/features/settings/settings_repository.dart';

void main() {
  group('SettingsRepository.consentPayload — 민감정보 동의', () {
    const uid = '11111111-1111-1111-1111-111111111111';

    test('필수 동의 2종은 항상 현재 버전으로 기록된다', () {
      final payload = SettingsRepository.consentPayload(userId: uid);

      expect(payload['user_id'], uid);
      expect(payload['terms_version'], kTermsVersion);
      expect(payload['privacy_version'], kPrivacyVersion);
    });

    test('sensitiveAgreed 가 null 이면 민감정보 키를 아예 넣지 않는다', () {
      // ★ 핵심 — PostgREST 의 upsert 는 payload 에 있는 컬럼만 SET 한다.
      //    키가 없어야 충돌 시 기존 동의가 보존된다(소셜 로그인 → claim 경로).
      final payload = SettingsRepository.consentPayload(
        userId: uid,
        sensitiveAgreed: null,
      );

      expect(payload.containsKey('sensitive_version'), isFalse);
      expect(payload.containsKey('sensitive_agreed_at'), isFalse);
    });

    test('동의하면 버전과 시각이 함께 기록된다', () {
      final now = DateTime.utc(2026, 8, 10, 3, 30);
      final payload = SettingsRepository.consentPayload(
        userId: uid,
        sensitiveAgreed: true,
        now: now,
      );

      expect(payload['sensitive_version'], kSensitiveConsentVersion);
      expect(payload['sensitive_agreed_at'], now.toIso8601String());
    });

    test('동의 시각은 UTC 로 보낸다 — 로컬 시각을 그대로 보내면 안 된다', () {
      // 이 프로젝트의 "벽시계 그대로" 컨벤션은 **수업 시각** 전용이다.
      // 동의 시각에 그걸 적용하면 KST 기준 9시간 미래로 기록된다.
      final localNow = DateTime(2026, 8, 10, 12, 30); // 로컬 타임존
      final payload = SettingsRepository.consentPayload(
        userId: uid,
        sensitiveAgreed: true,
        now: localNow,
      );

      final recorded = payload['sensitive_agreed_at'] as String;
      expect(recorded.endsWith('Z'), isTrue,
          reason: 'UTC 표기(Z)가 없으면 PG 가 naive 로 읽어 시각이 밀린다');
      expect(DateTime.parse(recorded).isAtSameMomentAs(localNow), isTrue);
    });

    test('동의하지 않으면 명시적으로 NULL 로 기록한다', () {
      // "동의한 적 없음"과 같은 상태. 키를 빼는 것(=건드리지 않음)과 구분된다.
      final payload = SettingsRepository.consentPayload(
        userId: uid,
        sensitiveAgreed: false,
      );

      expect(payload.containsKey('sensitive_version'), isTrue);
      expect(payload['sensitive_version'], isNull);
      expect(payload['sensitive_agreed_at'], isNull);
    });
  });

  group('Member.needsConsentConfirmation — 앱 미가입 회원 동의 근거', () {
    Member buildMember({DateTime? confirmedAt}) => Member(
          id: 'm1',
          name: '홍길동',
          createdAt: DateTime(2026, 1, 1),
          offlineConsentConfirmedAt: confirmedAt,
        );

    test('확인 기록이 없으면 소급 확인이 필요하다', () {
      expect(buildMember().needsConsentConfirmation, isTrue);
    });

    test('확인 기록이 있으면 더 묻지 않는다', () {
      final member = buildMember(confirmedAt: DateTime(2026, 8, 10));
      expect(member.needsConsentConfirmation, isFalse);
    });

    test('copyWith 로 다른 필드를 고쳐도 확인 기록은 보존된다', () {
      // 수정 화면이 이름만 바꿨는데 확인 기록이 날아가면, 동의 근거가 사라진
      // 회원이 조용히 생긴다.
      final confirmed = buildMember(confirmedAt: DateTime(2026, 8, 10));
      final renamed = confirmed.copyWith(name: '김철수');

      expect(renamed.needsConsentConfirmation, isFalse);
      expect(renamed.offlineConsentConfirmedAt, confirmed.offlineConsentConfirmedAt);
    });
  });
}
