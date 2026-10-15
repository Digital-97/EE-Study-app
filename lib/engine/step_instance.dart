import 'dart:math' as math;

import '../models/circuit.dart';
import '../models/content.dart';
import '../models/plot.dart';
import 'circuit_solver.dart';
import 'expression.dart';
import 'units.dart';

/// A concrete, randomized instance of a [StepSpec], ready to display.
///
/// All `{{expr}}` placeholders in text are resolved, options are shuffled and
/// the correct answer is known.
class StepInstance {
  StepInstance._(this.spec, this.vars, this._random, this.target);

  final StepSpec spec;
  final Map<String, double> vars;
  final math.Random _random;

  /// The chosen question variant from the step's `ask` list, if any.
  final Map<String, dynamic>? target;

  StepType get type => spec.type;

  /// Draws parameters for [spec] and returns a ready-to-use instance.
  factory StepInstance.create(StepSpec spec, [math.Random? random, int? targetIndex]) {
    final rnd = random ?? math.Random();
    Map<String, double> vars = {};
    for (var attempt = 0; attempt < 200; attempt++) {
      vars = drawVars(spec, rnd);
      if (spec.require == null) break;
      final ok = Expression.eval(spec.require!, vars);
      if (ok > 0) break;
    }
    final ask = spec.raw['ask'] as List?;
    final target = ask == null || ask.isEmpty
        ? null
        : Map<String, dynamic>.from(ask[targetIndex ?? rnd.nextInt(ask.length)] as Map);
    return StepInstance._(spec, vars, rnd, target);
  }

  /// Draws a random value for each param, evaluates derived values, solves
  /// the circuit (if it has solver values) and evaluates computed values.
  static Map<String, double> drawVars(StepSpec spec, math.Random rnd) {
    final vars = <String, double>{};
    spec.params.forEach((name, p) {
      vars[name] = _draw(p, rnd);
    });
    for (final d in spec.derived) {
      vars[d.key] = Expression.eval(d.value, vars);
    }
    final circuit = spec.circuit;
    if (circuit != null && CircuitSolver.isSolvable(circuit)) {
      vars.addAll(CircuitSolver.solve(circuit, vars));
    }
    for (final d in spec.computed) {
      vars[d.key] = Expression.eval(d.value, vars);
    }
    return vars;
  }

  static double _draw(ParamSpec p, math.Random rnd) {
    if (p.values != null && p.values!.isNotEmpty) {
      return p.values![rnd.nextInt(p.values!.length)];
    }
    final min = p.min ?? 0;
    final max = p.max ?? min;
    final step = p.step;
    if (step != null && step > 0) {
      final n = ((max - min) / step).floor();
      final v = min + rnd.nextInt(n + 1) * step;
      // Avoid floating point dust (0.30000000000000004).
      return double.parse(v.toStringAsPrecision(12));
    }
    return min + rnd.nextDouble() * (max - min);
  }

  static final _placeholder = RegExp(r'\{\{([^{}]+?)\}\}');

  /// Resolves `{{expr}}`, `{{expr|unit}}` and `{{expr|unit|sig}}` in [text].
  static String fill(String text, Map<String, double> vars) {
    return text.replaceAllMapped(_placeholder, (m) {
      final parts = m.group(1)!.split('|');
      var value = Expression.eval(parts[0].trim(), vars);
      // Floating-point noise (e.g. cos(90°) = 6e-17) would print as an odd
      // tiny number; nothing in first-year EE is this small, so snap to 0.
      if (value.abs() < 1e-12) value = 0;
      final unit = parts.length > 1 ? parts[1].trim() : '';
      // {{n|hex}}, {{n|bin}}, optionally padded: {{n|hex|4}} → 00FF.
      if (unit == 'hex' || unit == 'bin') {
        final digits = value.round().toRadixString(unit == 'hex' ? 16 : 2).toUpperCase();
        final width = parts.length > 2 ? int.parse(parts[2].trim()) : 0;
        return digits.padLeft(width, '0');
      }
      final sig = parts.length > 2 ? int.parse(parts[2].trim()) : 3;
      return SiFormat.format(value, unit, sig);
    });
  }

