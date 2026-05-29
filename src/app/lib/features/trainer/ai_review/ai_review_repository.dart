/// AI 검수 — 회원 안내 메시지(`outgoing_notifications`) read/write wrapper (Phase 1.9).
///
/// **범위 (1.9 검수 게이트):**
///   본 단계는 "검수 게이트"만 다룬다 — 큐에 쌓인 메시지 초안(draft)을 트레이너가
///   읽고 [approve]/[editContent]/[cancel] 하는 흐름. 초안을 만드는 두 경로가 있다:
///     1) 비-AI 기본 템플릿: 0016 의 pre_session cron (이미 적재)
///     2) AI 생성(AI-B): LLM Edge Function — 배포 파이프라인 준비 후 별도 진행
///   본 repository 는 (1)/(2) 어느 쪽이 만든 draft 든 동일하게 검수한다.
///
/// **핵심 안전장치:**
///   - status='sent' 로의 전이는 본 repository 가 하지 않는다(실발송 채널 없음).
///   - 트레이너 승인 없이는 회원에게 안 감 — RLS(notif_member_read_sent_only) +
///     CHECK(chk_sent_requires_approval) + 도메인 [NotificationStatus] 3중 방어.
///
/// 참고: docs/develop_plan.md §4 Phase 1.9, 와이어프레임 06_ai_review.md,
///       src/supabase/migrations/0007_init_outgoing_notifications.sql.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/models/enums.dart';

// =====================================================================
// NotificationStatus ↔ DB ENUM 문자열 변환
// =====================================================================

/// PG ENUM `notification_status` ↔ Dart [NotificationStatus].
/// 변환 책임을 data 계층에 모은다 (도메인은 enum 만 안다 — enums.dart 주석).
NotificationStatus _statusFromDb(String raw) {
  switch (raw) {
    case 'draft':
      return NotificationStatus.draft;
    case 'approved':
      return NotificationStatus.approved;
    case 'sent':
      return NotificationStatus.sent;
    case 'canceled':
      return NotificationStatus.canceled;
    default:
      // DB ENUM 에 새 값이 생겼는데 매핑을 안 했다면 조용히 넘기지 않고 실패.
      throw StateError('알 수 없는 notification_status 값: $raw');
  }
}

String _statusToDb(NotificationStatus status) {
  switch (status) {
    case NotificationStatus.draft:
      return 'draft';
    case NotificationStatus.approved:
      return 'approved';
    case NotificationStatus.sent:
      return 'sent';
    case NotificationStatus.canceled:
      return 'canceled';
  }
}

/// `trigger_type` 문자열을 트레이너가 읽을 한국어 라벨로.
///
/// trigger_type 은 DB 에서 자유 text 라(0007) enum 으로 못 박지 않고 매핑 + 폴백.
/// 새 트리거가 생겨도 화면이 깨지지 않게 default 는 원문 노출.
String triggerTypeLabel(String triggerType) {
  switch (triggerType) {
    case 'pre_session':
      return '내일 수업 안내';
    case 'renewal_half':
      return '재등록 — 절반 소진';
    case 'renewal_five_left':
      return '재등록 — 5회 남음';
    case 'renewal_expiring':
      return '재등록 — 만료 임박';
    case 'late_cancel_notice':
      return '당일 취소 안내';
    case 'manual':
      return '수동 작성';
    default:
      return triggerType;
  }
}

// =====================================================================
// 화면 표시용 모델 — 알림 1건 + 회원 표시명
// =====================================================================

/// 검수 화면 카드 1개에 필요한 데이터 묶음.
///
/// RenewalAlertItem / TrainerBookingRow 와 같은 결.
/// 화면은 본 객체만 받으면 카드/검수 다이얼로그를 그릴 수 있다.
class MessageDraft {
  final String id;
  final String memberId;
  final String memberName;

  /// 트리거 종류 원문 (pre_session 등). 라벨은 [triggerTypeLabel].
  final String triggerType;

  /// 실제 발송될 본문.
  final String content;

  final NotificationStatus status;

  /// AI 가 생성했는가 (false = 기본 템플릿/수동).
  final bool aiGenerated;

  /// 발송 예정 시각.
  final DateTime scheduledFor;

  final DateTime createdAt;

  const MessageDraft({
    required this.id,
    required this.memberId,
    required this.memberName,
    required this.triggerType,
    required this.content,
    required this.status,
    required this.aiGenerated,
    required this.scheduledFor,
    required this.createdAt,
  });
}

// =====================================================================
// AiReviewRepository
// =====================================================================

class AiReviewRepository {
  final SupabaseClient _client;
  AiReviewRepository(this._client);

  static const _table = 'outgoing_notifications';

