/// 수업 영상의 "시점 지적" 1건. `class_video_marks` 테이블의 1행과 1:1 대응.
/// (동작 습관·체형 제약 코칭 L2 — docs/design_movement_coaching.md §3.4)
///
/// **왜 이게 필요한가:**
///   "다리가 빠진다" 같은 동작 습관은 자동 검출이 거의 안 된다(설계 §2 — 실제로
///   되는 건 무릎 모임 하나뿐). 반면 트레이너의 눈은 이미 그걸 보고 있다.
///   그 관찰을 **영상의 그 순간에 붙여** 두면, 회원이 재생할 때 같은 지점에서 다시 뜬다.
///
/// **검수 게이트 없음:** 트레이너가 의도적으로 쓰는 코멘트라 AI 초안과 성격이 다르다
///   (영상 시스템 0027 과 같은 논리).
library;

/// 부위 태그 1개 — 코드와 표시명.
class VideoMarkBodyPart {
  final String code;
  final String label;

  const VideoMarkBodyPart(this.code, this.label);
}

/// 부위 태그 카탈로그.
///
/// **잠정 목록이다** — 트레이너가 실제로 쓰는 부위에 맞춰 조정한다. DB 는 `body_part`
/// 를 text 로 들고 있어(0038) 항목 변경에 마이그레이션이 필요 없다.
class VideoMarkBodyParts {
  const VideoMarkBodyParts._();

  static const items = <VideoMarkBodyPart>[
    VideoMarkBodyPart('knee', '무릎'),
    VideoMarkBodyPart('hip', '고관절·골반'),
    VideoMarkBodyPart('lumbar', '허리'),
    VideoMarkBodyPart('thoracic', '등·흉추'),
    VideoMarkBodyPart('shoulder', '어깨'),
    VideoMarkBodyPart('neck', '목'),
    VideoMarkBodyPart('ankle', '발목·발'),
    VideoMarkBodyPart('tempo', '속도·호흡'),
  ];

  /// 코드 → 표시명. 카탈로그에 없으면 원문을 그대로 돌려준다.
  ///
  /// 목록이 바뀌어도 **이미 저장된 마킹이 이름 없는 태그로 깨지지 않게** 하는 방어
  /// (`ConditionCatalog.labelOf` 와 같은 이유).
  static String labelOf(String code) {
    for (final p in items) {
      if (p.code == code) return p.label;
    }
    return code;
  }
}

/// 영상 시점 지적 1건.
class ClassVideoMark {
  final String id;

  /// 대상 영상 (class_videos.id).
  final String videoId;

  /// 영상 내 시점(밀리초).
  final int tMs;

  /// 부위 태그(선택).
  final String? bodyPart;

  /// 지적 내용.
  final String comment;

  /// 남긴 트레이너 user_id. 계정 삭제 시 null 이 될 수 있다.
  final String? createdBy;

  final DateTime createdAt;

  const ClassVideoMark({
    required this.id,
    required this.videoId,
    required this.tMs,
    required this.comment,
    required this.createdAt,
    this.bodyPart,
    this.createdBy,
  });

  /// 재생 위치로 쓰기 좋은 [Duration].
  Duration get position => Duration(milliseconds: tMs);

  /// 부위 표시명. 태그가 없으면 null.
  String? get bodyPartLabel =>
      bodyPart == null ? null : VideoMarkBodyParts.labelOf(bodyPart!);

  /// `0:12` 형태의 시점 표기. 1시간을 넘길 일이 없어(영상 120초 상한) 분:초로만.
  String get timeLabel => formatMs(tMs);

  /// 밀리초 → `m:ss`. 음수는 0으로 클램프(방어).
  static String formatMs(int ms) {
    final safe = ms < 0 ? 0 : ms;
    final totalSeconds = safe ~/ 1000;
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  factory ClassVideoMark.fromRow(Map<String, dynamic> row) {
    return ClassVideoMark(
      id: row['id'] as String,
      videoId: row['video_id'] as String,
      // PG int 는 SDK 가 num 으로 줄 수 있어 toInt() 로 흡수(CLAUDE.md 집계 캐스팅 지침).
      tMs: (row['t_ms'] as num).toInt(),
      bodyPart: row['body_part'] as String?,
      comment: row['comment'] as String,
      createdBy: row['created_by'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  /// INSERT payload. id/created_at 은 DB 기본값, created_by 는 호출 측이 주입.
  Map<String, dynamic> toInsertPayload() => {
        'video_id': videoId,
        't_ms': tMs,
        'body_part': _blankToNull(bodyPart),
        'comment': comment.trim(),
      };

  static String? _blankToNull(String? v) {
    final t = v?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

  @override
  String toString() => 'ClassVideoMark($timeLabel, $bodyPart, $comment)';
}

/// 재생 위치에 해당하는 마킹을 고르는 순수 로직.
///
/// **왜 도메인인가:** 트레이너 화면과 회원 화면이 **같은 순간에 같은 마킹**을 보여줘야
/// 한다. 화면마다 판정하면 어긋난다(develop_plan §5.1 원칙).
class VideoMarkTimeline {
  const VideoMarkTimeline._();

  /// 마킹이 화면에 떠 있는 시간(ms). 짧으면 놓치고, 길면 다음 동작을 가린다.
  static const displayWindowMs = 4000;

  /// [positionMs] 시점에 표시할 마킹. 없으면 null.
  ///
  /// 마킹 시점부터 [displayWindowMs] 동안 표시한다. 창이 겹치면 **가장 최근에
  /// 시작한 것**을 보여준다 — 지나간 지적보다 지금 지적이 우선.
  static ClassVideoMark? activeAt(List<ClassVideoMark> marks, int positionMs) {
    ClassVideoMark? active;
    for (final mark in marks) {
      if (positionMs < mark.tMs) continue;
      if (positionMs >= mark.tMs + displayWindowMs) continue;
      if (active == null || mark.tMs > active.tMs) active = mark;
    }
    return active;
  }

  /// 시점 오름차순 정렬본(표시·목록 공용).
  static List<ClassVideoMark> sorted(List<ClassVideoMark> marks) {
    final copy = [...marks]..sort((a, b) => a.tMs.compareTo(b.tMs));
    return List.unmodifiable(copy);
  }
}
