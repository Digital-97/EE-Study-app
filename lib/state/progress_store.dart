import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Result of a single finished lesson for a lesson.
class LessonRecord {
  LessonRecord({
    required this.completions,
    required this.bestAccuracy,
    required this.lastCompleted,
  });

  final int completions;

  /// Best first-try accuracy, 0..1.
  final double bestAccuracy;
  final DateTime lastCompleted;

  Map<String, dynamic> toJson() => {
        'c': completions,
        'a': bestAccuracy,
        't': lastCompleted.toIso8601String(),
      };

  factory LessonRecord.fromJson(Map<String, dynamic> j) => LessonRecord(
        completions: j['c'] as int,
        bestAccuracy: (j['a'] as num).toDouble(),
        lastCompleted: DateTime.parse(j['t'] as String),
      );
}

/// An exercise in the review queue, scheduled with spaced repetition
/// (a Leitner system): every correct review moves it to a higher box with a
/// longer interval; a mistake sends it back to box 0.
class ReviewItem {
  ReviewItem({required this.box, required this.due, required this.lapses, required this.lastWrong});

  /// 0 = just got it wrong. After a correct answer in the last box the item is
  /// considered mastered and leaves the queue.
  final int box;
  final DateTime due;

  /// Number of times answered wrong.
  final int lapses;
  final DateTime lastWrong;

  bool isDue(DateTime now) => !due.isAfter(now);

  Map<String, dynamic> toJson() => {
        'b': box,
        'd': due.toIso8601String(),
        'n': lapses,
        't': lastWrong.toIso8601String(),
      };

  factory ReviewItem.fromJson(Map<String, dynamic> j) {
    final lastWrong = DateTime.parse(j['t'] as String);
    return ReviewItem(
      // Older saves stored a correct-answer streak ('s') and no due date.
      box: (j['b'] ?? j['s'] ?? 0) as int,
      due: j['d'] == null ? lastWrong : DateTime.parse(j['d'] as String),
      lapses: (j['n'] ?? 1) as int,
      lastWrong: lastWrong,
    );
  }
}

/// A finished exam, kept for the history on the profile.
class ExamRecord {
  ExamRecord({
    required this.date,
    required this.title,
    required this.correct,
    required this.total,
    required this.seconds,
  });

  final DateTime date;
  final String title;
  final int correct;
  final int total;
  final int seconds;

  double get score => total == 0 ? 0 : correct / total;

  Map<String, dynamic> toJson() =>
      {'d': date.toIso8601String(), 'ti': title, 'c': correct, 'n': total, 's': seconds};