  MessageDraft _fromRow(Map<String, dynamic> row) {
    final member = row['member_profiles'] as Map<String, dynamic>;
    return MessageDraft(
      id: row['id'] as String,
      memberId: member['id'] as String,
      memberName: member['name'] as String,
      triggerType: row['trigger_type'] as String,
      content: row['content'] as String,
      status: _statusFromDb(row['status'] as String),
      aiGenerated: (row['ai_generated'] as bool?) ?? false,
      scheduledFor: DateTime.parse(row['scheduled_for'] as String),
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  // ---------------------------------------------------------------------
  // 조회
  // ---------------------------------------------------------------------

  /// 검수 대상 메시지 = 아직 발송 안 된 것(draft + approved).
  ///
  /// draft = 검수 대기, approved = 승인됐으나 발송 대기(실발송 채널 준비 전엔 여기 머묾).
  /// sent/canceled 는 검수 큐에서 제외.
  ///
  /// 회원 이름은 target_member_id → member_profiles(id) FK 로 inner join.
  /// RLS(notif_trainer_rw)가 트레이너 본인 행만 노출하므로 별도 trainer 필터 불필요.
  ///
  /// 정렬: 발송 예정 빠른 순.
  Future<List<MessageDraft>> listPendingMessages() async {
    final rows = await _client
        .from(_table)
        .select('''
          id, target_member_id, trigger_type, content, status,
          ai_generated, scheduled_for, created_at,
          member_profiles!inner(id, name)
        ''')
        .inFilter('status', ['draft', 'approved'])
        .order('scheduled_for', ascending: true);

    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(_fromRow)
        .toList(growable: false);
  }

  // ---------------------------------------------------------------------
  // 변경 — 검수 액션
  // ---------------------------------------------------------------------

  /// 발송 승인 — status='approved', approved_at=now.
  ///
  /// approved_at 을 함께 채워 둔다: 이후 실발송 단계에서 sent 로 가려면
  /// CHECK(chk_sent_requires_approval) 가 approved_at 을 요구하기 때문.
  Future<void> approve(String id) async {
    await _client.from(_table).update({
      'status': _statusToDb(NotificationStatus.approved),
      'approved_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  /// 여러 건 일괄 승인 (와이어 6.1 "모두 발송 승인").
  /// 빈 리스트면 호출하지 않음(상위에서 가드).
  Future<void> approveMany(List<String> ids) async {
    if (ids.isEmpty) return;
    await _client.from(_table).update({
      'status': _statusToDb(NotificationStatus.approved),
      'approved_at': DateTime.now().toIso8601String(),
    }).inFilter('id', ids);
  }

  /// 보류/취소 — status='canceled'. 발송 큐에서 제외.
  Future<void> cancel(String id) async {
    await _client.from(_table).update({
      'status': _statusToDb(NotificationStatus.canceled),
    }).eq('id', id);
  }

  /// 내용 수정. **수정 시 항상 draft 로 되돌린다** (재검수 강제).
  ///
  /// 와이어 6.2: "내용 수정 → status='draft' 유지". 승인 후 수정한 경우에도
  /// 승인을 무효화(approved_at=null)해서 "검수 안 된 내용이 승인 상태로 남는" 구멍을 막음.
  Future<void> editContent({
    required String id,
    required String content,
  }) async {
    await _client.from(_table).update({
      'content': content,
      'status': _statusToDb(NotificationStatus.draft),
      'approved_at': null,
    }).eq('id', id);
  }

  // ---------------------------------------------------------------------
  // AI 초안 생성 (AI-B) — Edge Function 호출
  // ---------------------------------------------------------------------

  /// `generate-message-draft` Edge Function 을 호출해 AI 메시지 초안을 생성한다.
  ///
  /// **LLM 키는 서버(시크릿)에만** 있으므로 클라이언트는 함수 호출만 한다.
  /// 서버가 동의 확인 / PII 마스킹 / 호출 한도 / Gemini 호출 / draft 적재를 모두 처리.
  /// 성공 시 생성된 draft id 반환(초안은 검수 큐에 status='draft' 로 쌓임).
  ///
  /// 실패는 [AiGenerationException] 으로 던진다(code 로 폴백 UX 분기):
  ///   - consent_required : 회원 AI 동의 없음
  ///   - rate_limited     : 일일 한도 초과
  ///   - llm_failed       : LLM/네트워크 오류 → 수동 작성 폴백 유도
  Future<String> generateMessageDraft({
    required String memberId,
    required String triggerType,
    String? tone,
    String? sessionId,
  }) async {
    try {
      final res = await _client.functions.invoke(
        'generate-message-draft',
        body: {
          'memberId': memberId,
          'triggerType': triggerType,
          // null-aware 맵 요소: 값이 null 이면 해당 키 자체가 빠짐.
          'tone': ?tone,
          'sessionId': ?sessionId,
        },
      );
      final data = res.data;
      if (data is Map && data['ok'] == true && data['draftId'] != null) {
        return data['draftId'] as String;
      }
      // 2xx 인데 ok=false 인 비정상 응답.
      throw AiGenerationException(
        code: (data is Map ? data['code'] as String? : null) ?? 'unknown',
        message: (data is Map ? data['message'] as String? : null) ??
            'AI 초안 생성에 실패했습니다.',
      );
    } on FunctionException catch (e) {
      // 함수가 4xx/5xx 를 반환하면 여기로. details 에 구조화된 본문(code/message)이 옴.
      final d = e.details;
      throw AiGenerationException(
        code: (d is Map ? d['code'] as String? : null) ?? 'unknown',
        message: (d is Map ? d['message'] as String? : null) ??
            'AI 초안 생성에 실패했습니다. (오류 ${e.status})',
      );
    }
  }
}

/// AI 초안 생성 실패 — [code] 로 폴백 UX 를 분기한다.
class AiGenerationException implements Exception {
  /// consent_required / rate_limited / llm_failed / unknown 등.
  final String code;

  /// 사용자에게 보여줄 한국어 메시지(서버 제공).
  final String message;

  AiGenerationException({required this.code, required this.message});

  @override
  String toString() => message;
}
