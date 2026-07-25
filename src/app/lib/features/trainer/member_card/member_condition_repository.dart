/// 회원 체형 제약(`member_conditions`) read/write wrapper — 트레이너 시점.
/// (동작 습관·체형 제약 코칭 L1-a — docs/design_movement_coaching.md)
///
/// **가시성:** 회원도 본인 제약을 볼 수 있다(RLS `member_cond_member_read`).
///   다만 `trainer_note` 는 트레이너 전용이라, **회원 측 조회를 구현할 때(L1-b)는
///   SELECT 목록에서 trainer_note 를 반드시 빼야 한다** — PG RLS 는 행 단위라
///   컬럼을 가리지 못하므로 컬럼 단위 방어가 유일한 수단이다(`next_memo` 선례).
///   본 repository 는 트레이너용이므로 전 컬럼을 조회한다.
///
/// 참고: src/supabase/migrations/0036_member_conditions.sql
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/models/member_condition.dart';

class MemberConditionRepository {
  final SupabaseClient _client;
  MemberConditionRepository(this._client);

  static const _table = 'member_conditions';

  /// 조회 컬럼 — 테이블에 컬럼을 추가하면 **이 문자열도 같이 갱신**할 것.
  /// 빠뜨리면 매핑은 통과하고 그 필드만 조용히 null 이 된다(CLAUDE.md 사례).
  static const _columns = 'id, member_id, code, label, source, member_note, '
      'trainer_note, active, recorded_by, created_at, updated_at';

  /// PG unique_violation SQLSTATE — 같은 회원에 같은 제약이 이미 활성일 때.
  static const _uniqueViolation = '23505';

  /// 회원 1명의 제약 전체(해제된 이력 포함).
  ///
  /// 정렬: 활성 먼저 → 최근 등록 먼저. 트레이너가 "지금 유효한 것"을 먼저 보게 한다.
  /// RLS 가 본인 담당 회원만 노출한다.
  Future<List<MemberCondition>> listForMember(String memberId) async {
    final rows = await _client
        .from(_table)
        .select(_columns)
        .eq('member_id', memberId)
        .order('active', ascending: false)
        .order('created_at', ascending: false);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(MemberCondition.fromRow)
        .toList(growable: false);
  }

  /// 제약 1건 등록. recorded_by 는 호출(컨트롤러)이 현재 트레이너 user_id 로 주입.
  /// 반환: 생성된 행 id.
  ///
  /// 같은 회원에 같은 코드가 이미 활성이면 DB 부분 유니크 인덱스에 걸린다 →
  /// 원문 PG 에러 대신 사람이 읽을 수 있는 메시지로 바꿔 던진다.
  Future<String> add({
    required MemberCondition condition,
    required String recordedBy,
  }) async {
    final payload = condition.toInsertPayload()..['recorded_by'] = recordedBy;
    try {
      final row =
          await _client.from(_table).insert(payload).select('id').single();
      return row['id'] as String;
    } on PostgrestException catch (e) {
      if (e.code == _uniqueViolation) {
        throw StateError('이미 등록된 항목입니다. 기존 항목을 수정하거나 해제 후 다시 등록해 주세요.');
      }
      rethrow;
    }
  }

  /// 제약 해제/재적용 — 삭제 대신 active 토글로 이력을 남긴다.
  ///
  /// 재적용(active=true) 시 같은 코드가 이미 활성이면 유니크 인덱스에 걸리므로
  /// [add] 와 같은 방식으로 메시지를 바꿔 던진다.
  Future<void> setActive({required String id, required bool active}) async {
    try {
      await _client.from(_table).update({'active': active}).eq('id', id);
    } on PostgrestException catch (e) {
      if (e.code == _uniqueViolation) {
        throw StateError('같은 항목이 이미 적용 중입니다. 기존 항목을 먼저 해제해 주세요.');
      }
      rethrow;
    }
  }

  /// 제약 1건 삭제(하드 삭제 — 잘못 등록한 항목 제거용).
  /// 이력을 남기려면 [setActive] 로 해제할 것.
  Future<void> delete(String id) async {
    await _client.from(_table).delete().eq('id', id);
  }
}
