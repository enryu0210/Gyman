/// 회원(member_profiles) CRUD repository.
///
/// **트레이너 시점만 다룬다:**
///   본 repository의 모든 메서드는 *현재 로그인한 트레이너* 시점에서
///   본인 담당 회원만 다룬다. RLS 정책 `member_by_trainer` 가 1차 방어.
///
/// **읽기 정책 (`listForCurrentTrainer`)**
///   - `member_by_trainer` RLS는 "트레이너 + 활성 계약 보유 회원" 만 노출
///   - 베타 단계엔 *계약 없는 회원* 도 표시해야 함 (계약은 1.3에서 등록)
///   - 따라서 본 메서드는 **회원이 본 트레이너의 어떤 데이터와 연결됐는가** 가
///     보장된 상태가 아니다 → 정책 추가 옵션을 1.3에서 검토 (예: created_by_trainer_id)
///   - 임시: 트레이너가 본인이 작성한 member_notes나 pt_contracts가 있는 회원만 뜸.
///     **본 단계엔 이 한계를 받아들이고, "회원 등록 후 곧바로 계약 등록" UX로 우회한다.**
///
/// 참고: docs/data_model.md §3.2 member_by_trainer 정책,
///       src/supabase/migrations/0013_member_profiles_offline_support.sql.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/models/member.dart';

/// 회원 추가 시 사용하는 입력 객체.
/// 모델보다 가벼움 — id/createdAt 등 서버 생성 필드는 제외.
class NewMemberInput {
  final String name;
  final String? phone;
  final String? goal;
  final String? experience;
  final String? injuryHistory;
  final String? bodyFeatures;
  final String? lifestyle;
  final DateTime? birthDate;
  final String? centerId;

  const NewMemberInput({
    required this.name,
    this.phone,
    this.goal,
    this.experience,
    this.injuryHistory,
    this.bodyFeatures,
    this.lifestyle,
    this.birthDate,
    this.centerId,
  });
}

class MemberRepository {
  final SupabaseClient _client;

  MemberRepository(this._client);

  static const _table = 'member_profiles';

  /// 행 1개를 [Member] 로 변환.
  ///
  /// Supabase는 timestamptz를 ISO8601 문자열로 반환.
  /// jsonb는 List/Map 으로 반환되지만 형태 변동 가능성 → 방어적 캐스팅.
  static Member _fromRow(Map<String, dynamic> row) {
    final raw = row['available_times'];
    final List<Map<String, dynamic>>? times = (raw is List)
        ? raw.whereType<Map<String, dynamic>>().toList()
        : null;

    return Member(
      id: row['id'] as String,
      userId: row['user_id'] as String?,
      centerId: row['center_id'] as String?,
      name: row['name'] as String,
      phone: row['phone'] as String?,
      birthDate: _parseDate(row['birth_date']),
      goal: row['goal'] as String?,
      experience: row['experience'] as String?,
      injuryHistory: row['injury_history'] as String?,
      bodyFeatures: row['body_features'] as String?,
      lifestyle: row['lifestyle'] as String?,
      availableTimes: times,
      createdAt: DateTime.parse(row['created_at'] as String),
      deletedAt: _parseDate(row['deleted_at']),
    );
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v as String);
  }

  /// 현재 로그인된 트레이너가 볼 수 있는 회원 목록.
  ///
  /// **현재 한계 (Phase 1.2-A):**
  ///   member_by_trainer RLS는 계약 보유 회원만 보여줌. 따라서 방금 등록한 회원도
  ///   계약이 없으면 본인이 작성한 INSERT의 RETURNING 응답으로만 보일 수 있음.
  ///   → Phase 1.3에서 created_by_trainer_id 컬럼 + 정책 추가 검토.
  ///
  /// soft delete된 회원은 제외. 이름순 정렬.
  Future<List<Member>> listForCurrentTrainer() async {
    final rows = await _client
        .from(_table)
        .select()
        .filter('deleted_at', 'is', null)
        .order('name');
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(_fromRow)
        .toList(growable: false);
  }

  /// 회원 1명 추가. INSERT 후 RETURNING 결과를 Member로 반환.
  ///
  /// user_id는 NULL로 시작 (앱 미가입). 회원 가입 후 [linkAuthUser] 로 매핑.
  Future<Member> addMember(NewMemberInput input) async {
    final row = await _client
        .from(_table)
        .insert({
          'name': input.name,
          'phone': input.phone,
          'goal': input.goal,
          'experience': input.experience,
          'injury_history': input.injuryHistory,
          'body_features': input.bodyFeatures,
          'lifestyle': input.lifestyle,
          'birth_date': input.birthDate?.toIso8601String(),
          'center_id': input.centerId,
          // user_id 미지정 — DB default NULL
        })
        .select()
        .single();
    return _fromRow(row);
  }

  /// 회원에 Supabase Auth 사용자 ID를 매핑.
  ///
  /// 사용 시점: 회원이 앱에 가입한 후, 트레이너가 "이 회원이다" 확정.
  /// 같은 user_id가 이미 다른 회원에게 매핑되어 있으면 UNIQUE 제약 위반.
  Future<Member> linkAuthUser({
    required String memberId,
    required String userId,
  }) async {
    final row = await _client
        .from(_table)
        .update({'user_id': userId})
        .eq('id', memberId)
        .select()
        .single();
    return _fromRow(row);
  }

  /// 회원 soft delete. 즉시 목록에서 사라지지만 DB row는 보존.
  Future<void> softDelete(String memberId) async {
    await _client
        .from(_table)
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', memberId);
  }
}
