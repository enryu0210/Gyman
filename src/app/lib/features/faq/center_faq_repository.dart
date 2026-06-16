/// 센터 PT 규정 FAQ 조회 repository (회원/트레이너 읽기 전용) — Phase 3.2 (C2).
///
/// 관리자가 입력한 `center_faqs`(0031)를 읽어 회원 FAQ 화면의 "PT 규정" 섹션을
/// 채운다(2.4 에서 "준비 중"으로 비워둔 자리). RLS(center_faq_member_read /
/// _trainer_read)가 **본인 센터의 살아있는 FAQ만** 돌려주므로 center_id 필터 불필요.
///
/// 반환은 도메인 [FaqItem](category=ptPolicy)으로 매핑해 화면이 운동 상식과 동일한
/// 위젯으로 그리게 한다.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/faq_item.dart';

class CenterFaqRepository {
  final SupabaseClient _client;
  CenterFaqRepository(this._client);

  static const _table = 'center_faqs';

  /// 본인 센터 PT 규정 FAQ(노출 순서 오름차순). 없으면 빈 리스트.
  Future<List<FaqItem>> fetchPolicyFaqs() async {
    final rows = await _client
        .from(_table)
        .select('question, answer')
        .isFilter('deleted_at', null)
        .order('sort_order', ascending: true);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(
          (r) => FaqItem(
            question: r['question'] as String,
            answer: r['answer'] as String,
            category: FaqCategory.ptPolicy,
          ),
        )
        .toList(growable: false);
  }
}
