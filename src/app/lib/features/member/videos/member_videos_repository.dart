/// 회원 본인 "수업 영상" 조회 repository (읽기 전용, S 시리즈).
///
/// 본인 영상만 본인 시점으로 가져온다(RLS 위임 — member_id 필터를 클라가 안 넘김.
/// 0027 class_videos_member_read 가 본인 행으로 좁혀줌). 트레이너 측 업로드/삭제와
/// 책임을 분리해 회원 화면은 조회·재생만 한다(변화추이 progress repository 와 같은 결).
///
/// 재생은 비공개 버킷이라 [signedVideoUrl] 로 매번 단기 서명 URL 을 발급
/// (0027 class_videos_objects_member_read 통과 시에만 발급됨).
///
/// 참고: docs/design_class_videos.md §5, 0027(RLS).
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/models/class_video.dart';

class MemberVideosRepository {
  final SupabaseClient _client;
  MemberVideosRepository(this._client);

  static const _table = 'class_videos';
  static const _bucket = 'class-videos';
  static const _signedUrlTtl = 3600;

  /// 본인 영상 목록 — 업로드 최신순. RLS 가 본인 것만 노출.
  Future<List<ClassVideo>> listMyVideos() async {
    final rows = await _client
        .from(_table)
        .select(
            'id, member_id, session_id, storage_path, title, duration_sec, size_bytes, uploaded_by, created_at')
        .order('created_at', ascending: false);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(ClassVideo.fromRow)
        .toList(growable: false);
  }

  /// object key → 재생용 단기 서명 URL(유효 [_signedUrlTtl]초).
  Future<String> signedVideoUrl(String storagePath) {
    return _client.storage.from(_bucket).createSignedUrl(storagePath, _signedUrlTtl);
  }
}
