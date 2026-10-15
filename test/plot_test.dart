import 'package:ee_study/engine/step_instance.dart';
import 'package:ee_study/models/plot.dart';
import 'package:ee_study/widgets/plot_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Map<String, dynamic> spec) async {
  final plot = PlotSpec.fromJson(spec).resolve(const {}, StepInstance.fill, revealed: true);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 360, child: PlotView(plot)))));
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('log axes beyond 1e18 draw (no integer overflow)', (tester) async {
    await _pump(tester, {
      'x': {'min': 1e14, 'max': 1e20, 'log': true, 'label': 'N'},
      'y': {'min': 1, 'max': 1e21, 'log': true},
      'curves': [
        {'f': 'x'},
      ],
    });
  });

  testWidgets('Smith charts, parametric curves and equal axes draw', (tester) async {
    await _pump(tester, {
      'smith': true,
      'curves': [
        {'x': '0.5*cos(t)', 'y': '0.5*sin(t)', 't': [0, '2*pi']},
      ],
      'points': [
        {'x': 0.2, 'y': 0.4, 'label': 'z_L'},
      ],
    });
    await _pump(tester, {
      'equal': true,
      'x': {'min': -1.5, 'max': 1.5},
      'y': {'min': -1.2, 'max': 1.2},
      'curves': [
        {'x': 'cos(t)', 'y': 'sin(t)', 't': [0, '2*pi'], 'label': 'unit circle'},
      ],
    });
  });

  test('parametric curves sample over t', () {
    final plot = PlotSpec.fromJson({
      'x': {'min': -1, 'max': 1},
      'y': {'min': -1, 'max': 1},
      'curves': [
        {'x': 'cos(t)', 'y': 'sin(t)', 't': [0, 'pi']},
      ],
    }).resolve(const {}, StepInstance.fill);
    final pts = plot.curves.single.sample(plot.x, 2);
    expect(pts.first.$1, closeTo(1, 1e-12));
    expect(pts[1].$2, closeTo(1, 1e-12));
    expect(pts.last.$1, closeTo(-1, 1e-12));
  });
}
