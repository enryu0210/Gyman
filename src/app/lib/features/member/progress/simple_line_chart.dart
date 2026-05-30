/// 의존성 없는 단순 라인차트 — CustomPainter 자체 구현 (S1 / 2.2).
///
/// **왜 차트 라이브러리 대신 자체 구현:**
///   develop_plan §0 의존성을 고정(추가 최소화)하기로 해서, 단일 시계열 라인 한 종류만
///   필요한 이 화면에는 fl_chart 등을 들이지 않고 CustomPainter 로 직접 그린다.
///   축/그리드/점/끝값 라벨까지만 — 인터랙션(툴팁/줌)은 범위 밖.
///
/// 입력은 도메인 [TrendPoint](날짜 + 값) 리스트. 중량/인바디 양쪽이 같은 위젯을 쓴다.
///
/// **빈/단일 데이터 방어:**
///   - 점 0개 → 호출 측이 빈 안내를 띄우므로 여기선 그리지 않음(빈 박스).
///   - 점 1개 → 가운데 점 하나 + 값만(선은 못 그림).
///   - 모든 값이 같음 → Y축이 평평해지지 않게 위아래로 약간 패딩.
library;

import 'package:flutter/material.dart';

import '../../../domain/weight_trend.dart';

class SimpleLineChart extends StatelessWidget {
  const SimpleLineChart({
    super.key,
    required this.points,
    required this.unit,
    this.height = 220,
  });

  /// 날짜 오름차순 데이터. (호출 측이 정렬해 넘긴다고 가정하되, 페인터도 안전 처리.)
  final List<TrendPoint> points;

