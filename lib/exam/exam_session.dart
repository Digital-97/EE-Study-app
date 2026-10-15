import 'dart:math' as math;

import '../content/content_repository.dart';
import '../engine/step_instance.dart';
import '../models/content.dart';

/// One question in an exam, with the student's result once answered.
class ExamQuestion {
  ExamQuestion(this.instance, this.unit);

  final StepInstance instance;
  final Unit unit;

  /// null while unanswered.
  bool? correct;
  String? answer;
  String? correctAnswer;

  bool get answered => correct != null;
}

/// A mock exam: random questions from the chosen subjects, answered without
/// feedback, optionally against the clock.
class ExamSession {
  ExamSession({required this.title, required this.questions, this.timeLimit});

  final String title;
  final List<ExamQuestion> questions;
  final Duration? timeLimit;
  final DateTime started = DateTime.now();

  int get correctCount => questions.where((q) => q.correct == true).length;

  /// Questions per unit, in the order units first appear.
  Map<Unit, List<ExamQuestion>> get byUnit {
    final out = <Unit, List<ExamQuestion>>{};
    for (final q in questions) {
      out.putIfAbsent(q.unit, () => []).add(q);
    }
    return out;
  }

  /// Seconds allowed per question in timed mode.
  static const secondsPerQuestion = 90;

  /// Builds an exam of [count] questions spread over the units of [subjects].
  static ExamSession? create(
    ContentRepository repo,
    List<Subject> subjects, {
    required int count,
    required bool timed,
    math.Random? random,
  }) {
    final rnd = random ?? math.Random();
    // Group questions by unit and draw round-robin, so every unit is covered
    // before any unit gets a second question.
    final pools = <(Unit, List<StepSpec>)>[];
    for (final s in subjects) {
      for (final u in s.units) {
        final steps = [
          for (final l in u.lessons)
            for (final st in l.steps)
              if (st.isQuestion) st,
        ]..shuffle(rnd);
        if (steps.isNotEmpty) pools.add((u, steps));
      }
    }
    if (pools.isEmpty) return null;
    pools.shuffle(rnd);
    final picked = <ExamQuestion>[];
    var round = 0;
    while (picked.length < count) {
      var added = false;
      for (final (unit, steps) in pools) {
        if (picked.length >= count) break;
        if (round < steps.length) {
          picked.add(ExamQuestion(StepInstance.create(steps[round], rnd), unit));
          added = true;
        }
      }
      if (!added) break;
      round++;
    }
    picked.shuffle(rnd);
    final title = subjects.length == 1 ? '${subjects.first.title} exam' : 'Mixed exam';
    return ExamSession(
      title: title,
      questions: picked,
      timeLimit: timed ? Duration(seconds: secondsPerQuestion * picked.length) : null,
    );
  }
}
