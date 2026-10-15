import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/content.dart';

/// Loads all study content bundled in `assets/content/`.
class ContentRepository {
  ContentRepository({required this.levels, required this.subjects});

  final List<Level> levels;
  final Map<String, Subject> subjects;

  late final Map<String, Lesson> _lessons = {
    for (final s in subjects.values)
      for (final l in s.lessons) l.id: l,
  };

  late final Map<String, Unit> _units = {
    for (final s in subjects.values)
      for (final u in s.units) u.id: u,
  };

  late final Map<String, StepSpec> _steps = {
    for (final l in _lessons.values)
      for (final s in l.steps) s.key: s,
  };

  Lesson? lesson(String id) => _lessons[id];
  Unit? unit(String id) => _units[id];
  StepSpec? step(String key) => _steps[key];

  List<Subject> subjectsFor(Level level) =>
      [for (final id in level.subjectIds) if (subjects[id] != null) subjects[id]!];

  Level? levelOf(Subject subject) {
    for (final l in levels) {
      if (l.subjectIds.contains(subject.id)) return l;
    }
    return null;
  }

  static const indexPath = 'assets/content/index.json';

  static Future<ContentRepository> load({AssetBundle? bundle, bool includeDrafts = false}) async {
    final b = bundle ?? rootBundle;
    final index = jsonDecode(await b.loadString(indexPath)) as Map<String, dynamic>;
    return fromJson(
      index,
      (file) async => jsonDecode(await b.loadString('assets/content/$file')),
      // A missing unit file should not take the whole app down.
      skipUnitError: (e) {
        debugPrint('Skipping unit file: $e');
        return e is! FormatException;
      },
      includeDrafts: includeDrafts,
    );
  }

  /// Builds the repository from the index JSON, loading each subject via
  /// [loadFile]. Shared by the app and tests.
  static Future<ContentRepository> fromJson(
      Map<String, dynamic> index, Future<dynamic> Function(String file) loadFile,
      {bool Function(Object error)? skipUnitError, bool includeDrafts = false}) async {
    final allLevels = [
      for (final l in (index['levels'] as List)) Level.fromJson(l as Map<String, dynamic>),
    ];
    final levels = includeDrafts ? allLevels : allLevels.where((l) => !l.draft).toList();
    final visible = {for (final l in levels) ...l.subjectIds};
    final subjects = <String, Subject>{};
    for (final file in (index['subjectFiles'] as List)) {
      final json = Map<String, dynamic>.from(await loadFile(file as String) as Map);
      // Subjects only in draft levels are hidden; their unit files may not
      // exist yet, so don't load them.
      if (!visible.contains(json['id'])) continue;
      // Units may be inline objects or file names of separate unit files.
      final units = <dynamic>[];
      for (final u in (json['units'] as List)) {
        if (u is String) {
          try {
            units.add(await loadFile(u));
          } catch (e) {
            if (skipUnitError == null || !skipUnitError(e)) rethrow;
          }
        } else {
          units.add(u);
        }
      }
      json['units'] = units;
      final s = Subject.fromJson(json);
      subjects[s.id] = s;
    }
    return ContentRepository(levels: levels, subjects: subjects);
  }
}
