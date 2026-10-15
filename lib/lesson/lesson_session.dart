import 'dart:collection';
import 'dart:math' as math;

import '../content/content_repository.dart';
import '../engine/step_instance.dart';
import '../models/content.dart';
import '../state/progress_store.dart';

enum SessionKind { lesson, review, practice }

/// The state of a running lesson: a queue of steps where wrongly answered
/// questions are re-queued (with fresh random values) until answered right.
class LessonSession {
  LessonSession({
    required this.kind,
    required this.title,
    required List<StepSpec> steps,
    this.lesson,
    math.Random? random,
  })  : _random = random ?? math.Random(),
        totalQuestions = steps.where((s) => s.isQuestion).length {
    for (final s in steps) {
      _queue.add(StepInstance.create(s, _random));
    }
  }

  final SessionKind kind;
  final String title;
  final Lesson? lesson;
  final math.Random _random;
  final Queue<StepInstance> _queue = Queue();
  final Set<String> _missed = {};
  final DateTime started = DateTime.now();

  final int totalQuestions;
  int _done = 0;
  int _firstTryCorrect = 0;
  final Set<String> _answeredOnce = {};

  StepInstance? get current => _queue.isEmpty ? null : _queue.first;
  bool get finished => _queue.isEmpty;

  /// Progress through the session (0..1), only advances on completed steps.
  double get progress {
    final total = _done + _queue.length;
    return total == 0 ? 1 : _done / total;
  }

  /// First-try accuracy over all questions.
  double get accuracy => totalQuestions == 0 ? 1 : _firstTryCorrect / totalQuestions;
  int get firstTryCorrect => _firstTryCorrect;
  int get mistakes => _missed.length;

  bool isFirstTry(StepInstance s) => !_answeredOnce.contains(s.spec.key);

  /// Records the answer for the current step and advances the queue.
  /// Returns whether this was the first attempt at this question.
  bool answer(bool correct, ProgressStore store) {
    final step = _queue.removeFirst();
    final first = isFirstTry(step);
    _answeredOnce.add(step.spec.key);
    store.recordAnswer(step.spec.key, correct: correct, firstTry: first);
    if (correct) {
      if (first) _firstTryCorrect++;
      _done++;
    } else {
      _missed.add(step.spec.key);
      // Try again later in the lesson, with new numbers.
      _queue.addLast(StepInstance.create(step.spec, _random));
    }
    return first;
  }

  /// Advances past an info step.
  void next() {
    _queue.removeFirst();
    _done++;
  }

  // ---- Factories ----

  static LessonSession forLesson(Lesson lesson) => LessonSession(
        kind: SessionKind.lesson,
        title: lesson.title,
        steps: lesson.steps,
        lesson: lesson,
      );

  /// A session with up to [count] due exercises from the review queue,
  /// most overdue first.
  static LessonSession? review(ContentRepository repo, ProgressStore store, {int count = 10}) {
    final steps = [
      for (final key in store.dueReviewKeys)
        if (repo.step(key) != null) repo.step(key)!,
    ].take(count).toList()
      ..shuffle();
    if (steps.isEmpty) return null;
    return LessonSession(kind: SessionKind.review, title: 'Review', steps: steps);
  }

  /// Random questions drawn from [lessons] (e.g. a unit or subject).
  static LessonSession? practice(String title, Iterable<Lesson> lessons, {int count = 8}) {
    final pool = [
      for (final l in lessons)
        for (final s in l.steps)
          if (s.isQuestion) s,
    ]..shuffle();
    if (pool.isEmpty) return null;
    return LessonSession(
      kind: SessionKind.practice,
      title: title,
      steps: pool.take(count).toList(),
    );
  }
}
