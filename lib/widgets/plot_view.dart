import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/units.dart';
import '../models/plot.dart';
import '../ui/theme.dart';
import 'schematic_label.dart';

/// Renders a [ResolvedPlot] as a graph.
class PlotView extends StatelessWidget {
  const PlotView(this.plot, {super.key, this.compact = false});

  final ResolvedPlot plot;

  /// Smaller fonts and margins, for graphs used as answer options.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: compact ? 130 : plot.height,
      width: double.infinity,
      child: CustomPaint(
        painter: _PlotPainter(
          plot: plot,
          compact: compact,
          fg: context.colors.onSurface,
          gridColor: context.border,
          primary: context.colors.primary,
          fontFamily: DefaultTextStyle.of(context).style.fontFamily,
        ),
      ),
    );
  }
}

Color plotColor(String name, Color primary) => switch (name) {
  'black' => const Color(0xFF3C3C3C),
  'red' => AppColors.red,
  'blue' => AppColors.blue,
  'orange' => AppColors.orange,
  'green' => AppColors.green,
  'purple' => const Color(0xFFA560E8),
  'grey' => AppColors.greyDark,
  _ => primary,
};

class _PlotPainter extends CustomPainter {
  _PlotPainter({
    required this.plot,
    required this.compact,
    required this.fg,
    required this.gridColor,
    required this.primary,
    this.fontFamily,
  });

  final ResolvedPlot plot;
  final bool compact;
  final Color fg;
  final Color gridColor;
  final Color primary;
  final String? fontFamily;

  double get _font => compact ? 9.5 : 11.5;

  SchematicLabel _text(String s, {Color? color, bool bold = false, double? size}) =>
      SchematicLabel.layout(s, color: color ?? fg, fontSize: size ?? _font, fontFamily: fontFamily, bold: bold);

