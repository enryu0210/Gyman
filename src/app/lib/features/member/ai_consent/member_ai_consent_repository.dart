/// 회원 본인의 AI 사용 동의 상태 조회 + 거부 토글.
///
/// **왜 회원 쪽에 따로 두나:** AI 동의를 켜는 UI 는 트레이너 화면에만 있었고
/// 회원은 본인 상태를 보지도 끄지도 못했다. 그런데 개인정보 처리방침은
/// "회원이 동의한 경우에만" LLM 에 보낸다고 단언한다 — 문안이 사실과 달랐다.
/// (docs/legal_docs_gap_check.md A-2)
///
/// **트레이너 저장소를 재사용하지 않는 이유:** `trainer/member/member_repository`
/// 는 "담당 회원 목록"이 전제라 RLS 경로가 다르고, 회원은 자기 행 하나만 보면 된다.
///
/// 쓰기는 `ai_consent_member_optout` **한 컬럼만** 건드린다. 트레이너가 기록하는
/// `ai_consent` 는 회원이 손대지 않는다 — 두 값은 별개의 사실이다(0040).
library;

import 'package:supabase_flutter/supabase_flutter.dart';

/// 회원 본인 시점의 AI 동의 상태.
class MemberAiConsentState {
  const MemberAiConsentState({
    required this.trainerRecorded,
    required this.memberOptedOut,
  });

  /// 트레이너가 "회원에게 동의를 받았다"고 기록했는지.
  final bool trainerRecorded;

  /// 회원 본인이 거부했는지.
  final bool memberOptedOut;

  /// 실제로 AI 에 전송되는 상태인지. 서버 판정(`ai_consent_effective`)과 같은 식.
  bool get isActive => trainerRecorded && !memberOptedOut;
}

class MemberAiConsentFailure implements Exception {
  MemberAiConsentFailure(this.message, {this.cause});
  final String message;
  final Object? cause;
  @override
  String toString() => 'MemberAiConsentFailure($message)';
}

class MemberAiConsentRepository {
  MemberAiConsentRepository(this._client);

  final SupabaseClient _client;

  /// 조회할 컬럼. 실효값은 클라가 계산하므로(Member.aiConsentEffective 와 동일 식)
  /// 원인이 되는 두 값을 받아 화면에서 "왜 꺼져 있는지"까지 설명할 수 있게 한다.
  static const _columns = 'id, ai_consent, ai_consent_member_optout';

  /// 로그인한 회원 본인의 동의 상태. 연결된 프로필이 없으면 null.
  Future<MemberAiConsentState?> fetchMine() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      // RLS member_self_rw(user_id = auth.uid()) 가 본인 행만 노출한다.
      final row = await _client
          .from('member_profiles')
          .select(_columns)
          .eq('user_id', uid)
          .maybeSingle();
      if (row == null) return null;
      return MemberAiConsentState(
        trainerRecorded: row['ai_consent'] as bool? ?? false,
        memberOptedOut: row['ai_consent_member_optout'] as bool? ?? false,
      );
    } catch (e) {
      throw MemberAiConsentFailure('AI 사용 설정을 불러오지 못했습니다.', cause: e);
    }
  }

  /// 회원 본인의 거부 여부를 바꾼다.
  ///
  /// [optOut] true = 거부(전송 중단), false = 거부 철회.
  /// DB 트리거가 "본인만 변경 가능"을 강제하므로, 다른 사람의 행을 노려도 막힌다.
  Future<void> setOptOut(bool optOut) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw MemberAiConsentFailure('로그인이 필요합니다.');
    }
    try {
      await _client
          .from('member_profiles')
          .update({'ai_consent_member_optout': optOut})
          .eq('user_id', uid);
    } catch (e) {
      throw MemberAiConsentFailure('AI 사용 설정을 저장하지 못했습니다.', cause: e);
    }
  }
}
