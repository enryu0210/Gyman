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
  ///
  /// **콜드 스타트 첫 로그인 레이스 방어(재시도):**
  ///   로그인 직후 세션 JWT 가 REST 클라이언트 헤더에 붙기 *전에* RLS 프로필
  ///   쿼리가 나가면, 본인 row 가 0행으로 잡혀 role=null(미연결)로 오판된다.
  ///   그러면 라우터가 기존 회원/트레이너를 초대코드 화면(/member/claim)으로
  ///   보내버린다(재로그인하면 그제야 정상 — 실제 버그였다).
  ///   → 프로필이 **하나도** 안 잡히면 짧게 재시도한다([resolveRoleWithRetry]).
  ///     하나라도 잡히면 즉시 확정. 진짜 미연결 신규 계정은 몇 번을 재시도해도
  ///     계속 0행이라 결국 [UserRoleInfo.none] 을 반환해 초대코드 화면으로 간다.
  Future<UserRoleInfo> getRoleInfo() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return UserRoleInfo.none;
    return resolveRoleWithRetry(fetch: () => _fetchRoleInfoOnce(userId));
  }

  /// 프로필 3종 존재 여부를 **한 번** 동시 조회해 역할로 환산(재시도 1회분).
  Future<UserRoleInfo> _fetchRoleInfoOnce(String userId) async {
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

/// 역할 판정 재시도 기본 대기 — 시도가 거듭될수록 조금씩 늘린다(150·300ms…).
/// 콜드 스타트 토큰-부착 창(대개 수십~수백 ms)을 넘기기 위한 짧은 백오프.
Future<void> _defaultRoleRetryDelay(int attempt) =>
    Future<void>.delayed(Duration(milliseconds: 150 * (attempt + 1)));

/// 콜드 스타트 토큰-부착 레이스 방어 재시도 오케스트레이션(순수 로직 — 단위 테스트 대상).
///
/// [fetch] 는 프로필 조회 1회분으로 [UserRoleInfo] 를 돌려준다.
///   - `role != null` (프로필 하나라도 있음) → 즉시 그 결과 확정 반환.
///   - `role == null` (전부 0행) → 레이스일 수 있으니 [delay] 후 재시도.
///   - [maxAttempts] 회까지 모두 0행이면 → 진짜 미연결로 보고 마지막 결과(none) 반환.
///
/// [delay] 를 주입 가능하게 둬(테스트에선 no-op), 실제 대기 없이 재시도 흐름을 검증한다.
Future<UserRoleInfo> resolveRoleWithRetry({
  required Future<UserRoleInfo> Function() fetch,
  int maxAttempts = 3,
  Future<void> Function(int attempt) delay = _defaultRoleRetryDelay,
}) async {
  var info = UserRoleInfo.none;
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    info = await fetch();
    // 프로필이 하나라도 잡히면(role 확정) 즉시 반환 — 재시도 불필요.
    if (info.role != null) return info;
    // 전부 0행 — 마지막 시도가 아니면 짧게 기다렸다 재시도.
    if (attempt < maxAttempts - 1) await delay(attempt);
  }
  return info;
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
