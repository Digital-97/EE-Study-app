// Validates all bundled study content: structure, ids, expressions, LaTeX
// and circuits. Run with `flutter test test/content_test.dart`.
//
// Set CONTENT_SUBJECT=<subject id> to validate only one subject file.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:ee_study/content/content_repository.dart';
import 'package:ee_study/engine/expression.dart';
import 'package:ee_study/engine/rich_segments.dart';
import 'package:ee_study/engine/step_instance.dart';
import 'package:ee_study/models/circuit.dart';
import 'package:ee_study/models/content.dart';
import 'package:ee_study/models/plot.dart';
import 'package:flutter_math_fork/tex.dart';
import 'package:flutter_test/flutter_test.dart';

const _gateKinds = {'and', 'or', 'not', 'nand', 'nor', 'xor', 'xnor', 'buffer'};
const _icons = {
  'bolt', 'memory', 'timeline', 'waves', 'developer_board', 'settings_input_component',
  'show_chart', 'electrical_services', 'calculate', 'tune', 'graphic_eq', 'functions',
  'flare', 'cable', 'code', 'speed', 'sensors', 'bar_chart', 'speaker', 'shield',
  'cell_tower', 'power', 'equalizer', 'account_tree', 'casino', 'electric_meter',
  'settings_input_antenna', 'grain', 'data_object',
};

void main() {
  late ContentRepository repo;
  final only = Platform.environment['CONTENT_SUBJECT'];

  setUpAll(() async {
    final index = jsonDecode(File('assets/content/index.json').readAsStringSync())
        as Map<String, dynamic>;
    // Unit files of draft levels may not exist yet.
    final draftSubjects = <String>{};
    final levelsJson = (index['levels'] as List).cast<Map<String, dynamic>>();
    for (final l in levelsJson.where((l) => l['draft'] == true)) {
      draftSubjects.addAll((l['subjects'] as List).cast<String>());
    }
    final draftUnitFiles = <String>{};
    for (final f in (index['subjectFiles'] as List).cast<String>()) {
      final file = File('assets/content/$f');
      if (!file.existsSync()) continue;
      final subject = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      if (draftSubjects.contains(subject['id'])) {
        draftUnitFiles.addAll((subject['units'] as List).cast<String>());
      }
    }
    bool isDraftFile(Object e) =>
        e is FileSystemException && draftUnitFiles.any((f) => (e.path ?? '').endsWith('/$f'));
    repo = await ContentRepository.fromJson(index, includeDrafts: true,
        skipUnitError: only == null ? isDraftFile : (e) => e is FileSystemException, (file) async {
      final f = File('assets/content/$file');
      if (!f.existsSync()) throw FileSystemException('Missing content file', f.path);
      try {
        return jsonDecode(f.readAsStringSync());
      } on FormatException catch (e) {
        fail('Invalid JSON in ${f.path}: $e');
      }
    });
  });

  test('levels reference existing subjects', () {
    for (final level in repo.levels) {
      for (final id in level.subjectIds) {
        expect(repo.subjects.containsKey(id), isTrue,
            reason: 'Level ${level.id} references missing subject $id');
      }
    }
    for (final s in repo.subjects.values) {
      expect(repo.levelOf(s), isNotNull, reason: 'Subject ${s.id} is not in any level');
    }
  });

  test('ids are unique', () {
    final unitIds = <String>{};
    final lessonIds = <String>{};
    for (final s in repo.subjects.values) {
      for (final u in s.units) {
        expect(unitIds.add(u.id), isTrue, reason: 'Duplicate unit id ${u.id}');
        for (final l in u.lessons) {
          expect(lessonIds.add(l.id), isTrue, reason: 'Duplicate lesson id ${l.id}');
          final stepIds = <String>{};
          for (final st in l.steps) {
            expect(stepIds.add(st.id), isTrue, reason: 'Duplicate step id ${st.id} in ${l.id}');
          }
        }
      }
    }
  });

  test('subjects, units and lessons are well-formed', () {
    final errors = <String>[];
    for (final s in repo.subjects.values) {
      if (only != null && s.id != only) continue;
      if (!_icons.contains(s.icon)) errors.add('${s.id}: unknown icon ${s.icon}');
      if (s.units.isEmpty && !(repo.levelOf(s)?.draft ?? false)) errors.add('${s.id}: no units');
      for (final u in s.units) {
        if (u.study.isEmpty) errors.add('${u.id}: no study cards');
        if (u.lessons.isEmpty) errors.add('${u.id}: no lessons');
        for (final c in u.study) {
          _checkText(c.body, '${u.id} study "${c.title}"', errors);
          _checkText(c.title, '${u.id} study title', errors);
          if (c.formula != null) _checkTex(c.formula!, '${u.id} study formula', errors);
          if (c.circuit != null) _checkCircuit(c.circuit!, '${u.id} study circuit', errors);
          if (c.plot != null) {
            try {
              _checkSpecPlot(c.plot!, const {}, '${u.id} study plot', errors);
            } catch (e) {
              errors.add('${u.id} study plot: $e');
            }
          }
        }
        for (final l in u.lessons) {
          if (l.questionCount < 3) errors.add('${l.id}: fewer than 3 questions');
          for (final st in l.steps) {
            _checkStep(st, errors);
          }
        }
      }
    }
    if (errors.isNotEmpty) fail('Content errors:\n${errors.join('\n')}');
  });
}

