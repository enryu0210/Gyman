/// 회원 "받은 안내" 화면용 Riverpod provider.
///
/// - [memberNoticesRepositoryProvider] : repository 인스턴스
/// - [myNoticesProvider]               : 본인이 받은(sent) 안내 리스트
/// - [unreadNoticeCountProvider]       : 안읽음 개수(홈 배지) — 목록에서 파생
/// - [noticeReadControllerProvider]    : 읽음 처리 액션
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

/// 안읽음 개수 — 홈 "받은 안내 N" 배지용. 별도 count 쿼리 없이 [myNoticesProvider]
/// 결과에서 파생(베타 규모에선 목록 로드 비용 무시 가능). 로딩/에러 시 0.
final unreadNoticeCountProvider = Provider.autoDispose<int>((ref) {
  final async = ref.watch(myNoticesProvider);
  return async.maybeWhen(
    data: (list) => list.where((n) => !n.isRead).length,
    orElse: () => 0,
  );
});

/// 읽음 처리 컨트롤러 — 안내 카드 탭 시 호출.
///
/// 읽음 처리는 **비핵심**이라 실패해도 목록/화면엔 지장 없음(에러를 조용히 흡수).
/// 성공 시 [myNoticesProvider] 를 invalidate → 안읽음 배지·강조가 갱신된다.
class NoticeReadController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> markRead(String id) async {
    try {
      await ref.read(memberNoticesRepositoryProvider).markRead(id);
      ref.invalidate(myNoticesProvider);
    } catch (_) {
      // 읽음 처리 실패는 무시 — 다음 조회/탭에서 다시 시도된다.
    }
  }
}

final noticeReadControllerProvider =
    AutoDisposeAsyncNotifierProvider<NoticeReadController, void>(
  NoticeReadController.new,
);
