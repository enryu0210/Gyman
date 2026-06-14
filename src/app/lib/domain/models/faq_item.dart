/// FAQ(자주 묻는 질문) 도메인 모델 — S3 / Phase 2.4.
///
/// **설계 배경(기획서 답변 13):** 회원이 트레이너에게 반복해서 묻는 질문을
/// 두 갈래로 나눠 운영한다.
///   1. 운동 상식([FaqCategory.exercise]) — 모든 센터 공통, 앱 내장 정적 데이터.
///   2. PT 규정([FaqCategory.ptPolicy]) — 센터마다 달라 별도 입력이 필요(환불·
///      취소·프로그램 규정 등). **Phase 3 관리자 앱**에서 센터별로 입력하도록
///      나중에 붙인다(현재는 enum 자리만 열어둠).
///
/// 현재(2.4)는 운동 상식만 정적으로 제공하므로 외부 의존(DB/LLM)이 전혀 없다.
/// 그래서 도메인 순수 Dart 로만 모델을 두고, 실제 콘텐츠 시드는
/// `features/faq/exercise_faq_data.dart` 에 co-locate 한다.
///
/// 참고: docs/develop_plan.md §4 Phase 2.4, assets 인터뷰 답변 13.
library;

// =====================================================================
// FaqCategory — FAQ 분류
// =====================================================================
/// FAQ 분류. 운영 주체와 출처가 갈리기 때문에 분리한다.
enum FaqCategory {
  /// 운동 상식 — 센터 무관 공통. 앱 내장 정적 데이터(2.4에서 제공).
  exercise,

  /// PT 규정 — 센터별로 다름(환불/취소/프로그램). Phase 3 관리자 입력 예정.
  /// 현재는 노출 콘텐츠가 없어 화면에서 "준비 중" 안내만 보여준다.
  ptPolicy,
}

extension FaqCategoryLabel on FaqCategory {
  /// 화면 섹션 제목으로 쓰는 한국어 라벨.
  String get label {
    switch (this) {
      case FaqCategory.exercise:
        return '운동 상식';
      case FaqCategory.ptPolicy:
        return 'PT 규정';
    }
  }
}

// =====================================================================
// FaqItem — 질문 1건
// =====================================================================
/// FAQ 한 항목(질문 + 답변 + 분류).
///
/// 검수 게이트가 없는 정적 콘텐츠라 답변은 단정적 의학 조언을 피하고
/// "일반적인 가이드 + 개인차 있으니 트레이너 상담" 톤으로 작성한다
/// (시드 데이터 작성 원칙).
class FaqItem {
  const FaqItem({
    required this.question,
    required this.answer,
    required this.category,
  });

  final String question;
  final String answer;
  final FaqCategory category;
}
