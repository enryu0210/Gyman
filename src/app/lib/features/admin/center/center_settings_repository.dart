/// 관리자 센터 설정 repository — Phase 3.2 (C2 전반부).
///
/// 두 가지를 다룬다:
///   1. 센터 규정(`centers.rules`) 읽기/저장 — [CenterRules].
///   2. 센터별 PT 규정 FAQ(`center_faqs`) CRUD.
///
/// 권한: 모두 본인 센터로 RLS(0031) 가 범위를 좁힌다.
///   - 센터 id 는 admin_profiles(본인 행, admin_self_read)에서 얻는다.
///   - FAQ INSERT 는 center_id 를 안 넘긴다 → DB DEFAULT current_admin_center_id()
///     가 채우고, WITH CHECK 가 위변조를 막는다(0028 회원 패턴과 동일 취지).
///
/// 참고: src/supabase/migrations/0031_center_settings.sql, 0002(centers.rules).
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/models/center_rules.dart';

// =====================================================================
// 모델
// =====================================================================

/// 센터 PT 규정 FAQ 한 항목.
class CenterFaq {
  final String id;
  final String question;
  final String answer;
  final int sortOrder;

  const CenterFaq({
    required this.id,
    required this.question,
    required this.answer,
    required this.sortOrder,
  });
}

/// 센터 설정 화면이 한 번에 그리는 데이터 묶음.
class CenterSettings {
  final String centerId;
  final String centerName;
  final CenterRules rules;

  /// 노출 순서(sort_order) 오름차순 FAQ 목록.
  final List<CenterFaq> faqs;

  const CenterSettings({
    required this.centerId,
    required this.centerName,
    required this.rules,
    required this.faqs,
  });
}

// =====================================================================
// Repository
// =====================================================================

class CenterSettingsRepository {
  final SupabaseClient _client;
  CenterSettingsRepository(this._client);

  static const _centersTable = 'centers';
  static const _faqsTable = 'center_faqs';
  static const _adminTable = 'admin_profiles';

  static const _faqColumns = 'id, question, answer, sort_order';

  /// 설정 화면 데이터 로드(센터 정보 + 규정 + FAQ).
  ///
  /// 관리자 프로필이 없으면(겸직 아님 등) [StateError]. 화면은 에러로 처리.
  Future<CenterSettings> loadSettings() async {
    final centerId = await _fetchAdminCenterId();
    if (centerId == null) {
      throw StateError('관리자 센터를 찾을 수 없습니다. admin_profiles 등록을 확인하세요.');
    }

    // 센터 정보(이름/규정)와 FAQ 목록을 병렬 로드.
    final results = await Future.wait([
      _fetchCenter(centerId),
      _fetchFaqs(),
    ]);

    final center = results[0] as Map<String, dynamic>;
    final faqs = results[1] as List<CenterFaq>;

    return CenterSettings(
      centerId: centerId,
      centerName: (center['name'] as String?) ?? '',
      rules: CenterRules.fromJson(
        (center['rules'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      faqs: faqs,
    );
  }

  /// 본인 관리 센터 id. admin_self_read RLS 로 본인 1행만 조회.
  Future<String?> _fetchAdminCenterId() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final row = await _client
        .from(_adminTable)
        .select('center_id')
        .eq('user_id', userId)
        .maybeSingle();
    return row?['center_id'] as String?;
  }

  Future<Map<String, dynamic>> _fetchCenter(String centerId) async {
    return _client
        .from(_centersTable)
        .select('id, name, rules')
        .eq('id', centerId)
        .single();
  }

  Future<List<CenterFaq>> _fetchFaqs() async {
    final rows = await _client
        .from(_faqsTable)
        .select(_faqColumns)
        .isFilter('deleted_at', null)
        .order('sort_order', ascending: true);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(_faqFromRow)
        .toList(growable: false);
  }

  // ---------------------------------------------------------------------
  // 쓰기
  // ---------------------------------------------------------------------

  /// 센터 규정 저장. RLS centers_admin_update 가 본인 센터만 허용.
  Future<void> updateRules(String centerId, CenterRules rules) async {
    await _client
        .from(_centersTable)
        .update({'rules': rules.toJson()})
        .eq('id', centerId);
  }

  /// FAQ 추가. center_id 는 DB DEFAULT(current_admin_center_id) 가 채운다.
  Future<void> addFaq({
    required String question,
    required String answer,
    int sortOrder = 0,
  }) async {
    await _client.from(_faqsTable).insert({
      'question': question,
      'answer': answer,
      'sort_order': sortOrder,
    });
  }

  /// FAQ 수정.
  Future<void> editFaq({
    required String id,
    required String question,
    required String answer,
    required int sortOrder,
  }) async {
    await _client.from(_faqsTable).update({
      'question': question,
      'answer': answer,
      'sort_order': sortOrder,
    }).eq('id', id);
  }

  /// FAQ 삭제(소프트 — deleted_at 채움). 회원/트레이너 read 정책이 즉시 가려준다.
  Future<void> deleteFaq(String id) async {
    await _client
        .from(_faqsTable)
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', id);
  }

  // ---------------------------------------------------------------------
  // 매핑
  // ---------------------------------------------------------------------

  static CenterFaq _faqFromRow(Map<String, dynamic> row) {
    return CenterFaq(
      id: row['id'] as String,
      question: row['question'] as String,
      answer: row['answer'] as String,
      sortOrder: (row['sort_order'] as num).toInt(),
    );
  }
}
