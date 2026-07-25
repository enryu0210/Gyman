/// 코칭 큐 Riverpod providers — 역할 공용 (L1-b).
///
/// - [coachingRulesProvider]        : 회원 화면용 규칙(상세 제외)
/// - [coachingRulesWithDetailProvider] : 트레이너 화면용 규칙(상세 포함)
/// - [myConditionsProvider]         : 회원 본인의 활성 제약
///
/// 큐 조합 자체는 provider 가 아니라 순수 함수([CoachingCueSelector])가 한다 —
/// 입력(제약·규칙·패턴)이 화면에서 실시간으로 바뀌므로, 타이핑마다 provider 를
/// 만드는 대신 이미 받아둔 목록으로 그 자리에서 계산하는 편이 단순하고 빠르다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_client.dart';
import '../../domain/coaching_cue.dart';
import '../../domain/models/member_condition.dart';
import '../auth/auth_providers.dart';
import 'coaching_repository.dart';

final coachingRuleRepositoryProvider = Provider<CoachingRuleRepository>((ref) {
  return CoachingRuleRepository(ref.watch(supabaseClientProvider));
});

final myConditionRepositoryProvider = Provider<MyConditionRepository>((ref) {
  return MyConditionRepository(ref.watch(supabaseClientProvider));
});

/// 큐 규칙 — 회원 화면용(트레이너용 `detail` 제외).
final coachingRulesProvider = FutureProvider<List<CoachingRule>>((ref) async {
  if (!ref.watch(isSupabaseReadyProvider)) return const [];
  if (ref.watch(authStateProvider).value == null) return const [];
  return ref.watch(coachingRuleRepositoryProvider).listAll();
});

/// 큐 규칙 — 트레이너 화면용(`detail` 포함).
final coachingRulesWithDetailProvider =
    FutureProvider<List<CoachingRule>>((ref) async {
  if (!ref.watch(isSupabaseReadyProvider)) return const [];
  if (ref.watch(authStateProvider).value == null) return const [];
  return ref.watch(coachingRuleRepositoryProvider).listAll(includeDetail: true);
});

/// 회원 본인의 활성 체형 제약.
final myConditionsProvider = FutureProvider<List<MemberCondition>>((ref) async {
  if (!ref.watch(isSupabaseReadyProvider)) return const [];
  if (ref.watch(authStateProvider).value == null) return const [];
  return ref.watch(myConditionRepositoryProvider).listMine();
});
