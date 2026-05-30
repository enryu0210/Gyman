/// 트레이너 ↔ 회원 1:1 채팅 repository (S2 / 2.3).
///
/// **역할 공용:** 트레이너든 회원이든 "상대(peer) user_id" 만 주면 동작한다.
///   본인 user_id 는 Supabase Auth 세션에서 가져온다.
///
/// **실시간:** Supabase `.stream()` 으로 messages 변경을 구독한다(0024 publication).
///   stream API 는 OR 필터를 못 거니, RLS 가 이미 "내 메시지"로 좁혀준 결과를 받아
///   클라이언트에서 peer 쌍만 추려낸다(회원은 트레이너 1명뿐이라 사실상 전부).
///
/// **보안:** sender 위조/무관한 상대 전송은 RLS(0024 messages_send)가 차단.
///   본 repository 는 sender_id 를 넣지 않고 DB 가 auth.uid() 로 강제하게 둔다.
///
/// 참고: 0006(messages), 0024(RLS·실시간), docs/develop_plan.md §4 2.3.
library;

import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/chat_message.dart';

class ChatRepository {
  final SupabaseClient _client;
  ChatRepository(this._client);

  static const _table = 'messages';

  /// 채팅 이미지 비공개 버킷(0026). 표시는 서명 URL 로만.
  static const _imageBucket = 'chat-images';

  /// 서명 URL 유효 시간(초). 1시간이면 대화 한 세션 동안 충분.
  static const _signedUrlTtl = 3600;

  /// 나([myUserId])와 상대([peerUserId]) 사이 메시지를 실시간 스트림으로.
  /// 전송 시각 오름차순(오래된 것 위 → 최신 아래, 일반 채팅 순서).
  ///
  /// ⚠️ supabase_flutter 의 stream `.order()` 는 일반 쿼리빌더와 달리 기본값이
  /// `ascending: false`(내림차순)다. 명시하지 않으면 최신이 위로 와서 한국식 채팅과
  /// 반대로 쌓인다 → 반드시 `ascending: true` 를 줘야 오래된 것이 위로 간다.
  Stream<List<ChatMessage>> messagesWith({
    required String myUserId,
    required String peerUserId,
  }) {
    return _client
        .from(_table)
        .stream(primaryKey: ['id'])
        .order('sent_at', ascending: true)
        .map((rows) {
      return rows
          .map(ChatMessage.fromRow)
          // RLS 가 내 메시지로 좁혀주지만, 여러 상대가 있을 수 있는 트레이너를 위해
          // 이 peer 와 주고받은 것만 추린다.
          .where((m) =>
              (m.senderId == myUserId && m.receiverId == peerUserId) ||
              (m.senderId == peerUserId && m.receiverId == myUserId))
          .toList(growable: false);
    });
  }

  /// 메시지 전송.
  ///
  /// sender_id 는 **반드시 명시**해야 한다 — 컬럼이 NOT NULL(0006)이고, RLS 는
  /// 값을 채워주는 게 아니라 `sender_id = auth.uid()` 인지 *검증*만 한다(위조 차단).
  /// 그래서 현재 로그인 user.id 를 직접 넣고, RLS 가 그게 본인인지 확인하게 둔다.
  /// 빈/공백 메시지는 호출 측(컨트롤러)이 거른다.
  Future<void> send({
    required String receiverId,
    required String content,
  }) async {
    final me = _client.auth.currentUser;
    if (me == null) {
      throw StateError('로그인이 필요합니다. 다시 로그인 후 시도해 주세요.');
    }
    await _client.from(_table).insert({
      'sender_id': me.id,
      'receiver_id': receiverId,
      'content': content,
    });
  }

