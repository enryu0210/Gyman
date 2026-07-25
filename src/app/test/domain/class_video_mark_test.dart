/// 영상 시점 지적 모델·타임라인 단위 테스트 (L2).
///
/// **왜 고정하는가:** 트레이너 화면과 회원 화면이 **같은 순간에 같은 지적**을 보여줘야
///   한다. 표시 창(window) 판정이 어긋나면 트레이너는 "0:12에 남겼는데 회원은 못 봤다"는
///   상황이 생기고, 그건 이 기능의 신뢰를 바로 깎는다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/domain/models/class_video_mark.dart';

ClassVideoMark mark(int tMs, {String id = 'm', String? bodyPart}) {
  return ClassVideoMark(
    id: '$id$tMs',
    videoId: 'v1',
    tMs: tMs,
    bodyPart: bodyPart,
    comment: '코멘트 $tMs',
    createdAt: DateTime(2026, 7, 25),
  );
}

void main() {
  group('시점 표기', () {
    test('밀리초를 m:ss 로 쓴다', () {
      expect(ClassVideoMark.formatMs(0), '0:00');
      expect(ClassVideoMark.formatMs(12000), '0:12');
      expect(ClassVideoMark.formatMs(65000), '1:05');
      expect(ClassVideoMark.formatMs(119999), '1:59');
    });

    test('음수는 0으로 클램프한다 (방어)', () {
      expect(ClassVideoMark.formatMs(-1), '0:00');
    });

    test('timeLabel 이 같은 포맷을 쓴다', () {
      expect(mark(12000).timeLabel, '0:12');
    });
  });

  group('부위 태그', () {
    test('코드가 표시명으로 바뀐다', () {
      expect(VideoMarkBodyParts.labelOf('knee'), '무릎');
      expect(VideoMarkBodyParts.labelOf('lumbar'), '허리');
    });

    test('카탈로그에 없는 코드는 원문 그대로 (기존 마킹이 안 깨짐)', () {
      expect(VideoMarkBodyParts.labelOf('elbow'), 'elbow');
    });

    test('태그가 없으면 bodyPartLabel 은 null', () {
      expect(mark(1000).bodyPartLabel, isNull);
      expect(mark(1000, bodyPart: 'knee').bodyPartLabel, '무릎');
    });

    test('부위 코드가 중복되지 않는다', () {
      final codes = VideoMarkBodyParts.items.map((p) => p.code).toList();
      expect(codes.toSet().length, codes.length);
    });
  });

  group('VideoMarkTimeline.activeAt — 표시 창', () {
    test('마킹 시점부터 표시된다', () {
      final marks = [mark(10000)];
      expect(VideoMarkTimeline.activeAt(marks, 9999), isNull);
      expect(VideoMarkTimeline.activeAt(marks, 10000)?.tMs, 10000);
    });

    test('표시 창이 끝나면 사라진다', () {
      final marks = [mark(10000)];
      final end = 10000 + VideoMarkTimeline.displayWindowMs;
      expect(VideoMarkTimeline.activeAt(marks, end - 1)?.tMs, 10000);
      expect(VideoMarkTimeline.activeAt(marks, end), isNull);
    });

    test('창이 겹치면 가장 최근에 시작한 마킹이 이긴다', () {
      // 지나간 지적보다 지금 지적이 우선.
      final marks = [mark(10000), mark(11000)];
      expect(VideoMarkTimeline.activeAt(marks, 11500)?.tMs, 11000);
    });

    test('마킹이 없거나 범위 밖이면 null', () {
      expect(VideoMarkTimeline.activeAt(const [], 5000), isNull);
      expect(VideoMarkTimeline.activeAt([mark(60000)], 1000), isNull);
    });

    test('입력 순서가 뒤죽박죽이어도 결과가 같다', () {
      final marks = [mark(11000), mark(10000)];
      expect(VideoMarkTimeline.activeAt(marks, 11500)?.tMs, 11000);
    });
  });

  group('VideoMarkTimeline.sorted', () {
    test('시점 오름차순으로 정렬한다', () {
      final sorted = VideoMarkTimeline.sorted([mark(5000), mark(1000), mark(3000)]);
      expect(sorted.map((m) => m.tMs), [1000, 3000, 5000]);
    });

    test('원본 리스트를 건드리지 않는다', () {
      final original = [mark(5000), mark(1000)];
      VideoMarkTimeline.sorted(original);
      expect(original.map((m) => m.tMs), [5000, 1000]);
    });
  });

  group('fromRow / toInsertPayload', () {
    test('행이 모델로 매핑된다', () {
      final m = ClassVideoMark.fromRow({
        'id': 'x1',
        'video_id': 'v1',
        't_ms': 12000,
        'body_part': 'knee',
        'comment': '무릎이 말려요',
        'created_by': 't1',
        'created_at': '2026-07-25T10:00:00Z',
      });
      expect(m.tMs, 12000);
      expect(m.bodyPartLabel, '무릎');
      expect(m.position, const Duration(seconds: 12));
    });

    test('t_ms 가 num 으로 와도 int 로 흡수한다', () {
      // PG int 를 SDK 가 num 으로 주는 경우 대비(집계 캐스팅 지침).
      final m = ClassVideoMark.fromRow({
        'id': 'x1',
        'video_id': 'v1',
        't_ms': 12000.0,
        'body_part': null,
        'comment': 'c',
        'created_by': null,
        'created_at': '2026-07-25T10:00:00Z',
      });
      expect(m.tMs, 12000);
    });

    test('payload 는 공백 태그를 null 로, 코멘트를 trim 한다', () {
      final p = ClassVideoMark(
        id: 'new',
        videoId: 'v1',
        tMs: 3000,
        bodyPart: '   ',
        comment: '  무릎  ',
        createdAt: DateTime(2026, 7, 25),
      ).toInsertPayload();

      expect(p['body_part'], isNull);
      expect(p['comment'], '무릎');
      expect(p['t_ms'], 3000);
      expect(p['video_id'], 'v1');
    });
  });
}
