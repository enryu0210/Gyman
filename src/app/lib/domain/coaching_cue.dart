/// 코칭 큐 규칙 모델 + 선별 로직 (동작 습관·체형 제약 코칭 L1-b).
/// docs/design_movement_coaching.md §3.3
///
/// **무엇을 계산하나:**
///   (회원의 활성 제약) × (지금 하려는 운동의 동작 패턴) → 보여줄 큐 목록.
///   예) 골반 전방경사 + `push_vertical` → "갈비뼈를 닫고 골반을 중립으로…"
///
/// **왜 순수 함수인가:** 표시 지점이 여러 곳(회원 셀프기록 · 트레이너 수업기록 ·
///   추후 고스트 화면)이라, 어느 화면에서 보든 같은 큐가 나와야 한다. 화면마다
///   조합 로직을 두면 어긋난다 — 도메인에 모아 단위 테스트로 고정한다
///   (develop_plan §5.1 원칙).
library;

import 'models/member_condition.dart';
import 'movement_pattern.dart';

/// 큐의 성격. 표시 우선순위이자 톤 결정자.
///
/// **`avoid`(금지)가 없는 것은 의도다** — "이 운동 하지 마세요"는 처방에 가깝다.
/// 대체가 필요하면 [modify] 로 표현하고 주체를 트레이너에 둔다(설계 §5).
/// DB CHECK(0037)에도 같은 3종만 허용돼 있다.
enum CueAction {
  /// 대체 권장 — 트레이너가 안내한 다른 동작으로. 가장 먼저 보여준다.
  modify('modify', '대체 권장', 0),

  /// 주의 — 하되 특정 실수를 조심.
  caution('caution', '주의', 1),

  /// 집중 — 특별히 신경 쓸 포인트.
  focus('focus', '체크', 2);

  const CueAction(this.code, this.label, this.priority);

  /// DB 에 저장되는 값.
  final String code;

  /// UI 표시명.
  final String label;

  /// 정렬 우선순위(작을수록 먼저). 주의가 필요한 것부터 위로.
  final int priority;

  /// DB 문자열 → enum. 모르는 값은 가장 약한 [focus] 로 흡수한다.
  ///
  /// 모호할 때 강한 경고로 승격하면 과잉 경고가 되고, 그게 반복되면 회원이
  /// 큐 전체를 무시하게 된다(§9 "잔소리 앱" 리스크).
  static CueAction fromCode(String? raw) {
    for (final a in CueAction.values) {
      if (a.code == raw) return a;
    }
    return CueAction.focus;
  }
}

/// `condition_coaching_rules` 1행 — 제약 × 패턴 → 큐 규칙.
class CoachingRule {
  final String id;

  /// NULL = 전 센터 공통 기본 시드 / 값 = 그 센터 전용 규칙.
  final String? centerId;

  /// `member_conditions.code` 와 같은 코드 체계.
  final String conditionCode;

  final MovementPattern pattern;
  final CueAction action;

  /// 회원에게 보이는 한 줄.
  final String cue;

  /// 트레이너용 상세. 회원 측 조회에서는 select 하지 않는다 → null.
  final String? detail;

  const CoachingRule({
    required this.id,
    required this.conditionCode,
    required this.pattern,
    required this.action,
    required this.cue,
    this.centerId,
    this.detail,
  });

  /// 센터 전용 규칙인지 — 같은 (제약, 패턴)이면 공통 시드를 덮어쓴다.
  bool get isCenterOverride => centerId != null;

  /// 행 → 모델. **패턴을 못 알아보면 null 을 반환한다.**
  ///
  /// 앱이 모르는 패턴 문자열이 DB 에 있으면(앱보다 DB 가 앞서 나간 경우) 그 규칙은
  /// 조용히 버린다 — 정체불명 규칙으로 엉뚱한 큐를 띄우는 것보다 안전하다.
  static CoachingRule? tryFromRow(Map<String, dynamic> row) {
    final pattern = MovementPattern.fromCode(row['movement_pattern'] as String?);
    if (pattern == null) return null;

    final cue = (row['cue'] as String?)?.trim() ?? '';
    if (cue.isEmpty) return null;

    return CoachingRule(
      id: row['id'] as String,
      centerId: row['center_id'] as String?,
      conditionCode: row['condition_code'] as String,
      pattern: pattern,
      action: CueAction.fromCode(row['action'] as String?),
      cue: cue,
      detail: row['detail'] as String?,
    );
  }
}

