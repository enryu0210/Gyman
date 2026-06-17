/// PT 알림 설정 + 재동기화 provider.
///
/// - [notificationServiceProvider] : 로컬 알림 플랫폼 래퍼(싱글톤)
/// - [ptReminderRepositoryProvider]: 다가올 예약 조회
/// - [ptReminderLeadProvider]      : 현재 리드타임(설정) + 변경/재동기화
///
/// **흐름:** 회원 홈 진입/새로고침·설정 변경 시 [PtReminderLeadController.resync] →
///   다가올 예약 조회 → [computePtReminders] 로 발화 목록 계산 → 서비스가 OS 예약.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../domain/pt_reminder.dart';
import 'pt_reminder_repository.dart';

/// SharedPreferences 키 — 리드타임 enum 이름 저장.
const _prefsKey = 'pt_reminder_lead';

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService.instance;
});

final ptReminderRepositoryProvider = Provider<PtReminderRepository>((ref) {
  return PtReminderRepository(ref.watch(supabaseClientProvider));
});

/// 현재 PT 알림 리드타임. 변경 시 저장 + 권한 요청 + 재동기화를 함께 처리한다.
class PtReminderLeadController extends AsyncNotifier<PtReminderLead> {
  Future<PtReminderLead> _load() async {
    final prefs = await SharedPreferences.getInstance();
    return PtReminderLead.fromName(prefs.getString(_prefsKey));
  }

  @override
  Future<PtReminderLead> build() => _load();

  /// 리드타임 변경: 로컬 저장 → (켜면) 권한 요청 → 알림 재동기화.
  Future<void> setLead(PtReminderLead lead) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, lead.name);
    state = AsyncData(lead);

    final service = ref.read(notificationServiceProvider);
    if (lead.isOn) {
      // 켤 때만 권한 요청(거부해도 앱은 정상, 알림만 안 뜸).
      await service.requestPermission();
    }
    await resync();
  }

  /// 현재 설정 기준으로 다가올 예약 알림을 다시 예약.
  /// 앱/회원 홈 진입·새로고침·예약 변경 후 호출(트레이너 승인분도 이때 반영).
  Future<void> resync() async {
    final lead = state.valueOrNull ?? await _load();
    final service = ref.read(notificationServiceProvider);

    if (!lead.isOn) {
      await service.cancelAll();
      return;
    }
    try {
      final starts = await ref
          .read(ptReminderRepositoryProvider)
          .fetchUpcomingSessionStarts();
      final reminders = computePtReminders(
        sessionStarts: starts,
        lead: lead,
        now: DateTime.now(),
      );
      await service.rescheduleAll(reminders);
    } catch (e) {
      // 조회/예약 실패해도 앱은 멈추지 않음 — 다음 진입 시 재시도.
      debugPrint('[PtReminder] resync 실패: $e');
    }
  }
}

final ptReminderLeadProvider =
    AsyncNotifierProvider<PtReminderLeadController, PtReminderLead>(
  PtReminderLeadController.new,
);
