/// 회원 "내 수업 기록" 화면용 Riverpod provider.
///
/// - [memberRecordsRepositoryProvider] : repository 인스턴스
/// - [myRecordsProvider]               : 본인 완료 수업 기록 리스트 FutureProvider
///
/// 새로고침은 `ref.invalidate(myRecordsProvider)` 로(당겨서 새로고침/재시도).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import 'member_records_repository.dart';

final memberRecordsRepositoryProvider =
    Provider<MemberRecordsRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return MemberRecordsRepository(client);
});

/// 본인 완료(done) 수업 기록 리스트.
final myRecordsProvider =
    FutureProvider.autoDispose<List<MemberSessionRecord>>((ref) async {
  return ref.watch(memberRecordsRepositoryProvider).listMyRecords();
});
