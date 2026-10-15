import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/step_instance.dart';
import '../engine/units.dart';
import '../models/content.dart';
import '../models/plot.dart';
import '../ui/theme.dart';
import '../widgets/chunky_button.dart';
import '../widgets/circuit_diagram.dart';
import '../widgets/graph_view.dart';
import '../widgets/plot_view.dart';
import '../widgets/rich_content.dart';

/// Connects an exercise widget with the lesson screen's "Check" button.
class ExerciseController extends ChangeNotifier {
  bool _ready = false;
  bool? _result;
  bool Function()? _checker;

  /// Extra feedback line set by the exercise (e.g. the correct answer).
  String? correctAnswerText;

  /// What the student answered, in words (used in exam results).
  String? answerText;

  bool get ready => _ready;
  bool? get result => _result;
  bool get checked => _result != null;

  void setReady(bool v) {
    if (_ready == v) return;
    _ready = v;
    notifyListeners();
  }

  void _register(bool Function() checker) => _checker = checker;

  bool check() {
    _result = _checker?.call() ?? false;
    notifyListeners();
    return _result!;
  }
}

/// Builds the right widget for an exercise instance.
class ExerciseView extends StatelessWidget {
  const ExerciseView({super.key, required this.instance, required this.controller});

  final StepInstance instance;
  final ExerciseController controller;

  @override
  Widget build(BuildContext context) {
    final key = ValueKey(instance);
    return switch (instance.type) {
      StepType.multipleChoice =>
        MultipleChoiceExercise(key: key, instance: instance, controller: controller),
      StepType.trueFalse => TrueFalseExercise(key: key, instance: instance, controller: controller),
      StepType.numeric => NumericExercise(key: key, instance: instance, controller: controller),
      StepType.matchPairs =>
        MatchPairsExercise(key: key, instance: instance, controller: controller),
      StepType.orderSteps =>
        OrderStepsExercise(key: key, instance: instance, controller: controller),
      StepType.tapCircuit =>
        TapCircuitExercise(key: key, instance: instance, controller: controller),
      StepType.slider => SliderExercise(key: key, instance: instance, controller: controller),
      StepType.info => const SizedBox.shrink(),
    };
  }
}

// ---------------------------------------------------------------------------

class MultipleChoiceExercise extends StatefulWidget {
  const MultipleChoiceExercise({super.key, required this.instance, required this.controller});

  final StepInstance instance;
  final ExerciseController controller;

  @override
  State<MultipleChoiceExercise> createState() => _MultipleChoiceExerciseState();
}

class _MultipleChoiceExerciseState extends State<MultipleChoiceExercise> {
  int? _selected;

