/// 출석 달력 시각 파싱 회귀 테스트.
///
/// 버그: PT 예약이 오후 2시(14:00)인데 달력에 23:00 으로 표시됨(+9h).
/// 원인: 세션 시각은 "벽시계 그대로" 컨벤션인데 출석 repository 만 `.toLocal()` 을
///   호출해 timestamptz 를 로컬(KST)로 한 번 더 밀어버림.
///
/// 이 테스트는 **호스트 타임존과 무관하게** 깨지도록 설계됐다:
///   - 수정 후: parse 결과가 isUtc=true 이고 hour 가 적재된 벽시계(14)와 일치.
///   - 수정 전(toLocal): isUtc=false 가 되어 `isUtc` 단언에서 결정적으로 실패
///     (UTC 호스트에서도 잡힌다 — hour 만 보면 UTC 머신에선 못 잡으므로 isUtc 도 함께 본다).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/core/util/date_format_ko.dart';
import 'package:gyman/features/member/attendance/member_attendance_repository.dart';

void main() {
  group('parseSessionTimestamp — 벽시계 보존(toLocal 금지)', () {
    test('timestamptz(+00:00) 의 시각을 로컬로 밀지 않는다', () {
      // PostgREST 가 timestamptz 를 돌려주는 형태(오후 2시로 적재된 예약).
      final dt = MemberAttendanceRepository.parseSessionTimestamp(
        '2026-06-17T14:00:00+00:00',
      );

      expect(dt, isNotNull);
      // toLocal 을 부르면 isUtc=false 가 된다 → 이 단언이 호스트 tz 와 무관하게 막는다.
      expect(dt!.isUtc, isTrue,
          reason: 'toLocal() 을 호출하면 isUtc=false 가 되어 시각이 밀린다');
      expect(dt.hour, 14, reason: '오후 2시는 14시로 유지돼야 한다(23시 X)');
      expect(dt.minute, 0);
    });

    test('Z 표기도 동일하게 벽시계 유지', () {
      final dt = MemberAttendanceRepository.parseSessionTimestamp(
        '2026-06-17T09:30:00Z',
      );
      expect(dt!.isUtc, isTrue);
      expect(dt.hour, 9);
      expect(dt.minute, 30);
    });

    test('date(시각 없음) 컬럼도 안전하게 파싱', () {
      final dt = MemberAttendanceRepository.parseSessionTimestamp('2026-06-17');
      expect(dt, isNotNull);
      expect(dt!.year, 2026);
      expect(dt.month, 6);
      expect(dt.day, 17);
    });

    test('null 은 null', () {
      expect(MemberAttendanceRepository.parseSessionTimestamp(null), isNull);
    });
  });

  group('달력 셀 시간 표기(formatHm) — 적재 시각 그대로', () {
    test('오후 2시 예약은 "14:00" 으로 표기된다', () {
      final dt = MemberAttendanceRepository.parseSessionTimestamp(
        '2026-06-17T14:00:00+00:00',
      )!;
      expect(formatHm(dt), '14:00');
    });
  });
}
