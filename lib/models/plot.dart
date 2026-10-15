import 'dart:math' as math;

import '../engine/expression.dart';
import '../engine/units.dart';

/// A graph described in content: axes, curves given as expressions in `x`,
/// marker points and reference lines. Optional sliders make it interactive.
/// See CONTENT_GUIDE.md.
class PlotSpec {
  PlotSpec(this.raw)
    : sliders = [for (final s in (raw['sliders'] as List? ?? const [])) SliderSpec.fromJson(s as Map<String, dynamic>)];

  final Map<String, dynamic> raw;

  /// Sliders the student can drag; each one sets a variable.
  final List<SliderSpec> sliders;

  bool get interactive => sliders.isNotEmpty;

  factory PlotSpec.fromJson(Map<String, dynamic> j) => PlotSpec(j);

  /// [vars] plus every slider's value (its default unless [vars] already
  /// sets it) and the plot's `let` values.
  Map<String, double> withSliders(Map<String, double> vars) {
    final all = Map<String, double>.of(vars);
    for (final s in sliders) {
      all.putIfAbsent(s.name, () => s.initial(vars));
    }
    final let = raw['let'] as Map<String, dynamic>? ?? const {};
    for (final e in let.entries) {
      all[e.key] = Expression.eval(e.value.toString(), all);
    }
    return all;
  }

  /// Evaluates all expressions with [vars] (plus slider values), producing
  /// numbers to draw. [fillText] resolves `{{...}}` placeholders in labels
  /// with the given variables. Items marked `"reveal": true` are only
  /// included when [revealed].
  ResolvedPlot resolve(
    Map<String, double> baseVars,
    String Function(String text, Map<String, double> vars) fillText, {
    bool revealed = false,
  }) {
    final vars = withSliders(baseVars);
    double ev(dynamic v) => v is num ? v.toDouble() : Expression.eval(v.toString(), vars);
    bool shown(dynamic item) => revealed || (item as Map)['reveal'] != true;

    PlotAxis axis(Map<String, dynamic> a) => PlotAxis(
      min: ev(a['min'] ?? 0),
      max: ev(a['max']),
      label: fillText((a['label'] ?? '') as String, vars),
      unit: (a['unit'] ?? '') as String,
      log: (a['log'] ?? false) as bool,
      ticks: a['ticks'] == null ? null : [for (final t in a['ticks'] as List) ev(t)],
    );

    final smith = (raw['smith'] ?? false) as bool;
    // A Smith chart plots the reflection coefficient: both axes run -1..1.
    const unitAxis = {'min': -1, 'max': 1};

    return ResolvedPlot(
      x: axis((raw['x'] ?? (smith ? unitAxis : null)) as Map<String, dynamic>),
      y: axis((raw['y'] ?? (smith ? unitAxis : null)) as Map<String, dynamic>),
      curves: [
        for (final c in (raw['curves'] as List? ?? const []))
          if (shown(c))
            () {
              final m = c as Map<String, dynamic>;
              if (m['f'] == null) {
                // Parametric curve: x(t), y(t) for t over the range `t`.
                final ex = Expression.parse(m['x'].toString());
                final ey = Expression.parse(m['y'].toString());
                final range = m['t'] as List? ?? const [0, 1];
                return PlotCurve(
                  xy: (t) {
                    final v = {...vars, 't': t};
                    return (ex.evaluate(v), ey.evaluate(v));
                  },
                  from: ev(range[0]),
                  to: ev(range[1]),
                  color: (m['color'] ?? 'primary') as String,
                  label: m['label'] == null ? null : fillText(m['label'] as String, vars),
                  dashed: (m['dash'] ?? false) as bool,
                  labelAt: ((m['labelAt'] ?? 0.62) as num).toDouble(),
                );
              }
              final expr = Expression.parse(m['f'] as String);
              return PlotCurve(
                f: (x) => expr.evaluate({...vars, 'x': x}),
                color: (m['color'] ?? 'primary') as String,
                label: m['label'] == null ? null : fillText(m['label'] as String, vars),
                dashed: (m['dash'] ?? false) as bool,
                labelAt: ((m['labelAt'] ?? 0.62) as num).toDouble(),
                from: m['from'] == null ? null : ev(m['from']),
                to: m['to'] == null ? null : ev(m['to']),
              );
            }(),
      ],
      points: [
        for (final p in (raw['points'] as List? ?? const []))
          if (shown(p))
            PlotPoint(
              x: ev((p as Map)['x']),
              y: ev(p['y']),
              label: p['label'] == null ? null : fillText(p['label'] as String, vars),
              guides: (p['guides'] ?? true) as bool,
              marker: (p['marker'] ?? 'dot') as String,
              color: (p['color'] ?? 'orange') as String,
            ),
      ],
      hlines: [
        for (final h in (raw['hlines'] as List? ?? const []))
          if (shown(h))
            PlotLine(
              value: ev((h as Map)['y']),
              label: h['label'] == null ? null : fillText(h['label'] as String, vars),
              color: h['color'] as String?,
            ),
      ],
      vlines: [
        for (final v in (raw['vlines'] as List? ?? const []))
          if (shown(v))
            PlotLine(
              value: ev((v as Map)['x']),
              label: v['label'] == null ? null : fillText(v['label'] as String, vars),
              color: v['color'] as String?,
            ),
      ],
      labels: [
        for (final l in (raw['labels'] as List? ?? const []))
          if (shown(l))
            PlotLabel(
              x: ev((l as Map)['x']),
              y: ev(l['y']),
              text: fillText(l['text'] as String, vars),
              color: (l['color'] ?? 'grey') as String,
            ),
      ],
      readouts: [
        for (final r in (raw['readouts'] as List? ?? const []))
          if (shown(r))
            () {
              final m = r as Map<String, dynamic>;
              final value = ev(m['value']);
              final unit = (m['unit'] ?? '') as String;
              final sig = ((m['sig'] ?? 3) as num).toInt();
              return (
                fillText(m['label'] as String, vars),
                SiFormat.format(value.abs() < 1e-12 ? 0 : value, unit, sig),
              );
            }(),
      ],
      grid: (raw['grid'] ?? true) as bool,
      equal: (raw['equal'] ?? false) as bool,
      smith: smith,
      height: ((raw['height'] ?? (smith ? 300 : 200)) as num).toDouble(),
    );
  }
}