  /// Plot area, ticks and y tick labels for axes [xa], [ya].
  (Rect, List<double>, List<double>, List<String>) _layout(PlotAxis xa, PlotAxis ya, Size size) {
    final xTicks = xa.ticks ?? _ticks(xa);
    final yTicks = ya.ticks ?? _ticks(ya);
    final yLabels = [for (final t in yTicks) _tickLabel(t, ya)];
    final yLabelW = compact ? 0.0 : yLabels.map((l) => _text(l).width).fold<double>(0, math.max) + 6;
    final left = (compact ? 6.0 : yLabelW + (ya.label.isEmpty ? 4 : 16));
    final bottom = compact ? 6.0 : (xa.label.isEmpty ? 20.0 : 34.0);
    const top = 10.0;
    final right = compact ? 6.0 : 14.0;
    return (Rect.fromLTRB(left, top, size.width - right, size.height - bottom), xTicks, yTicks, yLabels);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (plot.smith) {
      _paintSmith(canvas, size);
      return;
    }
    var xa = plot.x, ya = plot.y;
    var (area, xTicks, yTicks, yLabels) = _layout(xa, ya, size);
    if (plot.equal && !xa.log && !ya.log) {
      // Widen the axis with the finer scale so both get the same units per
      // pixel. The tick labels change the area slightly, so repeat a few times.
      for (var i = 0; i < 3; i++) {
        final sx = (plot.x.max - plot.x.min) / area.width, sy = (plot.y.max - plot.y.min) / area.height;
        if (sx > sy) {
          final mid = (plot.y.min + plot.y.max) / 2, half = sx * area.height / 2;
          xa = plot.x;
          ya = plot.y.withRange(mid - half, mid + half);
        } else {
          final mid = (plot.x.min + plot.x.max) / 2, half = sy * area.width / 2;
          xa = plot.x.withRange(mid - half, mid + half);
          ya = plot.y;
        }
        (area, xTicks, yTicks, yLabels) = _layout(xa, ya, size);
      }
    }

    double tx(double x) {
      if (xa.log) {
        final l0 = math.log(xa.min), l1 = math.log(xa.max);
        return area.left + (math.log(x) - l0) / (l1 - l0) * area.width;
      }
      return area.left + (x - xa.min) / (xa.max - xa.min) * area.width;
    }

    double ty(double y) {
      if (ya.log) {
        final l0 = math.log(ya.min), l1 = math.log(ya.max);
        return area.bottom - (math.log(y) - l0) / (l1 - l0) * area.height;
      }
      return area.bottom - (y - ya.min) / (ya.max - ya.min) * area.height;
    }

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = fg.withValues(alpha: 0.7)
      ..strokeWidth = 1.4;

    // Grid and ticks.
    if (plot.grid) {
      for (final t in xTicks) {
        canvas.drawLine(Offset(tx(t), area.top), Offset(tx(t), area.bottom), gridPaint);
      }
      for (final t in yTicks) {
        canvas.drawLine(Offset(area.left, ty(t)), Offset(area.right, ty(t)), gridPaint);
      }
      if (xa.log) {
        for (final t in _minorLog(xa)) {
          canvas.drawLine(
            Offset(tx(t), area.top),
            Offset(tx(t), area.bottom),
            Paint()
              ..color = gridColor.withValues(alpha: 0.5)
              ..strokeWidth = 0.7,
          );
        }
      }
    }
    // Axes: through zero when it is in range, otherwise along the border.
    final x0 = (!ya.log && ya.min < 0 && ya.max > 0) ? ty(0) : area.bottom;
    final y0 = (!xa.log && xa.min < 0 && xa.max > 0) ? tx(0) : area.left;
    canvas.drawLine(Offset(area.left, x0), Offset(area.right, x0), axisPaint);
    canvas.drawLine(Offset(y0, area.top), Offset(y0, area.bottom), axisPaint);

    if (!compact) {
      // Label every n-th tick when the labels would not fit side by side.
      final xLabels = [for (final t in xTicks) _text(_tickLabel(t, xa), color: fg.withValues(alpha: 0.75))];
      final widest = xLabels.fold<double>(0, (m, l) => math.max(m, l.width));
      final spacing = xTicks.length < 2 ? double.infinity : (tx(xTicks[1]) - tx(xTicks[0])).abs();
      final every = spacing.isInfinite ? 1 : math.max(1, ((widest + 8) / spacing).ceil());
      for (var i = 0; i < xTicks.length; i += every) {
        final tp = xLabels[i];
        final x = _fit((tx(xTicks[i]) - tp.width / 2), 0.0, size.width - tp.width);
        tp.paint(canvas, Offset(x, area.bottom + 4));
      }
      // Likewise on the y axis (e.g. a log axis over many decades).
      final yLabelH = _text('0').height;
      final ySpacing = yTicks.length < 2 ? double.infinity : (ty(yTicks[1]) - ty(yTicks[0])).abs();
      final yEvery = ySpacing.isInfinite ? 1 : math.max(1, ((yLabelH + 2) / ySpacing).ceil());
      for (var i = 0; i < yTicks.length; i += yEvery) {
        final tp = _text(yLabels[i], color: fg.withValues(alpha: 0.75));
        tp.paint(canvas, Offset(area.left - tp.width - 4, ty(yTicks[i]) - tp.height / 2));
      }
      if (xa.label.isNotEmpty) {
        final tp = _text(xa.label, bold: true);
        tp.paint(canvas, Offset(area.center.dx - tp.width / 2, size.height - tp.height));
      }
      if (ya.label.isNotEmpty) {
        final tp = _text(ya.label, bold: true);
        canvas.save();
        canvas.translate(0, area.center.dy + tp.width / 2);
        canvas.rotate(-math.pi / 2);
        tp.paint(canvas, Offset.zero);
        canvas.restore();
      }
    }

    _content(canvas, area, xa, ya, tx, ty);
  }

