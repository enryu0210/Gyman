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

  /// 현재 로그인 사용자의 역할 + 관리자 겸직 여부를 **한 번에** 판정한다.
  ///
  /// **왜 한 호출로 묶었나(레이스 수정):**
  ///   예전엔 역할(getCurrentUserRole)과 겸직(hasAdminProfile)이 별도 provider·별도
  ///   쿼리였다. 콜드 스타트 직후 로그인 시 JWT 가 REST 클라이언트에 붙는 찰나에
  ///   두 쿼리가 갈리면, trainer 쿼리는 성공(역할 판정 OK)하는데 admin 쿼리는 빈손
  ///   (isAdmin=false)으로 캐시돼 "관리자 대시보드 메뉴가 안 뜨다가 재로그인하면 뜸"
  ///   현상이 났다. 세 프로필을 한 번에 조회하면 동일 인증 컨텍스트에서 결정돼
  ///   "trainer 인데 admin 아님" 같은 불일치가 구조적으로 사라진다.
  ///
  /// 반환 [UserRoleInfo]:
  ///   - role   : 우선순위 trainer > admin > member (0029 DB current_user_role 과 동일)
  ///   - isAdmin: admin_profiles 보유 여부(겸직 포함). 메뉴 노출/라우터 허용 판정용.
  ///
  /// RLS(*_self_rw / admin_self_read)가 본인 row 만 노출 → 각 maybeSingle 로 충분.
  Future<UserRoleInfo> getRoleInfo() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return UserRoleInfo.none;

    // 세 프로필 존재 여부를 동시에 조회 — 같은 시점/같은 JWT 로 일관 판정.
    final results = await Future.wait([
      _existsProfile('trainer_profiles', userId),
      _existsProfile('admin_profiles', userId),
      _existsProfile('member_profiles', userId),
    ]);
    final hasTrainer = results[0];
    final isAdmin = results[1];
    final hasMember = results[2];

    // 우선순위: trainer > admin > member (한 사람이 여러 프로필이면 상위 역할).
    final role = hasTrainer
        ? UserRole.trainer
        : isAdmin
            ? UserRole.admin
            : hasMember
                ? UserRole.member
                : null;

    return UserRoleInfo(role: role, isAdmin: isAdmin);
  }

  /// 해당 프로필 테이블에 본인 row 가 있는지(RLS 로 본인 1행만 조회).
  Future<bool> _existsProfile(String table, String userId) async {
    final row = await _client
        .from(table)
        .select('user_id')
        .eq('user_id', userId)
        .maybeSingle();
    return row != null;
  }

  /// 가입 전 초대 코드 유효성 검증 (미사용 코드가 존재하는가).
  ///
  /// `verify_invite_code` RPC(0020) 호출 — anon 도 호출 가능(로그인 전).
  /// 유효한 코드 없이 계정이 만들어지지 않게, 회원가입 직전에 먼저 확인한다.
  Future<bool> verifyInviteCode(String code) async {
    final result = await _client.rpc(
      'verify_invite_code',
      params: {'p_code': code.trim()},
    );
    return result == true;
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

/// 역할 판정 결과 — 주 역할 + 관리자 겸직 여부를 한 묶음으로.
///
/// 역할과 겸직을 한 호출에서 같이 돌려줘, 둘을 쓰는 provider 들이 동일 소스에서
/// 일관된 값을 받게 한다(콜드 스타트 레이스 방지 — [RoleRepository.getRoleInfo]).
class UserRoleInfo {
  /// 우선순위로 정해진 단일 주 역할. 프로필 미생성이면 null.
  final UserRole? role;

  /// admin_profiles 보유 여부(겸직 포함). role 이 trainer 여도 true 일 수 있다.
  final bool isAdmin;

  const UserRoleInfo({required this.role, required this.isAdmin});

  /// 미로그인/미설정 기본값.
  static const none = UserRoleInfo(role: null, isAdmin: false);
}
