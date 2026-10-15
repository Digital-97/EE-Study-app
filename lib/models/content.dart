import 'package:flutter/material.dart';

import 'circuit.dart';
import 'plot.dart';

/// A study level, e.g. "Year 1 – Basics".
class Level {
  Level({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.subjectIds,
    this.draft = false,
  });

  final String id;

  /// Draft levels are still being written: hidden in the app, and their
  /// missing unit files are tolerated by the content tests.
  final bool draft;
  final String title;
  final String subtitle;
  final String description;
  final List<String> subjectIds;

  factory Level.fromJson(Map<String, dynamic> j) => Level(
        id: j['id'] as String,
        title: j['title'] as String,
        subtitle: (j['subtitle'] ?? '') as String,
        description: (j['description'] ?? '') as String,
        subjectIds: List<String>.from(j['subjects'] as List),
        draft: (j['draft'] ?? false) as bool,
      );
}

/// A subject within a level, e.g. "Circuit Theory".
class Subject {
  Subject({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.reference,
    required this.units,
  });

  final String id;
  final String title;
  final String description;
  final String icon;
  final Color color;
  final String reference;
  final List<Unit> units;

  Iterable<Lesson> get lessons => units.expand((u) => u.lessons);

  factory Subject.fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String;
    return Subject(
      id: id,
      title: j['title'] as String,
      description: (j['description'] ?? '') as String,
      icon: (j['icon'] ?? 'bolt') as String,
      color: _parseColor((j['color'] ?? '#58CC02') as String),
      reference: (j['reference'] ?? '') as String,
      units: [
        for (final u in (j['units'] as List))
          Unit.fromJson(u as Map<String, dynamic>, subjectId: id),
      ],
    );
  }
}

Color _parseColor(String hex) {
  final h = hex.replaceFirst('#', '');
  return Color(int.parse(h.length == 6 ? 'FF$h' : h, radix: 16));
}

class Unit {
  Unit({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.description,
    required this.reference,
    required this.study,
    required this.lessons,
  });

  final String id;
  final String subjectId;
  final String title;
  final String description;
  final String reference;
  final List<StudyCard> study;
  final List<Lesson> lessons;

  factory Unit.fromJson(Map<String, dynamic> j, {required String subjectId}) {
    final id = j['id'] as String;
    return Unit(
      id: id,
      subjectId: subjectId,
      title: j['title'] as String,
      description: (j['description'] ?? '') as String,
      reference: (j['reference'] ?? '') as String,
      study: [
        for (final s in (j['study'] as List? ?? const []))
          StudyCard.fromJson(s as Map<String, dynamic>),
      ],
      lessons: [
        for (final l in (j['lessons'] as List? ?? const []))
          Lesson.fromJson(l as Map<String, dynamic>, subjectId: subjectId, unitId: id),
      ],
    );
  }
}

/// A piece of study material: short explanation, optional formula/circuit.
class StudyCard {
  StudyCard({required this.title, required this.body, this.formula, this.circuit, this.plot});

  final String title;
  final String body;
  final String? formula;
  final CircuitSpec? circuit;
  final PlotSpec? plot;

  factory StudyCard.fromJson(Map<String, dynamic> j) => StudyCard(
        title: j['title'] as String,
        body: (j['body'] ?? '') as String,
        formula: j['formula'] as String?,
        circuit: j['circuit'] == null
            ? null
            : CircuitSpec.fromJson(j['circuit'] as Map<String, dynamic>),
        plot: j['plot'] == null ? null : PlotSpec.fromJson(j['plot'] as Map<String, dynamic>),
      );
}

enum LessonKind { learn, practice, challenge }

class Lesson {
  Lesson({
    required this.id,
    required this.subjectId,
    required this.unitId,
    required this.title,
    required this.kind,
    required this.steps,
  });

  final String id;
  final String subjectId;
  final String unitId;
  final String title;
  final LessonKind kind;
  final List<StepSpec> steps;

  int get questionCount => steps.where((s) => s.isQuestion).length;

  factory Lesson.fromJson(Map<String, dynamic> j,
      {required String subjectId, required String unitId}) {
    final id = j['id'] as String;
    return Lesson(
      id: id,
      subjectId: subjectId,
      unitId: unitId,
      title: j['title'] as String,
      kind: LessonKind.values.byName((j['kind'] ?? 'practice') as String),
      steps: [
        for (final s in (j['steps'] as List))
          StepSpec.fromJson(s as Map<String, dynamic>, lessonId: id),
      ],
    );
  }
}

enum StepType { info, multipleChoice, trueFalse, numeric, matchPairs, orderSteps, tapCircuit, slider }

/// Definition of a random parameter: either a list of values or a range.
class ParamSpec {
  ParamSpec({this.values, this.min, this.max, this.step});

  final List<double>? values;
  final double? min;
  final double? max;
  final double? step;

  factory ParamSpec.fromJson(dynamic j) {
    if (j is List) {
      return ParamSpec(values: [for (final v in j) (v as num).toDouble()]);
    }
    if (j is num) return ParamSpec(values: [j.toDouble()]);
    final m = j as Map<String, dynamic>;
    return ParamSpec(
      values: m['values'] == null
          ? null
          : [for (final v in (m['values'] as List)) (v as num).toDouble()],
      min: (m['min'] as num?)?.toDouble(),
      max: (m['max'] as num?)?.toDouble(),
      step: (m['step'] as num?)?.toDouble(),
    );
  }
}

/// A lesson step (an info card or an exercise) as authored in content.
class StepSpec {
  StepSpec({
    required this.id,
    required this.lessonId,
    required this.type,
    required this.raw,
    required this.params,
    required this.derived,
    required this.computed,
    required this.require,
    this.circuit,
    this.plot,
  });

  final String id;
  final String lessonId;
  final StepType type;
  final Map<String, dynamic> raw;
  final Map<String, ParamSpec> params;

  /// Values computed from params, in declaration order.
  final List<MapEntry<String, String>> derived;

  /// Values computed after the circuit has been solved (may use solver
  /// results such as V_R1).
  final List<MapEntry<String, String>> computed;

  /// Optional expression that must evaluate > 0 for a param draw to be valid.
  final String? require;
  final CircuitSpec? circuit;
  final PlotSpec? plot;

  bool get isQuestion => type != StepType.info;

  /// Globally unique key, used for mistake tracking.
  String get key => '$lessonId/$id';

  factory StepSpec.fromJson(Map<String, dynamic> j, {required String lessonId}) {
    final derivedRaw = j['derived'] as Map<String, dynamic>? ?? const {};
    final computedRaw = j['computed'] as Map<String, dynamic>? ?? const {};
    return StepSpec(
      id: j['id'] as String,
      lessonId: lessonId,
      type: StepType.values.byName(j['type'] as String),
      raw: j,
      params: {
        for (final e in (j['params'] as Map<String, dynamic>? ?? const {}).entries)
          e.key: ParamSpec.fromJson(e.value),
      },
      derived: [for (final e in derivedRaw.entries) MapEntry(e.key, e.value as String)],
      computed: [for (final e in computedRaw.entries) MapEntry(e.key, e.value as String)],
      require: j['require'] as String?,
      circuit: j['circuit'] == null
          ? null
          : CircuitSpec.fromJson(j['circuit'] as Map<String, dynamic>),
      plot: j['plot'] == null ? null : PlotSpec.fromJson(j['plot'] as Map<String, dynamic>),
    );
  }
}