void _checkText(String text, String where, List<String> errors) {
  // A single backslash before f, b, t, r or n in JSON turns LaTeX commands
  // like \frac, \beta, \theta, \rho or \neq into control characters.
  if (RegExp('[\x08\x0c\t\r]').hasMatch(text)) {
    errors.add('$where: control character in "$text" (use \\\\ for LaTeX backslashes)');
  }
  for (final seg in splitMath(text)) {
    if (seg.kind == SegmentKind.text && seg.content.contains(r'\n')) {
      errors.add('$where: literal \\n shown as text (write \\n in JSON, not \\\\n) in "$text"');
    }
    if (seg.kind != SegmentKind.text) {
      _checkTex(seg.content, where, errors);
      if (seg.content.contains('\n')) {
        errors.add('$where: line break inside math "${seg.content}" (\\neq written as \\n + eq?)');
      }
    }
  }
  if (RegExp(r'(?<!\\)\$').allMatches(text.replaceAll(r'$$', '')).length.isOdd) {
    errors.add('$where: unbalanced \$ in "$text"');
  }
  if (text.contains('{{')) errors.add('$where: unresolved placeholder in "$text"');
}

void _checkTex(String tex, String where, List<String> errors) {
  if (RegExp('[\x08\x0c\t\r\n]').hasMatch(tex)) {
    errors.add('$where: control character or line break in LaTeX "$tex"');
  }
  try {
    TexParser(tex, const TexParserSettings()).parse();
  } catch (e) {
    errors.add('$where: bad LaTeX "$tex": $e');
  }
}

void _checkCircuit(CircuitSpec c, String where, List<String> errors) {
  for (final e in c.elements) {
    if (!allCircuitTypes.contains(e.type)) {
      errors.add('$where: unknown circuit element ${e.type}');
      continue;
    }
    if ((e.type == 'wire' || e.type == 'signal') && e.points.length < 2) {
      errors.add('$where: ${e.type} needs 2+ points');
    }
    if ((twoTerminalTypes.contains(e.type) || e.type == 'arrow') &&
        (e.from == null || e.to == null)) {
      errors.add('$where: ${e.type} needs from/to');
    }
    if (pointTypes.contains(e.type) && e.at == null) errors.add('$where: ${e.type} needs at');
    if (e.type == 'gate' && !_gateKinds.contains(e.kind)) {
      errors.add('$where: gate kind ${e.kind} invalid');
    }
    if (e.from != null && e.to != null && e.from == e.to) {
      errors.add('$where: ${e.type} from == to');
    }
    if (e.type == 'text' && (e.label == null || e.label!.isEmpty)) {
      errors.add('$where: text element needs label');
    }
  }
}

