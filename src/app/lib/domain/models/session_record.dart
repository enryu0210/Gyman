/// 수업 기록 본문 (M2 수업 기록 화면).
///
/// **Session vs SessionRecord 분리 이유** (data_model.md §2.2):
///   - Session    : 예약/상태 추적 (모든 sessions가 가짐)
///   - SessionRecord: 운동 내용 본문 (status=done 인 수업에만 생성)
///   - 노쇼/취소는 Session 만 있고 SessionRecord 는 없다.
///
/// **exercises JSON 스키마 결정 근거** (DB 컬럼은 jsonb):
///   `[{"name":"스쿼트", "sets":[{"weight":60,"reps":10},{"weight":70,"reps":8}]}]`
///   - 종목별 무게/반복 자유도가 커서 정규화 테이블 대신 JSON
///   - 단점: SQL로 "회원의 평균 스쿼트 무게" 같은 집계가 어려움 — Phase 2의
///     변화 추이 그래프(S1) 단계에서 정규화 여부 재검토.
///   - 본 도메인이 JSON 모양을 책임지므로 [toJson]/[fromJson] 는 DB·UI 양쪽에서 공유.
///
/// 불변 객체로 둔 이유는 [PtContract] / [Session] 과 동일 — 계산/표시 일관성.
library;

// =====================================================================
// ExerciseSet — 종목 1개의 한 세트 (무게 × 반복)
// =====================================================================

/// 운동 한 세트.
///
/// weight 단위는 kg (원 단위), reps 는 회수.
/// 맨몸 운동 등 무게가 없는 경우 weight = 0 으로 저장한다.
/// 음수는 의미가 없으므로 [fromJson] 에서 음수면 0으로 보정.
class ExerciseSet {
  /// 무게 (kg). 정수만 지원 — 0.5kg 단위까지 필요해지면 double 로 승격.
  final int weight;

  /// 반복 횟수.
  final int reps;

  const ExerciseSet({required this.weight, required this.reps});

  Map<String, dynamic> toJson() => {'weight': weight, 'reps': reps};

  /// jsonb 에서 받은 Map → ExerciseSet.
  ///
  /// PG jsonb 의 숫자는 int/double 둘 다 올 수 있어 [num] 으로 받아 변환.
  /// 잘못된 값은 0으로 보정 — 입력 검증은 UI 가 책임진다.
  factory ExerciseSet.fromJson(Map<String, dynamic> json) {
    final w = (json['weight'] as num?)?.toInt() ?? 0;
    final r = (json['reps'] as num?)?.toInt() ?? 0;
    return ExerciseSet(
      weight: w < 0 ? 0 : w,
      reps: r < 0 ? 0 : r,
    );
  }

  ExerciseSet copyWith({int? weight, int? reps}) =>
      ExerciseSet(weight: weight ?? this.weight, reps: reps ?? this.reps);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExerciseSet &&
          runtimeType == other.runtimeType &&
          weight == other.weight &&
          reps == other.reps;

  @override
  int get hashCode => Object.hash(weight, reps);

  @override
  String toString() => 'ExerciseSet($weight kg × $reps)';
}

// =====================================================================
// Exercise — 종목 1개 + 세트 묶음
// =====================================================================

/// 운동 종목 1개. 이름 + 세트 리스트.
///
/// name 은 자유 텍스트(예: "스쿼트", "데드리프트"). 즐겨찾기/추천 종목 목록은
/// Phase 1.5 에서 추가될 예정 — 이 단계엔 사용자가 직접 입력.
class Exercise {
  final String name;
  final List<ExerciseSet> sets;

  const Exercise({required this.name, required this.sets});

  /// 종목 1개의 총 볼륨 (sum of weight × reps).
  /// 단위 테스트 / 변화 추이 그래프(S1)에서 재사용 가능.
  int get totalVolume =>
      sets.fold(0, (sum, s) => sum + s.weight * s.reps);

  Map<String, dynamic> toJson() => {
        'name': name,
        'sets': sets.map((s) => s.toJson()).toList(growable: false),
      };

