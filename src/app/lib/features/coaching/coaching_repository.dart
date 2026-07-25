/// 코칭 큐 데이터 접근 — 역할 공용 (L1-b).
/// docs/design_movement_coaching.md
///
/// 두 가지를 읽는다:
///   1. [CoachingRuleRepository] — 큐 규칙(공통 시드 + 본인 센터). 역할 무관.
///   2. [MyConditionRepository]  — **회원 본인**의 체형 제약.
///
/// **왜 회원용 제약 조회를 따로 두나:**
///   트레이너용(`member_card/member_condition_repository.dart`)은 전 컬럼을 읽지만,
///   회원용은 `trainer_note` 를 **SELECT 목록에서 빼야 한다.** PG RLS 는 행 단위라
///   컬럼을 가리지 못하므로, 컬럼 단위 방어가 유일한 수단이다
///   (`session_records.next_memo` 선례 — CLAUDE.md).
///   같은 repository 를 공유했다면 이 구분이 사라진다.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/coaching_cue.dart';
import '../../domain/models/member_condition.dart';

/// 큐 규칙 조회 — 공통 시드(center_id IS NULL) + 본인 센터 규칙.
/// 범위 판정은 전부 RLS(`coaching_rules_read`, 0037)가 한다.
class CoachingRuleRepository {
  final SupabaseClient _client;
  CoachingRuleRepository(this._client);

  static const _table = 'condition_coaching_rules';

  /// 회원 화면용 컬럼 — `detail`(트레이너용 상세) 제외.
  static const _memberColumns =
      'id, center_id, condition_code, movement_pattern, action, cue';

  /// 트레이너 화면용 컬럼 — `detail` 포함.
  static const _trainerColumns = '$_memberColumns, detail';

  /// 읽을 수 있는 규칙 전부.
  ///
  /// 규칙 수가 수십 건 규모라 전량 조회 후 앱에서 매칭한다(제약·패턴 조합이
  /// 화면에서 실시간으로 바뀌므로 조건별 재조회가 오히려 왕복을 늘린다).
  ///
  /// [includeDetail] 은 트레이너 화면에서만 true — 회원에게 상세를 노출하지 않는다.
  Future<List<CoachingRule>> listAll({bool includeDetail = false}) async {
    final rows = await _client
        .from(_table)
        .select(includeDetail ? _trainerColumns : _memberColumns);

    return (rows as List)
        .cast<Map<String, dynamic>>()
        // 앱이 모르는 패턴/빈 큐는 tryFromRow 가 null 로 걸러낸다.
        .map(CoachingRule.tryFromRow)
        .whereType<CoachingRule>()
        .toList(growable: false);
  }
}

/// 회원 **본인**의 체형 제약 조회(읽기 전용).
///
/// `member_id` 필터를 걸지 않는다 — RLS `member_cond_member_read`(0036)가
/// 본인 행만 노출하므로 앱이 id 를 알 필요가 없다(회원 홈·기록 repository 와 동일 패턴).
class MyConditionRepository {
  final SupabaseClient _client;
  MyConditionRepository(this._client);

  static const _table = 'member_conditions';

  /// ★ `trainer_note` 를 의도적으로 뺐다. 추가하지 말 것 — 회원 노출 금지 컬럼이다.
  static const _columns =
      'id, member_id, code, label, source, member_note, active, '
      'recorded_by, created_at, updated_at';

  /// 본인의 활성 제약(등록 순서).
  Future<List<MemberCondition>> listMine() async {
    final rows = await _client
        .from(_table)
        .select(_columns)
        .eq('active', true)
        .order('created_at', ascending: true);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(MemberCondition.fromRow)
        .toList(growable: false);
  }
}