void _checkStep(StepSpec st, List<String> errors) {
  final where = st.key;
  final raw = st.raw;
  final rnd = math.Random(42);

  // Expressions must reference only known variables.
  final known = {...st.params.keys};
  for (final d in st.derived) {
    try {
      final vars = Expression.parse(d.value).variables;
      final missing = vars.difference(known);
      if (missing.isNotEmpty) errors.add('$where: derived ${d.key} uses unknown $missing');
    } catch (e) {
      errors.add('$where: derived ${d.key}: $e');
    }
    known.add(d.key);
  }

  final required = <StepType, Set<String>>{
    StepType.info: {'title', 'body'},
    StepType.multipleChoice: {'prompt', 'answer'},
    StepType.trueFalse: {'prompt', 'answer'},
    StepType.numeric: {'prompt', 'answer', 'unit'},
    StepType.matchPairs: {'prompt', 'pairs'},
    StepType.orderSteps: {'prompt', 'items'},
    StepType.tapCircuit: {'prompt', 'circuit', 'answer'},
    StepType.slider: {'prompt', 'plot'},
  }[st.type]!;
  final ask = raw['ask'] as List?;
  if (ask != null && st.type != StepType.numeric) {
    errors.add('$where: "ask" is only supported on numeric steps');
  }
  for (final k in required) {
    if (raw.containsKey(k)) continue;
    if (ask != null && ask.isNotEmpty && ask.every((t) => (t as Map).containsKey(k))) continue;
    errors.add('$where: missing "$k"');
  }
  final askHasExplanations =
      ask != null && ask.isNotEmpty && ask.every((t) => (t as Map)['explanation'] != null);
  if (st.isQuestion && raw['explanation'] == null && !askHasExplanations) {
    errors.add('$where: questions need an "explanation"');
  }
  if (st.type == StepType.multipleChoice && raw['options'] == null && raw['optionPlots'] == null) {
    errors.add('$where: multipleChoice needs "options" or "optionPlots"');
  }
  if (st.type == StepType.slider) {
    if (st.plot == null || !st.plot!.interactive) errors.add('$where: slider steps need a plot with "sliders"');
    final answer = raw['answer'];
    if (raw['check'] == null && answer is! Map) {
      errors.add('$where: slider steps need "check" or an "answer" map {slider: value}');
    }
    if (answer is Map && st.plot != null) {
      final names = {for (final s in st.plot!.sliders) s.name};
      if (!names.containsAll(answer.keys)) errors.add('$where: answer names unknown sliders');
    }
  }
  if (errors.isNotEmpty && errors.last.startsWith(where)) return;

  final draws = st.params.isEmpty ? 1 : 25;
  final targets = ask?.length ?? 1;
  for (var i = 0; i < draws * targets; i++) {
    StepInstance inst;
    try {
      inst = StepInstance.create(st, rnd, ask == null ? null : i % targets);
      for (final v in inst.vars.entries) {
        if (!v.value.isFinite) errors.add('$where: ${v.key} is ${v.value}');
      }
      if (st.require != null && Expression.eval(st.require!, inst.vars) <= 0) {
        errors.add('$where: "require" could not be satisfied');
        return;
      }
      for (final key in ['prompt', 'title', 'body', 'formula', 'hint', 'explanation']) {
        final t = inst.optionalText(key);
        if (t == null) continue;
        if (key == 'formula') {
          _checkTex(t, '$where.$key', errors);
        } else {
          _checkText(t, '$where.$key', errors);
        }
      }
      final circuit = inst.circuit;
      if (circuit != null) _checkCircuit(circuit, '$where circuit', errors);
      if (st.plot != null) _checkSpecPlot(st.plot!, inst.vars, '$where plot', errors);
      final optionPlots = inst.optionPlots;
      if (optionPlots != null) {
        if (optionPlots.length < 2 || optionPlots.length > 4) {
          errors.add('$where: optionPlots needs 2-4 graphs');
        }
        if (raw['options'] != null && (raw['options'] as List).length != optionPlots.length) {
          errors.add('$where: options and optionPlots differ in length');
        }
        for (final p in optionPlots) {
          _checkPlot(p, '$where optionPlot', errors);
        }
      }

      switch (st.type) {
        case StepType.numeric:
          final a = inst.numericAnswer;
          if (!a.isFinite) errors.add('$where: answer is $a for ${inst.vars}');
          // The formatted answer must itself be accepted.
          if (!inst.checkNumeric(inst.formattedAnswer)) {
            errors.add('$where: formatted answer "${inst.formattedAnswer}" not accepted');
          }
        case StepType.multipleChoice:
          final opts = inst.options;
          if (opts.length < 2 || opts.length > 5) errors.add('$where: needs 2-5 options');
          if (opts.toSet().length != opts.length) {
            errors.add('$where: duplicate options $opts for ${inst.vars}');
          }
          final ans = raw['answer'];
          if (ans is! int && ans is! String) errors.add('$where: answer must be an index or expression');
          final idx = inst.correctOptionIndex;
          if (idx < 0 || idx >= opts.length) {
            errors.add('$where: answer index invalid for ${inst.vars}');
          }
          for (final o in opts) {
            _checkText(o, '$where option', errors);
          }
        case StepType.trueFalse:
          if (raw['answer'] is! bool && raw['answer'] is! String) {
            errors.add('$where: answer must be true/false or an expression');
          }
        case StepType.matchPairs:
          final p = inst.pairs;
          if (p.length < 3 || p.length > 5) errors.add('$where: needs 3-5 pairs');
          if (p.map((e) => e.$1).toSet().length != p.length ||
              p.map((e) => e.$2).toSet().length != p.length) {
            errors.add('$where: pair sides must be distinct');
          }
          for (final e in p) {
            _checkText(e.$1, '$where pair', errors);
            _checkText(e.$2, '$where pair', errors);
          }
        case StepType.orderSteps:
          final items = inst.orderedItems;
          if (items.length < 3 || items.length > 6) errors.add('$where: needs 3-6 items');
          if (items.toSet().length != items.length) errors.add('$where: items must be distinct');
          for (final e in items) {
            _checkText(e, '$where item', errors);
          }
        case StepType.tapCircuit:
          final names = {for (final e in inst.circuit!.elements) if (e.name != null) e.name!};
          final answer = inst.tapAnswer;
          final selectable = inst.tapSelectable;
          if (answer.isEmpty) errors.add('$where: answer must list at least one element');
          if (!names.containsAll(selectable)) {
            errors.add('$where: selectable names ${selectable.difference(names)} not in circuit');
          }
          if (!selectable.containsAll(answer)) {
            errors.add('$where: answer ${answer.difference(selectable)} is not selectable');
          }
          if (selectable.length < 2) errors.add('$where: give at least 2 tappable elements');
        case StepType.slider:
          _checkSliderStep(inst, where, errors);
        case StepType.info:
          break;
      }
    } catch (e) {
      errors.add('$where: $e');
      return;
    }
  }
}

