/// Splits content text into plain text, inline math (`$...$`) and display
/// math (`$$...$$`) segments. Plain text may contain `**bold**`.
enum SegmentKind { text, inlineMath, displayMath }

class Segment {
  const Segment(this.kind, this.content);
  final SegmentKind kind;
  final String content;

  @override
  String toString() => '$kind($content)';
}

List<Segment> splitMath(String input) {
  final out = <Segment>[];
  final buf = StringBuffer();
  var i = 0;
  void flushText() {
    if (buf.isNotEmpty) {
      out.add(Segment(SegmentKind.text, buf.toString()));
      buf.clear();
    }
  }

  while (i < input.length) {
    final ch = input[i];
    if (ch == r'\' && i + 1 < input.length && input[i + 1] == r'$') {
      buf.write(r'$');
      i += 2;
      continue;
    }
    if (ch == r'$') {
      final display = i + 1 < input.length && input[i + 1] == r'$';
      final delim = display ? r'$$' : r'$';
      final start = i + delim.length;
      final end = input.indexOf(delim, start);
      if (end < 0) {
        buf.write(input.substring(i));
        break;
      }
      flushText();
      out.add(Segment(display ? SegmentKind.displayMath : SegmentKind.inlineMath,
          input.substring(start, end).trim()));
      i = end + delim.length;
      continue;
    }
    buf.write(ch);
    i++;
  }
  flushText();
  return out;
}

/// Splits plain text into (text, bold) runs using `**` markers.
List<(String, bool)> splitBold(String text) {
  final parts = text.split('**');
  return [
    for (var i = 0; i < parts.length; i++)
      if (parts[i].isNotEmpty) (parts[i], i.isOdd),
  ];
}
