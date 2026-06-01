import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/domain/models/enums.dart';
import 'package:gyman/features/trainer/session_log/session_repository.dart';

/// 회귀 테스트 — 수업 기록 화면 저장 시 status 전이 규칙.
///
/// **막는 버그:** 예약(scheduled) 수업을 기록 화면에서 저장해도 status 가
///   계속 scheduled 로 남던 문제(updateRecord 가 status 를 안 건드림).
///
/// 규칙: 기록 저장 = "수업이 진행됐다" → done 전이. 단 이미 done 이면 status/
///   recorded_at 을 건드리지 않아 최초 기록 시각·기록자를 보존한다.
void main() {
  final scheduledAt = DateTime(2026, 6, 1, 10);
  final now = DateTime(2026, 6, 1, 11);

  group('SessionRepository.buildRecordedSessionUpdate', () {
    test('예약(scheduled) 수업을 기록하면 done 으로 전이 + 기록 메타 채움', () {
      final u = SessionRepository.buildRecordedSessionUpdate(
        previousStatus: SessionStatus.scheduled,
        scheduledAt: scheduledAt,
        trainerId: 'tr1',
        now: now,
      );
      expect(u['status'], 'done');
      expect(u['recorded_at'], now.toIso8601String());
      expect(u['recorded_by_trainer_id'], 'tr1');
      expect(u['scheduled_at'], scheduledAt.toIso8601String());
    });

    test('이미 done 인 수업의 본문 수정은 status/recorded 메타를 안 건드림(최초 기록 보존)', () {
      final u = SessionRepository.buildRecordedSessionUpdate(
        previousStatus: SessionStatus.done,
        scheduledAt: scheduledAt,
        trainerId: 'tr1',
        now: now,
      );
      // done 전이 메타는 빠지고, 일시만 갱신.
      expect(u.containsKey('status'), isFalse);
      expect(u.containsKey('recorded_at'), isFalse);
      expect(u.containsKey('recorded_by_trainer_id'), isFalse);
      expect(u['scheduled_at'], scheduledAt.toIso8601String());
    });

    test('done 이 아닌 다른 상태(requested/noShow/canceled/lateCancel)도 기록 시 done 전이', () {
      for (final s in [
        SessionStatus.requested,
        SessionStatus.noShow,
        SessionStatus.canceled,
        SessionStatus.lateCancel,
      ]) {
        final u = SessionRepository.buildRecordedSessionUpdate(
          previousStatus: s,
          scheduledAt: scheduledAt,
          trainerId: 'tr1',
          now: now,
        );
        expect(u['status'], 'done', reason: '$s 에서 기록 저장 시 done 이어야 함');
      }
    });
  });
}
