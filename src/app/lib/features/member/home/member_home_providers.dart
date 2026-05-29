/// 회원 홈 화면용 Riverpod provider.
///
/// - [memberHomeRepositoryProvider] : repository 인스턴스
/// - [memberHomeSummaryProvider]    : 홈 데이터(이름/다음수업/잔여) FutureProvider
///
/// 새로고침은 호출 측에서 `ref.invalidate(memberHomeSummaryProvider)` 로.
/// (예: 예약 신청 기능이 붙으면 신청 성공 후 invalidate → 다음 수업 갱신)
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import 'member_home_repository.dart';

final memberHomeRepositoryProvider = Provider<MemberHomeRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return MemberHomeRepository(client);
});

/// 회원 홈 요약 데이터.
///
/// AsyncValue 로 로딩/에러/데이터 분기를 화면이 그대로 받는다.
final memberHomeSummaryProvider =
    FutureProvider.autoDispose<MemberHomeSummary>((ref) async {
  return ref.watch(memberHomeRepositoryProvider).loadSummary();
});
