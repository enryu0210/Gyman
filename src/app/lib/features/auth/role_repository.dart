/// 사용자 역할 판정 repository.
///
/// **판정 로직:**
///   본인이 `trainer_profiles` 행을 가지면 [UserRole.trainer]
///   아니면 `member_profiles` 행을 가지면 [UserRole.member]
///   둘 다 없으면 null (계정만 있고 프로필 미생성 상태)
///
/// **왜 클라이언트에서 판정하나:**
///   - DB `current_user_role()` 함수와 동일 로직을 RPC로 호출할 수도 있지만,
///     라운드트립 1회로 충분하고 RLS가 본인 row만 보여주므로 안전
///   - 추후 admin_profiles 추가 시 우선순위 정의도 한 곳에 모음
///
/// **RLS 의존성:**
///   trainer_profiles의 `trainer_self_rw` 정책이 본인 row만 노출하므로
///   `SELECT user_id ... WHERE user_id = auth.uid()` 가 0행 또는 1행을 반환한다.
///   따라서 maybeSingle 사용으로 충분.
///
/// 참고: docs/data_model.md §3.1 current_user_role() 함수,
///       src/supabase/migrations/0010_rls_policies.sql trainer_self_rw, member_self_rw.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/enums.dart';

class RoleRepository {
  final SupabaseClient _client;

  RoleRepository(this._client);

  /// 현재 로그인된 사용자의 역할을 판정한다.
  ///
  /// 반환:
  ///   - [UserRole.trainer] : trainer_profiles에 본인 row 존재
  ///   - [UserRole.member]  : member_profiles에 본인 row 존재
  ///   - null              : 미로그인 또는 프로필 미생성
  ///
  /// 예시:
  ///   - 트레이너 계정 로그인 → UserRole.trainer
  ///   - 회원 계정 로그인 → UserRole.member
  ///   - Supabase Auth에는 가입됐지만 프로필 INSERT 전 → null
  Future<UserRole?> getCurrentUserRole() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    // 1) 트레이너 우선 (한 사람이 두 프로필을 가지는 경우는 데이터 오류 — 트레이너 우선)
    final trainer = await _client
        .from('trainer_profiles')
        .select('user_id')
        .eq('user_id', userId)
        .maybeSingle();
    if (trainer != null) return UserRole.trainer;

    // 2) 회원
    final member = await _client
        .from('member_profiles')
        .select('user_id')
        .eq('user_id', userId)
        .maybeSingle();
    if (member != null) return UserRole.member;

    // Phase 3에서 admin_profiles 추가될 때 여기에 분기 추가
    return null;
  }

  /// 초대 코드로 현재 로그인 계정에 회원 프로필을 연결.
  ///
  /// DB의 SECURITY DEFINER 함수 `claim_member_profile` 를 호출(0019).
  /// 반환: 연결된 member_profiles.id, 코드가 틀리거나 이미 사용된 경우 null.
  ///
  /// 가입 직후 회원은 아직 어떤 프로필과도 연결돼 있지 않아 RLS로 직접 UPDATE 할 수
  /// 없으므로, 좁게 제한된 RPC 로만 연결한다.
  Future<String?> claimMemberProfile(String code) async {
    final result = await _client.rpc(
      'claim_member_profile',
      params: {'p_code': code.trim()},
    );
    // rpc 는 스칼라(uuid 문자열) 또는 null 을 반환.
    return result as String?;
  }
}
