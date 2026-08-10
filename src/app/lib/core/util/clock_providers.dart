/// 시간 흐름을 UI에 흘려주는 시계 provider.
///
/// **왜 필요한가:** 트레이너 홈의 "다음 수업 — 14:00, 32분 후" 와 오늘 타임라인의
/// 예정 → 진행 중 → 기록 대기 전이는 *아무 입력 없이 시간만 지나도* 바뀌어야 한다
/// (ui_renewal_phase1_plan §4.2). 화면이 현재 시각을 build 시점에 한 번만 읽으면
/// 앱을 켜둔 채 수업 시간이 지나도 표시가 그대로 멈춘다.
///
/// 30초 간격인 이유: 표시 단위가 "분"이라 그보다 촘촘할 필요가 없고, 1분이면
/// 남은 시간이 최대 1분 늦게 갱신돼 "곧 시작"이 늦게 뜬다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 30초마다 현재 시각을 흘려보내는 스트림. 구독 즉시 첫 값을 준다.
final clockTickProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream<DateTime>.periodic(
    const Duration(seconds: 30),
    (_) => DateTime.now(),
  );
});

/// 지금 시각 — 스트림이 아직 첫 값을 못 준 순간에도 안전하게 쓰도록 평탄화.
final nowProvider = Provider<DateTime>((ref) {
  return ref.watch(clockTickProvider).value ?? DateTime.now();
});

/// 오늘 날짜 키(`yyyy-MM-dd`). 값이 바뀌는 순간 = 자정을 넘긴 순간.
///
/// 앱을 켜둔 채 날짜가 바뀌면 "오늘" 기준으로 캐시된 조회가 어제 것이 된다.
/// 화면이 이 값을 `ref.listen` 해서 해당 조회를 invalidate 하면 된다.
final todayKeyProvider = Provider<String>((ref) {
  final now = ref.watch(nowProvider);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)}';
});
