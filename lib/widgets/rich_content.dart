import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../engine/rich_segments.dart';

/// Renders content text: paragraphs, `- ` bullets, `**bold**`, inline `$math$`
/// and display `$$math$$`.
class RichContent extends StatelessWidget {
  const RichContent(this.text, {super.key, this.style, this.textAlign = TextAlign.start});

  final String text;
  final TextStyle? style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final base = (style ?? Theme.of(context).textTheme.bodyLarge!).copyWith(height: 1.4);
    final lines = text.split('\n');
    final children = <Widget>[];
    for (final line in lines) {
      final trimmed = line.trimRight();
      if (trimmed.isEmpty) {
        if (children.isNotEmpty) children.add(const SizedBox(height: 6));
        continue;
      }
      final segs = splitMath(trimmed);
      if (segs.length == 1 && segs.first.kind == SegmentKind.displayMath) {
        children.add(DisplayMath(segs.first.content, style: base));
        continue;
      }
      final bullet = trimmed.startsWith('- ') || trimmed.startsWith('• ');
      final content = bullet ? trimmed.substring(2) : trimmed;
      final rich = Text.rich(
        TextSpan(children: inlineSpans(content, base)),
        textAlign: textAlign,
      );
      if (bullet) {
        children.add(Padding(
          padding: const EdgeInsets.only(left: 4, top: 2, bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ', style: base.copyWith(fontWeight: FontWeight.w800)),
              Expanded(child: rich),
            ],
          ),
        ));
      } else {
        children.add(Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: rich));
      }
    }
    return Column(
      crossAxisAlignment: textAlign == TextAlign.center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

/// Builds spans for one line of text with inline math and bold runs.
List<InlineSpan> inlineSpans(String text, TextStyle style) {
  final spans = <InlineSpan>[];
  for (final seg in splitMath(text)) {
    if (seg.kind == SegmentKind.text) {
      for (final (t, bold) in splitBold(seg.content)) {
        spans.add(TextSpan(
          text: t,
          style: bold ? style.copyWith(fontWeight: FontWeight.w800) : style,
        ));
      }
    } else {
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        // Formulas wider than the line scroll horizontally instead of
        // overflowing.
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Math.tex(
            seg.content,
            mathStyle: seg.kind == SegmentKind.displayMath ? MathStyle.display : MathStyle.text,
            textStyle: style.copyWith(fontSize: (style.fontSize ?? 16) * 1.05),
            onErrorFallback: (e) => Text(seg.content, style: style),
          ),
        ),
      ));
    }
  }
  return spans;
}

/// A centered, horizontally scrollable display equation.
class DisplayMath extends StatelessWidget {
  const DisplayMath(this.tex, {super.key, this.style});

  final String tex;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final s = style ?? Theme.of(context).textTheme.bodyLarge!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Math.tex(
            tex,
            mathStyle: MathStyle.display,
            textStyle: s.copyWith(fontSize: (s.fontSize ?? 16) * 1.15),
            onErrorFallback: (e) => Text(tex, style: s),
          ),
        ),
      ),
    );
  }
}