  /// Reference lines, curves, labels and points.
  void _content(
    Canvas canvas,
    Rect area,
    PlotAxis xa,
    PlotAxis ya,
    double Function(double) tx,
    double Function(double) ty, {
    bool guides = true,
  }) {
    canvas.save();
    canvas.clipRect(area.inflate(1));

    // Reference lines.
    final refPaint = Paint()
      ..color = fg.withValues(alpha: 0.55)
      ..strokeWidth = 1.2;
    Paint linePaint(PlotLine l) => l.color == null
        ? refPaint
        : (Paint()
          ..color = plotColor(l.color!, primary)
          ..strokeWidth = 1.4);
    Color lineText(PlotLine l) => l.color == null ? fg.withValues(alpha: 0.8) : plotColor(l.color!, primary);
    for (final h in plot.hlines) {
      _dashed(canvas, Offset(area.left, ty(h.value)), Offset(area.right, ty(h.value)), linePaint(h));
      if (h.label != null) {
        final tp = _text(h.label!, color: lineText(h));
        final y = ty(h.value);
        // Above the line, unless that would leave the plot area.
        final above = y - tp.height - 1 >= area.top;
        tp.paint(canvas, Offset(area.right - tp.width - 2, above ? y - tp.height - 1 : y + 2));
      }
    }
    for (final v in plot.vlines) {
      _dashed(canvas, Offset(tx(v.value), area.top), Offset(tx(v.value), area.bottom), linePaint(v));
      if (v.label != null) {
        final tp = _text(v.label!, color: lineText(v));
        tp.paint(canvas, Offset(tx(v.value) + 3, area.top + 1));
      }
    }

    // Curves.
    for (final c in plot.curves) {
      final paint = Paint()
        ..color = plotColor(c.color, primary)
        ..strokeWidth = compact ? 2 : 2.4
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      var pen = false;
      for (final (x, y) in c.sample(xa)) {
        if (!x.isFinite || !y.isFinite || (ya.log && y <= 0) || (xa.log && x <= 0)) {
          pen = false;
          continue;
        }
        final p = Offset(
          tx(x).clamp(area.left - 50, area.right + 50),
          ty(y).clamp(area.top - 50, area.bottom + 50),
        );
        if (pen) {
          path.lineTo(p.dx, p.dy);
        } else {
          path.moveTo(p.dx, p.dy);
          pen = true;
        }
      }
      if (c.dashed) {
        for (final metric in path.computeMetrics()) {
          var d = 0.0;
          while (d < metric.length) {
            canvas.drawPath(metric.extractPath(d, d + 6), paint);
            d += 10;
          }
        }
      } else {
        canvas.drawPath(path, paint);
      }
      if (c.label != null && !compact) {
        // Label at `labelAt` of the way along, just below the curve (or above
        // it when the curve runs along the bottom).
        final (xe, ye) = c.at(c.labelAt, xa);
        if (xe.isFinite && ye.isFinite) {
          final tp = _text(c.label!, color: paint.color, bold: true);
          final yc = ty(ye);
          final below = yc + 6 + tp.height < area.bottom - 2;
          final py = _fit((below ? yc + 6 : yc - tp.height - 6), area.top, area.bottom - tp.height);
          tp.paint(canvas, Offset(_fit((tx(xe) + 4), area.left, area.right - tp.width), py));
        }
      }
    }
    canvas.restore();

    _labels(canvas, area, tx, ty);

    // Points.
    for (final p in plot.points) {
      final o = Offset(tx(p.x), ty(p.y));
      // Points can move with sliders; don't draw them outside the axes.
      if (!o.dx.isFinite || !o.dy.isFinite || !area.inflate(2).contains(o)) continue;
      if (p.guides && guides) {
        final g = Paint()
          ..color = plotColor(p.color, primary).withValues(alpha: 0.8)
          ..strokeWidth = 1.2;
        _dashed(canvas, Offset(o.dx, area.bottom), o, g);
        _dashed(canvas, Offset(area.left, o.dy), o, g);
      }
      final pc = plotColor(p.color, primary);
      final r = compact ? 3.5 : 5.0;
      final markPaint = Paint()
        ..color = pc
        ..strokeWidth = compact ? 1.8 : 2.4
        ..style = PaintingStyle.stroke;
      switch (p.marker) {
        case 'x':
          canvas.drawLine(o + Offset(-r, -r), o + Offset(r, r), markPaint);
          canvas.drawLine(o + Offset(-r, r), o + Offset(r, -r), markPaint);
        case 'o':
          canvas.drawCircle(o, r, markPaint);
        default:
          canvas.drawCircle(o, compact ? 3 : 4.5, Paint()..color = pc);
      }
      if (p.label != null) {
        final tp = _text(p.label!, color: pc, bold: true);
        final px = _fit((o.dx + 6), area.left, area.right - tp.width);
        tp.paint(canvas, Offset(px, o.dy - tp.height - 3));
      }
    }
  }

