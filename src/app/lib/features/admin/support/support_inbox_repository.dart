/// 운영자 문의함 데이터 접근 — 문의 목록 조회 + 처리완료 표시.
///
/// 운톡 불만 #5 대응의 수신 측: 사용자가 [설정 > 문의하기]로 남긴 문의를
/// 운영자(관리자 프로필 보유자)가 여기서 확인한다. 조회/수정 권한은 RLS(0033)가
/// `admin_profiles` 보유 여부로 막는다 — 본 repository 는 평범히 select/update 만 한다.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

/// 문의 1건.
class SupportInquiry {
  final String id;
  final String? userId;
  final String? role;
  final String message;
  final String? appVersion;

  /// 'open'(미처리) | 'handled'(처리완료).
  final String status;
  final DateTime? createdAt;
  final DateTime? handledAt;

  const SupportInquiry({
    required this.id,
    required this.userId,
    required this.role,
    required this.message,
    required this.appVersion,
    required this.status,
    required this.createdAt,
    required this.handledAt,
  });

  bool get isOpen => status == 'open';

  static SupportInquiry _fromRow(Map<String, dynamic> r) => SupportInquiry(
        id: r['id'] as String,
        userId: r['user_id'] as String?,
        role: r['role'] as String?,
        message: (r['message'] as String?) ?? '',
        appVersion: r['app_version'] as String?,
        status: (r['status'] as String?) ?? 'open',
        createdAt: _parseDate(r['created_at']),
        handledAt: _parseDate(r['handled_at']),
      );

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString())?.toLocal();
  }
}

class SupportInboxRepository {
  final SupabaseClient _client;

  SupportInboxRepository(this._client);

  static const _columns =
      'id, user_id, role, message, app_version, status, created_at, handled_at';

  /// 전체 문의를 미처리 우선·최신순으로. (RLS 로 운영자만 전체가 보인다.)
  Future<List<SupportInquiry>> fetchAll() async {
    final rows = await _client
        .from('support_inquiries')
        .select(_columns)
        // 미처리(open)가 위로, 그 안에서 최신순.
        .order('status', ascending: true)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => SupportInquiry._fromRow(e as Map<String, dynamic>))
        .toList();
  }

  /// 문의를 처리완료로 표시.
  Future<void> markHandled(String id) async {
    await _client.from('support_inquiries').update({
      'status': 'handled',
      'handled_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }
}