  /// Y축 값 단위 표기(예: "kg", "%").
  final String unit;

  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _LineChartPainter(
          points: points,
          unit: unit,
          lineColor: theme.colorScheme.primary,
          gridColor: theme.colorScheme.outlineVariant,
          labelColor: theme.colorScheme.onSurfaceVariant,
          fillColor: theme.colorScheme.primary.withValues(alpha: 0.10),
        ),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.points,
    required this.unit,
    required this.lineColor,
    required this.gridColor,
    required this.labelColor,
    required this.fillColor,
  });

  final List<TrendPoint> points;
  final String unit;
  final Color lineColor;
  final Color gridColor;
  final Color labelColor;
  final Color fillColor;

  // 그리기 영역 여백 — 왼쪽은 Y라벨, 아래는 X(날짜)라벨 공간.
  static const _padLeft = 44.0;
  static const _padRight = 12.0;
  static const _padTop = 12.0;
  static const _padBottom = 26.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    // 날짜순 보장(방어) — 호출 측 정렬을 신뢰하지 않음.
    final pts = [...points]..sort((a, b) => a.date.compareTo(b.date));

    final plotLeft = _padLeft;
    final plotRight = size.width - _padRight;
    final plotTop = _padTop;
    final plotBottom = size.height - _padBottom;
    final plotW = plotRight - plotLeft;
    final plotH = plotBottom - plotTop;
    if (plotW <= 0 || plotH <= 0) return;

    // --- Y 범위 계산 (값이 모두 같으면 위아래 패딩) ---
    var minV = pts.first.value;
    var maxV = pts.first.value;
    for (final p in pts) {
      if (p.value < minV) minV = p.value;
      if (p.value > maxV) maxV = p.value;
    }
    if (minV == maxV) {
      // 평평한 직선 방지 — 값의 약 5%(최소 1) 위아래로 벌림.
      final pad = (minV.abs() * 0.05).clamp(1.0, double.infinity);
      minV -= pad;
      maxV += pad;
    } else {
      // 위아래 여유 10%.
      final margin = (maxV - minV) * 0.1;
      minV -= margin;
      maxV += margin;
    }
    final range = maxV - minV;

    double yFor(double v) => plotBottom - ((v - minV) / range) * plotH;

    // --- X 범위 (날짜 → 0..1) ---
    final firstMs = pts.first.date.millisecondsSinceEpoch;
    final lastMs = pts.last.date.millisecondsSinceEpoch;
    final spanMs = (lastMs - firstMs).toDouble();
    double xFor(DateTime d) {
      if (spanMs <= 0) return plotLeft + plotW / 2; // 점 1개/같은날 → 가운데
      final t = (d.millisecondsSinceEpoch - firstMs) / spanMs;
      return plotLeft + t * plotW;
    }

    // --- 가로 그리드 + Y 라벨 (4구간) ---
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    const divisions = 4;
    for (var i = 0; i <= divisions; i++) {
      final v = maxV - (range / divisions) * i;
      final y = yFor(v);
      canvas.drawLine(Offset(plotLeft, y), Offset(plotRight, y), gridPaint);
      _drawText(
        canvas,
        _fmtNum(v),
        Offset(plotLeft - 6, y),
        labelColor,
        align: TextAlign.right,
        anchorRight: true,
        anchorMiddleV: true,
      );
    }

    // --- 단일 점이면 점만 ---
    final dotPaint = Paint()..color = lineColor;
    if (pts.length == 1) {
      final c = Offset(xFor(pts.first.date), yFor(pts.first.value));
      canvas.drawCircle(c, 4, dotPaint);
      _drawXLabel(canvas, pts.first.date, c.dx, plotBottom);
      return;
    }

    // --- 영역 채우기 + 라인 ---
    final linePath = Path();
    final fillPath = Path();
    for (var i = 0; i < pts.length; i++) {
      final o = Offset(xFor(pts[i].date), yFor(pts[i].value));
      if (i == 0) {
        linePath.moveTo(o.dx, o.dy);
        fillPath.moveTo(o.dx, plotBottom);
        fillPath.lineTo(o.dx, o.dy);
      } else {
        linePath.lineTo(o.dx, o.dy);
        fillPath.lineTo(o.dx, o.dy);
      }
    }
    fillPath.lineTo(xFor(pts.last.date), plotBottom);
    fillPath.close();

    canvas.drawPath(fillPath, Paint()..color = fillColor);
    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );

    // --- 각 점 ---
    for (final p in pts) {
      canvas.drawCircle(Offset(xFor(p.date), yFor(p.value)), 3, dotPaint);
    }

    // --- X 라벨: 처음/끝 날짜만 (가운데 라벨은 겹쳐서 생략) ---
    _drawXLabel(canvas, pts.first.date, xFor(pts.first.date), plotBottom,
        align: TextAlign.left);
    _drawXLabel(canvas, pts.last.date, xFor(pts.last.date), plotBottom,
        align: TextAlign.right);
  }

  /// "72" / "72.5" — 불필요한 .0 제거. 단위는 Y라벨엔 안 붙임(좁아서).
  String _fmtNum(double v) {
    final r = (v * 10).round() / 10; // 소수 1자리 반올림
    return r == r.roundToDouble() ? r.toInt().toString() : r.toString();
  }

  void _drawXLabel(Canvas canvas, DateTime d, double x, double plotBottom,
      {TextAlign align = TextAlign.center}) {
    final label = '${d.month}/${d.day}';
    final anchorRight = align == TextAlign.right;
    final centered = align == TextAlign.center;
    _drawText(
      canvas,
      label,
      Offset(x, plotBottom + 6),
      labelColor,
      align: align,
      anchorRight: anchorRight,
      anchorCenterH: centered,
    );
  }

  /// TextPainter 로 라벨 그리기. 앵커 옵션으로 좌/우/중앙·세로중앙 정렬.
  void _drawText(
    Canvas canvas,
    String text,
    Offset at,
    Color color, {
    TextAlign align = TextAlign.left,
    bool anchorRight = false,
    bool anchorCenterH = false,
    bool anchorMiddleV = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout();

    var dx = at.dx;
    if (anchorRight) dx = at.dx - tp.width;
    if (anchorCenterH) dx = at.dx - tp.width / 2;
    var dy = at.dy;
    if (anchorMiddleV) dy = at.dy - tp.height / 2;
    tp.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(_LineChartPainter old) =>
      old.points != points ||
      old.lineColor != lineColor ||
      old.unit != unit;
}
