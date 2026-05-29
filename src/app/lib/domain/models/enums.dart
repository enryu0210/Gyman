/// 도메인 레벨에서 쓰이는 enum 정의.
///
/// Supabase의 PostgreSQL ENUM과 1:1 대응 (`src/supabase/migrations/0001_init_enums.sql`).
/// DB 문자열과의 변환 책임은 data 계층(repository)에 둔다 — 도메인은 enum만 안다.
///
/// 왜 도메인에 두는가:
///   - 차감 규칙(`SessionStatus.deducts`) 같은 비즈니스 룰이 enum에 자연스럽게 붙음
///   - 외부(Flutter/Supabase) 의존 없이 단위 테스트 가능
library;

// =====================================================================
// UserRole — 사용자 역할 (트레이너/회원/관리자)
// =====================================================================
/// 사용자 역할. Supabase의 `user_role` ENUM과 1:1.
///
/// **판정 방법:**
///   클라이언트는 본인의 trainer_profiles / member_profiles 행 존재 여부로 판정.
///   DB의 `current_user_role()` 함수와 동일한 로직 (data_model.md §3.1).
///   admin은 Phase 3에서 추가 — 현재는 미사용.
///
/// 참고: docs/data_model.md §2.1 user_role ENUM,
///       docs/develop_plan.md §3 라우트 맵 (역할별 진입 화면).
enum UserRole {
  /// 트레이너 — `/trainer/*` 라우트로 진입.
  trainer,

  /// 회원 — `/member/*` 라우트로 진입.
  member,

  /// 관리자 — `/admin/*` 라우트 (Phase 3 활성).
  admin,
}

extension UserRoleRoute on UserRole {
  /// 로그인 직후 이동할 홈 경로.
  /// 라우터 redirect에서 사용.
  String get homeRoute {
    switch (this) {
      case UserRole.trainer:
        return '/trainer/home';
      case UserRole.member:
        return '/member/home';
      case UserRole.admin:
        return '/admin/dashboard';
    }
  }
}

// =====================================================================
// SessionStatus — 수업 1건의 상태
// =====================================================================
/// 수업 상태. 신청 → 예약 → 완료/노쇼/취소 전이.
///
/// 차감 규칙 (잔여 횟수에서 빠지는가):
///   - done, noShow, lateCancel → 차감 O
///   - requested, scheduled, canceled → 차감 X
///
/// 참고: docs/data_model.md §2.1, SQL `session_status` ENUM.
enum SessionStatus {
  /// 회원이 신청했으나 트레이너 미승인 (회원 로드맵 ⑤).
  /// 트레이너가 승인하면 [scheduled], 거절하면 행 삭제. 잔여 횟수 미차감.
  requested,

  /// 예약됨(확정) — 아직 진행 전.
  scheduled,

  /// 완료 — 트레이너가 수업 기록을 저장한 상태.
  done,

  /// 노쇼 — 회원이 안 옴. 차감 대상.
  noShow,

  /// 정상 취소 — 규정 시간 내 취소. 차감 X.
  canceled,

  /// 당일/지각 취소 — 규정 위반 취소. 차감 대상.
  lateCancel,
}

/// SessionStatus의 비즈니스 룰 헬퍼.
///
/// extension으로 둔 이유: enum 자체에 메서드를 추가하면 직렬화/역직렬화 시
/// 가독성이 떨어지고, 룰이 늘어났을 때 한 곳에 모이지 않게 됨.
extension SessionStatusRule on SessionStatus {
  /// 이 상태가 잔여 횟수에서 차감되는가.
  ///
  /// 예시:
  ///   - SessionStatus.done.deducts        → true
  ///   - SessionStatus.noShow.deducts      → true
  ///   - SessionStatus.lateCancel.deducts  → true
  ///   - SessionStatus.scheduled.deducts   → false
  ///   - SessionStatus.requested.deducts   → false
  ///   - SessionStatus.canceled.deducts    → false
  bool get deducts {
    switch (this) {
      case SessionStatus.done:
      case SessionStatus.noShow:
      case SessionStatus.lateCancel:
        return true;
      case SessionStatus.requested:
      case SessionStatus.scheduled:
      case SessionStatus.canceled:
        return false;
    }
  }

  /// 이 상태가 "완료된" 수업인가 (실제 진행됨).
  /// 평균 주당 빈도 계산 시 done만 카운트할지, 차감 전체를 셀지 정책이 갈리는데
  /// 본 도메인은 done만 "실제 수업"으로 본다.
  bool get isCompleted => this == SessionStatus.done;
}

