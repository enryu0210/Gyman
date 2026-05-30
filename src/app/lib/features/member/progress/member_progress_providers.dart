/// 회원 "변화 추이" 화면용 Riverpod provider (S1 / 2.2).
///
/// - [memberProgressRepositoryProvider] : repository 인스턴스
/// - [myProgressProvider]               : 본인 중량+인바디 데이터 FutureProvider
///
/// 새로고침은 `ref.invalidate(myProgressProvider)`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import 'member_progress_repository.dart';

final memberProgressRepositoryProvider =
    Provider<MemberProgressRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return MemberProgressRepository(client);
});

/// 본인 변화 추이 데이터(중량 + 인바디).
final myProgressProvider = FutureProvider.autoDispose<ProgressData>((ref) async {
  return ref.watch(memberProgressRepositoryProvider).loadMyProgress();
});
