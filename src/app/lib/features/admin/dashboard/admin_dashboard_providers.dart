/// 관리자 대시보드용 Riverpod provider.
///
/// - [adminDashboardRepositoryProvider] : repository 인스턴스
/// - [adminDashboardProvider]           : 대시보드 데이터(요약/트레이너/만료임박)
///
/// 새로고침은 화면에서 `ref.invalidate(adminDashboardProvider)` 로(당겨서 새로고침).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import 'admin_dashboard_repository.dart';

final adminDashboardRepositoryProvider =
    Provider<AdminDashboardRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return AdminDashboardRepository(client);
});

/// 대시보드 데이터. AsyncValue 로 로딩/에러/데이터 분기를 화면이 그대로 받는다.
final adminDashboardProvider =
    FutureProvider.autoDispose<AdminDashboardData>((ref) async {
  return ref.watch(adminDashboardRepositoryProvider).loadDashboard();
});
