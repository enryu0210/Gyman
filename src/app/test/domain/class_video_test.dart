import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/domain/models/class_video.dart';

/// ClassVideo 단위 테스트 (수업 영상 — S 시리즈).
///
/// **검증 포인트:**
///   - PG bigint(size_bytes)/int(duration_sec) 이 num/String 어느 형태로 와도 int 로 흡수
///     (CLAUDE.md: bigint 는 `as int` 직접 캐스팅 금지)
///   - 제목 미입력/공백 → displayTitle 이 "수업 영상"으로 폴백
///   - durationLabel 의 "분:초" 포맷(0초/없음은 null)
///   - nullable 메타(session_id/title/duration/size/uploaded_by) 보존
void main() {
  /// 필수 컬럼만 채운 최소 행 + 덮어쓸 값들.
  Map<String, dynamic> row(Map<String, dynamic> overrides) => {
        'id': 'v1',
        'member_id': 'mem1',
        'session_id': null,
        'storage_path': 'mem1/123_456.mp4',
        'title': null,
        'duration_sec': null,
        'size_bytes': null,
        'uploaded_by': null,
        'created_at': '2026-05-30T09:00:00.000Z',
        ...overrides,
      };

  group('ClassVideo.fromRow', () {
    test('정상 행 — 모든 메타 매핑', () {
      final v = ClassVideo.fromRow(row({
        'session_id': 'sess1',
        'title': '스쿼트 폼 체크',
        'duration_sec': 83,
        'size_bytes': 150000000,
        'uploaded_by': 'tr1',
      }));
      expect(v.id, 'v1');
      expect(v.memberId, 'mem1');
      expect(v.sessionId, 'sess1');
      expect(v.storagePath, 'mem1/123_456.mp4');
      expect(v.title, '스쿼트 폼 체크');
      expect(v.durationSec, 83);
      expect(v.sizeBytes, 150000000);
      expect(v.uploadedBy, 'tr1');
      expect(v.createdAt, DateTime.utc(2026, 5, 30, 9));
    });

    test('bigint/int 가 String 으로 와도 int 로 파싱', () {
      final v = ClassVideo.fromRow(row({
        'duration_sec': '120',
        'size_bytes': '262144000',
      }));
      expect(v.durationSec, 120);
      expect(v.sizeBytes, 262144000);
    });

    test('size/duration 이 num(double) 으로 와도 int 로 흡수', () {
      final v = ClassVideo.fromRow(row({
        'duration_sec': 90.0,
        'size_bytes': 1000.0,
      }));
      expect(v.durationSec, 90);
      expect(v.sizeBytes, 1000);
    });

    test('nullable 메타가 비어 있어도 안전', () {
      final v = ClassVideo.fromRow(row({}));
      expect(v.sessionId, isNull);
      expect(v.title, isNull);
      expect(v.durationSec, isNull);
      expect(v.sizeBytes, isNull);
      expect(v.uploadedBy, isNull);
      expect(v.sessionScheduledAt, isNull);
      expect(v.isLinkedToSession, isFalse);
    });
  });

  group('ClassVideo — 연결된 수업(sessions embed) 파싱', () {
    test('embed 가 Map 이면 scheduled_at 파싱 + isLinkedToSession true', () {
      final v = ClassVideo.fromRow(row({
        'session_id': 'sess1',
        'sessions': {
          'scheduled_at': '2026-05-30T05:00:00.000Z',
          'status': 'done',
        },
      }));
      expect(v.sessionId, 'sess1');
      expect(v.isLinkedToSession, isTrue);
      expect(v.sessionScheduledAt, DateTime.utc(2026, 5, 30, 5));
    });

    test('embed 가 List 형태로 와도 첫 행에서 파싱(방어적)', () {
      final v = ClassVideo.fromRow(row({
        'session_id': 'sess1',
        'sessions': [
          {'scheduled_at': '2026-05-30T05:00:00.000Z', 'status': 'scheduled'},
        ],
      }));
      expect(v.sessionScheduledAt, DateTime.utc(2026, 5, 30, 5));
    });

    test('embed 가 null/빈 List 면 sessionScheduledAt 은 null', () {
      expect(ClassVideo.fromRow(row({'sessions': null})).sessionScheduledAt,
          isNull);
      expect(ClassVideo.fromRow(row({'sessions': []})).sessionScheduledAt,
          isNull);
    });

    test('session_id 는 있는데 RLS 로 embed 가 안 와도(미동봉) 크래시 없음', () {
      // 회원이 수업 행을 못 읽는 등으로 sessions 키 자체가 없을 수 있음.
      final v = ClassVideo.fromRow(row({'session_id': 'sess1'}));
      expect(v.isLinkedToSession, isTrue); // session_id 컬럼 기준
      expect(v.sessionScheduledAt, isNull); // 일시는 못 채움(라벨 생략)
    });
  });

  group('ClassVideo.displayTitle', () {
    test('제목 있으면 그대로', () {
      final v = ClassVideo.fromRow(row({'title': '데드리프트'}));
      expect(v.displayTitle, '데드리프트');
    });

    test('제목 null 이면 "수업 영상" 폴백', () {
      final v = ClassVideo.fromRow(row({}));
      expect(v.displayTitle, '수업 영상');
    });

    test('제목이 공백뿐이면 "수업 영상" 폴백', () {
      final v = ClassVideo.fromRow(row({'title': '   '}));
      expect(v.displayTitle, '수업 영상');
    });
  });

  group('ClassVideo.durationLabel', () {
    test('83초 → "1:23"', () {
      final v = ClassVideo.fromRow(row({'duration_sec': 83}));
      expect(v.durationLabel, '1:23');
    });

    test('5초 → "0:05" (초 2자리 패딩)', () {
      final v = ClassVideo.fromRow(row({'duration_sec': 5}));
      expect(v.durationLabel, '0:05');
    });

    test('120초 → "2:00"', () {
      final v = ClassVideo.fromRow(row({'duration_sec': 120}));
      expect(v.durationLabel, '2:00');
    });

    test('길이 없음/0 이하 → null(표시 생략)', () {
      expect(ClassVideo.fromRow(row({})).durationLabel, isNull);
      expect(ClassVideo.fromRow(row({'duration_sec': 0})).durationLabel, isNull);
    });
  });
}