  @override
  void initState() {
    super.initState();
    widget.controller._register(() {
      final ok = _selected == widget.instance.correctOptionIndex;
      final plots = widget.instance.spec.raw['optionPlots'] != null;
      String name(int i) => plots ? 'Graph ${'ABCDE'[i]}' : widget.instance.options[i];
      widget.controller.correctAnswerText = name(widget.instance.correctOptionIndex);
      widget.controller.answerText = _selected == null ? null : name(_selected!);
      return ok;
    });
    widget.controller.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  void _select(int i) {
    setState(() => _selected = i);
    widget.controller.setReady(true);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.instance.options;
    final checked = widget.controller.checked;
    final correct = widget.instance.correctOptionIndex;
    final plots = _plots;
    if (plots != null) return _plotGrid(plots, checked, correct);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OptionTile(
              selected: _selected == i,
              state: !checked
                  ? null
                  : i == correct
                      ? true
                      : (i == _selected ? false : null),
              onTap: checked
                  ? null
                  : () {
                      setState(() => _selected = i);
                      widget.controller.setReady(true);
                    },
              child: Row(
                children: [
                  _KeyBadge(label: '${i + 1}', active: _selected == i),
                  const SizedBox(width: 12),
                  Expanded(child: RichContent(options[i], style: context.text.bodyLarge)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

extension on _MultipleChoiceExerciseState {
  List<ResolvedPlot>? get _plots => widget.instance.optionPlots;

  Widget _plotGrid(List<ResolvedPlot> plots, bool checked, int correct) {
    Widget tile(int i) => OptionTile(
          dense: true,
          selected: _selected == i,
          state: !checked ? null : (i == correct ? true : (i == _selected ? false : null)),
          onTap: checked ? null : () => _select(i),
          child: Column(children: [
            Align(alignment: Alignment.centerLeft, child: _KeyBadge(label: 'ABCDE'[i], active: _selected == i)),
            const SizedBox(height: 4),
            PlotView(plots[i], compact: true),
          ]),
        );
    return Column(children: [
      for (var r = 0; r < plots.length; r += 2)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: tile(r)),
            const SizedBox(width: 10),
            Expanded(child: r + 1 < plots.length ? tile(r + 1) : const SizedBox()),
          ]),
        ),
    ]);
  }
}

class _KeyBadge extends StatelessWidget {
  const _KeyBadge({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: active ? AppColors.blue : context.border, width: 2),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: active ? AppColors.blue : AppColors.greyDark,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class TrueFalseExercise extends StatefulWidget {
  const TrueFalseExercise({super.key, required this.instance, required this.controller});

  final StepInstance instance;
  final ExerciseController controller;

  @override
  State<TrueFalseExercise> createState() => _TrueFalseExerciseState();
}

class _TrueFalseExerciseState extends State<TrueFalseExercise> {
  bool? _selected;

  @override
  void initState() {
    super.initState();
    widget.controller._register(() {
      widget.controller.correctAnswerText = widget.instance.trueFalseAnswer ? 'True' : 'False';
      widget.controller.answerText = _selected == null ? null : (_selected! ? 'True' : 'False');
      return _selected == widget.instance.trueFalseAnswer;
    });
    widget.controller.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    super.dispose();
  }

  Widget _tile(bool value) {
    final checked = widget.controller.checked;
    final answer = widget.instance.trueFalseAnswer;
    return Expanded(
      child: OptionTile(
        selected: _selected == value,
        state: !checked ? null : (value == answer ? true : (_selected == value ? false : null)),
        onTap: checked
            ? null
            : () {
                setState(() => _selected = value);
                widget.controller.setReady(true);
              },
        child: Column(
          children: [
            Icon(
              value ? Icons.check_circle_rounded : Icons.cancel_rounded,
              size: 36,
              color: value ? AppColors.green : AppColors.red,
            ),
            const SizedBox(height: 6),
            Text(
              value ? 'True' : 'False',
              style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [_tile(true), const SizedBox(width: 12), _tile(false)]);
  }
}

// ---------------------------------------------------------------------------

class NumericExercise extends StatefulWidget {
  const NumericExercise({super.key, required this.instance, required this.controller});

  final StepInstance instance;
  final ExerciseController controller;

  @override
  State<NumericExercise> createState() => _NumericExerciseState();
}

class _NumericExerciseState extends State<NumericExercise> {
  final _text = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller._register(() {
      widget.controller.correctAnswerText = widget.instance.formattedAnswer;
      final given = SiFormat.parse(_text.text, widget.instance.unit);
      widget.controller.answerText = given == null
          ? _text.text
          : SiFormat.format(given, widget.instance.unit, 4);
      return widget.instance.checkNumeric(_text.text);
    });
    widget.controller.addListener(_rebuild);
    _text.addListener(() {
      widget.controller.setReady(SiFormat.parse(_text.text, widget.instance.unit) != null);
      setState(() {});
    });
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _insert(String s) {
    final sel = _text.selection;
    final t = _text.text;
    final start = sel.isValid ? sel.start : t.length;
    final end = sel.isValid ? sel.end : t.length;
    _text.value = TextEditingValue(
      text: t.replaceRange(start, end, s),
      selection: TextSelection.collapsed(offset: start + s.length),
    );
  }

  void _toggleSign() {
    final t = _text.text;
    _text.text = t.startsWith('-') ? t.substring(1) : '-$t';
    _text.selection = TextSelection.collapsed(offset: _text.text.length);
  }

  @override
  Widget build(BuildContext context) {
    final checked = widget.controller.checked;
    final result = widget.controller.result;
    final unit = widget.instance.unit;
    final parsed = SiFormat.parse(_text.text, unit);
    final color = !checked
        ? AppColors.blue
        : (result == true ? AppColors.green : AppColors.red);
    final showPrefixes = SiFormat.takesPrefix(unit);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _text,
          focusNode: _focus,
          enabled: !checked,
          autofocus: false,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,eE\-+/pnuµmkKMG ]')),
          ],
          style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            hintText: 'Your answer',
            suffixText: unit.isEmpty ? null : unit,
            suffixStyle: context.text.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.greyDark,
            ),
            filled: true,
            fillColor: context.isDark ? const Color(0xFF202F36) : const Color(0xFFF7F7F7),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: context.border, width: 2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: color, width: 2),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: color, width: 2),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (parsed != null && unit.isNotEmpty && !checked)
          Text(
            '= ${SiFormat.format(parsed, unit, 4)}',
            style: context.text.bodyMedium?.copyWith(color: AppColors.greyDark),
          ),
        if (!checked) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip('±', _toggleSign),
              if (showPrefixes)
                for (final p in _prefixesFor(unit))
                  // Compound units (A·t/Wb, V/m...) get just the prefix letter.
                  _chip(unit.length <= 3 && !unit.contains('/') ? '$p$unit' : p, () => _insert(p)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            showPrefixes
                ? 'Tip: use prefixes like 4.7k, 2.5m or 10µ.'
                : 'Enter a number.',
            style: context.text.bodySmall?.copyWith(color: AppColors.greyDark),
          ),
        ],
      ],
    );
  }

  /// Prefixes that make sense for typical first-year values of [unit].
  static List<String> _prefixesFor(String unit) => switch (unit) {
        'Ω' => const ['m', 'k', 'M'],
        'V' => const ['µ', 'm', 'k'],
        'A' => const ['n', 'µ', 'm'],
        'W' => const ['µ', 'm', 'k', 'M'],
        'F' => const ['p', 'n', 'µ', 'm'],
        'H' => const ['n', 'µ', 'm'],
        'Hz' || 'rad/s' => const ['k', 'M', 'G'],
        'bps' || 'b/s' || 'B/s' || 'baud' || 'S/s' => const ['k', 'M', 'G'],
        's' => const ['n', 'µ', 'm'],
        'J' => const ['µ', 'm', 'k'],
        'C' => const ['p', 'n', 'µ', 'm'],
        'A·t/Wb' || 'A/Wb' || 'H⁻¹' => const ['k', 'M'],
        _ => const ['n', 'µ', 'm', 'k', 'M'],
      };

  Widget _chip(String label, VoidCallback onTap) => ActionChip(
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        onPressed: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: context.border, width: 2),
        ),
      );
}