  factory ExamRecord.fromJson(Map<String, dynamic> j) => ExamRecord(
        date: DateTime.parse(j['d'] as String),
        title: j['ti'] as String,
        correct: j['c'] as int,
        total: j['n'] as int,
        seconds: j['s'] as int,
      );
}

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// All locally saved progress. Persisted as JSON in shared preferences.
class ProgressStore extends ChangeNotifier {
  ProgressStore(this._prefs, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    final raw = _prefs.getString(_key);
    if (raw != null) {
      try {
        _fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (e) {
        debugPrint('Could not read saved progress: $e');
      }
    }
  }

  static const _key = 'progress.v1';

  /// Review intervals in days for boxes 1, 2, ... A correct review in the
  /// last box masters the item.
  static const reviewIntervals = [1, 3, 7, 16, 35];

  final SharedPreferences _prefs;
  final DateTime Function() _clock;

  final Map<String, LessonRecord> _lessons = {};
  final Map<String, ReviewItem> _reviews = {};
  final Map<String, int> _xpByDay = {};
  final List<ExamRecord> _exams = [];
  int _xp = 0;
  int _dailyGoal = 30;
  String? _lastLevelId;
  int _questionsAnswered = 0;
  int _questionsCorrect = 0;
  int _mastered = 0;
  bool _reminderEnabled = false;
  int _reminderMinutes = 19 * 60;

  static Future<ProgressStore> load() async =>
      ProgressStore(await SharedPreferences.getInstance());

  void _fromJson(Map<String, dynamic> j) {
    _xp = (j['xp'] ?? 0) as int;
    _dailyGoal = (j['goal'] ?? 30) as int;
    _lastLevelId = j['level'] as String?;
    _questionsAnswered = (j['qa'] ?? 0) as int;
    _questionsCorrect = (j['qc'] ?? 0) as int;
    _mastered = (j['mastered'] ?? 0) as int;
    _reminderEnabled = (j['remind'] ?? false) as bool;
    _reminderMinutes = (j['remindAt'] ?? 19 * 60) as int;
    (j['lessons'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
      _lessons[k] = LessonRecord.fromJson(v as Map<String, dynamic>);
    });
    (j['mistakes'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
      _reviews[k] = ReviewItem.fromJson(v as Map<String, dynamic>);
    });
    (j['days'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
      _xpByDay[k] = v as int;
    });
    for (final e in (j['exams'] as List? ?? const [])) {
      _exams.add(ExamRecord.fromJson(e as Map<String, dynamic>));
    }
  }

  Map<String, dynamic> _toJson() => {
        'xp': _xp,
        'goal': _dailyGoal,
        'level': _lastLevelId,
        'qa': _questionsAnswered,
        'qc': _questionsCorrect,
        'mastered': _mastered,
        'remind': _reminderEnabled,
        'remindAt': _reminderMinutes,
        'lessons': _lessons.map((k, v) => MapEntry(k, v.toJson())),
        'mistakes': _reviews.map((k, v) => MapEntry(k, v.toJson())),
        'days': _xpByDay,
        'exams': [for (final e in _exams) e.toJson()],
      };

  Future<void> _save() => _prefs.setString(_key, jsonEncode(_toJson()));

  void _changed() {
    notifyListeners();
    _save();
  }

  // ---- Queries ----

  DateTime get now => _clock();
  int get xp => _xp;
  int get dailyGoal => _dailyGoal;
  String? get lastLevelId => _lastLevelId;
  int get questionsAnswered => _questionsAnswered;
  int get questionsCorrect => _questionsCorrect;
  Map<String, int> get xpByDay => Map.unmodifiable(_xpByDay);
  List<ExamRecord> get exams => List.unmodifiable(_exams);

  bool get reminderEnabled => _reminderEnabled;

  /// Reminder time as minutes after midnight.
  int get reminderMinutes => _reminderMinutes;

  int get todayXp => _xpByDay[dayKey(_clock())] ?? 0;

  LessonRecord? lesson(String id) => _lessons[id];
  bool isCompleted(String lessonId) => _lessons.containsKey(lessonId);
  int get lessonsCompleted => _lessons.length;

  Map<String, ReviewItem> get reviews => Map.unmodifiable(_reviews);

  /// Keys of review items that are due now, most overdue first.
  List<String> get dueReviewKeys {
    final now = _clock();
    final due = _reviews.entries.where((e) => e.value.isDue(now)).toList()
      ..sort((a, b) => a.value.due.compareTo(b.value.due));
    return [for (final e in due) e.key];
  }

  int get dueReviewCount => _reviews.values.where((r) => r.isDue(_clock())).length;
  int get reviewCount => _reviews.length;

  /// Exercises that went through all review boxes.
  int get masteredCount => _mastered;

  /// When the next not-yet-due review item becomes due, if any.
  DateTime? get nextReviewDue {
    final now = _clock();
    final upcoming = _reviews.values.where((r) => !r.isDue(now)).map((r) => r.due).toList()..sort();
    return upcoming.isEmpty ? null : upcoming.first;
  }

  /// Consecutive days with XP, ending today (or yesterday if nothing yet today).
  int get streak {
    var day = DateTime(_clock().year, _clock().month, _clock().day);
    if ((_xpByDay[dayKey(day)] ?? 0) == 0) {
      day = day.subtract(const Duration(days: 1));
    }
    var n = 0;
    while ((_xpByDay[dayKey(day)] ?? 0) > 0) {
      n++;
      day = DateTime(day.year, day.month, day.day - 1);
    }
    return n;
  }

  int get longestStreak {
    if (_xpByDay.isEmpty) return 0;
    final days = _xpByDay.entries.where((e) => e.value > 0).map((e) => DateTime.parse(e.key)).toList()
      ..sort();
    var best = 0, run = 0;
    DateTime? prev;
    for (final d in days) {
      if (prev != null && DateTime(prev.year, prev.month, prev.day + 1) == d) {
        run++;
      } else {
        run = 1;
      }
      if (run > best) best = run;
      prev = d;
    }
    return best;
  }

  /// Fraction of [lessonIds] completed, 0..1.
  double completion(Iterable<String> lessonIds) {
    final ids = lessonIds.toList();
    if (ids.isEmpty) return 0;
    return ids.where(isCompleted).length / ids.length;
  }

  // ---- Mutations ----

  set dailyGoal(int v) {
    _dailyGoal = v;
    _changed();
  }

  set lastLevelId(String? id) {
    if (_lastLevelId == id) return;
    _lastLevelId = id;
    _changed();
  }

  void setReminder({required bool enabled, int? minutes}) {
    _reminderEnabled = enabled;
    if (minutes != null) _reminderMinutes = minutes;
    _changed();
  }

  /// Records an answer. A first-try mistake (re)starts the exercise in the
  /// review queue; a correct first try on a due review item promotes it.
  void recordAnswer(String stepKey, {required bool correct, bool firstTry = true}) {
    final now = _clock();
    if (firstTry) {
      _questionsAnswered++;
      if (correct) _questionsCorrect++;
    }
    final item = _reviews[stepKey];
    if (!correct) {
      if (firstTry) {
        _reviews[stepKey] = ReviewItem(
          box: 0,
          due: now,
          lapses: (item?.lapses ?? 0) + 1,
          lastWrong: now,
        );
      }
    } else if (item != null && firstTry && item.isDue(now)) {
      final box = item.box + 1;
      if (box > reviewIntervals.length) {
        _reviews.remove(stepKey);
        _mastered++;
      } else {
        // Due at the start of the day, so a review is never "a few hours
        // early" the next day.
        final today = DateTime(now.year, now.month, now.day);
        _reviews[stepKey] = ReviewItem(
          box: box,
          due: today.add(Duration(days: reviewIntervals[box - 1])),
          lapses: item.lapses,
          lastWrong: item.lastWrong,
        );
      }
    }
    _changed();
  }

  /// Records a finished lesson and awards XP. Returns the XP earned.
  int completeLesson(String lessonId, {required double accuracy, required int questions}) {
    final prev = _lessons[lessonId];
    final earned = xpFor(accuracy: accuracy, questions: questions, repeat: prev != null);
    _lessons[lessonId] = LessonRecord(
      completions: (prev?.completions ?? 0) + 1,
      bestAccuracy: prev == null ? accuracy : (accuracy > prev.bestAccuracy ? accuracy : prev.bestAccuracy),
      lastCompleted: _clock(),
    );
    addXp(earned);
    return earned;
  }

  void addExam(ExamRecord exam) {
    _exams.add(exam);
    _changed();
  }

  void addXp(int amount) {
    _xp += amount;
    final k = dayKey(_clock());
    _xpByDay[k] = (_xpByDay[k] ?? 0) + amount;
    _changed();
  }

  /// XP for a finished lesson: 10 base, +5 for a perfect lesson, +1 per
  /// question. Repeating a lesson still earns XP (practice is good!).
  static int xpFor({required double accuracy, required int questions, bool repeat = false}) {
    var xp = 10 + questions;
    if (accuracy >= 0.999) xp += 5;
    if (repeat) xp = (xp * 0.6).round();
    return xp;
  }

  Future<void> reset() async {
    _lessons.clear();
    _reviews.clear();
    _xpByDay.clear();
    _exams.clear();
    _xp = 0;
    _questionsAnswered = 0;
    _questionsCorrect = 0;
    _mastered = 0;
    _lastLevelId = null;
    _changed();
  }

  // ---- Backup ----

  static const _backupApp = 'ee-study';

  /// All progress as a JSON document that can be saved and imported later.
  String exportBackup() => const JsonEncoder.withIndent(' ').convert({
        'app': _backupApp,
        'version': 1,
        'exported': _clock().toIso8601String(),
        'progress': _toJson(),
      });

  /// Replaces all progress with a backup made by [exportBackup].
  /// Throws [BackupException] if the file is not a valid backup; the current
  /// progress is left untouched in that case.
  Future<void> importBackup(String text) async {
    Map<String, dynamic> progress;
    try {
      final j = jsonDecode(text) as Map<String, dynamic>;
      if (j['app'] != _backupApp) throw BackupException('This is not an EE Study backup file.');
      progress = j['progress'] as Map<String, dynamic>;
      // Parse into a scratch store first so a broken file can't wipe progress.
      final probe = ProgressStore._empty(_prefs, _clock);
      probe._fromJson(progress);
    } on BackupException {
      rethrow;
    } catch (_) {
      throw BackupException('The backup file could not be read.');
    }
    _lessons.clear();
    _reviews.clear();
    _xpByDay.clear();
    _exams.clear();
    _fromJson(progress);
    notifyListeners();
    await _save();
  }

  ProgressStore._empty(this._prefs, this._clock);
}
