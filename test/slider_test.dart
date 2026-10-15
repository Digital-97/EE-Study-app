import 'package:ee_study/engine/step_instance.dart';
import 'package:ee_study/lesson/exercises.dart';
import 'package:ee_study/models/content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

StepSpec _step() => StepSpec.fromJson({
  'id': 's1',
  'type': 'slider',
  'prompt': 'Set k to 3.',
  'plot': {
    'x': {'min': 0, 'max': 1},
    'y': {'min': 0, 'max': 10},
    'sliders': [
      {'name': 'k', 'label': 'k', 'min': 0, 'max': 10, 'step': 1, 'value': 8},
    ],
    'curves': [
      {'f': 'k*x'},
    ],
    'readouts': [
      {'label': 'Slope', 'value': 'k', 'reveal': true},
    ],
  },
  'answer': {'k': '3'},
  'explanation': 'k = 3.',
}, lessonId: 'test');

void main() {
  test('slider answers and readouts', () {
    final inst = StepInstance.create(_step());
    expect(inst.checkSliders({'k': 3}), isTrue);
    expect(inst.checkSliders({'k': 4}), isFalse);
    expect(inst.sliderAnswerText, 'k = 3');
    final plot = inst.spec.plot!;
    expect(plot.resolve({}, StepInstance.fill).readouts, isEmpty);
    expect(plot.resolve({'k': 5}, StepInstance.fill, revealed: true).readouts.single.$2, '5');
    final s = plot.sliders.single;
    expect(s.fromPosition(0.31, const {}), 3);
    expect(s.positions(const {}), hasLength(11));
  });

  testWidgets('dragging the slider answers the exercise', (tester) async {
    final inst = StepInstance.create(_step());
    final controller = ExerciseController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SliderExercise(instance: inst, controller: controller),
        ),
      ),
    );
    expect(controller.ready, isFalse);
    final slider = tester.getRect(find.byType(Slider));
    // Material sliders leave a 24 px gutter on each side of the track.
    final track = slider.width - 48;
    await tester.tapAt(Offset(slider.left + 24 + track * 0.3, slider.center.dy));
    await tester.pump();
    expect(controller.ready, isTrue);
    expect(controller.check(), isTrue);
    expect(controller.answerText, 'k = 3');
  });

  testWidgets('the +/- buttons move the slider one step', (tester) async {
    final inst = StepInstance.create(_step());
    final controller = ExerciseController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SliderExercise(instance: inst, controller: controller)),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byTooltip('Decrease'));
      await tester.pump();
    }
    expect(controller.check(), isTrue); // 8 - 5 = 3
  });

  test('angle answers accept equivalent angles', () {
    final inst = StepInstance.create(
      StepSpec.fromJson({
        'id': 'q',
        'type': 'numeric',
        'prompt': 'Angle?',
        'answer': '179.5',
        'unit': '°',
        'absTolerance': 1,
        'explanation': '.',
      }, lessonId: 'test'),
    );
    expect(inst.checkNumeric('-179.8'), isTrue);
    expect(inst.checkNumeric('539.5'), isTrue);
    expect(inst.checkNumeric('170'), isFalse);
  });
}