// ---------------------------------------------------------------------------

class MatchPairsExercise extends StatefulWidget {
  const MatchPairsExercise({super.key, required this.instance, required this.controller});

  final StepInstance instance;
  final ExerciseController controller;

  @override
  State<MatchPairsExercise> createState() => _MatchPairsExerciseState();
}

class _MatchPairsExerciseState extends State<MatchPairsExercise> {
  late final List<(String, String)> _pairs = widget.instance.pairs;
  late final List<int> _leftOrder;
  late final List<int> _rightOrder;
  final Set<int> _matched = {};
  int? _left;
  int? _right;
  (int, int)? _wrong;
  int _mistakes = 0;

  @override
  void initState() {
    super.initState();
    final rnd = math.Random();
    _leftOrder = List.generate(_pairs.length, (i) => i)..shuffle(rnd);
    _rightOrder = List.generate(_pairs.length, (i) => i)..shuffle(rnd);
    widget.controller._register(() {
      widget.controller.correctAnswerText = null;
      widget.controller.answerText =
          _mistakes == 0 ? 'All pairs matched' : '$_mistakes wrong match${_mistakes == 1 ? '' : 'es'}';
      return _mistakes == 0;
    });
  }

  void _tryMatch() {
    if (_left == null || _right == null) return;
    if (_left == _right) {
      HapticFeedback.lightImpact();
      _matched.add(_left!);
      _left = null;
      _right = null;
      if (_matched.length == _pairs.length) widget.controller.setReady(true);
    } else {
      HapticFeedback.heavyImpact();
      _mistakes++;
      _wrong = (_left!, _right!);
      _left = null;
      _right = null;
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _wrong = null);
      });
    }
  }

  Widget _tile(int pairIndex, bool isLeft) {
    final text = isLeft ? _pairs[pairIndex].$1 : _pairs[pairIndex].$2;
    final matched = _matched.contains(pairIndex);
    final selected = isLeft ? _left == pairIndex : _right == pairIndex;
    final wrong = _wrong != null && (isLeft ? _wrong!.$1 == pairIndex : _wrong!.$2 == pairIndex);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: matched ? 0.45 : 1,
        child: OptionTile(
          dense: true,
          selected: selected,
          state: wrong ? false : (matched ? true : null),
          onTap: matched || widget.controller.checked
              ? null
              : () {
                  setState(() {
                    if (isLeft) {
                      _left = _left == pairIndex ? null : pairIndex;
                    } else {
                      _right = _right == pairIndex ? null : pairIndex;
                    }
                    _tryMatch();
                  });
                },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Center(
              child: RichContent(text,
                  textAlign: TextAlign.center,
                  style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Column(children: [for (final i in _leftOrder) _tile(i, true)])),
        const SizedBox(width: 12),
        Expanded(child: Column(children: [for (final i in _rightOrder) _tile(i, false)])),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class OrderStepsExercise extends StatefulWidget {
  const OrderStepsExercise({super.key, required this.instance, required this.controller});

  final StepInstance instance;
  final ExerciseController controller;

  @override
  State<OrderStepsExercise> createState() => _OrderStepsExerciseState();
}

class _OrderStepsExerciseState extends State<OrderStepsExercise> {
  late final List<String> _items = widget.instance.orderedItems;
  late final List<int> _bank;
  final List<int> _answer = [];

  @override
  void initState() {
    super.initState();
    final rnd = math.Random();
    _bank = List.generate(_items.length, (i) => i);
    // Make sure the shuffled order is not already correct.
    do {
      _bank.shuffle(rnd);
    } while (_items.length > 1 && _isSorted(_bank));
    widget.controller._register(() {
      widget.controller.correctAnswerText = [
        for (var i = 0; i < _items.length; i++) '${i + 1}. ${_items[i]}',
      ].join('\n');
      widget.controller.answerText = [
        for (var i = 0; i < _answer.length; i++) '${i + 1}. ${_items[_answer[i]]}',
      ].join('\n');
      return _isSorted(_answer) && _answer.length == _items.length;
    });
    widget.controller.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    super.dispose();
  }

  static bool _isSorted(List<int> l) {
    for (var i = 0; i < l.length; i++) {
      if (l[i] != i) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final checked = widget.controller.checked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          constraints: const BoxConstraints(minHeight: 80),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.border, width: 2),
          ),
          child: _answer.isEmpty
              ? Center(
                  child: Text('Tap the steps below in the right order',
                      style: context.text.bodyMedium?.copyWith(color: AppColors.greyDark)),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var pos = 0; pos < _answer.length; pos++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: OptionTile(
                          dense: true,
                          state: checked ? _answer[pos] == pos : null,
                          onTap: checked
                              ? null
                              : () {
                                  setState(() => _answer.removeAt(pos));
                                  widget.controller.setReady(false);
                                },
                          child: Row(
                            children: [
                              Text('${pos + 1}.',
                                  style: const TextStyle(fontWeight: FontWeight.w800)),
                              const SizedBox(width: 10),
                              Expanded(child: RichContent(_items[_answer[pos]])),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        for (final i in _bank)
          if (!_answer.contains(i))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OptionTile(
                dense: true,
                onTap: checked
                    ? null
                    : () {
                        setState(() => _answer.add(i));
                        widget.controller.setReady(_answer.length == _items.length);
                      },
                child: RichContent(_items[i]),
              ),
            ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

/// Tap elements in a schematic, e.g. "tap all resistors in parallel with R2".
class TapCircuitExercise extends StatefulWidget {
  const TapCircuitExercise({super.key, required this.instance, required this.controller});

  final StepInstance instance;
  final ExerciseController controller;

  @override
  State<TapCircuitExercise> createState() => _TapCircuitExerciseState();
}

class _TapCircuitExerciseState extends State<TapCircuitExercise> {
  final Set<String> _selected = {};
  late final Set<String> _answer = widget.instance.tapAnswer;
  late final Set<String> _selectable = widget.instance.tapSelectable;

  /// Display labels per element name (e.g. "R2" → "R_2").
  late final Map<String, String> _labels = {
    for (final e in widget.instance.circuit!.elements)
      if (e.name != null) e.name!: e.label ?? e.name!,
  };

  @override
  void initState() {
    super.initState();
    widget.controller._register(() {
      String list(Iterable<String> names) => names.isEmpty
          ? 'nothing'
          : (names.map((n) => '\$${_labels[n]}\$').toList()..sort()).join(', ');
      widget.controller.correctAnswerText = list(_answer);
      widget.controller.answerText = list(_selected);
      return _selected.length == _answer.length && _selected.containsAll(_answer);
    });
    widget.controller.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final checked = widget.controller.checked;
    final highlights = <String, Color>{};
    for (final n in _selectable) {
      if (checked) {
        if (_answer.contains(n)) {
          highlights[n] = _selected.contains(n) ? AppColors.green : AppColors.orange;
        } else if (_selected.contains(n)) {
          highlights[n] = AppColors.red;
        }
      } else if (_selected.contains(n)) {
        highlights[n] = AppColors.blue;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.border, width: 2),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: CircuitDiagram(
              widget.instance.circuit!,
              highlights: highlights,
              tappable: _selectable,
              onTapElement: checked
                  ? null
                  : (name) {
                      HapticFeedback.selectionClick();
                      setState(() => _selected.contains(name) ? _selected.remove(name) : _selected.add(name));
                      widget.controller.setReady(_selected.isNotEmpty);
                    },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          checked
              ? (_answer.length == _selected.length && _selected.containsAll(_answer)
                  ? 'All correct.'
                  : 'Green: right · Orange: missed · Red: should not be selected')
              : _selected.isEmpty
                  ? 'Tap the components in the schematic. Tap again to deselect.'
                  : 'Selected: ${(_selected.map((n) => _labels[n]!.replaceAll('_', '')).toList()..sort()).join(', ')}',
          style: context.text.bodySmall?.copyWith(color: AppColors.greyDark),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

/// Drag the slider(s) until the graph does what the prompt asks.
class SliderExercise extends StatefulWidget {
  const SliderExercise({super.key, required this.instance, required this.controller});

  final StepInstance instance;
  final ExerciseController controller;

  @override
  State<SliderExercise> createState() => _SliderExerciseState();
}

class _SliderExerciseState extends State<SliderExercise> {
  late final _values = ValueNotifier<Map<String, double>>({
    for (final s in widget.instance.spec.plot!.sliders) s.name: s.initial(widget.instance.vars),
  });

  @override
  void initState() {
    super.initState();
    widget.controller._register(() {
      final inst = widget.instance;
      widget.controller.correctAnswerText = inst.sliderAnswerText;
      widget.controller.answerText = [
        for (final s in inst.spec.plot!.sliders)
          '${s.label} = ${SiFormat.format(_values.value[s.name]!, s.unit, s.sig)}',
      ].join(', ');
      return inst.checkSliders(_values.value);
    });
    widget.controller.addListener(_rebuild);
    _values.addListener(() => widget.controller.setReady(true));
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    _values.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final checked = widget.controller.checked;
    return GraphView(
      spec: widget.instance.spec.plot!,
      vars: widget.instance.vars,
      values: _values,
      revealed: checked,
      enabled: !checked,
    );
  }
}
