/// PT 알림 발화 시각 계산 단위 테스트 (순수 도메인).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/domain/pt_reminder.dart';

void main() {
  // 기준 현재: 2026-06-17 10:00 (벽시계).
  final now = DateTime(2026, 6, 17, 10, 0);

  group('PtReminderLead', () {
    test('off 는 꺼짐, 나머지는 켜짐', () {
      expect(PtReminderLead.off.isOn, isFalse);
      expect(PtReminderLead.hour1.isOn, isTrue);
      expect(PtReminderLead.hour1.lead, const Duration(hours: 1));
    });

    test('fromName 복원, 알 수 없으면 기본 1시간 전', () {
      expect(PtReminderLead.fromName('min30'), PtReminderLead.min30);
      expect(PtReminderLead.fromName(null), PtReminderLead.hour1);
      expect(PtReminderLead.fromName('garbage'), PtReminderLead.hour1);
    });
  });

  group('computePtReminders', () {
    test('off 면 빈 목록', () {
      final r = computePtReminders(
        sessionStarts: [DateTime(2026, 6, 17, 14, 0)],
        lead: PtReminderLead.off,
        now: now,
      );
      expect(r, isEmpty);
    });

    test('1시간 전 — 오후 2시 수업이면 13:00 에 발화', () {
      final r = computePtReminders(
        sessionStarts: [DateTime(2026, 6, 17, 14, 0)],
        lead: PtReminderLead.hour1,
        now: now,
      );
      expect(r.length, 1);
      expect(r.single.sessionStart, DateTime(2026, 6, 17, 14, 0));
      expect(r.single.fireAt, DateTime(2026, 6, 17, 13, 0));
    });

    test('발화 시각이 이미 지났으면 제외 (수업이 30분 뒤인데 1시간 전 알림)', () {
      // now=10:00, 수업 10:30 → 발화 09:30(과거) → 스킵.
      final r = computePtReminders(
        sessionStarts: [DateTime(2026, 6, 17, 10, 30)],
        lead: PtReminderLead.hour1,
        now: now,
      );
      expect(r, isEmpty);
    });

    test('isUtc(파싱 결과 모방) 입력도 벽시계 필드 그대로 사용 — tz 변환 안 함', () {
      // scheduled_at 파싱 결과는 isUtc=true, 필드=벽시계 14:00. KST 로 밀면 안 됨.
      final r = computePtReminders(
        sessionStarts: [DateTime.utc(2026, 6, 17, 14, 0)],
        lead: PtReminderLead.hour1,
        now: now,
      );
      expect(r.single.sessionStart, DateTime(2026, 6, 17, 14, 0));
      expect(r.single.fireAt, DateTime(2026, 6, 17, 13, 0));
    });

    test('발화 시각 오름차순 정렬 + max 제한', () {
      final starts = [
        DateTime(2026, 6, 20, 14, 0),
        DateTime(2026, 6, 18, 9, 0),
        DateTime(2026, 6, 19, 18, 0),
      ];
      final r = computePtReminders(
        sessionStarts: starts,
        lead: PtReminderLead.hour1,
        now: now,
        max: 2,
      );
      expect(r.length, 2); // max
      expect(r[0].fireAt.isBefore(r[1].fireAt), isTrue); // 정렬
      expect(r[0].sessionStart, DateTime(2026, 6, 18, 9, 0)); // 가장 가까운 것
    });

    test('하루 전 리드타임', () {
      final r = computePtReminders(
        sessionStarts: [DateTime(2026, 6, 20, 14, 0)],
        lead: PtReminderLead.dayBefore,
        now: now,
      );
      expect(r.single.fireAt, DateTime(2026, 6, 19, 14, 0));
    });
  });
}
