// Renders lesson steps as they appear in the app (phone size, real fonts) to
// PNG files, one per step, for checking graphs, tap questions and layouts.
//
//   CONTENT_UNIT=tr-rc PREVIEW_OUT=build/steps flutter test tool/step_preview_test.dart
//   CONTENT_STEP=tr-rc-2/q3 ...   (optional: only steps whose key contains this)
//   PREVIEW_WORKED=1 ...           (also render worked solutions, 360×2400)
//   PREVIEW_HEIGHT=1100 ...        (taller screen, e.g. to see sliders under a graph)
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:ee_study/content/content_repository.dart';
import 'package:ee_study/lesson/lesson_screen.dart';
import 'package:ee_study/lesson/worked_solution_screen.dart';
import 'package:ee_study/lesson/lesson_session.dart';
import 'package:ee_study/screens/unit_study_screen.dart';
import 'package:ee_study/state/progress_store.dart';
import 'package:ee_study/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Loads Roboto (from the Flutter SDK) and every font in the app's font
/// manifest (KaTeX math fonts, Material icons).
Future<void> _loadFonts() async {
  final sdk = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final roboto = FontLoader('Roboto');
  for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']) {
    final file = File('$sdk/bin/cache/artifacts/material_fonts/$f');
    if (file.existsSync()) roboto.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  }
  await roboto.load();
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final entry in manifest) {
    final loader = FontLoader(entry['family'] as String);
    for (final font in entry['fonts'] as List) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

// ignore_for_file: invalid_use_of_visible_for_testing_member

void main() {
  testWidgets('render step previews', (tester) async {
    SharedPreferences.setMockInitialValues({});
    late ContentRepository repo;
    late ProgressStore store;
    await tester.runAsync(() async {
      await _loadFonts();
      repo = await ContentRepository.load(includeDrafts: true);
      store = await ProgressStore.load();
    });
    final unitId = Platform.environment['CONTENT_UNIT'];
    final stepFilter = Platform.environment['CONTENT_STEP'];
    final out = Directory(Platform.environment['PREVIEW_OUT'] ?? 'build/steps')
      ..createSync(recursive: true);
    final unit = unitId == null ? null : repo.unit(unitId);
    if (unit == null) fail('Set CONTENT_UNIT to a unit id');
    final subject = repo.subjects[unit.subjectId]!;
    final height = double.tryParse(Platform.environment['PREVIEW_HEIGHT'] ?? '') ?? 740;
    await tester.binding.setSurfaceSize(Size(360, height));
    final rnd = math.Random(5);

    Future<void> shot(Widget page, String name) async {
      final key = GlobalKey();
      await tester.pumpWidget(MultiProvider(
        providers: [Provider.value(value: repo), ChangeNotifierProvider.value(value: store)],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light).copyWith(
            textTheme: buildTheme(Brightness.light).textTheme.apply(fontFamily: 'Roboto'),
          ),
          home: RepaintBoundary(key: key, child: page),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('${out.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    if (stepFilter == null) {
      await shot(UnitStudyScreen(subject: subject, unit: unit), '${unit.id}__study');
    }
    for (final lesson in unit.lessons) {
      for (final step in lesson.steps) {
        if (stepFilter != null && !step.key.contains(stepFilter)) continue;
        final session = LessonSession(
          kind: SessionKind.lesson,
          title: lesson.title,
          steps: [step],
          lesson: lesson,
          random: rnd,
        );
        await shot(LessonScreen(session: session), step.key.replaceAll('/', '__'));
        final inst = session.current!;
        if (Platform.environment['PREVIEW_WORKED'] != null && inst.hasWorkedSolution) {
          await tester.binding.setSurfaceSize(const Size(360, 2400));
          await shot(
            WorkedSolutionScreen(circuit: inst.circuit!, report: inst.workedSolution(), question: inst.prompt),
            '${step.key.replaceAll('/', '__')}__worked',
          );
          await tester.binding.setSurfaceSize(Size(360, height));
        }
      }
    }
    await tester.binding.setSurfaceSize(null);
  });
}
