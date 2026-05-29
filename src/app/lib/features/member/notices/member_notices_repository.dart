/// 회원 본인 시점의 "받은 안내" 조회 repository (읽기 전용).
///
/// **무엇이 보이나 — sent 만:**
///   트레이너가 검수·승인 후 발송(sent)한 안내만 회원에게 보인다.
///   draft/approved/canceled 는 절대 노출되지 않는다. 1차 방어는 RLS
///   (`notif_member_read_sent_only`: target_member_id=current_member_profile_id()
///   AND status='sent'), 2차가 도메인 [NotificationStatus.isVisibleToMember].
///   → 쿼리에서 굳이 status 필터를 안 걸어도 RLS가 sent 만 돌려준다(여기선 명시도 함).
///
/// **FCM 없이 in-app 전달:** 별도 푸시 채널 없이, 트레이너가 sent 로 전이하는
///   순간 이 화면에 나타난다(트레이너 `AiReviewRepository.markSent`).
///
/// 참고: docs/develop_plan.md §4 회원 로드맵 ④,
///       src/supabase/migrations/0007(outgoing_notifications)·0013(RLS).
library;

import 'package:supabase_flutter/supabase_flutter.dart';

// =====================================================================
// 표시용 모델
// =====================================================================

/// 회원이 받은 안내 1건.
class MemberNotice {
  final String id;

  /// 트리거 종류 원문(pre_session 등). 회원용 라벨은 [memberNoticeLabel].
  final String triggerType;

  /// 안내 본문.
  final String content;

  /// 실제 발송(전달) 시각. sent 전이 시 채워짐.
  final DateTime? sentAt;

  const MemberNotice({
    required this.id,
    required this.triggerType,
    required this.content,
    required this.sentAt,
  });
}

/// 트리거 종류 → **회원이 읽을** 친근한 분류 라벨.
///
/// 트레이너 쪽(`triggerTypeLabel`)보다 단순하게 묶는다 — 회원에겐 내부 트리거
/// 구분(절반/5회/만료)이 의미 없으므로 "재등록 안내"로 통합. 새 트리거가 와도
/// 화면이 깨지지 않게 default 는 일반 라벨.
String memberNoticeLabel(String triggerType) {
  switch (triggerType) {
    case 'pre_session':
      return '수업 안내';
    case 'renewal_half':
    case 'renewal_five_left':
    case 'renewal_expiring':
      return '재등록 안내';
    case 'late_cancel_notice':
      return '취소 안내';
    default:
      return '안내';
  }
}

// =====================================================================
// Repository
// =====================================================================

class MemberNoticesRepository {
  final SupabaseClient _client;
  MemberNoticesRepository(this._client);

  static const _table = 'outgoing_notifications';

  /// 본인이 받은(sent) 안내를 최신 발송순으로 조회.
  ///
  /// RLS가 본인 앞 + sent 만 노출하지만, 의도를 명확히 드러내려고 status 필터도 건다.
  Future<List<MemberNotice>> listMyNotices({int limit = 50}) async {
    final rows = await _client
        .from(_table)
        .select('id, trigger_type, content, sent_at')
        .eq('status', 'sent')
        .order('sent_at', ascending: false)
        .limit(limit);

    return (rows as List).cast<Map<String, dynamic>>().map((r) {
      return MemberNotice(
        id: r['id'] as String,
        triggerType: r['trigger_type'] as String,
        content: r['content'] as String,
        sentAt: _parseTimestamp(r['sent_at']),
      );
    }).toList(growable: false);
  }

  static DateTime? _parseTimestamp(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v as String);
  }
}
