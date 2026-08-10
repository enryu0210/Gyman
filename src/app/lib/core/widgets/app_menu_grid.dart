library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'bento_layout.dart';

/// 바로가기 타일이 표현할 정보와 동작입니다.
class AppMenuItem {
  const AppMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badgeCount = 0,
    this.highlight = false,
    this.columnSpan = 1,
  }) : assert(columnSpan > 0);

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int badgeCount;
  final bool highlight;
  final int columnSpan;
}

/// 기능 바로가기를 반응형 벤토 격자로 보여줍니다.
///
/// 강조 기능은 두 칸을 써서 다음 행동을 분명하게 만들고, 나머지는 동일한 밀도로
/// 배치해 메뉴가 길어져도 빠르게 훑을 수 있게 합니다.
class AppMenuGrid extends StatelessWidget {
  const AppMenuGrid({super.key, required this.items, this.spacing = 12});

  final List<AppMenuItem> items;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return BentoGrid(
      spacing: spacing,
      items: [
        for (final item in items)
          BentoGridItem(
            columnSpan: item.highlight ? 2 : item.columnSpan,
            minHeight: item.highlight ? 156 : 132,
            child: _MenuTile(item: item),
          ),
      ],
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
    final background = item.highlight
        ? AppTheme.volt
        : AppTheme.menuTileSurface(theme.brightness);
    final foreground = item.highlight ? AppTheme.onVolt : colors.onSurface;
    final iconBackground = item.highlight
        ? AppTheme.onVolt.withValues(alpha: 0.10)
        : colors.onSurface.withValues(alpha: 0.05);
    final radius = BorderRadius.circular(24);

    return Material(
      color: background,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: item.onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: item.highlight
                ? null
                : Border.all(color: AppTheme.menuTileBorder(theme.brightness)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: iconBackground,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(item.icon, size: 22, color: foreground),
                  ),
                  if (item.badgeCount > 0) _CountBadge(count: item.badgeCount),
                ],
              ),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