  /// A field of the step, taking the chosen `ask` variant into account.
  dynamic field(String key) => target?[key] ?? spec.raw[key];

  String text(String key) => optionalText(key) ?? '';

  String? optionalText(String key) {
    final v = field(key);
    if (v == null) return null;
    return fill(v as String, vars);
  }

  /// The prompt: the step's prompt followed by the chosen variant's prompt.
  String get prompt {
    final base = spec.raw['prompt'] as String?;
    final extra = target?['prompt'] as String?;
    return fill([?base, ?extra].join(' '), vars);
  }

  String get title => text('title');
  String get body => text('body');
  String? get formula => optionalText('formula');
  String? get hint => optionalText('hint');
  String? get explanation => optionalText('explanation');

  CircuitSpec? get circuit => spec.circuit == null ? null : resolveCircuit(spec.circuit!, vars);

  /// Fills placeholders in labels and adds value labels for solver elements.
  static CircuitSpec resolveCircuit(CircuitSpec c, Map<String, double> vars) => c.mapText(
        (t) => fill(t, vars),
        autoValue: (e) {
          if (e.val == null || unitForElement(e.type).isEmpty) return null;
          final text = formatElementValue(e.type, Expression.eval(e.val!, vars));
          if (c.ac == null || e.phase == null) return text;
          // AC source phasor: "10∠30° V".
          final angle = '∠${SiFormat.formatNumber(Expression.eval(e.phase!, vars), 3)}°';
          final i = text.indexOf(' ');
          return i < 0 ? '$text$angle' : '${text.substring(0, i)}$angle${text.substring(i)}';
        },
      );

  /// The step's graph at the sliders' starting values.
  ResolvedPlot? get plot => spec.plot?.resolve(vars, fill);

  /// Graphs shown as the answer options of a multiple-choice step, in
  /// display order (null when the options are text).
  List<ResolvedPlot>? get optionPlots {
    final raw = spec.raw['optionPlots'] as List?;
    if (raw == null) return null;
    final plots = [
      for (final p in raw) PlotSpec.fromJson(p as Map<String, dynamic>).resolve(vars, fill),
    ];
    return [for (final i in optionOrder) plots[i]];
  }

  // ---- Tap the circuit ----

  /// Names of the elements the student should tap.
  Set<String> get tapAnswer => {for (final n in (spec.raw['answer'] as List)) n as String};

  /// Names the student can tap (default: every named element).
  Set<String> get tapSelectable {
    final raw = spec.raw['selectable'] as List?;
    if (raw != null) return {for (final n in raw) n as String};
    return {
      for (final e in spec.circuit?.elements ?? const <CircuitElement>[])
        if (e.name != null) e.name!,
    };
  }

  /// Whether this step's circuit is solved by the app (Circuit Lab style),
  /// so a worked solution can be shown.
  bool get hasWorkedSolution =>
      spec.circuit != null &&
      CircuitSolver.isSolvable(spec.circuit!) &&
      // Without an independent source every node voltage is 0: nothing to show.
      spec.circuit!.elements.any((e) => e.val != null && _independentSources.contains(e.type));

  static const _independentSources = {'vsource', 'battery', 'acsource', 'isource'};

  CircuitReport workedSolution() => CircuitSolver.report(spec.circuit!, vars);

  // ---- Slider ----

