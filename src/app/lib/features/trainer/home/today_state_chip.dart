/// 오늘 타임라인의 상태 배지 — 예정 / 진행 중 / 기록 대기 / 완료 …
///
/// **왜 [SessionStatusBadge] 를 그대로 안 쓰나:** 그 배지는 DB 상태(예약·완료·노쇼)를
/// 보여준다. 오늘 타임라인은 같은 "예약"이라도 시각에 따라 예정 / 진행 중 / 기록 대기로
/// 갈리므로, 화면 상태([TodaySessionState])를 그리는 배지가 따로 필요하다.
///
/// **강조 방향(계획서 §4.1):** 손이 필요한 상태(진행 중·기록 대기)를 눈에 띄게 하고,
/// 이미 끝난 상태(완료·취소)는 가라앉힌다. 볼트 라임은 쓰지 않는다 — 화면의 유일한
/// 라임 강조는 하단 바의 "기록하기" 버튼 하나로 유지한다.
///
/// **다크 대응:** 의미색(앰버/주황/빨강)은 밝은 shade 를 고정하면 다크 카드 위에서
/// 밝은 블록으로 떠 깨진다(프로젝트 반복 함정) → 밝기별로 배경/글씨를 뒤집는다.
library;

import 'package:flutter/material.dart';

import '../../../domain/today_schedule.dart';

/// 상태별 라벨·배경·글씨색. 톤을 바꿀 땐 이 함수 한 곳만 수정한다.
({String label, Color bg, Color fg}) todayStateStyle(
  TodaySessionState state,
  ColorScheme colors,
) {
  final isDark = colors.brightness == Brightness.dark;
  switch (state) {
    case TodaySessionState.pending: // 승인 대기 = 주의(앰버)
      return isDark
          ? (
              label: '승인 대기',
              bg: const Color(0xFF33290A),
              fg: const Color(0xFFE7C15A)
            )
          : (
              label: '승인 대기',
              bg: const Color(0xFFFFF0C8),
              fg: const Color(0xFF8A6400)
            );
    case TodaySessionState.upcoming:
      return (
        label: '예정',
        bg: colors.surfaceContainerHighest,
        fg: colors.onSurfaceVariant,
      );
    case TodaySessionState.inProgress:
      // 지금 이 순간의 수업 — 유일하게 강조색(primary 계열) 을 쓴다.
      return (
        label: '진행 중',
        bg: colors.primaryContainer,
        fg: colors.onPrimaryContainer,
      );
    case TodaySessionState.awaitingRecord: // 밀린 기록 = 주의(주황)
      return isDark
          ? (
              label: '기록 대기',
              bg: const Color(0xFF352712),
              fg: const Color(0xFFFFB870)
            )
          : (
              label: '기록 대기',
              bg: const Color(0xFFFFF3E0),
              fg: const Color(0xFFE65100)
            );
    case TodaySessionState.done:
      // 끝난 일은 가라앉힌다 — 손이 필요한 상태만 시선을 가져가도록.
      return (
        label: '기록 완료',
        bg: colors.surfaceContainerHighest,
        fg: colors.onSurfaceVariant,
      );
    case TodaySessionState.missed: // 노쇼 = 경고(빨강)
      return isDark
          ? (
              label: '노쇼',
              bg: const Color(0xFF3A1D1F),
              fg: const Color(0xFFFF8A8F)
            )
          : (
              label: '노쇼',
              bg: const Color(0xFFFDE7E8),
              fg: const Color(0xFFC62828)
            );
    case TodaySessionState.canceled:
      return (
        label: '취소',
        bg: colors.surfaceContainerHighest,
        fg: colors.onSurfaceVariant,
      );
  }
}

/// 오늘 타임라인용 상태 배지 위젯.
class TodayStateChip extends StatelessWidget {
  const TodayStateChip({super.key, required this.state});
  final TodaySessionState state;

  @override
  Widget build(BuildContext context) {
    final style = todayStateStyle(state, Theme.of(context).colorScheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        style.label,
        style: TextStyle(
          fontSize: 11,
          color: style.fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
