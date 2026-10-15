// Renders every circuit in the content to PNG contact sheets (one per unit) so
// diagrams can be checked visually.
//
//   flutter test tool/circuit_preview_test.dart
//   CONTENT_SUBJECT=circuit-theory PREVIEW_OUT=/tmp/previews flutter test tool/circuit_preview_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:ee_study/content/content_repository.dart';
import 'package:ee_study/engine/step_instance.dart';
import 'package:ee_study/models/circuit.dart';
import 'package:ee_study/widgets/circuit_diagram.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _loadFonts() async {
  final dir = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final fonts = '$dir/bin/cache/artifacts/material_fonts';
  final loader = FontLoader('Roboto');
  for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']) {
    final file = File('$fonts/$f');
    if (file.existsSync()) {
      loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    }
  }
  await loader.load();
}

void main() {
  testWidgets('render circuit previews', (tester) async {
    await tester.runAsync(_loadFonts);
    final index = jsonDecode(File('assets/content/index.json').readAsStringSync())
        as Map<String, dynamic>;
    final only = Platform.environment['CONTENT_SUBJECT'];
    final repo = await ContentRepository.fromJson(
        index,
        skipUnitError: (e) => e is FileSystemException,
        includeDrafts: true,
        (f) async => jsonDecode(File('assets/content/$f').readAsStringSync()));
    final onlyUnit = Platform.environment['CONTENT_UNIT'];
    final out = Directory(Platform.environment['PREVIEW_OUT'] ?? 'build/circuit_previews')
      ..createSync(recursive: true);
    final rnd = math.Random(1);

    for (final subject in repo.subjects.values) {
      if (only != null && subject.id != only) continue;
      for (final unit in subject.units) {
        if (onlyUnit != null && unit.id != onlyUnit) continue;
        final items = <(String, CircuitSpec)>[];
        for (final c in unit.study) {
          if (c.circuit != null) items.add(('study: ${c.title}', c.circuit!));
        }
        for (final l in unit.lessons) {
          for (final s in l.steps) {
            if (s.circuit == null) continue;
            final inst = StepInstance.create(s, rnd);
            items.add((s.key, inst.circuit!));
          }
        }
        if (items.isEmpty) continue;
        final key = GlobalKey();
        await tester.binding.setSurfaceSize(Size(400, 330.0 * items.length));
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Roboto'),
          home: RepaintBoundary(
            key: key,
            child: Material(
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (title, spec) in items)
                    Container(
                      height: 330,
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: Colors.black12))),
                      child: Column(children: [
                        Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Expanded(child: Center(child: CircuitDiagram(spec))),
                      ]),
                    ),
                ],
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1.5);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('${out.path}/${unit.id}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }
    }
    await tester.binding.setSurfaceSize(null);
  });
}
