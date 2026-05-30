/// 중량 추이 계산 — 수업 기록(exercises JSON)에서 종목별 시계열을 뽑는다.
///
/// **왜 도메인에 두나 (단위테스트 필수 대상):**
///   `session_records.exercises` 는 jsonb 자유 구조라 SQL 집계가 어렵다(0023 주석,
///   session_record.dart 참조). 그래서 클라이언트에서 계산하되, "한 수업의 종목별
///   대표 중량을 무엇으로 볼 것인가" 같은 규칙은 화면이 아니라 도메인이 책임진다.
///   화면이 여러 개 생겨도 같은 추이를 보장하기 위함.
///
/// **대표 중량 = 그 수업에서 해당 종목의 최고 중량(top set weight):**
///   평균은 워밍업 세트에 휘둘리고, 볼륨은 세트 수에 좌우된다. "그날 든 제일 무거운
///   무게"가 회원이 체감하는 성장 지표에 가장 가깝다. 같은 수업에 같은 종목이 여러 번
///   나와도 최고값으로 합친다(방어적).
///
/// 참고: docs/develop_plan.md §4 Phase 2 2.2(S1), domain/models/session_record.dart.
library;

import 'models/session_record.dart';

/// 추이 한 점 — 측정/수업 시점 + 수치.
class TrendPoint {
  final DateTime date;
  final double value;

  const TrendPoint({required this.date, required this.value});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrendPoint &&
          runtimeType == other.runtimeType &&
          date == other.date &&
          value == other.value;

  @override
  int get hashCode => Object.hash(date, value);

  @override
  String toString() => 'TrendPoint($date, $value)';
}

/// 계산기에 넣는 입력 단위 — 수업 1건(일시 + 운동 내용).
///
/// 화면 repository 가 done 수업을 이 형태로 변환해 넘긴다.
class WorkoutEntry {
  final DateTime date;
  final List<Exercise> exercises;

  const WorkoutEntry({required this.date, required this.exercises});
}

class WeightTrendCalculator {
  /// 종목별 중량 추이를 계산한다.
  ///
  /// 반환: `{ 종목명: [TrendPoint(날짜오름차순)] }`.
  ///   - 해당 종목을 실제로 한 수업만 점으로 포함(안 한 날은 건너뜀 — 가짜 0 방지).
  ///   - 한 종목의 모든 세트 weight 가 0(맨몸 운동)이면 그 시점은 제외.
  ///     중량 추이 그래프의 의미가 없기 때문.
  ///   - 빈 종목명("")은 집계에서 제외(입력은 UI가 막지만 도메인도 방어).
  ///
  /// 예시:
  ///   입력 = [
  ///     (3/1, 스쿼트[60×10, 70×8]),
  ///     (3/8, 스쿼트[80×5], 벤치[50×10]),
  ///   ]
  ///   출력 = {
  ///     "스쿼트": [(3/1, 70), (3/8, 80)],   // 각 수업 최고 중량
  ///     "벤치":   [(3/8, 50)],
  ///   }
  static Map<String, List<TrendPoint>> byExercise(List<WorkoutEntry> entries) {
    final result = <String, List<TrendPoint>>{};

    // 날짜 오름차순으로 정렬해 점들이 시간순으로 쌓이게 한다(입력 순서 무관).
    final sorted = [...entries]..sort((a, b) => a.date.compareTo(b.date));

    for (final entry in sorted) {
      // 한 수업 안에서 같은 종목이 여러 번 나올 수 있어 종목명→최고중량으로 먼저 합친다.
      final topByName = <String, int>{};
      for (final ex in entry.exercises) {
        final name = ex.name.trim();
        if (name.isEmpty) continue;
        final top = _topSetWeight(ex);
        if (top <= 0) continue; // 맨몸/무게 미기록은 중량 추이에서 제외
        final prev = topByName[name];
        if (prev == null || top > prev) topByName[name] = top;
      }

      // 합친 결과를 종목별 시계열에 한 점씩 추가.
      topByName.forEach((name, top) {
        (result[name] ??= <TrendPoint>[])
            .add(TrendPoint(date: entry.date, value: top.toDouble()));
      });
    }

    return result;
  }

  /// 자주 기록한 종목 순으로 종목명 목록 — 그래프 기본 선택지 정렬에 사용.
  /// 빈도 동률이면 가나다/알파벳순으로 안정 정렬.
  static List<String> exercisesByFrequency(List<WorkoutEntry> entries) {
    final count = <String, int>{};
    for (final entry in entries) {
      // 한 수업에 같은 종목이 중복돼도 1회로 — "그 수업에 했는지"가 빈도의 의미.
      final seen = <String>{};
      for (final ex in entry.exercises) {
        final name = ex.name.trim();
        if (name.isEmpty || _topSetWeight(ex) <= 0) continue;
        seen.add(name);
      }
      for (final name in seen) {
        count[name] = (count[name] ?? 0) + 1;
      }
    }

    final names = count.keys.toList();
    names.sort((a, b) {
      final byCount = count[b]!.compareTo(count[a]!); // 많이 한 종목 먼저
      if (byCount != 0) return byCount;
      return a.compareTo(b);
    });
    return names;
  }

  /// 종목 1개의 최고 세트 중량(kg). 세트가 없으면 0.
  static int _topSetWeight(Exercise ex) {
    var max = 0;
    for (final s in ex.sets) {
      if (s.weight > max) max = s.weight;
    }
    return max;
  }
}
