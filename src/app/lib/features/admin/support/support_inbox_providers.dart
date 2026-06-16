/// 운영자 문의함 provider + 처리 액션.
///
/// - [supportInboxRepositoryProvider] : 문의함 repository
/// - [supportInquiriesProvider]       : 전체 문의 목록(미처리 우선)
/// - [openInquiryCountProvider]       : 미처리 건수(관리자 대시보드 배지)
/// - [markInquiryHandledControllerProvider] : 처리완료 표시 액션
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import 'support_inbox_repository.dart';

final supportInboxRepositoryProvider = Provider<SupportInboxRepository>((ref) {
  return SupportInboxRepository(ref.watch(supabaseClientProvider));
});

/// 전체 문의 목록. 문의함 화면에서 watch.
final supportInquiriesProvider =
    FutureProvider.autoDispose<List<SupportInquiry>>((ref) async {
  return ref.watch(supportInboxRepositoryProvider).fetchAll();
});

/// 미처리 문의 건수 — 관리자 대시보드의 "문의함" 배지용.
///
/// open 상태 id 만 가볍게 조회(본문 미로드). RLS 로 운영자는 전체, 그 외엔 본인 것만.
final openInquiryCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final rows = await ref
      .watch(supabaseClientProvider)
      .from('support_inquiries')
      .select('id')
      .eq('status', 'open');
  return (rows as List).length;
});

/// 문의 처리완료 표시 컨트롤러. 성공 시 목록·배지 invalidate.
class MarkInquiryHandledController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> markHandled(String id) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(supportInboxRepositoryProvider).markHandled(id);
    });
    if (!state.hasError) {
      ref.invalidate(supportInquiriesProvider);
      ref.invalidate(openInquiryCountProvider);
    }
  }
}

final markInquiryHandledControllerProvider =
    AutoDisposeAsyncNotifierProvider<MarkInquiryHandledController, void>(
  MarkInquiryHandledController.new,
);
