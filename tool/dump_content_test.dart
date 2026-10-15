// Writes every lesson step, with one random draw resolved, to a readable text
// file per subject, for reviewing content correctness.
//
//   CONTENT_SUBJECT=circuit-theory DUMP_OUT=build/dump flutter test tool/dump_content_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:ee_study/content/content_repository.dart';
import 'package:ee_study/engine/step_instance.dart';
import 'package:ee_study/models/content.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dump content', () async {
    final index = jsonDecode(File('assets/content/index.json').readAsStringSync())
        as Map<String, dynamic>;
    final repo = await ContentRepository.fromJson(
      index,
      skipUnitError: (e) => e is FileSystemException,
      includeDrafts: true,
      (f) async => jsonDecode(File('assets/content/$f').readAsStringSync()),
    );
    final only = Platform.environment['CONTENT_SUBJECT'];
    final out = Directory(Platform.environment['DUMP_OUT'] ?? 'build/dump')
      ..createSync(recursive: true);
    final rnd = math.Random(3);
    for (final subject in repo.subjects.values) {
      if (only != null && subject.id != only) continue;
      final b = StringBuffer('# ${subject.title}\n');
      for (final unit in subject.units) {
        b.writeln('\n## ${unit.id}: ${unit.title} (${unit.reference})');
        for (final c in unit.study) {
          b.writeln('\n[study] ${c.title}\n${c.body}');
          if (c.formula != null) b.writeln('FORMULA: ${c.formula}');
        }
        for (final lesson in unit.lessons) {
          b.writeln('\n### ${lesson.id} (${lesson.kind.name}): ${lesson.title}');
          for (final step in lesson.steps) {
            final ask = (step.raw['ask'] as List?)?.length ?? 1;
            for (var t = 0; t < ask; t++) {
              final i = StepInstance.create(step, rnd, step.raw['ask'] == null ? null : t);
              b.writeln('\n--- ${step.key} [${step.type.name}]${ask > 1 ? ' variant ${t + 1}/$ask' : ''}');
              if (i.vars.isNotEmpty) {
                b.writeln('VARS: ${i.vars.entries.where((e) => !e.key.startsWith('P_')).map((e) => '${e.key}=${e.value.toStringAsPrecision(4)}').join(', ')}');
              }
              switch (step.type) {
                case StepType.info:
                  b.writeln('TITLE: ${i.title}\n${i.body}');
                  if (i.formula != null) b.writeln('FORMULA: ${i.formula}');
                case StepType.multipleChoice:
                  b.writeln('Q: ${i.prompt}');
                  if (i.optionPlots != null) b.writeln('  (options are graphs; see JSON optionPlots)');
                  for (var k = 0; k < i.options.length; k++) {
                    b.writeln('  ${k == i.correctOptionIndex ? '[x]' : '[ ]'} ${i.options[k]}');
                  }
                case StepType.trueFalse:
                  b.writeln('Q: ${i.prompt}\nANSWER: ${i.trueFalseAnswer}');
                case StepType.numeric:
                  b.writeln('Q: ${i.prompt}\nANSWER: ${i.formattedAnswer} (${i.numericAnswer}, tol ${i.tolerance})');
                case StepType.matchPairs:
                  b.writeln('Q: ${i.prompt}');
                  for (final p in i.pairs) {
                    b.writeln('  ${p.$1}  <->  ${p.$2}');
                  }
                case StepType.tapCircuit:
                  b.writeln('Q: ${i.prompt}\nANSWER (tap): ${i.tapAnswer.join(', ')} of ${i.tapSelectable.join(', ')}');
                case StepType.slider:
                  final sl = i.spec.plot!.sliders;
                  b.writeln('Q: ${i.prompt}');
                  for (final s in sl) {
                    b.writeln('  SLIDER ${s.name} (${s.label}): ${s.minValue(i.vars)}..${s.maxValue(i.vars)} start ${s.initial(i.vars)}');
                  }
                  final ans = i.sliderAnswerText;
                  b.writeln('ANSWER: ${ans ?? 'check: ${i.spec.raw['check']}'}');
                  if (sl.length == 1) {
                    final ok = sl.first.positions(i.vars).where((v) => i.checkSliders({sl.first.name: v})).toList();
                    b.writeln(ok.isEmpty ? '  (NO passing position!)' : '  passes for ${ok.first}..${ok.last}');
                  }
                case StepType.orderSteps:
                  b.writeln('Q: ${i.prompt}');
                  for (final (k, it) in i.orderedItems.indexed) {
                    b.writeln('  ${k + 1}. $it');
                  }
              }
              if (i.circuit != null) {
                final els = i.circuit!.elements
                    .where((e) => e.type != 'wire' && (e.label != null || e.value != null))
                    .map((e) => '${e.type}(${[e.label, e.value].whereType<String>().join(' ')})');
                b.writeln('CIRCUIT: ${els.join(', ')}');
              }
              if (i.explanation != null) b.writeln('EXPLANATION: ${i.explanation}');
            }
          }
        }
      }
      File('${out.path}/${subject.id}.txt').writeAsStringSync(b.toString());
    }
  });
}