void _checkPlot(ResolvedPlot p, String where, List<String> errors) {
  for (final (name, a) in [('x', p.x), ('y', p.y)]) {
    if (!(a.max > a.min)) errors.add('$where: $name axis needs max > min (${a.min}..${a.max})');
    if (a.log && a.min <= 0) errors.add('$where: log $name axis needs min > 0');
  }
  if (p.curves.isEmpty && p.points.isEmpty) errors.add('$where: nothing to draw');
  if (p.equal && (p.x.log || p.y.log)) errors.add('$where: "equal" needs linear axes');
  bool inside(double v, PlotAxis a) => v >= a.min - (a.max - a.min) * 0.05 && v <= a.max + (a.max - a.min) * 0.05;
  for (final c in p.curves) {
    if (c.xy != null && !(c.from!.isFinite && c.to!.isFinite && c.to! > c.from!)) {
      errors.add('$where: parametric curve "${c.label ?? ''}" needs "t": [min, max] with max > min');
      continue;
    }
    var finite = 0;
    var inRange = 0;
    for (final (x, y) in c.sample(p.x, 20)) {
      if (x.isFinite && y.isFinite) {
        finite++;
        if (inside(y, p.y) && (c.xy == null || inside(x, p.x))) inRange++;
      }
    }
    if (finite < 15) errors.add('$where: curve "${c.label ?? ''}" is mostly undefined');
    if (inRange < 5) errors.add('$where: curve "${c.label ?? ''}" is mostly outside the y axis range');
  }
}

