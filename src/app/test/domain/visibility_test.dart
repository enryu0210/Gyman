import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/domain/models/enums.dart';

/// 메모 가시성 도메인 단위 테스트.
///
/// **스코프 한정:** 본 테스트는 [NoteVisibility] enum과 헬퍼의 일관성만 검증한다.
/// **실제 권한 차단(트레이너만 보임, 회원은 0건)은 Supabase RLS 통합 테스트가
/// 담당하며, 그건 별도 환경(supabase 로컬 또는 별도 Node.js 스크립트)에서 돌린다.**
///
/// 그럼에도 도메인 테스트가 필요한 이유:
///   - UI 레벨에서 "이 메모는 회원에게 보여줘도 되는가" 판단할 때 enum 헬퍼를 쓴다
///   - 향후 NoteVisibility 값이 늘었을 때(예: 'center_admin_only') 도메인이 먼저
///     일관성을 잡아주면 UI가 갈라지지 않는다
///   - RLS는 1차 방어, 도메인 enum은 2차 방어 (defense in depth)
///
/// 참고:
///   docs/data_model.md §3.2 member_notes RLS (1차 방어),
///   docs/data_model.md §7 RLS-1, RLS-12 (통합 테스트 시나리오 위치).
void main() {
  group('NoteVisibility.isVisibleToMember — 회원 노출 판정', () {
    test('trainerOnly는 회원에게 절대 안 보임', () {
      // 본 제품의 핵심 안전장치 — 이 검증이 깨지면 즉시 베타 중단 사유.
      expect(NoteVisibility.trainerOnly.isVisibleToMember, isFalse);
    });

    test('shared는 회원에게 보임', () {
      expect(NoteVisibility.shared.isVisibleToMember, isTrue);
    });
  });

  group('NoteVisibility — enum 완전성', () {
    test('현재 정의된 값은 trainerOnly / shared 두 가지뿐', () {
      // 새 값이 추가될 때 본 테스트가 실패하도록 → 추가 시 isVisibleToMember
      // 분기와 RLS 정책 동시 갱신을 강제.
      expect(NoteVisibility.values.length, 2);
      expect(NoteVisibility.values, contains(NoteVisibility.trainerOnly));
      expect(NoteVisibility.values, contains(NoteVisibility.shared));
    });

    test('모든 enum 값이 isVisibleToMember 분기를 가진다 (예외 없음)', () {
      // 호출 자체가 던지면 안 됨 — 모든 값에 대해 정의됐는지 확인.
      for (final v in NoteVisibility.values) {
        expect(() => v.isVisibleToMember, returnsNormally,
            reason: '$v에 isVisibleToMember 분기 누락');
      }
    });
  });

  group('NoteSource — AI 메모 출처 추적 일관성', () {
    test('현재 정의된 값은 manual / aiDraft / aiConfirmed 세 가지', () {
      // 새 출처가 추가될 때 본 테스트가 실패하도록 → 추가 시 UI(검수 화면)와
      // RLS 정책 영향도 확인 강제.
      expect(NoteSource.values.length, 3);
      expect(NoteSource.values, contains(NoteSource.manual));
      expect(NoteSource.values, contains(NoteSource.aiDraft));
      expect(NoteSource.values, contains(NoteSource.aiConfirmed));
    });
  });

  group('NotificationStatus.isVisibleToMember — 안내 메시지 노출 판정 (AI-B)', () {
    test('sent 만 회원에게 보임', () {
      // 발송 완료된 메시지만 회원 노출. RLS notif_member_read_sent_only 와 동일 의미.
      expect(NotificationStatus.sent.isVisibleToMember, isTrue);
    });

    test('draft / approved / canceled 는 회원에게 절대 안 보임', () {
      // 미검수(draft)·승인 대기(approved)·취소(canceled)가 회원에게 새면
      // 즉시 베타 중단 사유 — AI-B 핵심 안전장치.
      expect(NotificationStatus.draft.isVisibleToMember, isFalse);
      expect(NotificationStatus.approved.isVisibleToMember, isFalse);
      expect(NotificationStatus.canceled.isVisibleToMember, isFalse);
    });

    test('isPendingReview 는 draft 만 true (홈 검수 배지 기준)', () {
      expect(NotificationStatus.draft.isPendingReview, isTrue);
      expect(NotificationStatus.approved.isPendingReview, isFalse);
      expect(NotificationStatus.sent.isPendingReview, isFalse);
      expect(NotificationStatus.canceled.isPendingReview, isFalse);
    });

    test('정확히 하나(sent)만 회원 가시 — 가시 상태 과다 노출 회귀 방지', () {
      final visible =
          NotificationStatus.values.where((s) => s.isVisibleToMember).toList();
      expect(visible, [NotificationStatus.sent]);
    });
  });

  group('NotificationStatus — enum 완전성', () {
    test('현재 정의된 값은 draft / approved / sent / canceled 네 가지', () {
      // 새 값 추가 시 본 테스트 실패 → isVisibleToMember 분기 + RLS +
      // CHECK(chk_sent_requires_approval) 동시 점검 강제.
      expect(NotificationStatus.values.length, 4);
    });
  });

  group('SessionStatus 불변성 — 차감 룰 회귀 방지', () {
    // visibility 테스트 파일이지만, "도메인 enum 회귀 방지" 카테고리로 묶어
    // 룰 변경 시 1) 도메인 2) RLS 3) 마이그레이션 동기화를 강제한다.
    test('차감 대상 enum 셋이 정확히 done/noShow/lateCancel', () {
      final deducting = SessionStatus.values.where((s) => s.deducts).toSet();
      expect(
        deducting,
        {SessionStatus.done, SessionStatus.noShow, SessionStatus.lateCancel},
        reason: '차감 룰이 바뀌면 0011_triggers_views.sql의 view 식도 같이 갱신',
      );
    });

    test('requested(회원 신청)는 차감되지 않는다', () {
      // 신청만으로 잔여가 줄면 안 됨 — v_contract_status(0021) 와 동일 의미.
      expect(SessionStatus.requested.deducts, isFalse);
    });

    test('현재 정의된 값은 requested 포함 6가지', () {
      // 새 상태 추가 시 본 테스트 실패 → deducts 분기 + RLS + 마이그레이션 동시 점검.
      expect(SessionStatus.values.length, 6);
      expect(SessionStatus.values, contains(SessionStatus.requested));
    });
  });
}
