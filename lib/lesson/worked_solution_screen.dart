import 'package:flutter/material.dart';

import '../engine/circuit_solver.dart';
import '../engine/units.dart';
import '../models/circuit.dart';
import '../ui/theme.dart';
import '../widgets/circuit_diagram.dart';
import '../widgets/rich_content.dart';

/// Full nodal-analysis solution of a solved (Circuit Lab) circuit: named
/// nodes, constraints, KCL equations, node voltages and every element's
/// voltage, current and power.
class WorkedSolutionScreen extends StatelessWidget {
  const WorkedSolutionScreen({super.key, required this.circuit, required this.report, this.question});

  final CircuitSpec circuit;
  final CircuitReport report;
  final String? question;

  static Future<void> open(
    BuildContext context, {
    required CircuitSpec circuit,
    required CircuitReport report,
    String? question,
  }) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => WorkedSolutionScreen(circuit: circuit, report: report, question: question),
      ));

  @override
  Widget build(BuildContext context) {
    final tagged = CircuitSpec(
      [
        ...circuit.elements,
        for (final n in report.nodes)
          if (!n.ground) CircuitElement(type: 'tag', at: n.at, label: n.name),
      ],
      height: circuit.height,
    );
    // Op-amp outputs deliver power too (drawn from their supplies).
    final sources = report.elements.where((e) => e.isSource || e.kind == 'opamp');
    final passives = report.elements.where((e) => !e.isSource && e.kind != 'opamp');
    final opamps = report.elements.any((e) => e.kind == 'opamp');
    final delivered = sources.fold<double>(0, (s, e) => s + e.power);
    final absorbed = passives.fold<double>(0, (s, e) => s + e.power);
    var step = 0;
    String next() => '${++step}';

    return Scaffold(
      appBar: AppBar(title: const Text('Worked solution')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          if (question != null) ...[
            RichContent(question!, style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: CircuitDiagram(tagged),
          ),
          if (report.ac)
            _Section(
              number: next(),
              title: 'Impedances',
              subtitle: 'In sinusoidal steady state every R, L and C becomes an impedance, and every '
                  'voltage and current a phasor (${report.rmsNote}).',
              child: Column(children: [
                if (report.omegaTex != null) DisplayMath(report.omegaTex!),
                for (final z in report.impedances) DisplayMath(z),
              ]),
            ),
          _Section(
            number: next(),
            title: 'Name the nodes',
            child: RichContent(
              'The reference node 0 (0 V) is the ground symbol, or the − side of the source when none is drawn. '
              'The other nodes are labelled ${report.nodes.where((n) => !n.ground).map((n) => '**${n.name}**').join(', ')} '
              'in the schematic; their ${report.ac ? 'phasor ' : ''}node voltages are the unknowns.',
            ),
          ),
          if (report.constraints.isNotEmpty)
            _Section(
              number: next(),
              title: 'Sources and op amps fix some voltages',
              child: Column(children: [for (final c in report.constraints) DisplayMath(c)]),
            ),
          if (report.equations.isNotEmpty)
            _Section(
              number: next(),
              title: 'Write KCL',
              subtitle: 'Sum of currents leaving the node = 0. A current source contributes '
                  '+I if its arrow points away from the node, −I if it points into it.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (where, eq) in report.equations) ...[
                    Text(where, style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                    DisplayMath(eq),
                  ],
                ],
              ),
            ),
          _Section(
            number: next(),
            title: 'Solve for the node voltages',
            child: Column(children: [
              for (final n in report.nodes.where((n) => !n.ground))
                _Row(
                  label: '${report.ac ? r'\mathbf{V}' : 'v'}_{\\text{${n.name.replaceAll('_', r'\_')}}}',
                  value: report.quantity(n.phasor, 'V', 4),
                ),
            ]),
          ),
          if (report.elements.isNotEmpty)
            _Section(
              number: next(),
              title: 'Every element',
              subtitle: 'Voltage across (from the first to the second terminal), current through, '
                  'and ${report.ac ? 'average ' : ''}power absorbed (delivered for sources).',
              child: _ElementTable(report: report),
            ),
          if (sources.isNotEmpty && passives.isNotEmpty)
            _Section(
              number: next(),
              title: 'Check: power balance',
              child: RichContent(
                '${report.ac ? 'On average, s' : 'S'}ources${opamps ? ' and op-amp outputs' : ''} deliver ${SiFormat.format(delivered, 'W')}; the other elements absorb '
                '${SiFormat.format(absorbed, 'W')}. '
                '${(delivered - absorbed).abs() <= 1e-6 + 1e-3 * absorbed.abs() ? 'They match ✓' : ''}',
              ),
            ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.number, required this.title, required this.child, this.subtitle});

  final String number;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.border, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            CircleAvatar(
              radius: 12,
              backgroundColor: AppColors.blue,
              child: Text(number,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ),
          ]),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!, style: context.text.bodySmall?.copyWith(color: AppColors.greyDark)),
          ],
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  /// LaTeX symbol, e.g. v_{\text{A}}.
  final String label;

  /// Value text (may contain inline math).
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: RichContent('\$$label\$')),
        Flexible(
          child: RichContent(value,
              textAlign: TextAlign.end, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }
}

class _ElementTable extends StatelessWidget {
  const _ElementTable({required this.report});

  final CircuitReport report;

  @override
  Widget build(BuildContext context) {
    final elements = report.elements;
    final head = context.text.labelMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.greyDark);
    final cell = context.text.bodyMedium;
    TableRow row(List<String> cells, TextStyle? style) => TableRow(children: [
          for (final c in cells)
            Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: RichContent(c, style: style)),
        ]);
    if (report.ac) {
      // Phasors are too wide for table columns on a phone: one block per element.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final e in elements)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 52,
                  child: Text(e.name, style: cell?.copyWith(fontWeight: FontWeight.w800)),
                ),
                Expanded(
                  child: Wrap(spacing: 14, runSpacing: 2, children: [
                    RichContent('V = ${report.quantity(e.v, 'V')}', style: cell),
                    if (!e.current.isNaN) RichContent('I = ${report.quantity(e.i, 'A')}', style: cell),
                    if (!e.power.isNaN) RichContent('P = ${SiFormat.format(e.power, 'W')}', style: cell),
                  ]),
                ),
              ]),
            ),
        ],
      );
    }
    return Table(
      columnWidths: const {0: FlexColumnWidth(1.1), 1: FlexColumnWidth(1.3), 2: FlexColumnWidth(1.3), 3: FlexColumnWidth(1.3)},
      children: [
        row(['', 'V', 'I', 'P'], head),
        for (final e in elements)
          row([
            e.name,
            report.quantity(e.v, 'V'),
            e.current.isNaN ? '–' : report.quantity(e.i, 'A'),
            e.power.isNaN ? '–' : SiFormat.format(e.power, 'W'),
          ], cell),
      ],
    );
  }
}