/// Interactive plots: sliders are sane, and the plot draws at the default,
/// minimum and maximum slider positions.
void _checkSpecPlot(PlotSpec spec, Map<String, double> vars, String where, List<String> errors) {
  _checkPlot(spec.resolve(vars, StepInstance.fill), where, errors);
  if (!spec.interactive) return;
  final names = <String>{};
  for (final s in spec.sliders) {
    if (!names.add(s.name)) errors.add('$where: duplicate slider ${s.name}');
    if (vars.containsKey(s.name)) errors.add('$where: slider ${s.name} hides a variable of the same name');
    _checkText(s.label, '$where slider label', errors);
    final lo = s.minValue(vars), hi = s.maxValue(vars);
    if (!(hi > lo)) errors.add('$where: slider ${s.name} needs max > min');
    if (s.log && lo <= 0) errors.add('$where: log slider ${s.name} needs min > 0');
    if (!s.log && s.step == null) errors.add('$where: slider ${s.name} needs a "step"');
    final d = s.divisions(vars);
    if (!s.log && d == null) errors.add('$where: slider ${s.name} has too many (or no) steps');
  }
  for (final at in [0.0, 1.0]) {
    final setting = {for (final s in spec.sliders) s.name: s.fromPosition(at, vars)};
    final plot = spec.resolve({...vars, ...setting}, StepInstance.fill, revealed: true);
    for (final c in plot.curves) {
      var finite = 0;
      for (final (x, y) in c.sample(plot.x, 20)) {
        if (x.isFinite && y.isFinite) finite++;
      }
      if (finite < 15) errors.add('$where: curve "${c.label ?? ''}" is mostly undefined at slider position $at');
    }
    for (final (label, value) in plot.readouts) {
      _checkText(label, '$where readout', errors);
      if (value.contains('NaN') || value.contains('∞')) {
        errors.add('$where: readout "$label" is $value at slider position $at');
      }
    }
  }
  final revealed = spec.resolve(vars, StepInstance.fill, revealed: true);
  _checkPlot(revealed, '$where (revealed)', errors);
}

/// A slider exercise must be solvable, and not already solved at the start.
void _checkSliderStep(StepInstance inst, String where, List<String> errors) {
  final spec = inst.spec.plot!;
  final start = {for (final s in spec.sliders) s.name: s.initial(inst.vars)};
  if (inst.checkSliders(start)) errors.add('$where: the starting slider position is already correct (${inst.vars})');
  final answer = inst.spec.raw['answer'];
  if (answer is Map) {
    final all = spec.withSliders(inst.vars);
    final target = {
      for (final s in spec.sliders)
        s.name: answer.containsKey(s.name)
            ? s.snap(Expression.eval(answer[s.name].toString(), all), inst.vars)
            : s.initial(inst.vars),
    };
    if (!inst.checkSliders(target)) {
      errors.add('$where: the answer is not reachable on the slider grid (tolerance too tight?) for ${inst.vars}');
    }
    if (inst.sliderAnswerText == null) errors.add('$where: no answer text');
    return;
  }
  // Only a "check": search the slider grid for a passing setting.
  if (spec.sliders.length > 2) {
    errors.add('$where: use an "answer" map with more than 2 sliders');
    return;
  }
  final a = spec.sliders[0];
  final b = spec.sliders.length > 1 ? spec.sliders[1] : null;
  final pa = a.positions(inst.vars);
  final pb = b == null ? <double?>[null] : _sample(b.positions(inst.vars), 60);
  final found = _sample(pa, b == null ? 2001 : 60).any((x) => pb.any((y) => inst.checkSliders({
        ...start,
        a.name: x,
        if (b != null) b.name: y!,
      })));
  if (!found) errors.add('$where: no slider position satisfies "check" for ${inst.vars}');
}

List<T> _sample<T>(List<T> l, int n) =>
    l.length <= n ? l : [for (var i = 0; i < n; i++) l[(i * (l.length - 1) / (n - 1)).round()]];