/// A slider that sets variable [name] of an interactive plot.
class SliderSpec {
  SliderSpec({
    required this.name,
    required this.label,
    required this.min,
    required this.max,
    this.step,
    this.value,
    this.unit = '',
    this.log = false,
    this.sig = 3,
  });

  final String name;

  /// Shown before the value (may contain inline math, e.g. "$\\zeta$").
  final String label;

  /// Range and default: numbers or expressions in the step's variables.
  final String min;
  final String max;
  final String? value;

  /// Grid the value snaps to (linear sliders).
  final double? step;
  final String unit;

  /// Logarithmic slider (e.g. a frequency over decades).
  final bool log;
  final int sig;

  factory SliderSpec.fromJson(Map<String, dynamic> j) => SliderSpec(
    name: j['name'] as String,
    label: (j['label'] ?? j['name']) as String,
    min: j['min'].toString(),
    max: j['max'].toString(),
    step: (j['step'] as num?)?.toDouble(),
    value: j['value']?.toString(),
    unit: (j['unit'] ?? '') as String,
    log: (j['log'] ?? false) as bool,
    sig: ((j['sig'] ?? 3) as num).toInt(),
  );

  double minValue(Map<String, double> vars) => Expression.eval(min, vars);
  double maxValue(Map<String, double> vars) => Expression.eval(max, vars);

  double initial(Map<String, double> vars) =>
      snap(value == null ? minValue(vars) : Expression.eval(value!, vars), vars);

  /// Number of discrete positions minus one (null: continuous).
  int? divisions(Map<String, double> vars) {
    if (log) return 200;
    if (step == null || step! <= 0) return null;
    final n = ((maxValue(vars) - minValue(vars)) / step!).round();
    return n >= 1 && n <= 2000 ? n : null;
  }

  /// Slider position (0..1) for [v], and back.
  double toPosition(double v, Map<String, double> vars) {
    final lo = minValue(vars), hi = maxValue(vars);
    if (log) return (math.log(v / lo) / math.log(hi / lo)).clamp(0.0, 1.0);
    return ((v - lo) / (hi - lo)).clamp(0.0, 1.0);
  }

  double fromPosition(double t, Map<String, double> vars) {
    final lo = minValue(vars), hi = maxValue(vars);
    return snap(log ? lo * math.pow(hi / lo, t) : lo + (hi - lo) * t, vars);
  }

