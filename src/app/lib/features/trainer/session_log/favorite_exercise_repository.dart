/// 트레이너 즐겨찾기 종목(trainer_favorite_exercises) repository.
///
/// Phase 1.5 — "자주 쓰는 종목을 1탭으로 추가" 를 위한 데이터 액세스.
///
/// **RLS:** `fav_owner_rw` 정책으로 본인 즐겨찾기만 read/write 가능.
/// trainer_id 는 DB default(auth.uid()) 가 채우므로 INSERT 시 명시 불필요.
///
/// **정렬:** position 오름차순, 같으면 created_at. SQL 인덱스도 동일 키.
/// 드래그 정렬 UX 가 추가될 때 [updatePosition] 추가.
///
/// 참고: src/supabase/migrations/0015_trainer_favorite_exercises.sql.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

/// 즐겨찾기 1행 — 화면에서는 name 만 보이지만, 삭제/정렬 시 id 가 필요해 객체로.
class FavoriteExercise {
  final String id;
  final String name;
  final int position;
  final DateTime createdAt;

  const FavoriteExercise({
    required this.id,
    required this.name,
    required this.position,
    required this.createdAt,
  });
}

class FavoriteExerciseRepository {
  final SupabaseClient _client;
  FavoriteExerciseRepository(this._client);

  static const _table = 'trainer_favorite_exercises';

  static FavoriteExercise _fromRow(Map<String, dynamic> row) => FavoriteExercise(
        id: row['id'] as String,
        name: row['name'] as String,
        // PG int4 → Dart 에선 그냥 int 로 오지만 view 조회 패턴과 통일해 num 캐스팅.
        position: (row['position'] as num).toInt(),
        createdAt: DateTime.parse(row['created_at'] as String),
      );

  /// 현재 로그인된 트레이너의 즐겨찾기 리스트 (position → created_at 오름차순).
  ///
  /// RLS 가 본인 행만 노출 → 별도 필터 불필요.
  Future<List<FavoriteExercise>> listForCurrentTrainer() async {
    final rows = await _client
        .from(_table)
        .select()
        .order('position')
        .order('created_at');
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(_fromRow)
        .toList(growable: false);
  }

  /// 즐겨찾기 추가. trainer_id 는 DB default 가 채움.
  ///
  /// UNIQUE(trainer_id, name) 위반 시 PostgrestException 이 그대로 위로 던져짐.
  /// 호출 측은 메시지로 "이미 등록된 종목입니다." 안내.
  ///
  /// position 은 현재 가장 큰 값 + 10 으로 새로 잡아 "맨 뒤" 에 배치.
  /// (10 단위 간격으로 두면 나중에 사이에 끼워넣기 쉬움 — 향후 드래그 정렬 대비)
  Future<FavoriteExercise> addFavorite(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('종목명이 비어 있습니다.');
    }

    // 현재 최대 position 조회 — 없으면 0 부터.
    final maxRow = await _client
        .from(_table)
        .select('position')
        .order('position', ascending: false)
        .limit(1)
        .maybeSingle();
    final nextPosition =
        ((maxRow?['position'] as num?)?.toInt() ?? 0) + 10;

    final row = await _client
        .from(_table)
        .insert({
          'name': trimmed,
          'position': nextPosition,
        })
        .select()
        .single();
    return _fromRow(row);
  }

  /// 즐겨찾기 1건 삭제. RLS 가 본인 행만 노출하므로 다른 트레이너 것은 영향 없음.
  Future<void> deleteFavorite(String id) async {
    await _client.from(_table).delete().eq('id', id);
  }
}
