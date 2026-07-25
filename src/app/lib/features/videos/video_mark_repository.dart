/// 수업 영상 시점 지적(`class_video_marks`) read/write — 역할 공용 (L2).
/// docs/design_movement_coaching.md §3.4
///
/// **가시성:** 트레이너는 담당 회원 영상의 마킹을 rw, 회원은 본인 영상 마킹을 read.
///   권한 판정은 전부 RLS(0038)가 class_videos 를 경유해 한다 — 앱은 video_id 만 넘긴다.
///   숨길 컬럼이 없어(코멘트 자체가 회원에게 전할 내용) 역할별 SELECT 분기도 없다.
///
/// 참고: src/supabase/migrations/0038_class_video_marks.sql
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/class_video_mark.dart';

class VideoMarkRepository {
  final SupabaseClient _client;
  VideoMarkRepository(this._client);

  static const _table = 'class_video_marks';

  /// 조회 컬럼 — 테이블에 컬럼 추가 시 **이 문자열도 같이 갱신**할 것
  /// (빠뜨리면 그 필드만 조용히 null — CLAUDE.md).
  static const _columns =
      'id, video_id, t_ms, body_part, comment, created_by, created_at';

  /// 영상 1개의 마킹 — 시점 오름차순.
  Future<List<ClassVideoMark>> listForVideo(String videoId) async {
    final rows = await _client
        .from(_table)
        .select(_columns)
        .eq('video_id', videoId)
        .order('t_ms', ascending: true);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(ClassVideoMark.fromRow)
        .toList(growable: false);
  }

  /// 마킹 1건 추가. created_by 는 호출(컨트롤러)이 현재 트레이너 user_id 로 주입.
  Future<String> add({
    required ClassVideoMark mark,
    required String createdBy,
  }) async {
    final payload = mark.toInsertPayload()..['created_by'] = createdBy;
    final row = await _client.from(_table).insert(payload).select('id').single();
    return row['id'] as String;
  }

  /// 마킹 1건 삭제(하드 삭제 — 잘못 찍은 지점 제거).
  Future<void> delete(String id) async {
    await _client.from(_table).delete().eq('id', id);
  }
}
