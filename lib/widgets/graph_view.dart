import 'package:flutter/material.dart';

import '../engine/step_instance.dart';
import '../engine/units.dart';
import '../models/plot.dart';
import '../ui/theme.dart';
import 'plot_view.dart';
import 'rich_content.dart';

/// Draws a [PlotSpec]. Plots with sliders become interactive: dragging a
/// slider redraws the graph and its readouts live.
class GraphView extends StatefulWidget {
  const GraphView({
    super.key,
    required this.spec,
    this.vars = const {},
    this.values,
    this.revealed = false,
    this.enabled = true,
  });

  final PlotSpec spec;

  /// The step's variables (random parameters etc.).
  final Map<String, double> vars;

  /// Slider values, shared with a slider exercise. Created internally when
  /// null.
  final ValueNotifier<Map<String, double>>? values;

  /// Show items marked `"reveal": true` (after a slider exercise is checked).
  final bool revealed;

  /// Whether the sliders can be dragged.
  final bool enabled;

  @override
  State<GraphView> createState() => _GraphViewState();
}

class _GraphViewState extends State<GraphView> {
  late ValueNotifier<Map<String, double>> _values;
  bool _ownsValues = false;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    _ownsValues = widget.values == null;
    _values = widget.values ?? ValueNotifier({for (final s in widget.spec.sliders) s.name: s.initial(widget.vars)});
    _values.addListener(_changed);
  }

  void _detach() {
    _values.removeListener(_changed);
    if (_ownsValues) _values.dispose();
  }

  @override
  void didUpdateWidget(GraphView old) {
    super.didUpdateWidget(old);
    if (old.values != widget.values || old.spec != widget.spec) {
      _detach();
      _attach();
    }
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plot = widget.spec.resolve({...widget.vars, ..._values.value}, StepInstance.fill, revealed: widget.revealed);
    if (!widget.spec.interactive) return PlotView(plot);
    final all = widget.spec.withSliders({...widget.vars, ..._values.value});
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlotView(plot),
        if (plot.readouts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final (label, value) in plot.readouts)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.blue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text.rich(TextSpan(children: inlineSpans('$label = **$value**', context.text.bodyMedium!))),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        for (final s in widget.spec.sliders) _slider(context, s, all),
      ],
    );
  }

  Widget _slider(BuildContext context, SliderSpec s, Map<String, double> all) {
    final value = _values.value[s.name] ?? s.initial(widget.vars);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded, size: 18, color: widget.enabled ? AppColors.blue : AppColors.greyDark),
              const SizedBox(width: 6),
              Expanded(
                child: RichContent(
                  '${s.label} = **${SiFormat.format(value, s.unit, s.sig)}**',
                  style: context.text.bodyMedium,
                ),
              ),
            ],
          ),
          Row(
            children: [
              _nudge(s, all, -1, Icons.remove_rounded),
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(tickMarkShape: SliderTickMarkShape.noTickMark),
                    child: Slider(
                      value: s.toPosition(value, all),
                      divisions: s.divisions(widget.vars),
                      activeColor: AppColors.blue,
                      onChanged: widget.enabled
                          ? (t) {
                              final v = s.fromPosition(t, widget.vars);
                              if (v != _values.value[s.name]) {
                                _values.value = {..._values.value, s.name: v};
                              }
                            }
                          : null,
                    ),
                  ),
                ),
              ),
              _nudge(s, all, 1, Icons.add_rounded),
            ],
          ),
        ],
      ),
    );
  }

  /// A small −/+ button that moves the slider one position, for settings
  /// that are hard to hit by dragging on a phone.
  Widget _nudge(SliderSpec s, Map<String, double> all, int direction, IconData icon) {
    void step() {
      final current = _values.value[s.name] ?? s.initial(widget.vars);
      final n = s.divisions(widget.vars) ?? 400;
      final p0 = s.toPosition(current, all);
      // Move by one position; on a log slider rounding can repeat a value,
      // so keep going until it changes.
      for (var k = 1; k <= n; k++) {
        final t = (p0 + direction * k / n).clamp(0.0, 1.0);
        final v = s.fromPosition(t, widget.vars);
        if (v != current) {
          _values.value = {..._values.value, s.name: v};
          return;
        }
        if (t == 0 || t == 1) return;
      }
    }

    return SizedBox(
      width: 34,
      height: 34,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 20,
        color: AppColors.blue,
        tooltip: direction < 0 ? 'Decrease' : 'Increase',
        onPressed: widget.enabled ? step : null,
        icon: Icon(icon),
      ),
    );
  }
}
