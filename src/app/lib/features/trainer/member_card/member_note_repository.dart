/// 트레이너 전용 메모(member_notes) read/write wrapper (Phase 1.10, AI-C).
///
/// **회원에게 절대 안 보임** — RLS notes_member_deny + visibility='trainer_only'.
/// 도메인 [NoteVisibility]/[NoteSource] 가 2차 방어.
///
/// AI 초안 생성은 generate-memo-draft Edge Function 호출(키는 서버에만).
/// 생성된 초안은 source='ai_draft' 로 적재되고, 트레이너가 [confirm] 으로
/// source='ai_confirmed' 전환해야 "확정" 상태가 된다(와이어 6.4).
///
/// 참고: docs/develop_plan.md §4 1.10, src/supabase/migrations/0004_init_notes.sql.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/models/enums.dart';
import '../ai_review/ai_review_repository.dart' show AiGenerationException;

// =====================================================================
// NoteSource ↔ DB ENUM 문자열
// =====================================================================

NoteSource _sourceFromDb(String raw) {
  switch (raw) {
    case 'manual':
      return NoteSource.manual;
    case 'ai_draft':
      return NoteSource.aiDraft;
    case 'ai_confirmed':
      return NoteSource.aiConfirmed;
    default:
      throw StateError('알 수 없는 note_source 값: $raw');
  }
}

String _sourceToDb(NoteSource s) {
  switch (s) {
    case NoteSource.manual:
      return 'manual';
    case NoteSource.aiDraft:
      return 'ai_draft';
    case NoteSource.aiConfirmed:
      return 'ai_confirmed';
  }
}

// =====================================================================
// 화면 표시용 모델
// =====================================================================

class MemberNote {
  final String id;
  final String memberId;
  final String content;
  final NoteSource source;
  final String? sourceSessionId;
  final DateTime? confirmedAt;
  final DateTime createdAt;

  const MemberNote({
    required this.id,
    required this.memberId,
    required this.content,
    required this.source,
    required this.sourceSessionId,
    required this.confirmedAt,
    required this.createdAt,
  });

  /// 트레이너 검수 대기 중인 AI 초안.
  bool get isDraft => source == NoteSource.aiDraft;

  /// 확정된 메모(AI 확정 또는 수동 작성) — 회원 카드 메모 영역에 노출(트레이너 전용).
  bool get isConfirmed =>
      source == NoteSource.aiConfirmed || source == NoteSource.manual;
}

// =====================================================================
// Repository
// =====================================================================

class MemberNoteRepository {
  final SupabaseClient _client;
  MemberNoteRepository(this._client);

  static const _table = 'member_notes';

  MemberNote _fromRow(Map<String, dynamic> r) {
    return MemberNote(
      id: r['id'] as String,
      memberId: r['member_id'] as String,
      content: r['content'] as String,
      source: _sourceFromDb(r['source'] as String),
      sourceSessionId: r['source_session_id'] as String?,
      confirmedAt: r['confirmed_at'] == null
          ? null
          : DateTime.tryParse(r['confirmed_at'] as String),
      createdAt: DateTime.parse(r['created_at'] as String),
    );
  }

  /// 회원 1명의 메모 전체(초안 + 확정). 최신 먼저.
  /// RLS(notes_owner_rw)가 트레이너 본인 메모만 노출.
  Future<List<MemberNote>> listForMember(String memberId) async {
    final rows = await _client
        .from(_table)
        .select(
            'id, member_id, content, source, source_session_id, confirmed_at, created_at')
        .eq('member_id', memberId)
        .order('created_at', ascending: false);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(_fromRow)
        .toList(growable: false);
  }

  /// AI 메모 초안 생성 — generate-memo-draft Edge Function 호출.
  /// [sessionId] 미지정 시 서버가 회원의 최근 done 수업을 기반으로 생성.
  /// 실패는 [AiGenerationException](code)으로 던짐(consent/rate/llm/no_session).
  Future<String> generateMemoDraft({
    required String memberId,
    String? sessionId,
  }) async {
    try {
      final res = await _client.functions.invoke(
        'generate-memo-draft',
        body: {'memberId': memberId, 'sessionId': ?sessionId},
      );
      final data = res.data;
      if (data is Map && data['ok'] == true && data['noteId'] != null) {
        return data['noteId'] as String;
      }
      throw AiGenerationException(
        code: (data is Map ? data['code'] as String? : null) ?? 'unknown',
        message: (data is Map ? data['message'] as String? : null) ??
            'AI 메모 초안 생성에 실패했습니다.',
      );
    } on FunctionException catch (e) {
      final d = e.details;
      throw AiGenerationException(
        code: (d is Map ? d['code'] as String? : null) ?? 'unknown',
        message: (d is Map ? d['message'] as String? : null) ??
            'AI 메모 초안 생성에 실패했습니다. (오류 ${e.status})',
      );
    }
  }

  /// 초안 확정 — source='ai_confirmed', confirmed_at=now.
  Future<void> confirm(String id) async {
    await _client.from(_table).update({
      'source': _sourceToDb(NoteSource.aiConfirmed),
      'confirmed_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  /// 내용 수정. source 는 유지(초안이면 초안 그대로 — 재검수).
  Future<void> editContent({required String id, required String content}) async {
    await _client.from(_table).update({'content': content}).eq('id', id);
  }

  /// 메모 삭제(하드 삭제). 초안 폐기 또는 잘못된 메모 제거.
  Future<void> delete(String id) async {
    await _client.from(_table).delete().eq('id', id);
  }

  /// 수동 메모 추가 — source='manual', 트레이너 전용.
  Future<String> addManual({
    required String memberId,
    required String content,
    required String trainerId,
  }) async {
    final row = await _client
        .from(_table)
        .insert({
          'member_id': memberId,
          'trainer_id': trainerId,
          'content': content,
          'visibility': 'trainer_only',
          'source': _sourceToDb(NoteSource.manual),
        })
        .select('id')
        .single();
    return row['id'] as String;
  }
}
