/// 센터 PT 규정 FAQ provider — Phase 3.2 (C2).
///
/// 회원 FAQ 화면의 "PT 규정" 섹션이 watch 한다. 실패(미설정/네트워크)·빈 결과는
/// 화면이 "준비 중" 폴백으로 처리한다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_client.dart';
import '../../domain/models/faq_item.dart';
import 'center_faq_repository.dart';

final centerFaqRepositoryProvider = Provider<CenterFaqRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return CenterFaqRepository(client);
});

/// 본인 센터 PT 규정 FAQ 목록.
final centerPolicyFaqsProvider =
    FutureProvider.autoDispose<List<FaqItem>>((ref) async {
  return ref.watch(centerFaqRepositoryProvider).fetchPolicyFaqs();
});