  /// A Smith chart: the unit circle of the reflection coefficient Γ with
  /// circles of constant normalized resistance r and arcs of constant
  /// normalized reactance x, then the plot content in Γ coordinates.
  void _paintSmith(Canvas canvas, Size size) {
    final margin = compact ? 4.0 : 18.0;
    final side = math.max(10.0, math.min(size.width, size.height) - 2 * margin);
    final area = Rect.fromCenter(center: size.center(Offset.zero), width: side, height: side);
    final c = area.center, rad = side / 2;
    double tx(double x) => c.dx + x * rad;
    double ty(double y) => c.dy - y * rad;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final axisPaint = Paint()
      ..color = fg.withValues(alpha: 0.7)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    const values = [0.2, 0.5, 1.0, 2.0, 5.0];

    canvas.save();
    canvas.clipPath(Path()..addOval(area));
    for (final r in values) {
      // Constant r: centre (r/(1+r), 0), radius 1/(1+r).
      canvas.drawCircle(Offset(tx(r / (1 + r)), c.dy), rad / (1 + r), gridPaint);
    }
    for (final x in values) {
      // Constant ±x: centre (1, ±1/x), radius 1/x.
      canvas.drawCircle(Offset(tx(1), ty(1 / x)), rad / x, gridPaint);
      canvas.drawCircle(Offset(tx(1), ty(-1 / x)), rad / x, gridPaint);
    }
    canvas.restore();
    canvas.drawLine(Offset(tx(-1), c.dy), Offset(tx(1), c.dy), axisPaint);
    canvas.drawCircle(c, rad, axisPaint);

    if (!compact) {
      final muted = fg.withValues(alpha: 0.6);
      for (final r in values) {
        // Where the r circle crosses the real axis on the left: Γ = (r-1)/(r+1).
        final tp = _text(SiFormat.formatNumber(r), color: muted, size: 9.5);
        tp.paint(canvas, Offset(tx((r - 1) / (r + 1)) + 2, c.dy - tp.height - 1));
      }
      for (final x in values) {
        for (final s in [1, -1]) {
          // Where the x arc meets the unit circle: Γ = ((x²-1) + 2jx)/(x²+1).
          final gx = (x * x - 1) / (x * x + 1), gy = s * 2 * x / (x * x + 1);
          final tp = _text('${s < 0 ? '-' : ''}j${SiFormat.formatNumber(x)}', color: muted, size: 9.5);
          final o = Offset(c.dx + gx * (rad + 3 + tp.width / 2), c.dy - gy * (rad + 3 + tp.height / 2));
          tp.paint(canvas, o - Offset(tp.width / 2, tp.height / 2));
        }
      }
    }

    _content(canvas, area, plot.x, plot.y, tx, ty, guides: false);
  }

  void _labels(Canvas canvas, Rect area, double Function(double) tx, double Function(double) ty) {
    for (final l in plot.labels) {
      final tp = _text(l.text, color: plotColor(l.color, primary), bold: true);
      final x = _fit(tx(l.x), area.left, area.right - tp.width);
      final y = _fit((ty(l.y) - tp.height / 2), area.top, area.bottom - tp.height);
      tp.paint(canvas, Offset(x, y));
    }
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    final len = (b - a).distance;
    if (len == 0) return;
    final dir = (b - a) / len;
    for (var d = 0.0; d < len; d += 8) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + 4, len), paint);
    }
  }

  static List<double> _ticks(PlotAxis a) {
    if (a.log) {
      final out = <double>[];
      var e = (math.log(a.min) / math.ln10).ceil();
      while (math.pow(10.0, e) <= a.max * 1.0001) {
        out.add(math.pow(10.0, e).toDouble());
        e++;
      }
      return out;
    }
    final span = a.max - a.min;
    if (span <= 0) return [a.min];
    final raw = span / 5;
    final mag = math.pow(10.0, (math.log(raw) / math.ln10).floor()).toDouble();
    final norm = raw / mag;
    final step =
        (norm < 1.5
            ? 1
            : norm < 3.5
            ? 2
            : norm < 7.5
            ? 5
            : 10) *
        mag;
    final out = <double>[];
    for (var t = (a.min / step).ceil() * step; t <= a.max + step * 1e-6; t += step) {
      out.add(double.parse(t.toStringAsPrecision(10)));
    }
    return out;
  }

  static List<double> _minorLog(PlotAxis a) {
    final out = <double>[];
    var e = (math.log(a.min) / math.ln10).floor();
    while (math.pow(10.0, e) <= a.max) {
      for (var k = 2; k <= 9; k++) {
        final v = k * math.pow(10.0, e).toDouble();
        if (v > a.min && v < a.max) out.add(v);
      }
      e++;
    }
    return out;
  }

  static String _tickLabel(double v, PlotAxis a) {
    if (v.abs() < 1e-12) return '0';
    return a.unit.isEmpty ? SiFormat.formatNumber(v) : SiFormat.format(v, a.unit);
  }

  @override
  bool shouldRepaint(covariant _PlotPainter old) => old.plot != plot || old.fg != fg;
}

/// Clamps [v] to [lo, hi]; when the range is empty (a label wider than the
/// space for it) the label is placed at [lo] instead of throwing.
double _fit(double v, double lo, double hi) => hi < lo ? lo : v.clamp(lo, hi);
