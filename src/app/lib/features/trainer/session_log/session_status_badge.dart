/// 수업(세션) 상태 배지 — 예약 화면·최근 수업 섹션 등 트레이너 세션 뷰 공용.
///
/// **왜 공용인가:** 상태→색 매핑이 예약 화면과 최근 수업 섹션에 각각 복제돼 있어
///   한쪽만 고치면 톤이 어긋났다(실제로 그런 사고가 있었다). 한 곳으로 모은다.
///
/// **다크 대응:** 의미색(주황/빨강 등)은 밝기별로 분기한다 — 라이트의 밝은 shade
///   배지는 다크 카드 위에서 밝은 블록으로 떠 깨지므로(재등록 알림과 동일 함정),
///   다크에선 어두운 배경 + 밝은 글씨로 뒤집는다. 완료/예약/취소는 의미색이 아니라
///   `ColorScheme` 역할값을 그대로 써 자동으로 밝기 대응된다.
library;

import 'package:flutter/material.dart';

import '../../../domain/models/enums.dart';

/// 상태 배지 위젯 — 라벨 pill(라운드 10, 11px, w600).
class SessionStatusBadge extends StatelessWidget {
  const SessionStatusBadge({super.key, required this.status});
  final SessionStatus status;

  @override
  Widget build(BuildContext context) {
    final style = sessionStatusBadgeStyle(status, Theme.of(context).colorScheme);
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

/// 상태별 라벨·배경·글씨색. 색 톤을 바꿀 땐 이 함수 한 곳만 수정한다.
({String label, Color bg, Color fg}) sessionStatusBadgeStyle(
  SessionStatus s,
  ColorScheme colors,
) {
  final isDark = colors.brightness == Brightness.dark;
  switch (s) {
    case SessionStatus.requested: // 승인 대기 = 주의(앰버)
      return isDark
          ? (label: '승인대기', bg: const Color(0xFF33290A), fg: const Color(0xFFE7C15A))
          : (label: '승인대기', bg: const Color(0xFFFFF0C8), fg: const Color(0xFF8A6400));
    case SessionStatus.done:
      return (
        label: '완료',
        bg: colors.primaryContainer,
        fg: colors.onPrimaryContainer,
      );
    case SessionStatus.scheduled:
      return (
        label: '예약',
        bg: colors.surfaceContainerHighest,
        fg: colors.onSurfaceVariant,
      );
    case SessionStatus.noShow: // 노쇼 = 경고(빨강)
      return isDark
          ? (label: '노쇼', bg: const Color(0xFF3A1D1F), fg: const Color(0xFFFF8A8F))
          : (label: '노쇼', bg: const Color(0xFFFDE7E8), fg: const Color(0xFFC62828));
    case SessionStatus.canceled:
      return (
        label: '취소',
        bg: colors.surfaceContainerHighest,
        fg: colors.onSurfaceVariant,
      );
    case SessionStatus.lateCancel: // 지각취소 = 주의(주황)
      return isDark
          ? (label: '지각취소', bg: const Color(0xFF352712), fg: const Color(0xFFFFB870))
          : (label: '지각취소', bg: const Color(0xFFFFF3E0), fg: const Color(0xFFE65100));
  }
}
