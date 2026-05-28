/// 재등록 알림 Riverpod providers (Phase 1.7).
///
/// **invalidation 정책:**
///   계약 추가/삭제 / sessions 상태 변경(수업 기록 저장, 노쇼/취소 등) 모두 알림에
///   영향 → 호출 측 컨트롤러가 본 provider 를 invalidate. 현재 cross-effect 가 있는 곳:
///     - contract: addContractController.* / softDelete
///     - session: createDone / editRecord / delete / createScheduled / changeStatus / cancel
///   각 컨트롤러에서 [trainerRenewalAlertsProvider] 를 함께 invalidate 한다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../auth/auth_providers.dart';
import 'renewal_alert_repository.dart';

final renewalAlertRepositoryProvider = Provider<RenewalAlertRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return RenewalAlertRepository(client);
});

/// 트레이너 본인의 모든 활성 계약 + 알림 단계 리스트.
/// 호출 측은 .where((i) => i.level != none) 같은 필터로 표시 후보를 추린다.
final trainerRenewalAlertsProvider =
    FutureProvider<List<RenewalAlertItem>>((ref) async {
  if (!ref.watch(isSupabaseReadyProvider)) return const [];
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const [];

  return ref.watch(renewalAlertRepositoryProvider).listForCurrentTrainer();
});
