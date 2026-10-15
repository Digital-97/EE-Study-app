import 'dart:convert';
import 'dart:io';

import 'package:ee_study/engine/circuit_solver.dart';
import 'package:ee_study/engine/expression.dart';
import 'package:ee_study/models/circuit.dart';
import 'package:flutter_test/flutter_test.dart';

CircuitSpec c(List<Map<String, dynamic>> els) => CircuitSpec.fromJson({'elements': els});

void main() {
  test('voltage divider', () {
    final r = CircuitSolver.solve(
        c([
          {'type': 'vsource', 'name': 'Vs', 'val': '12', 'from': [0, 2], 'to': [0, 0]},
          {'type': 'wire', 'points': [[0, 0], [2, 0]]},
          {'type': 'resistor', 'name': 'R1', 'val': '1000', 'from': [2, 0], 'to': [2, 1]},
          {'type': 'resistor', 'name': 'R2', 'val': '2000', 'from': [2, 1], 'to': [2, 2]},
          {'type': 'wire', 'points': [[2, 2], [0, 2]]},
          {'type': 'ground', 'at': [0, 2]},
          {'type': 'node', 'at': [2, 1], 'label': 'x'},
        ]),
        {});
    expect(r['V_R2'], closeTo(8, 1e-6));
    expect(r['V_R1'], closeTo(4, 1e-6));
    expect(r['I_R1'], closeTo(0.004, 1e-9));
    expect(r['v_x'], closeTo(8, 1e-6));
    expect(r['I_Vs'], closeTo(0.004, 1e-9)); // delivered
    expect(r['P_Vs'], closeTo(0.048, 1e-9));
    expect(r['P_R1']! + r['P_R2']!, closeTo(r["P_Vs"]!, 1e-9));
  });

  test('T-junction on a wire and equivalent resistance', () {
    // a ── R1 ──┬── R3 ── b ; R2 from the middle (on a wire) down to b's wire.
    final r = CircuitSolver.solve(
        c([
          {'type': 'terminal', 'at': [0, 0], 'label': 'a'},
          {'type': 'resistor', 'name': 'R1', 'val': 'R1', 'from': [0, 0], 'to': [2, 0]},
          {'type': 'wire', 'points': [[2, 0], [4, 0]]},
          {'type': 'resistor', 'name': 'R2', 'val': '600', 'from': [3, 0], 'to': [3, 2]},
          {'type': 'resistor', 'name': 'R3', 'val': '300', 'from': [4, 0], 'to': [4, 2]},
          {'type': 'wire', 'points': [[0, 2], [4, 2]]},
          {'type': 'terminal', 'at': [0, 2], 'label': 'b'},
        ]),
        {'R1': 100});
    expect(r['Req'], closeTo(100 + 200, 1e-6));
    expect(r['R_a_b'], closeTo(300, 1e-6));
  });

  test('thevenin with current source', () {
    // 2 mA source in parallel with 1k, series 1k to terminal a.
    final r = CircuitSolver.solve(
        c([
          {'type': 'isource', 'name': 'Is', 'val': '0.002', 'from': [0, 2], 'to': [0, 0]},
          {'type': 'wire', 'points': [[0, 0], [2, 0]]},
          {'type': 'resistor', 'name': 'R1', 'val': '1000', 'from': [2, 0], 'to': [2, 2]},
          {'type': 'resistor', 'name': 'R2', 'val': '1000', 'from': [2, 0], 'to': [4, 0]},
          {'type': 'terminal', 'at': [4, 0], 'label': 'a'},
          {'type': 'wire', 'points': [[0, 2], [4, 2]]},
          {'type': 'terminal', 'at': [4, 2], 'label': 'b'},
        ]),
        {});
    expect(r['Voc'], closeTo(2, 1e-6));
    expect(r['Req'], closeTo(2000, 1e-3));
    expect(r['Isc'], closeTo(0.001, 1e-9));
    expect(r['V_Is'], closeTo(2, 1e-6));
  });

  test('inverting op amp', () {
    final r = CircuitSolver.solve(
        c([
          {'type': 'vsource', 'name': 'Vin', 'val': '1', 'from': [-2, 2], 'to': [-2, 0.5]},
          {'type': 'resistor', 'name': 'R1', 'val': '1000', 'from': [-2, 0.5], 'to': [1, 0.5]},
          {'type': 'opamp', 'name': 'U1', 'at': [2, 1]},
          {'type': 'wire', 'points': [[1, 0.5], [1, -0.5]]},
          {'type': 'resistor', 'name': 'R2', 'val': '4000', 'from': [1, -0.5], 'to': [3, -0.5]},
          {'type': 'wire', 'points': [[3, -0.5], [3, 1]]},
          {'type': 'wire', 'points': [[1, 1.5], [1, 2]]},
          {'type': 'wire', 'points': [[-2, 2], [1, 2]]},
          {'type': 'ground', 'at': [1, 2]},
          {'type': 'terminal', 'at': [3, 1], 'label': 'out'},
        ]),
        {});
    expect(r['v_out'], closeTo(-4, 1e-6));
    // Output current: through R2 (−4 V − 0)/4k = −1 mA flows from out back to
    // the inverting node, so the output pin sources −1 mA.
    expect(r['I_U1'], closeTo(-0.001, 1e-9));
  });

  test('dependent source (CCVS) and DC steady state', () {
    // 10 V source, R1 = 1k, then CCVS 500·I(R1) in series, inductor short, cap open.
    final r = CircuitSolver.solve(
        c([
          {'type': 'vsource', 'name': 'Vs', 'val': '10', 'from': [0, 2], 'to': [0, 0]},
          {'type': 'resistor', 'name': 'R1', 'val': '1000', 'from': [0, 0], 'to': [2, 0]},
          {'type': 'inductor', 'name': 'L', 'from': [2, 0], 'to': [4, 0]},
          {'type': 'cvsource', 'name': 'E', 'val': '500', 'ctrl': 'I(R1)', 'from': [4, 2], 'to': [4, 0]},
          {'type': 'capacitor', 'name': 'C', 'from': [2, 0], 'to': [2, 2]},
          {'type': 'wire', 'points': [[0, 2], [4, 2]]},
          {'type': 'ground', 'at': [0, 2]},
        ]),
        {});
    // 10 = 1000 i + 500 i → i = 1/150 A.
    expect(r['I_R1'], closeTo(1 / 150, 1e-9));
    expect(r['I_L'], closeTo(1 / 150, 1e-9));
    expect(r['V_C'], closeTo(500 / 150, 1e-6));
  });

  test('named CCCS reports its current', () {
    // 1 mA source into R1 (1k); CCCS 2·I(R1) from ground into node y with R2.
    final r = CircuitSolver.solve(
        c([
          {'type': 'isource', 'name': 'Is', 'val': '0.001', 'from': [0, 2], 'to': [0, 0]},
          {'type': 'resistor', 'name': 'R1', 'val': '1000', 'from': [0, 0], 'to': [0, 2], 'flip': true},
          {'type': 'ccsource', 'name': 'F', 'val': '2', 'ctrl': 'I(R1)', 'from': [3, 2], 'to': [3, 0]},
          {'type': 'resistor', 'name': 'R2', 'val': '500', 'from': [3, 0], 'to': [3, 2]},
          {'type': 'wire', 'points': [[0, 2], [3, 2]]},
          {'type': 'ground', 'at': [0, 2]},
        ]),
        {});
    expect(r['I_R1'], closeTo(0.001, 1e-9));
    expect(r['I_F'], closeTo(0.002, 1e-9));
    expect(r['V_R2'], closeTo(1, 1e-6));
  });

  test('worked solution matches the solver for all Circuit Lab content', () async {
    // Every solved circuit in the content: report node voltages must agree
    // with the solver and each KCL equation must hold.
    final files = Directory('assets/content').listSync(recursive: true).whereType<File>()
        .where((f) => f.path.endsWith('.json'));
    var checked = 0;
    for (final f in files) {
      void walk(dynamic o) {
        if (o is Map) {
          if (o['circuit'] is Map && (o['circuit']['elements'] as List).any((e) => e['val'] != null)) {
            final spec = CircuitSpec.fromJson(o['circuit'] as Map<String, dynamic>);
            final params = (o['params'] as Map?) ?? {};
            final vars = <String, double>{};
            params.forEach((k, v) {
              final first = v is List ? v.first : (v is Map ? (v['values']?.first ?? v['min']) : v);
              vars[k as String] = (first as num).toDouble();
            });
            (o['derived'] as Map? ?? {}).forEach((k, v) {
              vars[k as String] = Expression.eval(v as String, vars);
            });
            final report = CircuitSolver.report(spec, vars);
            expect(report.nodes.where((n) => n.ground), hasLength(1), reason: f.path);
            checked++;
          }
          o.values.forEach(walk);
        } else if (o is List) {
          o.forEach(walk);
        }
      }
      walk(jsonDecode(f.readAsStringSync()));
    }
    expect(checked, greaterThan(50));
  });

  test('worked solution equations', () {
    final r = CircuitSolver.report(
        c([
          {'type': 'vsource', 'name': 'Vs', 'val': '12', 'from': [0, 2], 'to': [0, 0]},
          {'type': 'resistor', 'name': 'R1', 'val': '1000', 'from': [0, 0], 'to': [2, 0]},
          {'type': 'resistor', 'name': 'R2', 'val': '2200', 'from': [2, 0], 'to': [2, 2]},
          {'type': 'wire', 'points': [[2, 0], [4, 0]]},
          {'type': 'isource', 'name': 'Is', 'val': '0.002', 'from': [4, 2], 'to': [4, 0]},
          {'type': 'wire', 'points': [[0, 2], [4, 2]]},
          {'type': 'ground', 'at': [0, 2]},
        ]),
        {});
    expect(r.nodes.map((n) => n.name), ['0', 'A', 'B']);
    expect(r.constraints, [r'v_A = 12\,\mathrm{V}']);
    expect(r.equations.single.$2,
        r'\frac{v_B - v_A}{1\,\mathrm{k\Omega}} + \frac{v_B}{2.2\,\mathrm{k\Omega}} - 2\,\mathrm{mA} = 0');
    expect(r.nodes.last.voltage, closeTo(9.625, 1e-6));
    final pDelivered = r.elements.where((e) => e.isSource).fold<double>(0, (s, e) => s + e.power);
    final pAbsorbed = r.elements.where((e) => !e.isSource).fold<double>(0, (s, e) => s + e.power);
    expect(pDelivered, closeTo(pAbsorbed, 1e-9));
  });

  test('unsupported element throws', () {
    expect(
        () => CircuitSolver.solve(
            c([
              {'type': 'vsource', 'val': '1', 'from': [0, 1], 'to': [0, 0]},
              {'type': 'diode', 'from': [0, 0], 'to': [0, 1]},
            ]),
            {}),
        throwsA(isA<CircuitException>()));
  });

  test('AC series RLC (phasors, peak)', () {
    final r = CircuitSolver.solve(
        CircuitSpec.fromJson({
          'ac': {'f': 'f'},
          'elements': [
            {'type': 'acsource', 'name': 'Vs', 'val': '10', 'from': [0, 2], 'to': [0, 0]},
            {'type': 'resistor', 'name': 'R1', 'val': '100', 'from': [0, 0], 'to': [2, 0]},
            {'type': 'inductor', 'name': 'L1', 'val': '0.1', 'from': [2, 0], 'to': [4, 0]},
            {'type': 'capacitor', 'name': 'C1', 'val': '10e-6', 'from': [4, 0], 'to': [4, 2]},
            {'type': 'wire', 'points': [[4, 2], [0, 2]]},
            {'type': 'ground', 'at': [0, 2]},
          ],
        }),
        {'f': 50});
    expect(r['I_Vs'], closeTo(0.0329139, 1e-6));
    expect(r['I_Vs_ph'], closeTo(70.7834, 1e-3));
    expect(r['V_C1'], closeTo(10.47684, 1e-4));
    expect(r['V_C1_ph'], closeTo(-19.2166, 1e-3));
    expect(r['P_R1'], closeTo(0.0541664, 1e-6));
    expect(r['P_Vs'], closeTo(0.0541664, 1e-6));
    expect(r['Q_Vs'], closeTo(-0.1554001, 1e-6));
    expect(r['P_L1'], closeTo(0, 1e-9));
    expect(r['Z_L1'], closeTo(2 * 3.141592653589793 * 50 * 0.1, 1e-9));
    expect(r['Z_L1_ph'], closeTo(90, 1e-9));
    expect(r['Z_C1_ph'], closeTo(-90, 1e-9));
    expect(r['pf_Vs'], closeTo(0.3291, 1e-3));

    // The same circuit as rms phasors: power doubles.
    final rms = CircuitSolver.solve(
        CircuitSpec.fromJson({
          'ac': {'omega': '2*pi*50', 'rms': true},
          'elements': [
            {'type': 'vsource', 'name': 'Vs', 'val': '10', 'from': [0, 2], 'to': [0, 0]},
            {'type': 'resistor', 'name': 'R1', 'val': '100', 'from': [0, 0], 'to': [2, 0]},
            {'type': 'inductor', 'name': 'L1', 'val': '0.1', 'from': [2, 0], 'to': [4, 0]},
            {'type': 'capacitor', 'name': 'C1', 'val': '10e-6', 'from': [4, 0], 'to': [4, 2]},
            {'type': 'wire', 'points': [[4, 2], [0, 2]]},
          ],
        }),
        {});
    expect(rms['P_R1'], closeTo(2 * 0.0541664, 1e-6));
  });

  test('AC Thevenin equivalent', () {
    final r = CircuitSolver.solve(
        CircuitSpec.fromJson({
          'ac': {'omega': '1000'},
          'elements': [
            {'type': 'acsource', 'name': 'Vs', 'val': '10', 'phase': '30', 'from': [0, 2], 'to': [0, 0]},
            {'type': 'resistor', 'name': 'R1', 'val': '50', 'from': [0, 0], 'to': [2, 0]},
            {'type': 'capacitor', 'name': 'C1', 'val': '20e-6', 'from': [2, 0], 'to': [2, 2]},
            {'type': 'wire', 'points': [[0, 2], [4, 2]]},
            {'type': 'wire', 'points': [[2, 0], [4, 0]]},
            {'type': 'terminal', 'at': [4, 0], 'label': 'a'},
            {'type': 'terminal', 'at': [4, 2], 'label': 'b'},
          ],
        }),
        {});
    expect(r['Voc'], closeTo(7.0710678, 1e-6));
    expect(r['Voc_ph'], closeTo(-15, 1e-6));
    expect(r['Zeq_re'], closeTo(25, 1e-6));
    expect(r['Zeq_im'], closeTo(-25, 1e-6));
    expect(r['Zeq'], closeTo(35.355339, 1e-5));
    expect(r['Zeq_ph'], closeTo(-45, 1e-6));
    expect(r['Isc'], closeTo(0.2, 1e-9));
    expect(r['Isc_ph'], closeTo(30, 1e-6));

    final report = CircuitSolver.report(
        CircuitSpec.fromJson({
          'ac': {'omega': '1000'},
          'elements': [
            {'type': 'acsource', 'name': 'Vs', 'val': '10', 'phase': '30', 'from': [0, 2], 'to': [0, 0]},
            {'type': 'resistor', 'name': 'R1', 'val': '50', 'from': [0, 0], 'to': [2, 0]},
            {'type': 'capacitor', 'name': 'C1', 'val': '20e-6', 'from': [2, 0], 'to': [2, 2]},
            {'type': 'wire', 'points': [[0, 2], [2, 2]]},
          ],
        }),
        {});
    expect(report.ac, isTrue);
    expect(report.impedances, hasLength(2));
    expect(report.impedances.last, contains('-j50'));
    final delivered = report.elements.where((e) => e.isSource).fold<double>(0, (s, e) => s + e.power);
    final absorbed = report.elements.where((e) => !e.isSource).fold<double>(0, (s, e) => s + e.power);
    expect(delivered, closeTo(absorbed, 1e-9));
  });
}
