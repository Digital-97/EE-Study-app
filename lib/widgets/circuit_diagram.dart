import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/circuit.dart';
import 'schematic_label.dart';

/// Renders a [CircuitSpec] schematic, scaled to the available width.
class CircuitDiagram extends StatelessWidget {
  const CircuitDiagram(
    this.spec, {
    super.key,
    this.maxCell = 56,
    this.highlights = const {},
    this.onTapElement,
    this.tappable,
  });

  final CircuitSpec spec;
  final double maxCell;

  /// Element names drawn with a coloured glow behind them.
  final Map<String, Color> highlights;

  /// Called with the name of the element the user tapped.
  final void Function(String name)? onTapElement;

  /// Names that respond to taps (default: all named elements).
  final Set<String>? tappable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bounds = _bounds(spec);
    return LayoutBuilder(builder: (context, c) {
      final maxW = c.maxWidth.isFinite ? c.maxWidth : 360.0;
      var cell = math.min(maxCell, maxW / bounds.width);
      if (spec.height != null) {
        cell = math.min(cell, spec.height! / bounds.height);
      }
      if (c.maxHeight.isFinite) {
        cell = math.min(cell, c.maxHeight / bounds.height);
      }
      final painter = CustomPaint(
            painter: CircuitPainter(
              spec: spec,
              highlights: highlights,
              origin: bounds.topLeft,
              cell: cell,
              color: theme.colorScheme.onSurface,
              accent: theme.colorScheme.primary,
              background: theme.colorScheme.surface,
              fontFamily: DefaultTextStyle.of(context).style.fontFamily ??
                  theme.textTheme.bodyMedium?.fontFamily,
            ),
          );
      return Center(
        child: SizedBox(
          width: bounds.width * cell,
          height: bounds.height * cell,
          child: onTapElement == null
              ? painter
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) {
                    final hit = _hitTest(d.localPosition / cell + bounds.topLeft);
                    if (hit != null) onTapElement!(hit);
                  },
                  child: painter,
                ),
        ),
      );
    });
  }

  /// The tappable element nearest to grid point [p], if close enough.
  String? _hitTest(Offset p) {
    String? best;
    var bestD = 0.7; // grid units
    for (final e in spec.elements) {
      final name = e.name;
      if (name == null || (tappable != null && !tappable!.contains(name))) continue;
      double d;
      if (e.from != null && e.to != null) {
        d = _distToSegment(p, e.from!, e.to!);
      } else if (e.at != null) {
        // Larger symbols get a larger target.
        final r = switch (e.type) {
          'opamp' || 'npn' || 'pnp' || 'nmos' || 'pmos' || 'gate' || 'block' || 'transformer' => 0.5,
          'sum' => 0.3,
          _ => 0.0,
        };
        d = math.max(0, (p - e.at!).distance - r);
      } else {
        continue;
      }
      if (d < bestD) {
        bestD = d;
        best = name;
      }
    }
    return best;
  }

  static double _distToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / ab.distanceSquared).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  static Rect _bounds(CircuitSpec spec) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final e in spec.elements) {
      for (final p in e.extent) {
        minX = math.min(minX, p.dx);
        minY = math.min(minY, p.dy);
        maxX = math.max(maxX, p.dx);
        maxY = math.max(maxY, p.dy);
      }
    }
    if (!minX.isFinite) return const Rect.fromLTWH(0, 0, 1, 1);
    // Make room for labels next to two-terminal elements and terminals,
    // estimating their size in grid units.
    double textW(String t) => t.replaceAll(RegExp(r'[_~{}]'), '').length * 0.17;
    void include(Offset p) {
      minX = math.min(minX, p.dx);
      minY = math.min(minY, p.dy);
      maxX = math.max(maxX, p.dx);
      maxY = math.max(maxY, p.dy);
    }

    for (final e in spec.elements) {
      final labels = [
        if (e.label != null && e.label!.isNotEmpty) e.label!,
        if (e.value != null && e.value!.isNotEmpty) e.value!,
      ];
      if (labels.isEmpty) continue;
      final w = labels.map(textW).reduce(math.max);
      final hgt = labels.length * 0.36;
      if (e.from != null && e.to != null && e.type != 'wire') {
        final mid = (e.from! + e.to!) / 2;
        final side = labelSide(e);
        final gap = e.type == 'arrow' ? 0.15 : 0.45;
        if (side.dx.abs() > side.dy.abs()) {
          include(mid + Offset(side.dx.sign * (gap + w), 0));
        } else {
          include(mid + Offset(-w / 2, side.dy.sign * (gap + hgt)));
          include(mid + Offset(w / 2, 0));
        }
      } else if (e.type == 'terminal' && e.at != null) {
        include(e.at! + Offset((e.flip ? -1 : 1) * (0.35 + w), 0));
      }
    }
    // Base margin.
    const m = 0.45;
    return Rect.fromLTRB(minX - m, minY - m, maxX + m, maxY + m);
  }
}