  /// 사진 메시지 전송: 파일을 비공개 버킷에 올리고 image_path 로 메시지를 INSERT.
  ///
  /// **보상 트랜잭션(CLAUDE.md 패턴):** Supabase Dart 는 멀티테이블 트랜잭션 미지원.
  ///   1단계(Storage 업로드) 성공 + 2단계(messages INSERT) 실패 시 업로드한 파일을
  ///   hard delete 해 고아 파일을 막는다.
  ///
  /// object key 규칙(0026): "{내 user_id}/{uuid}.{ext}". 첫 세그먼트가 Storage RLS
  ///   권한 키라 반드시 본인 user_id 폴더여야 한다. 경로는 ASCII 만(한글 금지).
  Future<void> sendImage({
    required String receiverId,
    required File file,
  }) async {
    final me = _client.auth.currentUser;
    if (me == null) {
      throw StateError('로그인이 필요합니다. 다시 로그인 후 시도해 주세요.');
    }

    // 확장자 보존(소문자, jpg/png/webp 외에는 jpg 로 폴백 — 서버 MIME 검증과 일치).
    final ext = _safeExtension(file.path);
    final objectKey =
        '${me.id}/${DateTime.now().millisecondsSinceEpoch}_${_randomToken()}.$ext';

    // 1단계: Storage 업로드.
    await _client.storage.from(_imageBucket).upload(
          objectKey,
          file,
          fileOptions: FileOptions(contentType: 'image/$ext'),
        );

    // 2단계: 메시지 INSERT. 실패하면 1단계 보상(업로드 파일 삭제) 후 재던짐.
    try {
      await _client.from(_table).insert({
        'sender_id': me.id,
        'receiver_id': receiverId,
        'image_path': objectKey,
        // content 는 보내지 않음 → DB 에서 NULL(이미지 전용 메시지).
      });
    } catch (e) {
      // 보상: 메시지가 안 남았는데 파일만 떠도는 상황 방지.
      try {
        await _client.storage.from(_imageBucket).remove([objectKey]);
      } catch (_) {
        // 정리 실패는 원래 에러를 가리지 않게 무시(고아 파일은 정리 잡 대상).
      }
      rethrow;
    }
  }

  /// 이미지 object key → 표시용 서명 URL(유효 [_signedUrlTtl]초).
  /// 비공개 버킷이라 공개 URL 이 없으므로 매번 서명해서 보여준다.
  Future<String> signedImageUrl(String objectKey) {
    return _client.storage
        .from(_imageBucket)
        .createSignedUrl(objectKey, _signedUrlTtl);
  }

  /// 파일 경로에서 허용 확장자만 추출. 미지원 확장자는 jpg 로 폴백.
  static String _safeExtension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return 'jpeg';
    final ext = path.substring(dot + 1).toLowerCase();
    if (ext == 'jpg') return 'jpeg'; // MIME 와 통일(image/jpeg)
    if (ext == 'png' || ext == 'webp' || ext == 'jpeg') return ext;
    return 'jpeg';
  }

  /// 파일명 충돌 방지용 짧은 난수 토큰(시각 + 이 값으로 사실상 유일).
  static String _randomToken() =>
      (DateTime.now().microsecondsSinceEpoch % 1000000).toString();

  /// 내가 받은, 아직 안 읽은 메시지 총 개수 — 안읽음 배지용(가벼운 조회).
  /// 역할 공용(회원/트레이너 둘 다). 미로그인/미설정이면 0.
  Future<int> unreadCount() async {
    final me = _client.auth.currentUser;
    if (me == null) return 0;
    final rows = await _client
        .from(_table)
        .select('id')
        .eq('receiver_id', me.id)
        .isFilter('read_at', null);
    return (rows as List).length;
  }

  /// 상대([peerUserId])가 보낸, 내가 아직 안 읽은 메시지를 읽음 처리.
  /// RLS(messages_mark_read)가 receiver=본인 행만 update 허용.
  Future<void> markReadFrom(String peerUserId) async {
    final me = _client.auth.currentUser;
    if (me == null) return;
    await _client
        .from(_table)
        .update({'read_at': DateTime.now().toIso8601String()})
        .eq('receiver_id', me.id)
        .eq('sender_id', peerUserId)
        .isFilter('read_at', null);
  }
}
