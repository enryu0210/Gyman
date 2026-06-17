/// PT 알림용 조회 — 다가올 예약(scheduled) 수업 시작 시각 목록.
///
/// 알림 스케줄러가 "언제 알릴지" 계산하려면 본인의 확정 예약 시각만 있으면 된다.
/// RLS(sessions_member_read)가 본인 수업만 노출하므로 member_id 필터 불필요.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

class PtReminderRepository {
  final SupabaseClient _client;
  PtReminderRepository(this._client);

  /// 지금 이후 확정(scheduled) 수업의 시작 시각 목록(가까운 순, 최대 50건).
  Future<List<DateTime>> fetchUpcomingSessionStarts() async {
    // 다른 회원 화면과 동일 컨벤션: naive local ISO 로 경계 비교(member_home 참조).
    final nowIso = DateTime.now().toIso8601String();
    final rows = await _client
        .from('sessions')
        .select('scheduled_at')
        .eq('status', 'scheduled')
        .gte('scheduled_at', nowIso)
        .order('scheduled_at', ascending: true)
        .limit(50);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map((r) => DateTime.parse(r['scheduled_at'] as String))
        .toList(growable: false);
  }
}