  /// jsonb 에서 받은 Map → Exercise.
  ///
  /// `sets` 가 List 가 아니거나 비어 있어도 빈 리스트로 안전 처리.
  /// name 누락은 빈 문자열 — UI 가 표시 시 폴백 처리.
  factory Exercise.fromJson(Map<String, dynamic> json) {
    final rawSets = json['sets'];
    final sets = (rawSets is List)
        ? rawSets
            .whereType<Map<String, dynamic>>()
            .map(ExerciseSet.fromJson)
            .toList(growable: false)
        : const <ExerciseSet>[];
    return Exercise(
      name: (json['name'] as String?) ?? '',
      sets: sets,
    );
  }

  Exercise copyWith({String? name, List<ExerciseSet>? sets}) =>
      Exercise(name: name ?? this.name, sets: sets ?? this.sets);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Exercise) return false;
    if (name != other.name) return false;
    if (sets.length != other.sets.length) return false;
    for (var i = 0; i < sets.length; i++) {
      if (sets[i] != other.sets[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(name, Object.hashAll(sets));

  @override
  String toString() => 'Exercise($name, ${sets.length} sets)';
}

// =====================================================================
// SessionRecord — 수업 1건의 본문 (운동/컨디션/통증/다음 메모)
// =====================================================================

/// 수업 1건의 기록 본문. session_records 테이블의 1행과 1:1 대응.
///
/// **컨디션 코드 정책:**
///   `good` / `normal` / `bad` 셋 중 하나를 권장하지만, DB 컬럼은 자유 text 라
///   회원 표현이 더 풍부할 수 있도록 [SessionCondition] enum 으로 강제하지 않는다.
///   UI 는 칩 선택 + 직접 입력 둘 다 허용.
class SessionRecord {
  /// 소속 수업 ID — sessions.id 와 PK 공유 (1:1).
  final String sessionId;

  /// 종목 리스트. 빈 리스트도 유효 — 컨디션/메모만 기록할 수 있음.
  final List<Exercise> exercises;

  /// 회원 컨디션. good/normal/bad 권장 (UI 가 칩으로 입력).
  final String? condition;

  /// 통증/특이사항.
  final String? pain;

  /// 다음 수업을 위한 메모. 트레이너 본인이 다음에 떠올릴 단서.
  final String? nextMemo;

  /// 기록 행 생성 시각.
  final DateTime createdAt;

  /// 기록 마지막 수정 시각.
  final DateTime updatedAt;

  const SessionRecord({
    required this.sessionId,
    required this.exercises,
    required this.createdAt,
    required this.updatedAt,
    this.condition,
    this.pain,
    this.nextMemo,
  });

  /// 전체 세트 수 (모든 종목 합).
  int get totalSets =>
      exercises.fold(0, (sum, e) => sum + e.sets.length);

  /// 전체 볼륨 (모든 종목의 weight × reps 합).
  int get totalVolume =>
      exercises.fold(0, (sum, e) => sum + e.totalVolume);

  /// session_records 행으로부터 도메인 객체 생성.
  ///
  /// PG jsonb 의 `exercises` 컬럼은 List 로 전달됨.
  /// timestamptz 는 ISO8601 문자열 → DateTime.parse.
  factory SessionRecord.fromRow(Map<String, dynamic> row) {
    final rawExercises = row['exercises'];
    final exercises = (rawExercises is List)
        ? rawExercises
            .whereType<Map<String, dynamic>>()
            .map(Exercise.fromJson)
            .toList(growable: false)
        : const <Exercise>[];
    return SessionRecord(
      sessionId: row['session_id'] as String,
      exercises: exercises,
      condition: row['condition'] as String?,
      pain: row['pain'] as String?,
      nextMemo: row['next_memo'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  /// INSERT/UPDATE 시 보낼 payload.
  /// sessionId / created_at / updated_at 은 별도 처리 — 본 메서드는 본문만 직렬화.
  Map<String, dynamic> toInsertPayload() => {
        'exercises': exercises.map((e) => e.toJson()).toList(growable: false),
        'condition': condition,
        'pain': pain,
        'next_memo': nextMemo,
      };

  SessionRecord copyWith({
    String? sessionId,
    List<Exercise>? exercises,
    String? condition,
    String? pain,
    String? nextMemo,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SessionRecord(
      sessionId: sessionId ?? this.sessionId,
      exercises: exercises ?? this.exercises,
      condition: condition ?? this.condition,
      pain: pain ?? this.pain,
      nextMemo: nextMemo ?? this.nextMemo,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() =>
      'SessionRecord(session: $sessionId, ${exercises.length} exercises, '
      'condition: $condition)';
}