/// Unit vector pointing to the side where an element's labels are drawn:
/// above horizontal elements, right of vertical ones (`flip` swaps).
Offset labelSide(CircuitElement e) {
  final d = e.to! - e.from!;
  final dir = d / d.distance;
  final normal = Offset(-dir.dy, dir.dx);
  var side = (dir.dx.abs() >= dir.dy.abs())
      ? (normal.dy < 0 ? normal : -normal)
      : (normal.dx > 0 ? normal : -normal);
  if (e.flip) side = -side;
  return side;
}

class CircuitPainter extends CustomPainter {
  CircuitPainter({
    required this.spec,
    this.highlights = const {},
    required this.origin,
    required this.cell,
    required this.color,
    required this.accent,
    required this.background,
    this.fontFamily,
  });

  final CircuitSpec spec;
  final Map<String, Color> highlights;
  final Offset origin;
  final double cell;
  final Color color;
  final Color accent;
  final Color background;
  final String? fontFamily;

  late final Paint _stroke = Paint()
    ..color = color
    ..strokeWidth = math.max(1.6, cell / 28)
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  late final Paint _fill = Paint()
    ..color = color
    ..style = PaintingStyle.fill;

  late final Paint _bgFill = Paint()
    ..color = background
    ..style = PaintingStyle.fill;

  Offset _p(Offset grid) => (grid - origin) * cell;

  double get _font => math.max(11, cell * 0.3);

  @override
  void paint(Canvas canvas, Size size) {
    // Selection glows behind everything.
    for (final e in spec.elements) {
      final c = e.name == null ? null : highlights[e.name];
      if (c == null) continue;
      final glow = Paint()
        ..color = c.withValues(alpha: 0.35)
        ..strokeWidth = cell * 0.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      if (e.from != null && e.to != null) {
        final a = _p(e.from!), b = _p(e.to!);
        final dir = (b - a) / (b - a).distance;
        canvas.drawLine(a + dir * cell * 0.2, b - dir * cell * 0.2, glow);
      } else if (e.at != null) {
        canvas.drawCircle(_p(e.at!), cell * (e.type == 'node' ? 0.25 : 0.7),
            Paint()..color = c.withValues(alpha: 0.35));
      }
    }
    // Wires first so component bodies draw on top.
    for (final e in spec.elements.where((e) => e.type == 'wire' || e.type == 'signal')) {
      _polyline(canvas, e.points.map(_p).toList());
      if (e.type == 'signal') _signalHead(canvas, e);
    }
    for (final e in spec.elements) {
      switch (e.type) {
        case 'wire' || 'signal':
          break;
        case 'transformer':
          _transformer(canvas, e);
        case 'block':
          _block(canvas, e);
        case 'sum':
          _sum(canvas, e);
        case 'arrow':
          _arrow(canvas, e);
        case 'ground':
          _ground(canvas, e);
        case 'node':
          canvas.drawCircle(_p(e.at!), cell * 0.08, _fill);
          if (e.label != null) _labelNear(canvas, _p(e.at!), e.label!, const Offset(0.18, -0.25));
        case 'terminal':
          canvas.drawCircle(_p(e.at!), cell * 0.09, _bgFill);
          canvas.drawCircle(_p(e.at!), cell * 0.09, _stroke);
          if (e.label != null) {
            _labelNear(canvas, _p(e.at!), e.label!, e.flip ? const Offset(-0.3, 0) : const Offset(0.3, 0),
                alignRight: e.flip);
          }
        case 'text':
          _text(canvas, e.label!, _p(e.at!), center: true);
        case 'loop':
          _loop(canvas, e);
        case 'tag':
          _tag(canvas, e);
        case 'opamp':
          _opamp(canvas, e);
        case 'gate':
          _gate(canvas, e);
        case 'npn' || 'pnp':
          _bjt(canvas, e);
        case 'nmos' || 'pmos':
          _mosfet(canvas, e);
        default:
          if (twoTerminalTypes.contains(e.type)) _twoTerminal(canvas, e);
      }
    }
  }

