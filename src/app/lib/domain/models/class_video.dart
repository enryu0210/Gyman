/// 수업 영상 1건. class_videos 테이블의 1행과 1:1 대응 (S 시리즈).
///
/// **검수 게이트가 없는 이유:**
///   영상은 트레이너가 *의도적으로* 올린 자료다. body_assessments(사진/AI 분석)처럼
///   "AI 추론 → 트레이너 코멘트 후 노출"이 아니라, 인바디 수치(0023)와 같은 결로
///   회원이 본인 것을 바로 본다. 가시성은 RLS(0027)가 회원=본인/트레이너=담당으로 분리.
///
/// **실파일은 Storage, 모델엔 경로/메타만:** 채팅 이미지(0026)·인바디(0023)와 동일 패턴.
///   재생은 [storagePath] 로 매번 단기 서명 URL 을 발급해 video_player 에 넘긴다.
///
/// 불변 객체로 둔 이유는 [BodyMeasurement] / [SessionRecord] 와 동일 — 표시 일관성.
library;

class ClassVideo {
  /// 영상 메타 PK.
  final String id;

  /// 대상 회원 (member_profiles.id).
  final String memberId;

  /// 연결된 수업 (sessions.id). 회원 단위로만 올렸으면 null.
  final String? sessionId;

  /// 비공개 버킷 class-videos 내 object key. "{member_id}/{unique}.mp4".
  final String storagePath;

  /// 표시 제목. 입력 안 했으면 null → UI 에서 "수업 영상"으로 폴백.
  final String? title;

  /// 길이(초). 추출 실패 시 null.
  final int? durationSec;

  /// 용량(바이트). 모니터링/표시용. null 가능.
  final int? sizeBytes;

  /// 업로드한 트레이너 user_id. 계정 삭제 등으로 비어 있을 수 있어 nullable.
  final String? uploadedBy;

  /// 행 생성 시각(업로드 시각).
  final DateTime createdAt;

  const ClassVideo({
    required this.id,
    required this.memberId,
    required this.storagePath,
    required this.createdAt,
    this.sessionId,
    this.title,
    this.durationSec,
    this.sizeBytes,
    this.uploadedBy,
  });

  /// 제목이 비어 있으면 기본 표시명으로 대체 — UI 가 매번 분기하지 않게.
  String get displayTitle {
    final t = title?.trim() ?? '';
    return t.isEmpty ? '수업 영상' : t;
  }

  /// "1:23" 형태의 길이 라벨. durationSec 가 없으면 null(표시 생략).
  String? get durationLabel {
    final s = durationSec;
    if (s == null || s <= 0) return null;
    final m = s ~/ 60;
    final sec = s % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  /// class_videos 행 → 도메인 객체.
  ///
  /// PG int/bigint 는 SDK 가 num 으로 줄 수 있어 [_toInt] 로 흡수
  /// (CLAUDE.md: bigint 는 `as int` 직접 캐스팅 시 view 조회에서 런타임 오류).
  factory ClassVideo.fromRow(Map<String, dynamic> row) {
    return ClassVideo(
      id: row['id'] as String,
      memberId: row['member_id'] as String,
      sessionId: row['session_id'] as String?,
      storagePath: row['storage_path'] as String,
      title: row['title'] as String?,
      durationSec: _toInt(row['duration_sec']),
      sizeBytes: _toInt(row['size_bytes']),
      uploadedBy: row['uploaded_by'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  /// num/text/int 어느 형태로 와도 int 로. 빈 값/파싱 실패는 null.
  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  @override
  String toString() => 'ClassVideo($id, member:$memberId, "$displayTitle")';
}
