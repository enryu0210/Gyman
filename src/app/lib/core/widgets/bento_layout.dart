import 'package:flutter/material.dart';

/// 화면 폭에 따라 열 수를 늘리는 공통 벤토 레이아웃입니다.
///
/// 각 기능 화면이 임의의 `GridView` 값을 갖지 않도록 한 곳에서 반응형 규칙을
/// 관리합니다. 모바일에서는 정보의 읽기 순서를 유지하고, 넓은 화면에서는 같은
/// 카드가 자연스럽게 여러 칸을 차지하도록 설계했습니다.
class BentoGrid extends StatelessWidget {
  const BentoGrid({super.key, required this.items, this.spacing = 12});

  final List<BentoGridItem> items;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCount = switch (constraints.maxWidth) {
          >= 1120 => 6,
          >= 760 => 4,
          _ => 2,
        };

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in items)
              _BentoGridCell(
                item: item,
                columnCount: columnCount,
                spacing: spacing,
                availableWidth: constraints.maxWidth,
              ),
          ],
        );
      },
    );
  }
}

/// [BentoGrid] 안에서 카드가 차지할 열 수와 최소 높이를 정의합니다.
class BentoGridItem {
  const BentoGridItem({
    required this.child,
    this.columnSpan = 1,
    this.minHeight,
  }) : assert(columnSpan > 0);

  final Widget child;
  final int columnSpan;
  final double? minHeight;
}

class _BentoGridCell extends StatelessWidget {
  const _BentoGridCell({
    required this.item,
    required this.columnCount,
    required this.spacing,
    required this.availableWidth,
  });

  final BentoGridItem item;
  final int columnCount;
  final double spacing;
  final double availableWidth;

  @override
  Widget build(BuildContext context) {
    // 작은 화면에서 큰 카드가 잘리는 일을 막기 위해 span을 현재 열 수로 제한합니다.
    final span = item.columnSpan.clamp(1, columnCount);
    final cellWidth =
        (availableWidth - spacing * (columnCount - 1)) / columnCount;
    final width = cellWidth * span + spacing * (span - 1);

    return SizedBox(
      width: width,
      child: item.minHeight == null
          ? item.child
          : ConstrainedBox(
              constraints: BoxConstraints(minHeight: item.minHeight!),
              child: item.child,
            ),
    );
  }
}

/// 클릭 가능한 카드의 공통 외피입니다.
///
/// 카드 모양, 잉크 반응, 접근성 힌트를 통일해 화면마다 서로 다른 터치 감각이
/// 생기지 않도록 합니다. 색상과 테두리는 전역 테마에서 관리합니다.
class BentoCard extends StatelessWidget {
  const BentoCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(18),
    this.color,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(24);
    return Card(
      color: color,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
