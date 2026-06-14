/// 회원 셀프 운동 기록 1건 — self_workout_logs 테이블의 1행과 1:1 (S4 / 2.5).
///
/// **session_record(트레이너 작성 수업 기록)와 다른 모델인 이유:**
///   이건 회원이 혼자 운동한 날 직접 남기는 자율 일지다(기획서 답변 11). 트레이너의
///   수업 기록과 작성 주체·가시성이 다르므로 별도 모델·테이블로 둔다(0028 주석 참조).
///
/// **간단 입력 원칙:** 필드는 날짜 + 운동 한 줄 + 컨디션 점수(1~10) + 선택 메모.
///   컨디션은 자유 텍스트 대신 점수로 받아 입력 마찰을 줄인다(높을수록 좋음).
///   [workout]/[conditionScore]/[note] 중 하나만 있어도 유효(전부 비면 DB CHECK 가 막음).
///
/// 불변 객체로 둔 이유는 다른 도메인 모델과 동일 — 표시 일관성.
library;

class SelfWorkoutLog {
  /// 기록 PK.
  final String id;

  /// 작성 회원 (member_profiles.id). INSERT 시엔 DB DEFAULT 가 채우므로 보내지 않는다.
  final String memberId;

  /// 기록 날짜 (시각 없이 날짜 단위).
  final DateTime loggedAt;

  /// 운동 내용 한 줄. 점수/메모만 남긴 경우 null.
  final String? workout;

  /// 그날 컨디션 점수 1~10(높을수록 좋음). 미입력이면 null.
  final int? conditionScore;

  /// 선택 메모. 운동/점수만 남긴 경우 null.
  final String? note;

  /// 행 생성 시각.
  final DateTime createdAt;

  const SelfWorkoutLog({
    required this.id,
    required this.memberId,
    required this.loggedAt,
    required this.createdAt,
    this.workout,
    this.conditionScore,
    this.note,
  });

  /// self_workout_logs 행 → 도메인 객체.
  /// logged_at 은 `YYYY-MM-DD` date 문자열, created_at 은 ISO8601 timestamptz.
  factory SelfWorkoutLog.fromRow(Map<String, dynamic> row) {
    return SelfWorkoutLog(
      id: row['id'] as String,
      memberId: row['member_id'] as String,
      loggedAt: DateTime.parse(row['logged_at'] as String),
      workout: row['workout'] as String?,
      // smallint 는 SDK 가 int 로 주지만, 안전하게 num 경유로 흡수.
      conditionScore: (row['condition_score'] as num?)?.toInt(),
      note: row['note'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  /// INSERT payload. id/member_id/created_at 은 DB 가 채운다(member_id 는
  /// DEFAULT current_member_profile_id()). logged_at 은 시각이 섞이지 않게
  /// `YYYY-MM-DD` 문자열로(CLAUDE.md date 지침).
  ///
  /// 빈 문자열은 NULL 로 보내 DB CHECK(둘 중 하나 필수)와 의미를 맞춘다.
  Map<String, dynamic> toInsertPayload() => {
        'logged_at': _dateOnly(loggedAt),
        'workout': _nullIfBlank(workout),
        'condition_score': conditionScore,
        'note': _nullIfBlank(note),
      };

  /// UPDATE payload — 수정 가능한 필드만(날짜/운동/점수/메모).
  Map<String, dynamic> toUpdatePayload() => {
        'logged_at': _dateOnly(loggedAt),
        'workout': _nullIfBlank(workout),
        'condition_score': conditionScore,
        'note': _nullIfBlank(note),
      };

  static String? _nullIfBlank(String? v) {
    if (v == null) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  /// DateTime → `YYYY-MM-DD`.
  static String _dateOnly(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  @override
  String toString() => 'SelfWorkoutLog($loggedAt, workout:$workout, '
      'condition:$conditionScore, note:$note)';
}
