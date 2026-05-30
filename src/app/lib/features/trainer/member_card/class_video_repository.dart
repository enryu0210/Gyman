/// 수업 영상 read/write wrapper — 트레이너용 (S 시리즈).
///
/// **가시성:** 영상은 트레이너가 의도적으로 올린 자료라 검수 게이트 없이 회원에게 노출.
///   RLS(0027): 트레이너는 담당 회원 rw(class_videos_trainer_rw),
///   회원은 본인 read(class_videos_member_read). 회원 측 조회는
///   features/member/videos 의 별도 repository 가 본인 시점으로 수행.
///
/// **업로드 = 보상 트랜잭션(CLAUDE.md 패턴):** Supabase Dart 는 멀티테이블 트랜잭션
///   미지원. 1단계(Storage 업로드) 성공 + 2단계(class_videos INSERT) 실패 시 업로드한
///   파일을 hard delete 해 고아 파일을 막는다(채팅 0026 sendImage 와 동일 원칙).
///
/// **object key 규칙(0027):** "{member_id}/{unique}.mp4". 첫 세그먼트가 Storage RLS
///   권한 키(= 대상 회원). 채팅과 달리 업로더(트레이너) 폴더가 아니라 회원 폴더에 넣는다.
///   경로는 ASCII 만(한글 금지).
///
/// 참고: docs/design_class_videos.md §2~4, 0027 마이그레이션.
library;

import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/models/class_video.dart';

class ClassVideoRepository {
  final SupabaseClient _client;
  ClassVideoRepository(this._client);

  static const _table = 'class_videos';

  /// 수업 영상 비공개 버킷(0027). 재생은 서명 URL 로만.
  static const _bucket = 'class-videos';

  /// 서명 URL 유효 시간(초). 1시간이면 영상 한 편 시청에 충분.
  static const _signedUrlTtl = 3600;

  /// 회원 1명의 영상 목록 — 업로드 최신순.
  /// RLS 가 트레이너 본인 담당 회원만 노출.
  Future<List<ClassVideo>> listForMember(String memberId) async {
    final rows = await _client
        .from(_table)
        .select(
            'id, member_id, session_id, storage_path, title, duration_sec, size_bytes, uploaded_by, created_at')
        .eq('member_id', memberId)
        .order('created_at', ascending: false);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(ClassVideo.fromRow)
        .toList(growable: false);
  }

  /// 영상 1건 업로드 + 메타 INSERT (보상 트랜잭션).
  ///
  /// [memberId] 대상 회원, [file] 영상 파일, [title]/[durationSec] 메타(선택),
  /// [uploadedBy] 현재 로그인 트레이너 user_id.
  ///
  /// 절차:
  ///   1) Storage 업로드("{memberId}/{unique}.mp4").
  ///   2) class_videos INSERT(경로·제목·길이·용량·uploaded_by).
  ///   3) 2단계 실패 시 1단계 업로드 파일 hard delete(고아 방지) 후 재던짐.
  Future<void> upload({
    required String memberId,
    required File file,
    required String uploadedBy,
    String? title,
    int? durationSec,
  }) async {
    // 파일명 = 시각 + 난수 토큰으로 사실상 유일. 확장자는 mp4 고정(버킷 MIME 와 일치).
    final unique =
        '${DateTime.now().millisecondsSinceEpoch}_${_randomToken()}';
    final objectKey = '$memberId/$unique.mp4';

    // 용량은 업로드 전에 측정해 메타에 남긴다(모니터링/정리용).
    final sizeBytes = await file.length();

    // 1단계: Storage 업로드.
    await _client.storage.from(_bucket).upload(
          objectKey,
          file,
          fileOptions: const FileOptions(contentType: 'video/mp4'),
        );

    // 2단계: 메타 INSERT. 실패하면 1단계 보상(업로드 파일 삭제) 후 재던짐.
    try {
      await _client.from(_table).insert({
        'member_id': memberId,
        'storage_path': objectKey,
        'title': (title != null && title.trim().isNotEmpty) ? title.trim() : null,
        'duration_sec': durationSec,
        'size_bytes': sizeBytes,
        'uploaded_by': uploadedBy,
      });
    } catch (e) {
      // 보상: 메타가 안 남았는데 파일만 떠도는 상황 방지.
      try {
        await _client.storage.from(_bucket).remove([objectKey]);
      } catch (_) {
        // 정리 실패는 원래 에러를 가리지 않게 무시(고아 파일은 정리 잡 대상).
      }
      rethrow;
    }
  }

  /// 영상 1건 삭제 — 메타 + Storage 객체 둘 다.
  ///
  /// 메타를 먼저 지우고 파일을 지운다(메타가 권한 출처). 파일 삭제 실패는 무시 —
  /// 메타가 사라지면 회원에게 더는 노출되지 않고, 고아 파일은 정리 잡 대상.
  Future<void> delete({required String id, required String storagePath}) async {
    await _client.from(_table).delete().eq('id', id);
    try {
      await _client.storage.from(_bucket).remove([storagePath]);
    } catch (_) {
      // 파일 정리 실패는 치명적이지 않음(메타 삭제로 노출은 이미 차단).
    }
  }

  /// object key → 재생용 단기 서명 URL(유효 [_signedUrlTtl]초).
  /// 비공개 버킷이라 공개 URL 이 없으므로 매번 서명해서 재생기에 넘긴다.
  Future<String> signedVideoUrl(String storagePath) {
    return _client.storage.from(_bucket).createSignedUrl(storagePath, _signedUrlTtl);
  }

  /// 파일명 충돌 방지용 짧은 난수 토큰(시각 + 이 값으로 사실상 유일).
  static String _randomToken() =>
      (DateTime.now().microsecondsSinceEpoch % 1000000).toString();
}
