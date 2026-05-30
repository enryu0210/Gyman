/// 방해금지(DND) 설정 read/write — 채팅 공용 (2.3).
///
/// - 트레이너: 본인 설정 조회/저장(trainer_self_rw, 0010).
/// - 회원(공용 ChatScreen): 상대(트레이너) user_id 의 DND 조회
///   (trainer_read_by_member, 0010/0013). 회원이 상대면 trainer_profiles 행이 없어 null.
///
/// 참고: 0025(dnd 컬럼·정책 정리), docs/develop_plan.md §4 2.3.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/dnd_settings.dart';

class DndRepository {
  final SupabaseClient _client;
  DndRepository(this._client);

  static const _table = 'trainer_profiles';
  static const _cols = 'dnd_enabled, dnd_start, dnd_end';

  /// 현재 로그인 트레이너 본인의 DND 설정. 행이 없으면 기본(off).
  Future<DndSettings> loadMine() async {
    final me = _client.auth.currentUser;
    if (me == null) return const DndSettings(enabled: false);
    final row = await _client
        .from(_table)
        .select(_cols)
        .eq('user_id', me.id)
        .maybeSingle();
    if (row == null) return const DndSettings(enabled: false);
    return DndSettings.fromRow(row);
  }

  /// 본인 DND 설정 저장.
  Future<void> saveMine(DndSettings settings) async {
    final me = _client.auth.currentUser;
    if (me == null) {
      throw StateError('로그인이 필요합니다.');
    }
    await _client
        .from(_table)
        .update(settings.toUpdatePayload())
        .eq('user_id', me.id);
  }

  /// 상대([peerUserId])의 DND 설정. 상대가 트레이너가 아니면(회원 등) null.
  /// 회원이 본인 트레이너를 조회할 때 사용(배너 표시 판단).
  Future<DndSettings?> loadForPeer(String peerUserId) async {
    final row = await _client
        .from(_table)
        .select(_cols)
        .eq('user_id', peerUserId)
        .maybeSingle();
    if (row == null) return null;
    return DndSettings.fromRow(row);
  }
}
