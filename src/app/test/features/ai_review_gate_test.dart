/// AI 검수 흐름 게이트 — 상태 전이 payload 불변식 단위 테스트 (Phase 1 DoD 2).
///
/// draft → 승인(approved) → 발송(sent) 게이트의 클라이언트측 write payload 를
/// SupabaseClient 없이 순수 검증한다. 특히 "수정하면 승인이 무효화된다
/// (approved_at=null)"는 안전 불변식을 고정 — 이게 깨지면 미검수 내용이 승인
/// 상태로 남아 회원에게 새어나갈 수 있다.
///
/// AI-B 메시지 초안과 AI 재등록 유도 멘트(generate-renewal-pitch)가 모두 이
/// 동일 게이트를 공유하므로, 여기서 게이트를 잠그면 두 기능 모두 보호된다.
/// (DB 측 RLS/CHECK 강제는 마이그레이션 0007 검증 SQL 로 별도 확인.)
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/features/trainer/ai_review/ai_review_repository.dart';

void main() {
  final now = DateTime(2026, 7, 18, 9, 30);
  final nowIso = now.toIso8601String();

  group('상태 전이 payload', () {
    test('승인: status=approved + approved_at 채움 (sent 전이 CHECK 근거)', () {
      final p = AiReviewRepository.approvePayload(now);
      expect(p['status'], 'approved');
      expect(p['approved_at'], nowIso);
    });

    test('수정: draft 로 되돌리고 approved_at 을 null 로 — 미검수 승인 구멍 차단', () {
      final p = AiReviewRepository.editPayload('바뀐 본문');
      expect(p['content'], '바뀐 본문');
      expect(p['status'], 'draft');
      // 키가 존재하면서 값이 null 이어야 update 가 approved_at 을 실제로 비운다.
      // (키가 아예 빠지면 기존 approved_at 이 남아 "수정했는데 승인 유지" 구멍이 생김.)
      expect(p.containsKey('approved_at'), isTrue);
      expect(p['approved_at'], isNull);
    });

    test('발송: status=sent + sent_at + send_channel=in_app', () {
      final p = AiReviewRepository.markSentPayload(now);
      expect(p['status'], 'sent');
      expect(p['sent_at'], nowIso);
      expect(p['send_channel'], 'in_app');
    });

    test('발송 payload 는 approved_at 을 건드리지 않는다 (승인 시점 보존 → CHECK 유지)', () {
      final p = AiReviewRepository.markSentPayload(now);
      expect(p.containsKey('approved_at'), isFalse);
    });

    test('보류: status=canceled 만 (발송 흔적 없음)', () {
      final p = AiReviewRepository.cancelPayload();
      expect(p['status'], 'canceled');
      expect(p.containsKey('sent_at'), isFalse);
    });

    test('승인+발송(한 번에): status=sent + approved_at + sent_at + in_app', () {
      final p = AiReviewRepository.approveAndSendPayload(now);
      expect(p['status'], 'sent');
      expect(p['sent_at'], nowIso);
      expect(p['send_channel'], 'in_app');
      // 핵심 불변식: sent 로 가면서 approved_at 을 **같은 update 에** 채워야
      // DB CHECK(chk_sent_requires_approval)를 단일 원자 update 로 만족한다.
      // (안 채우면 draft→sent 직행이 CHECK 위반으로 거부됨.)
      expect(p['approved_at'], nowIso);
      expect(p['approved_at'], isNotNull);
    });
  });

  group('triggerTypeLabel — 트리거 라벨 매핑', () {
    test('renewal_pitch → "재등록 유도(AI)"', () {
      expect(triggerTypeLabel('renewal_pitch'), '재등록 유도(AI)');
    });

    test('기존 트리거 라벨 유지', () {
      expect(triggerTypeLabel('pre_session'), '내일 수업 안내');
      expect(triggerTypeLabel('renewal_expiring'), '재등록 — 만료 임박');
    });

    test('모르는 트리거는 원문 폴백 (화면 안 깨짐)', () {
      expect(triggerTypeLabel('some_new_trigger'), 'some_new_trigger');
    });
  });
}