// =====================================================================
// NoteVisibility — 회원 메모의 가시성
// =====================================================================
/// 트레이너가 작성한 회원 메모의 노출 범위.
///
/// **본 제품의 핵심 안전장치**: trainerOnly로 표시된 메모는
/// 회원에게 절대 노출되면 안 된다 (기획서 답변 9). 1차 방어는 Supabase RLS
/// (`notes_member_deny` 정책), 2차 방어가 이 도메인 enum이다.
///
/// 참고: docs/data_model.md §3.2 member_notes RLS.
enum NoteVisibility {
  /// 트레이너만 볼 수 있음 (회원/타 트레이너 차단).
  trainerOnly,

  /// 회원도 볼 수 있는 코칭 노트 (향후 확장용 — 현재는 미사용).
  shared,
}

extension NoteVisibilityRule on NoteVisibility {
  /// 회원 본인이 이 메모를 볼 수 있는가.
  ///
  /// 예시:
  ///   - NoteVisibility.trainerOnly.isVisibleToMember → false
  ///   - NoteVisibility.shared.isVisibleToMember      → true
  bool get isVisibleToMember => this == NoteVisibility.shared;
}

// =====================================================================
// RenewalAlertLevel — 재등록 알림 단계
// =====================================================================
/// 재등록 시점 알림 단계.
///
/// 우선순위 (높음→낮음): expiring > fiveLeft > half > none
/// 한 계약이 동시에 여러 조건을 만족해도 가장 높은 단계 하나만 표시.
///
/// 참고: docs/data_model.md §2.1 `renewal_alert_level` ENUM,
///       develop_plan.md §4 1.7 재등록 알림 자동화.
enum RenewalAlertLevel {
  /// 알림 없음.
  none,

  /// 횟수 절반 소진.
  half,

  /// 5회 남음 (혹은 이하).
  fiveLeft,

  /// 곧 만료 — 기준: 7일 이내 만료 예상 OR end_date가 7일 이내.
  expiring,
}

// =====================================================================
// NoteSource — 메모 생성 출처 (AI-C)
// =====================================================================
/// 메모가 누구에 의해 생성됐는지.
///
/// 트레이너 검수 흐름 추적용:
///   manual → 트레이너가 직접 작성
///   aiDraft → AI 자동 초안 (트레이너 미확인)
///   aiConfirmed → AI 초안을 트레이너가 확인 (수정 여부 무관)
///
/// 참고: docs/data_model.md §2.1, AI-C 안전성.
enum NoteSource {
  manual,
  aiDraft,
  aiConfirmed,
}

// =====================================================================
// NotificationStatus — 발송 안내 메시지의 검수/발송 상태 (AI-B)
// =====================================================================
/// 회원 안내 메시지(`outgoing_notifications`)의 상태. Supabase `notification_status`
/// ENUM과 1:1 (`0001_init_enums.sql`).
///
/// **본 제품의 핵심 안전장치 (AI-B):**
///   "트레이너 검수 없이는 회원에게 안 간다"를 상태 흐름으로 강제한다.
///     draft → (트레이너 승인) → approved → (실제 발송) → sent
///                                                ↘ (보류) canceled
///   1차 방어는 DB (RLS `notif_member_read_sent_only` + CHECK `chk_sent_requires_approval`),
///   2차 방어가 이 도메인 enum 이다. ([NotificationStatus.isVisibleToMember])
///
/// 참고: docs/data_model.md §2.2, 와이어프레임 06_ai_review.md.
enum NotificationStatus {
  /// 초안 — 트레이너 검수 대기. 회원에게 절대 안 보임.
  draft,

  /// 트레이너 승인됨 — 발송 큐 대기. 아직 회원에게 안 보임.
  approved,

  /// 발송 완료 — 이때만 회원에게 노출.
  sent,

  /// 보류/취소 — 발송 안 함. 회원에게 안 보임.
  canceled,
}

extension NotificationStatusRule on NotificationStatus {
  /// 회원 본인이 이 메시지를 볼 수 있는가. **sent 만** true.
  ///
  /// RLS `notif_member_read_sent_only` 와 동일 의미 — 미검수(draft)/승인 대기
  /// (approved)/취소(canceled)는 어떤 경우에도 회원에게 노출되지 않는다.
  ///
  /// 예시:
  ///   - NotificationStatus.sent.isVisibleToMember     → true
  ///   - NotificationStatus.draft.isVisibleToMember    → false
  ///   - NotificationStatus.approved.isVisibleToMember → false
  ///   - NotificationStatus.canceled.isVisibleToMember → false
  bool get isVisibleToMember => this == NotificationStatus.sent;

  /// 트레이너 검수 대기 상태인가 (초안). 홈의 "검수 N건" 카운트 기준.
  bool get isPendingReview => this == NotificationStatus.draft;
}
