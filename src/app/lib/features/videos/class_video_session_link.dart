/// 수업 영상이 특정 수업과 연결됐을 때 표시하는 작은 라인 — 트레이너/회원 공용.
///
/// 영상 목록 타일의 부제(subtitle) 안에서 "어느 수업의 영상인지"를 한 줄로 보여준다.
/// 트레이너 카드(class_videos_card)와 회원 화면(member_videos_screen)이 같은 모양을
/// 쓰도록 공용 위젯으로 분리(중복 제거 — CLAUDE.md 모듈화).
///
/// 날짜만 표기(시각 생략) — 타일은 좁고, 정확한 시각은 수업 기록 화면에서 확인.
library;

import 'package:flutter/material.dart';

import '../../core/util/date_format_ko.dart';

class ClassVideoSessionLink extends StatelessWidget {
  const ClassVideoSessionLink({super.key, required this.date});

  /// 연결된 수업의 진행 일시.
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.link, size: 14, color: colors.primary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '${formatKoreanDate(date)} 수업',
              style: theme.textTheme.bodySmall?.copyWith(color: colors.primary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
