/// 회원 측 채팅 진입 providers (S2 / 2.3).
///
/// 회원은 상대(트레이너)를 직접 모르므로, 본인 계약에서 트레이너 user_id + 이름을
/// 해석해 [ChatScreen] 에 넘긴다. 계약/트레이너가 없으면 null → 화면이 안내.
///
/// RLS: 계약은 contract_member_read(본인 계약만), 트레이너 이름은
///   trainer_read_by_member(본인 트레이너만) 로 안전하게 조회된다(0013).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../auth/auth_providers.dart';
import '../../chat/chat_providers.dart';

/// 채팅 상대인 트레이너 정보.
class ChatPeerTrainer {
  final String userId;
  final String name;
  const ChatPeerTrainer({required this.userId, required this.name});
}

/// 본인의 담당 트레이너(가장 최근 계약 기준). 없으면 null.
final myTrainerProvider =
    FutureProvider.autoDispose<ChatPeerTrainer?>((ref) async {
  if (!ref.watch(isSupabaseReadyProvider)) return null;
  final user = ref.watch(authStateProvider).value;
  if (user == null) return null;

  final client = ref.watch(supabaseClientProvider);

  // 1) 본인 계약에서 트레이너 user_id (최근 시작 계약 우선).
  //    RLS(contract_member_read)가 본인 계약만 노출하므로 member_id 필터 불필요.
  final contractRow = await client
      .from('pt_contracts')
      .select('trainer_id, start_date')
      .order('start_date', ascending: false)
      .limit(1)
      .maybeSingle();
  final trainerId = contractRow?['trainer_id'] as String?;
  if (trainerId == null) return null;

  // 2) 트레이너 표시명. RLS(trainer_read_by_member)로 본인 트레이너만 조회 가능.
  final trainerRow = await client
      .from('trainer_profiles')
      .select('name')
      .eq('user_id', trainerId)
      .maybeSingle();
  final name = (trainerRow?['name'] as String?) ?? '트레이너';

  return ChatPeerTrainer(userId: trainerId, name: name);
});

/// 회원이 받은 안읽음 메시지 수(FutureProvider). 홈 진입 때마다 가볍게 재조회.
final memberUnreadTotalProvider =
    FutureProvider.autoDispose<int>((ref) async {
  if (!ref.watch(isSupabaseReadyProvider)) return 0;
  final user = ref.watch(authStateProvider).value;
  if (user == null) return 0;
  return ref.watch(chatRepositoryProvider).unreadCount();
});

/// 홈 배지용 — 로딩/에러 시 0 으로 폴백(배지를 안 띄움).
final memberUnreadCountProvider = Provider.autoDispose<int>((ref) {
  return ref.watch(memberUnreadTotalProvider).maybeWhen(
        data: (n) => n,
        orElse: () => 0,
      );
});
