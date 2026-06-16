/// 설정 화면 데이터 접근 — 문의 전송 / 동의 기록 / 회원 탈퇴.
///
/// **왜 한 repository로 묶나:** 모두 "계정/지원" 성격의 단발 동작이라 화면과
/// co-locate 한다. 탈퇴만 Edge Function(service_role 필요), 나머지는 RLS 직접 접근.
///
/// 참고: migrations 0033(support_inquiries)·0034(user_consents),
///       functions/delete-account, docs/untok_improvement_plan.md §5 A·B.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_info.dart';

/// 설정 동작 실패를 사용자 친화 메시지로 감싼 예외.
class SettingsFailure implements Exception {
  final String message;
  final Object? cause;
  const SettingsFailure(this.message, {this.cause});

  @override
  String toString() => 'SettingsFailure($message)';
}

class SettingsRepository {
  final SupabaseClient _client;

  SettingsRepository(this._client);

  /// 앱 내 문의 전송 — support_inquiries 에 본인 명의로 적재(RLS).
  ///
  /// 운영자(관리자)가 문의함에서 확인한다. [role] 은 작성 시점 역할 라벨(참고용).
  Future<void> submitInquiry({required String message, String? role}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const SettingsFailure('로그인이 필요합니다.');
    final trimmed = message.trim();
    if (trimmed.isEmpty) throw const SettingsFailure('문의 내용을 입력해 주세요.');

    try {
      await _client.from('support_inquiries').insert({
        'user_id': uid,
        'role': role,
        'message': trimmed,
        'app_version': kAppVersion,
      });
    } catch (e) {
      throw SettingsFailure('문의 전송에 실패했습니다. 잠시 후 다시 시도해 주세요.', cause: e);
    }
  }

  /// 이용약관/개인정보 동의 기록(upsert). 가입 직후 호출.
  ///
  /// 동의 기록 실패가 가입 흐름을 막지 않도록 예외를 삼킨다(UI 체크박스가 1차 게이트).
  Future<void> recordConsent() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await _client.from('user_consents').upsert({
        'user_id': uid,
        'terms_version': kTermsVersion,
        'privacy_version': kPrivacyVersion,
      });
    } catch (_) {
      // 의도적 무시 — 동의 자체는 UI 에서 강제됐고, 기록은 보조.
    }
  }

  /// 회원 탈퇴(익명화) — Edge Function `delete-account` 호출.
  ///
  /// 서버에서 PII 익명화 + auth 계정 삭제까지 수행한다. 성공 후 호출 측이 로그아웃.
  /// 실패 코드별 메시지는 함수가 내려준 본문([FunctionException.details])을 우선 사용.
  Future<void> deleteAccount({required String reason, String? detail}) async {
    try {
      final res = await _client.functions.invoke(
        'delete-account',
        body: {
          'reason': reason,
          if (detail != null && detail.trim().isNotEmpty) 'detail': detail.trim(),
        },
      );
      final data = res.data;
      final ok = data is Map && data['ok'] == true;
      if (!ok) {
        final msg = (data is Map && data['message'] is String)
            ? data['message'] as String
            : '탈퇴 처리에 실패했습니다. 잠시 후 다시 시도해 주세요.';
        throw SettingsFailure(msg);
      }
    } on SettingsFailure {
      rethrow;
    } on FunctionException catch (e) {
      // .details = 함수가 내려준 JSON 본문(코드별 메시지 포함).
      final det = e.details;
      final msg = (det is Map && det['message'] is String)
          ? det['message'] as String
          : '탈퇴 처리에 실패했습니다. 잠시 후 다시 시도해 주세요.';
      throw SettingsFailure(msg, cause: e);
    } catch (e) {
      // 네트워크/미배포 등 — 일반 예외.
      throw SettingsFailure('네트워크 오류로 탈퇴를 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.', cause: e);
    }
  }
}
