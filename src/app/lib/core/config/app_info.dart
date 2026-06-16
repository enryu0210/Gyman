/// 앱 메타 정보 상수.
///
/// pubspec.yaml 의 version 과 **수동 동기화** — package_info_plus 의존성을 추가하지
/// 않기 위해 상수로 둔다(develop_plan §0 의존성 고정). 버전 올릴 때 같이 갱신할 것.
///
/// 약관/개인정보 버전은 문서 개정 추적용 — 본문을 고치면 날짜를 올려 재동의를
/// 유도할 수 있다(user_consents 테이블, 0034).
library;

/// 앱 표시 버전. 문의 전송 시 함께 보내 재현 추적에 사용.
/// ⚠ pubspec.yaml `version:` 과 일치시킬 것.
const String kAppVersion = '1.0.0';

/// 이용약관 버전(개정일). 본문 수정 시 함께 올린다.
const String kTermsVersion = '2026-06-16';

/// 개인정보 처리방침 버전(개정일). 본문 수정 시 함께 올린다.
const String kPrivacyVersion = '2026-06-16';