  /// Rounds [v] to the slider's grid (or to 3 significant figures on a log
  /// slider) and keeps it in range.
  double snap(double v, Map<String, double> vars) {
    final lo = minValue(vars), hi = maxValue(vars);
    var out = v.clamp(math.min(lo, hi), math.max(lo, hi)).toDouble();
    if (log) {
      out = double.parse(out.toStringAsPrecision(3));
    } else if (step != null && step! > 0) {
      out = lo + ((out - lo) / step!).round() * step!;
    }
    return double.parse(out.toStringAsPrecision(12));
  }

  /// Every position the slider can take (sampled for continuous sliders).
  List<double> positions(Map<String, double> vars) {
    final n = divisions(vars) ?? 400;
    return [for (var i = 0; i <= n; i++) fromPosition(i / n, vars)];
  }
}

class PlotAxis {
  PlotAxis({
    required this.min,
    required this.max,
    required this.label,
    required this.unit,
    required this.log,
    this.ticks,
  });

  final double min;
  final double max;
  final String label;

  /// Unit for tick labels (formatted with SI prefixes), e.g. "s", "Hz", "V".
  final String unit;
  final bool log;

  /// Explicit tick positions; computed automatically when null.
  final List<double>? ticks;

  /// The same axis over a different range.
  PlotAxis withRange(double min, double max) =>
      PlotAxis(min: min, max: max, label: label, unit: unit, log: log, ticks: ticks);
}

class PlotCurve {
  PlotCurve({
    this.f,
    this.xy,
    required this.color,
    this.label,
    this.dashed = false,
    this.labelAt = 0.62,
    this.from,
    this.to,
  }) : assert((f == null) != (xy == null));

  /// y as a function of x, or null for a parametric curve.
  final double Function(double x)? f;

  /// (x, y) as a function of the parameter t, for parametric curves.
  final (double, double) Function(double t)? xy;

  /// Where along the curve's range (0..1) its label is placed.
  final double labelAt;

  /// "primary", "red", "blue", "orange", "green", "purple" or "grey".
  final String color;
  final String? label;
  final bool dashed;

  /// Optional x-range of the curve (defaults to the whole axis); the t-range
  /// of a parametric curve.
  final double? from;
  final double? to;

  /// The point at fraction [u] (0..1) along the curve: along the x-range on
  /// [axis] (log-spaced on a log axis), or along the t-range.
  (double, double) at(double u, PlotAxis axis) {
    if (xy != null) return xy!(from! + (to! - from!) * u);
    final lo = from ?? axis.min, hi = to ?? axis.max;
    final x = axis.log ? lo * math.pow(hi / lo, u) : lo + (hi - lo) * u;
    return (x, f!(x));
  }

  /// [n] + 1 evenly spaced points along the curve.
  List<(double, double)> sample(PlotAxis axis, [int n = 300]) => [for (var i = 0; i <= n; i++) at(i / n, axis)];
}

class PlotPoint {
  PlotPoint({
    required this.x,
    required this.y,
    this.label,
    this.guides = true,
    this.marker = 'dot',
    this.color = 'orange',
  });

  final double x;
  final double y;
  final String? label;

  /// "dot", "x" (pole) or "o" (zero).
  final String marker;
  final String color;

  /// Draw dashed lines from the point to both axes.
  final bool guides;
}

class PlotLine {
  PlotLine({required this.value, this.label, this.color});

  final double value;
  final String? label;

  /// Optional colour name (default: grey-ish foreground).
  final String? color;
}

/// Free text placed at a data position (left edge at x, vertically centred on y).
class PlotLabel {
  PlotLabel({required this.x, required this.y, required this.text, required this.color});

  final double x;
  final double y;
  final String text;
  final String color;
}

class ResolvedPlot {
  ResolvedPlot({
    required this.x,
    required this.y,
    required this.curves,
    required this.points,
    required this.hlines,
    required this.vlines,
    this.labels = const [],
    this.readouts = const [],
    required this.grid,
    this.equal = false,
    this.smith = false,
    required this.height,
  });

  final PlotAxis x;
  final PlotAxis y;
  final List<PlotCurve> curves;
  final List<PlotPoint> points;
  final List<PlotLine> hlines;
  final List<PlotLine> vlines;
  final List<PlotLabel> labels;

  /// Live values shown under an interactive plot: (label, formatted value).
  final List<(String, String)> readouts;
  final bool grid;

  /// Same scale on both axes (circles look round): the shorter axis range is
  /// widened to fit.
  final bool equal;

  /// Draw a Smith chart; x and y are the real and imaginary part of the
  /// reflection coefficient Γ.
  final bool smith;
  final double height;
}
