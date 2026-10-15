import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../ui/theme.dart';

/// A small text label for diagrams and graphs. `X_sub` / `X_{sub}` render as
/// a lowered subscript, `~X` / `~{AB}` as overlined (complemented) text.
class SchematicLabel {
  SchematicLabel._(this._pieces, this.height, this._color, this._lineWidth);

  factory SchematicLabel.layout(
    String text, {
    required Color color,
    required double fontSize,
    String? fontFamily,
    bool bold = false,
  }) {
    final style = TextStyle(
      color: color,
      fontSize: fontSize,
      fontFamily: fontFamily,
      fontFamilyFallback: symbolFontFallback,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      height: 1.15,
    );
    final sub = style.copyWith(fontSize: fontSize * 0.72);
    final pieces = <_Piece>[];
    TextPainter tp(String t, TextStyle st) =>
        TextPainter(text: TextSpan(text: t, style: st), textDirection: TextDirection.ltr)..layout();
    // Subscripts and overlines take letters of any script (e.g. Z_Δ).
    final re = RegExp(r'_\{([^}]*)\}|_([\p{L}\p{N}]+)|~\{([^}]*)\}|~([\p{L}\p{N}])', unicode: true);
    var last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) pieces.add(_Piece(tp(text.substring(last, m.start), style)));
      if (m.group(1) != null || m.group(2) != null) {
        pieces.add(_Piece(tp(m.group(1) ?? m.group(2)!, sub), dy: fontSize * 0.38));
      } else {
        pieces.add(_Piece(tp(m.group(3) ?? m.group(4)!, style), overline: true));
      }
      last = m.end;
    }
    if (last < text.length) pieces.add(_Piece(tp(text.substring(last), style)));
    final hasSub = pieces.any((p) => p.dy > 0);
    return SchematicLabel._(
        pieces, fontSize * 1.15 + (hasSub ? fontSize * 0.15 : 0), color, math.max(1.0, fontSize / 12));
  }

  final List<_Piece> _pieces;
  final double height;
  final Color _color;
  final double _lineWidth;

  double get width => _pieces.fold<double>(0, (s, p) => s + p.painter.width);

  void paint(Canvas canvas, Offset topLeft) {
    var x = topLeft.dx;
    for (final p in _pieces) {
      p.painter.paint(canvas, Offset(x, topLeft.dy + p.dy));
      if (p.overline) {
        final y = topLeft.dy + p.painter.height * 0.12;
        canvas.drawLine(
          Offset(x + 1, y),
          Offset(x + p.painter.width - 1, y),
          Paint()
            ..color = _color
            ..strokeWidth = _lineWidth,
        );
      }
      x += p.painter.width;
    }
  }
}

class _Piece {
  _Piece(this.painter, {this.dy = 0, this.overline = false});

  final TextPainter painter;
  final double dy;
  final bool overline;
}
