/// 역할 판정 재시도 로직 회귀 테스트 — 콜드 스타트 토큰-부착 레이스 방어.
///
/// **왜 이 테스트가 있나(버그 재발 방지):**
///   콜드 스타트 후 첫 로그인 시, 세션 JWT 가 REST 클라이언트에 붙기 전에 RLS
///   프로필 쿼리가 나가면 본인 row 가 0행으로 잡혀 role=null(미연결)로 오판됐다.
///   그러면 기존 회원/트레이너가 초대코드 화면(/member/claim)으로 튕겼고,
///   로그아웃 후 재로그인해야만 정상 동작했다. [resolveRoleWithRetry] 가 "전부
///   0행"일 때만 짧게 재시도해 이 레이스를 흡수한다.
///
/// 실제 Supabase 조회는 RLS 에 위임하므로, 여기서는 재시도 오케스트레이션(순수
/// 로직)만 fake fetch + no-op delay 로 검증한다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/domain/models/enums.dart';
import 'package:gyman/features/auth/role_repository.dart';

void main() {
  // 테스트에선 실제 대기 없이 재시도 흐름만 본다.
  Future<void> noDelay(int _) async {}

  group('resolveRoleWithRetry — 콜드 스타트 토큰 레이스 방어', () {
    test('첫 조회가 0행(레이스)이어도 재시도에서 프로필이 잡히면 그 역할로 확정', () async {
      // 1회차: JWT 미부착 → 0행(none). 2회차부터: trainer 프로필 잡힘.
      var calls = 0;
      Future<UserRoleInfo> fetch() async {
        calls++;
        if (calls == 1) return UserRoleInfo.none;
        return const UserRoleInfo(role: UserRole.trainer, isAdmin: false);
      }

      final info = await resolveRoleWithRetry(fetch: fetch, delay: noDelay);

      expect(info.role, UserRole.trainer);
      expect(calls, 2, reason: '1회 재시도 후 확정되어야 한다');
    });

    test('프로필이 하나라도 있으면 즉시 확정 — 재시도하지 않는다', () async {
      var calls = 0;
      Future<UserRoleInfo> fetch() async {
        calls++;
        return const UserRoleInfo(role: UserRole.member, isAdmin: false);
      }

      final info = await resolveRoleWithRetry(fetch: fetch, delay: noDelay);

      expect(info.role, UserRole.member);
      expect(calls, 1, reason: '첫 성공이면 재시도 없이 끝나야 한다');
    });

    test('트레이너 겸 관리자: role=trainer + isAdmin=true 를 그대로 보존', () async {
      final info = await resolveRoleWithRetry(
        fetch: () async =>
            const UserRoleInfo(role: UserRole.trainer, isAdmin: true),
        delay: noDelay,
      );

      expect(info.role, UserRole.trainer);
      expect(info.isAdmin, isTrue);
    });

    test('끝까지 0행이면(진짜 미연결 신규 계정) maxAttempts 소진 후 none 반환', () async {
      var calls = 0;
      Future<UserRoleInfo> fetch() async {
        calls++;
        return UserRoleInfo.none;
      }

      final info = await resolveRoleWithRetry(
        fetch: fetch,
        maxAttempts: 3,
        delay: noDelay,
      );

      expect(info.role, isNull, reason: '진짜 미연결은 재시도해도 null → 초대코드 화면으로');
      expect(info.isAdmin, isFalse);
      expect(calls, 3, reason: '전부 0행이면 maxAttempts 만큼 시도한다');
    });
  });
}
