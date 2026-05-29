/// 회원 "받은 안내" 화면용 Riverpod provider.
///
/// - [memberNoticesRepositoryProvider] : repository 인스턴스
/// - [myNoticesProvider]               : 본인이 받은(sent) 안내 리스트
///
/// 새로고침은 `ref.invalidate(myNoticesProvider)` 로.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import 'member_notices_repository.dart';

final memberNoticesRepositoryProvider =
    Provider<MemberNoticesRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return MemberNoticesRepository(client);
});

/// 본인이 받은(sent) 안내 리스트.
final myNoticesProvider =
    FutureProvider.autoDispose<List<MemberNotice>>((ref) async {
  return ref.watch(memberNoticesRepositoryProvider).listMyNotices();
});
