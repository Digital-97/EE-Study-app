// Renders the app and every lesson step at phone size to catch layout
// overflows and rendering errors in content.
import 'dart:math' as math;

import 'package:ee_study/content/content_repository.dart';
import 'package:ee_study/engine/step_instance.dart';
import 'package:ee_study/lesson/lesson_screen.dart';
import 'package:ee_study/lesson/lesson_session.dart';
import 'package:ee_study/lesson/worked_solution_screen.dart';
import 'package:ee_study/exam/exam_screens.dart';
import 'package:ee_study/exam/exam_session.dart';
import 'package:ee_study/main.dart';
import 'package:ee_study/models/content.dart';
import 'package:ee_study/screens/unit_study_screen.dart';
import 'package:ee_study/state/progress_store.dart';
import 'package:ee_study/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const phone = Size(360, 740);

Future<(ContentRepository, ProgressStore)> _load(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  late ContentRepository repo;
  late ProgressStore store;
  await tester.runAsync(() async {
    repo = await ContentRepository.load();
    store = await ProgressStore.load();
  });
  return (repo, store);
}

Widget _wrap(ContentRepository repo, ProgressStore store, Widget child) => MultiProvider(
      providers: [Provider.value(value: repo), ChangeNotifierProvider.value(value: store)],
      child: MaterialApp(theme: buildTheme(Brightness.light), home: child),
    );

void main() {
  testWidgets('home, subject and lesson navigation', (tester) async {
    await tester.binding.setSurfaceSize(phone);
    final (repo, store) = await _load(tester);
    await tester.pumpWidget(EeStudyApp(content: repo, progress: store));
    await tester.pumpAndSettle();
    expect(find.text(repo.levels.first.title), findsOneWidget);

    // Open the first subject's path.
    final subject = repo.subjectsFor(repo.levels.first).first;
    await tester.ensureVisible(find.text(subject.title).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(subject.title).first);
    await tester.pumpAndSettle();
    expect(find.text(subject.units.first.title), findsWidgets);

    // Visit the other tabs.
    await tester.pageBack();
    await tester.pumpAndSettle();
    for (final tab in ['Study', 'Practice', 'Profile', 'Learn']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('an exam can be taken and shows results', (tester) async {
    await tester.binding.setSurfaceSize(phone);
    final (repo, store) = await _load(tester);
    final exam = ExamSession.create(repo, repo.subjectsFor(repo.levels.first), count: 10, timed: true)!;
    expect(exam.questions, hasLength(10));
    // Questions are spread over different units.
    expect(exam.byUnit.length, greaterThan(5));
    await tester.pumpWidget(_wrap(repo, store, ExamSetupScreen()));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_wrap(repo, store, ExamScreen(exam: exam)));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.text('SKIP'));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(find.text('0%'), findsOneWidget);
    expect(store.exams, hasLength(1));
    expect(store.reviewCount, 10);
    await tester.binding.setSurfaceSize(null);
  });

  // Handing in right after a slider is checked (and so disabled) used to trip
  // a semantics assertion; random exams only hit it now and then.
  testWidgets('an exam ending on a slider question can be handed in', (tester) async {
    await tester.binding.setSurfaceSize(phone);
    final (repo, store) = await _load(tester);
    final rnd = math.Random(1);
    final (unit, spec) = [
      for (final s in repo.subjectsFor(repo.levels.first))
        for (final u in s.units)
          for (final l in u.lessons)
            for (final st in l.steps)
              if (st.isQuestion && StepInstance.create(st, rnd).type == StepType.slider) (u, st),
    ].first;
    final exam = ExamSession(title: 'Slider exam', questions: [ExamQuestion(StepInstance.create(spec, rnd), unit)]);
    await tester.pumpWidget(_wrap(repo, store, ExamScreen(exam: exam)));
    await tester.pump();
    await tester.tap(find.text('SKIP'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('0%'), findsOneWidget);
    expect(store.exams, hasLength(1));
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('every lesson step and study card renders', (tester) async {
    await tester.binding.setSurfaceSize(phone);
    final (repo, store) = await _load(tester);
    final failures = <String>[];
    final rnd = math.Random(7);
    // One app instance; only the page under test is swapped.
    final page = ValueNotifier<Widget>(const SizedBox());
    await tester.pumpWidget(_wrap(
      repo,
      store,
      ValueListenableBuilder<Widget>(valueListenable: page, builder: (_, w, _) => w),
    ));

    // Collect Flutter errors ourselves so each one is attributed to a step.
    final errors = <String>[];
    final oldHandler = FlutterError.onError;
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split('\n').first);

    Future<void> show(Widget w, String what) async {
      errors.clear();
      page.value = KeyedSubtree(key: UniqueKey(), child: w);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      if (errors.isNotEmpty) failures.add('$what: ${errors.toSet().join(' | ')}');
    }

    for (final subject in repo.subjects.values) {
      for (final unit in subject.units) {
        await show(UnitStudyScreen(subject: subject, unit: unit), '${unit.id} study');
        for (final lesson in unit.lessons) {
          for (final step in lesson.steps) {
            final session = LessonSession(
              kind: SessionKind.lesson,
              title: lesson.title,
              steps: [step],
              lesson: lesson,
              random: rnd,
            );
            await show(LessonScreen(session: session), step.key);
            final inst = session.current!;
            if (inst.hasWorkedSolution) {
              await show(
                WorkedSolutionScreen(circuit: inst.circuit!, report: inst.workedSolution()),
                '${step.key} worked solution',
              );
            }
          }
        }
      }
    }
    FlutterError.onError = oldHandler;
    await tester.binding.setSurfaceSize(null);
    if (failures.isNotEmpty) {
      fail('Render failures (${failures.length}):\n${failures.take(150).join('\n')}');
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}