  /// Whether the slider setting [sliders] (name → value) answers the step:
  /// either `check` evaluates > 0, or every slider in `answer` is within
  /// tolerance of its target.
  bool checkSliders(Map<String, double> sliders) {
    final all = spec.plot!.withSliders({...vars, ...sliders});
    final check = spec.raw['check'] as String?;
    if (check != null) return Expression.eval(check, all) > 0;
    final answer = spec.raw['answer'] as Map<String, dynamic>;
    final rel = ((spec.raw['tolerance'] ?? 0.05) as num).toDouble();
    final abs = ((spec.raw['absTolerance'] ?? 0) as num).toDouble();
    return answer.entries.every((e) => SiFormat.isClose(
        all[e.key] ?? double.nan, Expression.eval(e.value.toString(), all),
        relTol: rel, absTol: abs));
  }

  /// The correct setting in words, e.g. "ζ = 0.46" (null when the step only
  /// has a `check` and no `solution` text).
  String? get sliderAnswerText {
    final solution = optionalText('solution');
    if (solution != null) return solution;
    final answer = spec.raw['answer'] as Map<String, dynamic>?;
    if (answer == null) return null;
    final all = spec.plot!.withSliders(vars);
    return [
      for (final e in answer.entries)
        () {
          final s = spec.plot!.sliders.firstWhere((s) => s.name == e.key);
          return '${s.label} = ${SiFormat.format(Expression.eval(e.value.toString(), all), s.unit, s.sig)}';
        }(),
    ].join(', ');
  }

  // ---- Numeric ----

  double get numericAnswer => Expression.eval(field('answer') as String, vars);
  String get unit => (field('unit') ?? '') as String;
  double get tolerance => ((field('tolerance') ?? 0.02) as num).toDouble();

  /// The correct answer for display. Whole numbers without a unit (counts,
  /// ADC codes, bin indexes) are shown exactly instead of rounded.
  String get formattedAnswer {
    final a = numericAnswer;
    if (unit.isEmpty && a == a.roundToDouble() && a.abs() < 1e9) {
      return a.toStringAsFixed(0);
    }
    return SiFormat.format(a, unit, 3);
  }

  bool checkNumeric(String input) {
    var v = SiFormat.parse(input, unit);
    if (v == null) return false;
    if (unit == '°') {
      // Angles: −170° and 190° are the same; compare the nearest equivalent.
      final a = numericAnswer;
      v = a + ((v - a) % 360 + 540) % 360 - 180;
    }
    return SiFormat.isClose(v, numericAnswer,
        relTol: tolerance, absTol: ((field('absTolerance') ?? 1e-12) as num).toDouble());
  }

  // ---- Multiple choice ----

  late final List<String> _options = spec.raw['options'] == null && spec.raw['optionPlots'] != null
      ? [for (var i = 0; i < (spec.raw['optionPlots'] as List).length; i++) 'Graph ${i + 1}']
      : [for (final o in (spec.raw['options'] as List? ?? const [])) fill(o as String, vars)];

  /// Shuffled display order: indexes into the authored option list.
  late final List<int> optionOrder = () {
    final idx = List<int>.generate(_options.length, (i) => i);
    if (spec.raw['shuffle'] != false) idx.shuffle(_random);
    return idx;
  }();

  List<String> get options => [for (final i in optionOrder) _options[i]];

  /// Index (in display order) of the correct option.
  /// Index (in display order) of the correct option. `answer` is either an
  /// index or an expression evaluating to one (e.g. to classify a random case).
  int get correctOptionIndex {
    final a = spec.raw['answer'] ?? 0;
    final authored = a is int ? a : Expression.eval(a as String, vars).round();
    return optionOrder.indexOf(authored);
  }

  // ---- True / false ----

  /// `answer` is true/false, or an expression that is true when > 0.
  bool get trueFalseAnswer {
    final a = spec.raw['answer'];
    return a is bool ? a : Expression.eval(a as String, vars) > 0;
  }

  // ---- Match pairs ----

  List<(String, String)> get pairs => [
        for (final p in (spec.raw['pairs'] as List))
          (fill((p as List)[0] as String, vars), fill(p[1] as String, vars)),
      ];

  // ---- Order steps ----

  List<String> get orderedItems =>
      [for (final i in (spec.raw['items'] as List)) fill(i as String, vars)];
}