/// 화면에 띄울 큐 1건 — 규칙 + 어떤 제약 때문인지를 합친 결과.
class CoachingCue {
  /// 근거가 된 제약 코드.
  final String conditionCode;

  /// 근거가 된 제약의 표시명(예: '골반 전방경사'). "왜 이 큐가 뜨는지" 설명용.
  final String conditionLabel;

  final MovementPattern pattern;
  final CueAction action;
  final String cue;

  /// 트레이너용 상세(회원 화면에선 항상 null).
  final String? detail;

  const CoachingCue({
    required this.conditionCode,
    required this.conditionLabel,
    required this.pattern,
    required this.action,
    required this.cue,
    this.detail,
  });

  @override
  String toString() => 'CoachingCue($conditionLabel/${pattern.code}/${action.code})';
}

/// (제약 × 패턴 × 규칙) → 표시할 큐 목록.
class CoachingCueSelector {
  const CoachingCueSelector._();

  /// 한 화면에 띄울 기본 상한.
  ///
  /// 큐가 많으면 회원이 전부 무시한다(§9 "잔소리 앱" 리스크). 가장 주의가 필요한
  /// 것부터 3개까지만 — 나머지는 UI 가 "더 보기"로 접는다.
  static const defaultLimit = 3;

  /// 큐 선별.
  ///
  /// - [conditions] 중 **active 인 것만** 사용한다(해제된 이력은 무시).
  /// - [patterns] 가 비면 결과도 빈 목록 — 종목을 못 알아본 경우 큐를 안 띄운다.
  /// - 같은 (제약, 패턴)에 공통 시드와 센터 규칙이 둘 다 있으면 **센터 규칙이 이긴다.**
  /// - 정렬: 대체 권장 → 주의 → 체크, 같은 등급이면 제약 등록 순서.
  static List<CoachingCue> select({
    required List<MemberCondition> conditions,
    required List<CoachingRule> rules,
    required Set<MovementPattern> patterns,
    int limit = defaultLimit,
  }) {
    if (patterns.isEmpty || conditions.isEmpty || rules.isEmpty) {
      return const [];
    }

    // 활성 제약만, 등록 순서 유지(동점 시 정렬 안정성에 사용).
    final activeConditions =
        conditions.where((c) => c.active).toList(growable: false);
    if (activeConditions.isEmpty) return const [];

    // (제약코드, 패턴) → 채택된 규칙. 센터 규칙이 공통 시드를 덮어쓴다.
    final chosen = <String, CoachingRule>{};
    for (final rule in rules) {
      if (!patterns.contains(rule.pattern)) continue;

      final key = '${rule.conditionCode}|${rule.pattern.code}';
      final existing = chosen[key];
      // 이미 센터 규칙이 잡혀 있으면 공통 시드로 덮어쓰지 않는다.
      if (existing != null && existing.isCenterOverride && !rule.isCenterOverride) {
        continue;
      }
      chosen[key] = rule;
    }
    if (chosen.isEmpty) return const [];

    final cues = <CoachingCue>[];
    // 제약 등록 순서로 돌면서 매칭되는 규칙을 모은다 — 동점 정렬의 기준이 된다.
    for (var i = 0; i < activeConditions.length; i++) {
      final condition = activeConditions[i];
      for (final pattern in patterns) {
        final rule = chosen['${condition.code}|${pattern.code}'];
        if (rule == null) continue;
        cues.add(CoachingCue(
          conditionCode: condition.code,
          conditionLabel: condition.displayName,
          pattern: pattern,
          action: rule.action,
          cue: rule.cue,
          detail: rule.detail,
        ));
      }
    }

    // 주의가 필요한 것부터. List.sort 는 안정 정렬이 아니라서 동점 시 순서가
    // 보장되지 않으므로, 등록 순서를 인덱스로 명시 비교한다.
    final order = {
      for (var i = 0; i < activeConditions.length; i++)
        activeConditions[i].code: i,
    };
    cues.sort((a, b) {
      final byAction = a.action.priority.compareTo(b.action.priority);
      if (byAction != 0) return byAction;
      final ai = order[a.conditionCode] ?? 1 << 20;
      final bi = order[b.conditionCode] ?? 1 << 20;
      return ai.compareTo(bi);
    });

    return cues.length <= limit
        ? List.unmodifiable(cues)
        : List.unmodifiable(cues.take(limit));
  }
}
