/// 홈 화면 "바로가기" 메뉴 격자 컴포넌트.
///
/// **왜 그리드인가:**
///   기존 홈 메뉴는 `ListTile` 을 세로로 쌓은 "일자 목록"이라 실제 앱보다 설정
///   화면처럼 밋밋했다. 아이콘 칩 + 라벨 타일을 2열 격자로 배치하면 스캔이 빠르고
///   앱다운 밀도가 생긴다. 회원 홈·트레이너 홈이 같은 컴포넌트를 공유한다.
///
/// **디자인(리포 루트 `DESIGN.md` 준수):**
///   - 타일 = 카드 톤(surface + 얇은 [AppTheme.lineColor] 테두리 + 라운드 16). 그림자 X.
///   - 아이콘은 Material `*_outlined` 라인 아이콘을 옅은 칩 위에. 이모지 금지.
///   - 강조가 필요한 "대표 액션" 한 칸만 [AppMenuItem.highlight] = 볼트 라임 채우기
///     + 잉크 글씨(라임은 fill 전용 규칙). 남발하면 에너지가 죽으니 화면당 0~1개.
///   - 배지(안읽음·대기 건수)는 우상단 카운트 필(`errorContainer` 톤).
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 메뉴 격자 한 칸.
class AppMenuItem {
  const AppMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badgeCount = 0,
    this.highlight = false,
  });

  /// 라인 아이콘(`*_outlined` 권장).
  final IconData icon;

  /// 한 줄 라벨(길면 말줄임). 부연은 두지 않는다 — 격자는 라벨만으로 읽히게.
  final String label;

  /// 탭 동작. 비동기 후처리(예: 채팅 다녀온 뒤 배지 갱신)도 `() async {}` 로 넘길 수 있다.
  final VoidCallback onTap;

  /// >0 이면 우상단에 카운트 배지 표시(안읽음·승인 대기 등).
  final int badgeCount;

  /// true 면 볼트 라임 강조 타일(화면당 대표 액션 1개 권장).
  final bool highlight;
}

/// [AppMenuItem] 들을 2열 격자로 배치한다.
///
/// 스크롤은 바깥 리스트가 담당하므로, 이 위젯은 높이만큼만 차지하도록
/// [Wrap] 으로 자연 높이 타일을 흘려 배치한다(그리드 고정 종횡비의 오버플로 회피).
class AppMenuGrid extends StatelessWidget {
  const AppMenuGrid({super.key, required this.items, this.spacing = 12});

  final List<AppMenuItem> items;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 2열 — 각 타일 폭 = (가용폭 - 칸 간격) / 2.
        final tileWidth = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in items)
              SizedBox(
                width: tileWidth,
                child: _MenuTile(item: item),
              ),
          ],
        );
      },
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.item});
  final AppMenuItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final highlight = item.highlight;

    // 강조 타일이면 볼트 채우기 + 잉크 글씨, 아니면 타일 톤(다크는 배경과 분리되게
    // 한 단계 밝은 표면 — [AppTheme.menuTileSurface]).
    final bg = highlight ? AppTheme.volt : AppTheme.menuTileSurface(theme.brightness);
    final fg = highlight ? AppTheme.onVolt : colors.onSurface;
    // 아이콘 칩 배경 — 강조 타일은 잉크 반투명, 일반 타일은 옅은 중립.
    final chipBg = highlight
        ? AppTheme.onVolt.withValues(alpha: 0.10)
        : colors.onSurface.withValues(alpha: 0.05);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: item.onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            // 강조 타일엔 테두리 불필요(채우기 자체가 경계). 일반 타일만 또렷한
            // 타일 경계선(다크에서 배경과 확실히 구분되도록 카드보다 밝은 톤).
            border: highlight
                ? null
                : Border.all(color: AppTheme.menuTileBorder(theme.brightness)),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 아이콘 칩 + (있으면) 우상단 배지.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: chipBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(item.icon, size: 22, color: fg),
                  ),
                  if (item.badgeCount > 0) _CountBadge(count: item.badgeCount),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 우상단 카운트 배지 — 안읽음·대기 건수 표시(홈 전체 공통 톤).
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      constraints: const BoxConstraints(minWidth: 20),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        // 99 초과는 자리수 폭주 방지로 99+.
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: colors.onErrorContainer,
        ),
      ),
    );
  }
}