  void _polyline(Canvas canvas, List<Offset> pts) {
    if (pts.length < 2) return;
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, _stroke);
  }

  // ---------------------------------------------------------------------------
  // Two-terminal components
  // ---------------------------------------------------------------------------

  void _twoTerminal(Canvas canvas, CircuitElement e) {
    final a = _p(e.from!);
    final b = _p(e.to!);
    final len = (b - a).distance;
    final dir = (b - a) / len;
    final angle = math.atan2(dir.dy, dir.dx);
    final mid = (a + b) / 2;

    // Body length in pixels.
    final body = switch (e.type) {
      'capacitor' || 'battery' => cell * 0.3,
      'vsource' || 'isource' || 'acsource' || 'voltmeter' || 'ammeter' || 'lamp' || 'motor' ||
      'generator' =>
        cell * 0.7,
      'cvsource' || 'ccsource' => cell * 0.76,
      'diode' || 'zener' || 'led' => cell * 0.42,
      'switch' => cell * 0.7,
      'inductor' => cell * 0.9,
      _ => cell * 0.9,
    };
    final half = math.min(body, len) / 2;
    // Leads.
    canvas.drawLine(a, mid - dir * half, _stroke);
    canvas.drawLine(mid + dir * half, b, _stroke);

    canvas.save();
    canvas.translate(mid.dx, mid.dy);
    canvas.rotate(angle);
    // In local coordinates the element runs along +x from -half to +half.
    switch (e.type) {
      case 'resistor':
        _resistor(canvas, half);
      case 'capacitor':
        _capacitor(canvas, half);
      case 'inductor':
        _inductor(canvas, half);
      case 'vsource':
        _circleSource(canvas, half);
        // + near "to" (positive x), − near "from".
        _localSign(canvas, Offset(half * 0.45, 0), plus: true, rot: angle);
        _localSign(canvas, Offset(-half * 0.45, 0), plus: false, rot: angle);
      case 'acsource':
        _circleSource(canvas, half);
        _sine(canvas, half * 0.55, angle);
      case 'isource':
        _circleSource(canvas, half);
        _localArrow(canvas, -half * 0.55, half * 0.55);
      case 'battery':
        _battery(canvas, half);
      case 'cvsource':
        _diamond(canvas, half);
        _localSign(canvas, Offset(half * 0.45, 0), plus: true, rot: angle);
        _localSign(canvas, Offset(-half * 0.45, 0), plus: false, rot: angle);
      case 'ccsource':
        _diamond(canvas, half);
        _localArrow(canvas, -half * 0.5, half * 0.5);
      case 'diode' || 'zener' || 'led':
        _diode(canvas, half, e.type);
      case 'switch':
        _switch(canvas, half, e.closed);
      case 'lamp':
        _circleSource(canvas, half);
        final r = half * 0.7;
        canvas.drawLine(Offset(-r, -r), Offset(r, r), _stroke);
        canvas.drawLine(Offset(-r, r), Offset(r, -r), _stroke);
      case 'voltmeter' || 'ammeter' || 'motor' || 'generator':
        _circleSource(canvas, half);
        canvas.restore();
        final letter = switch (e.type) { 'voltmeter' => 'V', 'ammeter' => 'A', 'motor' => 'M', _ => 'G' };
        _text(canvas, letter, mid, center: true, bold: true);
        canvas.save();
    }
    canvas.restore();

    // Labels on the side of the element.
    // Default side: above for horizontal, right for vertical.
    final side = labelSide(e);
    final bodyHalfWidth = switch (e.type) {
      'vsource' || 'isource' || 'acsource' || 'voltmeter' || 'ammeter' || 'lamp' || 'motor' ||
      'generator' =>
        0.36,
      'cvsource' || 'ccsource' => 0.4,
      'capacitor' || 'battery' => 0.32,
      _ => 0.22,
    };
    final labels = [
      if (e.label != null && e.label!.isNotEmpty) e.label!,
      if (e.value != null && e.value!.isNotEmpty) e.value!,
    ];
    if (labels.isNotEmpty) {
      final anchor = mid + side * (bodyHalfWidth * cell + 4);
      _labelBlock(canvas, anchor, labels, side);
    }
    if (e.polarity != null) {
      final plusAtFrom = e.polarity == '+-';
      final plates = e.type == 'capacitor' || e.type == 'battery';
      final off = side * (plates ? cell * 0.18 : bodyHalfWidth * cell * 0.9 + 2);
      final along = half + cell * (plates ? 0.2 : 0.08);
      final pFrom = mid - dir * along + off;
      final pTo = mid + dir * along + off;
      _text(canvas, plusAtFrom ? '+' : '−', pFrom, center: true, bold: true, color: accent);
      _text(canvas, plusAtFrom ? '−' : '+', pTo, center: true, bold: true, color: accent);
    }
  }

  void _resistor(Canvas canvas, double half) {
    const zigs = 6;
    final h = cell * 0.16;
    final path = Path()..moveTo(-half, 0);
    for (var i = 0; i < zigs; i++) {
      final x = -half + (i + 0.5) * (2 * half / zigs);
      path.lineTo(x, i.isEven ? -h : h);
    }
    path.lineTo(half, 0);
    canvas.drawPath(path, _stroke);
  }

  void _capacitor(Canvas canvas, double half) {
    final h = cell * 0.3;
    canvas.drawLine(Offset(-half, -h), Offset(-half, h), _stroke);
    canvas.drawLine(Offset(half, -h), Offset(half, h), _stroke);
  }

  void _inductor(Canvas canvas, double half) {
    const loops = 4;
    final w = 2 * half / loops;
    final path = Path()..moveTo(-half, 0);
    for (var i = 0; i < loops; i++) {
      final x0 = -half + i * w;
      path.arcTo(Rect.fromLTWH(x0, -w / 2, w, w), math.pi, math.pi, false);
    }
    canvas.drawPath(path, _stroke);
  }

  void _circleSource(Canvas canvas, double half) {
    canvas.drawCircle(Offset.zero, half, _bgFill);
    canvas.drawCircle(Offset.zero, half, _stroke);
  }

  void _diamond(Canvas canvas, double half) {
    final path = Path()
      ..moveTo(-half, 0)
      ..lineTo(0, -half)
      ..lineTo(half, 0)
      ..lineTo(0, half)
      ..close();
    canvas.drawPath(path, _bgFill);
    canvas.drawPath(path, _stroke);
  }

  void _sine(Canvas canvas, double r, double elementAngle) {
    final path = Path()..moveTo(-r, 0);
    for (var i = 1; i <= 20; i++) {
      final t = i / 20;
      path.lineTo(-r + 2 * r * t, -math.sin(t * 2 * math.pi) * r * 0.5);
    }
    // Undo the element rotation so the sine wave is always drawn upright.
    canvas.save();
    canvas.rotate(-elementAngle);
    canvas.drawPath(path, _stroke);
    canvas.restore();
  }

  void _localArrow(Canvas canvas, double x0, double x1) {
    canvas.drawLine(Offset(x0, 0), Offset(x1, 0), _stroke);
    final s = cell * 0.12;
    final head = Path()
      ..moveTo(x1, 0)
      ..lineTo(x1 - s, -s * 0.7)
      ..lineTo(x1 - s, s * 0.7)
      ..close();
    canvas.drawPath(head, _fill);
  }

  /// Draws + or − at a local position, keeping the glyph upright.
  void _localSign(Canvas canvas, Offset pos, {required bool plus, required double rot}) {
    final s = cell * 0.08;
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(-rot);
    canvas.drawLine(Offset(-s, 0), Offset(s, 0), _stroke);
    if (plus) canvas.drawLine(Offset(0, -s), Offset(0, s), _stroke);
    canvas.restore();
  }

  void _battery(Canvas canvas, double half) {
    // Long plate (+) at +x, short plate (−) at −x.
    final hl = cell * 0.32;
    final hs = cell * 0.16;
    canvas.drawLine(Offset(half, -hl), Offset(half, hl), _stroke);
    final thick = Paint()
      ..color = color
      ..strokeWidth = _stroke.strokeWidth * 2.2;
    canvas.drawLine(Offset(-half, -hs), Offset(-half, hs), thick);
  }

  void _diode(Canvas canvas, double half, String type) {
    final h = cell * 0.22;
    final tri = Path()
      ..moveTo(-half, -h)
      ..lineTo(half, 0)
      ..lineTo(-half, h)
      ..close();
    canvas.drawPath(tri, type == 'led' ? _bgFill : _fill);
    canvas.drawPath(tri, _stroke);
    canvas.drawLine(Offset(half, -h), Offset(half, h), _stroke);
    if (type == 'zener') {
      final k = h * 0.4;
      canvas.drawLine(Offset(half, -h), Offset(half - k, -h - k * 0.6), _stroke);
      canvas.drawLine(Offset(half, h), Offset(half + k, h + k * 0.6), _stroke);
    }
    if (type == 'led') {
      for (final dx in [-0.1, 0.15]) {
        final s = Offset(dx * cell, -h - cell * 0.05);
        final t = s + Offset(cell * 0.15, -cell * 0.18);
        canvas.drawLine(s, t, _stroke);
        canvas.drawCircle(t, cell * 0.03, _fill);
      }
    }
  }

  void _switch(Canvas canvas, double half, bool closed) {
    canvas.drawCircle(Offset(-half, 0), cell * 0.05, _fill);
    canvas.drawCircle(Offset(half, 0), cell * 0.05, _fill);
    final end = closed ? Offset(half, 0) : Offset(half * 0.8, -cell * 0.32);
    canvas.drawLine(Offset(-half, 0), end, _stroke);
  }

  // ---------------------------------------------------------------------------
  // Point components
  // ---------------------------------------------------------------------------

  void _ground(Canvas canvas, CircuitElement e) {
    final p = _p(e.at!);
    canvas.save();
    canvas.translate(p.dx, p.dy);
    canvas.rotate(e.rotation * math.pi / 180);
    final s = cell * 0.22;
    canvas.drawLine(Offset.zero, Offset(0, s), _stroke);
    for (var i = 0; i < 3; i++) {
      final w = s * (1.2 - i * 0.4);
      final y = s + i * s * 0.35;
      canvas.drawLine(Offset(-w, y), Offset(w, y), _stroke);
    }
    canvas.restore();
  }

  void _arrow(Canvas canvas, CircuitElement e) {
    final a = _p(e.from!);
    final b = _p(e.to!);
    final dir = (b - a) / (b - a).distance;
    final tip = (a + b) / 2 + dir * cell * 0.12;
    final s = cell * 0.14;
    final n = Offset(-dir.dy, dir.dx);
    final head = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo((tip - dir * s + n * s * 0.6).dx, (tip - dir * s + n * s * 0.6).dy)
      ..lineTo((tip - dir * s - n * s * 0.6).dx, (tip - dir * s - n * s * 0.6).dy)
      ..close();
    final p = Paint()
      ..color = accent
      ..style = PaintingStyle.fill;
    canvas.drawPath(head, p);
    if (e.label != null) {
      var side = (dir.dx.abs() >= dir.dy.abs())
          ? (n.dy < 0 ? n : -n)
          : (n.dx > 0 ? n : -n);
      if (e.flip) side = -side;
      _labelBlock(canvas, (a + b) / 2 + side * (cell * 0.12), [e.label!], side, color: accent);
    }
  }

  /// Arrowhead at the end of a `signal` polyline (block diagrams).
  void _signalHead(Canvas canvas, CircuitElement e) {
    if (e.points.length < 2) return;
    final a = _p(e.points[e.points.length - 2]), b = _p(e.points.last);
    final dir = (b - a) / (b - a).distance;
    final n = Offset(-dir.dy, dir.dx);
    final s = cell * 0.16;
    final head = Path()
      ..moveTo(b.dx, b.dy)
      ..lineTo((b - dir * s + n * s * 0.55).dx, (b - dir * s + n * s * 0.55).dy)
      ..lineTo((b - dir * s - n * s * 0.55).dx, (b - dir * s - n * s * 0.55).dy)
      ..close();
    canvas.drawPath(head, _fill);
    if (e.label != null) {
      // Label above the middle of the first segment.
      final p0 = _p(e.points[0]), p1 = _p(e.points[1]);
      final side = e.flip ? 1.0 : -1.0;
      final lbl = _layout(e.label!);
      final m = (p0 + p1) / 2;
      lbl.paint(canvas, Offset(m.dx - lbl.width / 2, side < 0 ? m.dy - lbl.height - 2 : m.dy + 2));
    }
  }

  /// Transformer: primary pins at at+(-1,∓1), secondary at at+(1,∓1).
  void _transformer(Canvas canvas, CircuitElement e) {
    final a = e.at!;
    final xl = a.dx - 0.38, xr = a.dx + 0.38;
    // Leads from the pins to the coil ends.
    for (final (pin, coilX, y) in [
      (a + const Offset(-1, -1), xl, a.dy - 0.7),
      (a + const Offset(-1, 1), xl, a.dy + 0.7),
      (a + const Offset(1, -1), xr, a.dy - 0.7),
      (a + const Offset(1, 1), xr, a.dy + 0.7),
    ]) {
      _polyline(canvas, [_p(pin), _p(Offset(coilX, pin.dy)), _p(Offset(coilX, y))]);
    }
    // Coils: four half-circle bumps, primary bulging right, secondary left.
    const loops = 4;
    final h = 1.4 / loops;
    for (final (x, dir) in [(xl, 1.0), (xr, -1.0)]) {
      final path = Path()..moveTo(_p(Offset(x, a.dy - 0.7)).dx, _p(Offset(x, a.dy - 0.7)).dy);
      for (var i = 0; i < loops; i++) {
        final top = a.dy - 0.7 + i * h;
        final r = Rect.fromLTWH(_p(Offset(x - h / 2, top)).dx, _p(Offset(x, top)).dy, h * cell, h * cell);
        path.arcTo(r, -math.pi / 2, dir * math.pi, false);
      }
      canvas.drawPath(path, _stroke);
    }
    // Iron core.
    for (final dx in [-0.07, 0.07]) {
      canvas.drawLine(_p(Offset(a.dx + dx, a.dy - 0.75)), _p(Offset(a.dx + dx, a.dy + 0.75)), _stroke);
    }
    // Dot convention: both dots at the top (flip puts the secondary dot at the bottom).
    final r = cell * 0.06;
    canvas.drawCircle(_p(Offset(xl - 0.22, a.dy - 0.62)), r, _fill);
    canvas.drawCircle(_p(Offset(xr + 0.22, e.flip ? a.dy + 0.62 : a.dy - 0.62)), r, _fill);
    if (e.label != null) {
      final lbl = _layout(e.label!);
      final c = _p(Offset(a.dx, a.dy - 1.08));
      lbl.paint(canvas, Offset(c.dx - lbl.width / 2, c.dy - lbl.height));
    }
  }

  /// A labelled box for block diagrams; pins at the middle of each side.
  void _block(Canvas canvas, CircuitElement e) {
    final sz = e.size ?? const Offset(2, 1);
    final rect = Rect.fromCenter(center: _p(e.at!), width: sz.dx * cell, height: sz.dy * cell);
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(cell * 0.08));
    canvas.drawRRect(rr, _bgFill);
    canvas.drawRRect(rr, _stroke);
    if (e.label != null) {
      final lbl = _layout(e.label!);
      lbl.paint(canvas, rect.center - Offset(lbl.width / 2, lbl.height / 2));
    }
    if (e.value != null) {
      final lbl = _layout(e.value!);
      lbl.paint(canvas, Offset(rect.center.dx - lbl.width / 2, rect.top - lbl.height - 2));
    }
  }

  /// Summing junction. `kind` gives the input signs for the left, bottom and
  /// top inputs, e.g. "+-" (left +, bottom −).
  void _sum(Canvas canvas, CircuitElement e) {
    final c = _p(e.at!);
    final r = cell * 0.3;
    canvas.drawCircle(c, r, _bgFill);
    canvas.drawCircle(c, r, _stroke);
    final d = r * 0.7071;
    canvas.drawLine(c + Offset(-d, -d), c + Offset(d, d), _stroke);
    canvas.drawLine(c + Offset(-d, d), c + Offset(d, -d), _stroke);
    final signs = e.kind ?? '';
    final spots = [Offset(-r - cell * 0.12, -r * 0.9), Offset(r * 0.9 + cell * 0.05, r + cell * 0.14), Offset(r * 0.9 + cell * 0.05, -r - cell * 0.14)];
    for (var i = 0; i < signs.length && i < spots.length; i++) {
      final ch = signs[i] == '-' ? '−' : signs[i];
      _text(canvas, ch, c + spots[i], center: true, bold: true);
    }
    if (e.label != null) _labelNear(canvas, c, e.label!, const Offset(0.35, -0.45));
  }

  /// A node name badge used in worked solutions.
  void _tag(Canvas canvas, CircuitElement e) {
    final p = _p(e.at!) + Offset(cell * 0.2, -cell * 0.22);
    final label = _layout(e.label ?? '', bold: true, color: Colors.white);
    final r = math.max(label.width, label.height) / 2 + 3;
    canvas.drawCircle(p, r, Paint()..color = accent);
    label.paint(canvas, p - Offset(label.width / 2, label.height / 2));
  }

  /// A circular mesh-current arrow (clockwise, or counter-clockwise with flip).
  void _loop(Canvas canvas, CircuitElement e) {
    final c = _p(e.at!);
    final r = cell * 0.38;
    final paint = Paint()
      ..color = accent
      ..strokeWidth = _stroke.strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final ccw = e.flip;
    // Arc from 120° sweeping 300° (gap at the top-left), y axis points down.
    const start = -math.pi * 0.35;
    const sweep = math.pi * 1.6;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), ccw ? start + sweep : start,
        ccw ? -sweep : sweep, false, paint);
    // Arrowhead at the end of the arc, tangent to the direction of travel.
    final endAngle = ccw ? start : start + sweep;
    final tip = c + Offset(math.cos(endAngle), math.sin(endAngle)) * r;
    final tangent = ccw
        ? Offset(math.sin(endAngle), -math.cos(endAngle))
        : Offset(-math.sin(endAngle), math.cos(endAngle));
    final n = Offset(-tangent.dy, tangent.dx);
    final s = cell * 0.13;
    final head = Path()
      ..moveTo((tip + tangent * s * 0.6).dx, (tip + tangent * s * 0.6).dy)
      ..lineTo((tip - tangent * s * 0.6 + n * s * 0.6).dx, (tip - tangent * s * 0.6 + n * s * 0.6).dy)
      ..lineTo((tip - tangent * s * 0.6 - n * s * 0.6).dx, (tip - tangent * s * 0.6 - n * s * 0.6).dy)
      ..close();
    canvas.drawPath(head, Paint()..color = accent);
    if (e.label != null) _text(canvas, e.label!, c, center: true, color: accent);
  }

  void _opamp(Canvas canvas, CircuitElement e) {
    final c = _p(e.at!);
    final w = cell * 1.6;
    final h = cell * 1.6;
    final left = c.dx - w / 2;
    final tri = Path()
      ..moveTo(left, c.dy - h / 2)
      ..lineTo(left + w, c.dy)
      ..lineTo(left, c.dy + h / 2)
      ..close();
    canvas.drawPath(tri, _bgFill);
    canvas.drawPath(tri, _stroke);
    // Input leads from pin positions (x-1, y∓0.5) to the triangle edge.
    final inTop = _p(e.at! + const Offset(-1, -0.5));
    final inBot = _p(e.at! + const Offset(-1, 0.5));
    canvas.drawLine(inTop, Offset(left, inTop.dy), _stroke);
    canvas.drawLine(inBot, Offset(left, inBot.dy), _stroke);
    final out = _p(e.at! + const Offset(1, 0));
    canvas.drawLine(Offset(left + w, c.dy), out, _stroke);
    final topSign = e.flip ? '+' : '−';
    final botSign = e.flip ? '−' : '+';
    _text(canvas, topSign, Offset(left + cell * 0.2, inTop.dy), center: true, bold: true);
    _text(canvas, botSign, Offset(left + cell * 0.2, inBot.dy), center: true, bold: true);
    if (e.label != null) {
      _text(canvas, e.label!, Offset(c.dx + cell * 0.05, c.dy - h / 2 - _font * 0.2), center: true);
    }
  }

  void _gate(Canvas canvas, CircuitElement e) {
    final c = _p(e.at!);
    final kind = e.kind ?? 'and';
    final w = cell * 1.1;
    final h = cell * 1.1;
    final left = c.dx - w / 2;
    final right = c.dx + w / 2;
    final top = c.dy - h / 2;
    final bot = c.dy + h / 2;
    final base = kind.replaceFirst(RegExp(r'^n(?=and|or)'), '').replaceFirst('xnor', 'xor');
    final inverted = kind.startsWith('n') || kind == 'not' || kind == 'xnor';
    final bubbleR = cell * 0.09;
    final bodyRight = inverted ? right - 2 * bubbleR : right;

    final path = Path();
    var inputEdgeX = left;
    if (kind == 'not' || kind == 'buffer') {
      path
        ..moveTo(left, top)
        ..lineTo(bodyRight, c.dy)
        ..lineTo(left, bot)
        ..close();
    } else if (base == 'and') {
      // The arc's rightmost point lands on bodyRight (leaving room for the
      // inversion bubble on NAND).
      final arcX = bodyRight - h / 2;
      path
        ..moveTo(left, top)
        ..lineTo(arcX, top)
        ..arcToPoint(Offset(arcX, bot), radius: Radius.circular(h / 2))
        ..lineTo(left, bot)
        ..close();
    } else {
      // OR / XOR shape.
      final curve = w * 0.25;
      inputEdgeX = left + curve * 0.5;
      path
        ..moveTo(left, top)
        ..quadraticBezierTo(left + w * 0.55, top, bodyRight, c.dy)
        ..quadraticBezierTo(left + w * 0.55, bot, left, bot)
        ..quadraticBezierTo(left + curve, c.dy, left, top)
        ..close();
      if (base == 'xor') {
        final x = Path()
          ..moveTo(left - cell * 0.15, top)
          ..quadraticBezierTo(left - cell * 0.15 + curve, c.dy, left - cell * 0.15, bot);
        canvas.drawPath(x, _stroke);
      }
    }
    canvas.drawPath(path, _bgFill);
    canvas.drawPath(path, _stroke);
    if (inverted) {
      canvas.drawCircle(Offset(bodyRight + bubbleR, c.dy), bubbleR, _bgFill);
      canvas.drawCircle(Offset(bodyRight + bubbleR, c.dy), bubbleR, _stroke);
    }
    // Pins.
    final out = _p(e.at! + const Offset(1, 0));
    canvas.drawLine(Offset(right, c.dy), out, _stroke);
    final single = kind == 'not' || kind == 'buffer';
    final ins = single
        ? [e.at! + const Offset(-1, 0)]
        : [e.at! + const Offset(-1, -0.3), e.at! + const Offset(-1, 0.3)];
    for (final i in ins) {
      final p = _p(i);
      canvas.drawLine(p, Offset(base == 'or' || base == 'xor' ? inputEdgeX + cell * 0.04 : left, p.dy), _stroke);
    }
    if (e.label != null) {
      _text(canvas, e.label!, Offset(c.dx, bot + _font * 0.8), center: true);
    }
  }

  void _bjt(Canvas canvas, CircuitElement e) {
    final c = _p(e.at!);
    final pnp = e.type == 'pnp';
    final barX = c.dx - cell * 0.35;
    final bar = cell * 0.35;
    canvas.drawCircle(Offset(c.dx - cell * 0.1, c.dy), cell * 0.55, _stroke);
    // Base lead.
    canvas.drawLine(_p(e.at! + const Offset(-1, 0)), Offset(barX, c.dy), _stroke);
    final thick = Paint()
      ..color = color
      ..strokeWidth = _stroke.strokeWidth * 2;
    canvas.drawLine(Offset(barX, c.dy - bar), Offset(barX, c.dy + bar), thick);
    // Upper and lower diagonal leads to (x, y∓1).
    final upper = Offset(c.dx, c.dy - cell * 0.45);
    final lower = Offset(c.dx, c.dy + cell * 0.45);
    canvas.drawLine(Offset(barX, c.dy - bar * 0.45), upper, _stroke);
    canvas.drawLine(Offset(barX, c.dy + bar * 0.45), lower, _stroke);
    canvas.drawLine(upper, _p(e.at! + const Offset(0, -1)), _stroke);
    canvas.drawLine(lower, _p(e.at! + const Offset(0, 1)), _stroke);
    // Emitter arrow: npn → emitter is lower, arrow pointing out (toward lower).
    // pnp → emitter is upper, arrow pointing in (toward bar).
    final from = pnp ? upper : Offset(barX, c.dy + bar * 0.45);
    final to = pnp ? Offset(barX, c.dy - bar * 0.45) : lower;
    final dir = (to - from) / (to - from).distance;
    final tip = from + (to - from) * 0.8;
    final n = Offset(-dir.dy, dir.dx);
    final s = cell * 0.13;
    final head = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo((tip - dir * s + n * s * 0.55).dx, (tip - dir * s + n * s * 0.55).dy)
      ..lineTo((tip - dir * s - n * s * 0.55).dx, (tip - dir * s - n * s * 0.55).dy)
      ..close();
    canvas.drawPath(head, _fill);
    if (e.label != null) {
      _labelNear(canvas, c, e.label!, const Offset(0.55, -0.15));
    }
  }

  void _mosfet(Canvas canvas, CircuitElement e) {
    final c = _p(e.at!);
    final pmos = e.type == 'pmos';
    final gateX = c.dx - cell * 0.45;
    final chanX = c.dx - cell * 0.3;
    final h = cell * 0.4;
    // Gate lead and plate.
    final gateIn = _p(e.at! + const Offset(-1, 0));
    final gateEnd = pmos ? gateX - cell * 0.16 : gateX;
    canvas.drawLine(gateIn, Offset(gateEnd, c.dy), _stroke);
    if (pmos) {
      canvas.drawCircle(Offset(gateX - cell * 0.08, c.dy), cell * 0.08, _stroke);
    }
    canvas.drawLine(Offset(gateX, c.dy - h), Offset(gateX, c.dy + h), _stroke);
    // Channel.
    final thick = Paint()
      ..color = color
      ..strokeWidth = _stroke.strokeWidth * 1.6;
    canvas.drawLine(Offset(chanX, c.dy - h), Offset(chanX, c.dy + h), thick);
    final top = c.dy - h * 0.8;
    final bot = c.dy + h * 0.8;
    canvas.drawLine(Offset(chanX, top), Offset(c.dx, top), _stroke);
    canvas.drawLine(Offset(chanX, bot), Offset(c.dx, bot), _stroke);
    canvas.drawLine(Offset(c.dx, top), _p(e.at! + const Offset(0, -1)), _stroke);
    canvas.drawLine(Offset(c.dx, bot), _p(e.at! + const Offset(0, 1)), _stroke);
    // Arrow on the source lead (nmos: source at bottom, arrow pointing out;
    // pmos: source at top, arrow pointing in).
    final y = pmos ? top : bot;
    final mid = (chanX + c.dx) / 2;
    final s = cell * 0.12;
    final pointsRight = !pmos;
    final tipX = pointsRight ? mid + s / 2 : mid - s / 2;
    final backX = pointsRight ? tipX - s : tipX + s;
    final head = Path()
      ..moveTo(tipX, y)
      ..lineTo(backX, y - s * 0.6)
      ..lineTo(backX, y + s * 0.6)
      ..close();
    canvas.drawPath(head, _fill);
    if (e.label != null) {
      _labelNear(canvas, c, e.label!, const Offset(0.2, -0.05));
    }
  }

  // ---------------------------------------------------------------------------
  // Text
  // ---------------------------------------------------------------------------

  /// Draws a stack of labels next to [anchor], on the given [side].
  void _labelBlock(Canvas canvas, Offset anchor, List<String> labels, Offset side,
      {Color? color}) {
    final painters = [for (final l in labels) _layout(l, color: color)];
    final width = painters.map((p) => p.width).reduce(math.max);
    final height = painters.fold<double>(0, (s, p) => s + p.height);
    Offset topLeft;
    if (side.dx.abs() > side.dy.abs()) {
      // Left / right of a vertical element.
      final x = side.dx > 0 ? anchor.dx : anchor.dx - width;
      topLeft = Offset(x, anchor.dy - height / 2);
    } else {
      final y = side.dy < 0 ? anchor.dy - height : anchor.dy;
      topLeft = Offset(anchor.dx - width / 2, y);
    }
    var y = topLeft.dy;
    for (final p in painters) {
      final x = side.dx.abs() > side.dy.abs()
          ? (side.dx > 0 ? topLeft.dx : topLeft.dx + width - p.width)
          : anchor.dx - p.width / 2;
      p.paint(canvas, Offset(x, y));
      y += p.height;
    }
  }

  void _labelNear(Canvas canvas, Offset p, String text, Offset gridOffset,
      {bool alignRight = false}) {
    final tp = _layout(text);
    final o = p + gridOffset * cell;
    tp.paint(canvas, Offset(alignRight ? o.dx - tp.width : o.dx, o.dy - tp.height / 2));
  }

  void _text(Canvas canvas, String text, Offset pos,
      {bool center = false, bool bold = false, Color? color}) {
    final tp = _layout(text, bold: bold, color: color);
    tp.paint(canvas, center ? pos - Offset(tp.width / 2, tp.height / 2) : pos);
  }

  /// Lays out a label. `X_sub` / `X_{sub}` render as a lowered subscript,
  /// `~X` / `~{AB}` as overlined (complemented) text.
  SchematicLabel _layout(String text, {bool bold = false, Color? color}) => SchematicLabel.layout(
        text,
        color: color ?? this.color,
        fontSize: _font,
        fontFamily: fontFamily,
        bold: bold,
      );

  @override
  bool shouldRepaint(covariant CircuitPainter old) =>
      old.spec != spec || old.cell != cell || old.color != color || old.highlights != highlights;
}
