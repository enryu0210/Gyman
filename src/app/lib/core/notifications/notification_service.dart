/// 로컬 알림 플랫폼 래퍼 (flutter_local_notifications).
///
/// PT 시작 전 알림을 **기기에서 직접 예약**한다(FCM 없음). 언제 알릴지(발화 목록)는
/// 순수 도메인 [computePtReminders] 가 계산하고, 여기서는 그 목록을 실제 OS 알림으로
/// 예약/취소하는 플랫폼 작업만 담당한다.
///
/// **방어적 설계:** 플랫폼 미지원(테스트 VM·데스크톱)·권한 거부 등에서 호출돼도
///   크래시 없이 조용히 no-op 하도록 모든 플랫폼 호출을 try-catch 로 감싼다.
///
/// **정시(exact) 대신 inexact:** `inexactAllowWhileIdle` 사용 → SCHEDULE_EXACT_ALARM
///   권한 불필요(Android14 정책 회피). "1시간 전" 알림에 몇 분 오차는 무방.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../domain/pt_reminder.dart';
import '../util/date_format_ko.dart';

class NotificationService {
  NotificationService._();

  /// 앱 전역 싱글톤(main 초기화 + provider 공유).
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// 타임존 DB + 플러그인 초기화. 여러 번 불려도 1회만 수행.
  Future<void> init() async {
    if (_initialized) return;
    try {
      // tz DB 로드 — zonedSchedule 의 TZDateTime 에 필요. tz.local 은 UTC 기본값을
      // 쓰며, 예약은 "지금(tz.local)부터 N후" 상대 시각이라 기기 타임존 탐지 불필요.
      tz_data.initializeTimeZones();

      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      // iOS 권한은 init 에서 요청하지 않고, 사용자가 알림을 켤 때 요청한다.
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: darwin),
      );
      _initialized = true;
    } catch (e) {
      debugPrint('[NotificationService] init 실패(플랫폼 미지원?): $e');
    }
  }

  /// 알림 권한 요청. 허용 여부 반환(미지원/실패 시 false).
  Future<bool> requestPermission() async {
    await init();
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        return await android.requestNotificationsPermission() ?? false;
      }
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        return await ios.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }
    } catch (e) {
      debugPrint('[NotificationService] 권한 요청 실패: $e');
    }
    return false;
  }

  /// 예약된 모든 알림 취소.
  Future<void> cancelAll() async {
    await init();
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('[NotificationService] cancelAll 실패: $e');
    }
  }

  /// 기존 예약을 모두 지우고 [reminders] 를 새로 예약한다(idempotent 재동기화).
  Future<void> rescheduleAll(List<PtReminder> reminders) async {
    await init();
    try {
      await _plugin.cancelAll();
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'pt_reminder',
          'PT 수업 알림',
          channelDescription: '예약된 PT 수업 시작 전에 보내는 알림',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      );

      final now = DateTime.now();
      for (var i = 0; i < reminders.length; i++) {
        final r = reminders[i];
        // 절대 시각 대신 "지금부터 남은 시간"으로 예약 → 기기 타임존과 무관하게
        // 정확. (fireAt·now 모두 벽시계 naive 라 차이가 곧 실제 남은 시간)
        final delay = r.fireAt.difference(now);
        if (delay.isNegative) continue; // 방어: 이미 지난 발화는 스킵.
        final when = tz.TZDateTime.now(tz.local).add(delay);
        await _plugin.zonedSchedule(
          i,
          'PT 수업 알림',
          '${formatKoreanDateTime(r.sessionStart)} 수업이 곧 시작돼요.',
          when,
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    } catch (e) {
      debugPrint('[NotificationService] rescheduleAll 실패: $e');
    }
  }
}
