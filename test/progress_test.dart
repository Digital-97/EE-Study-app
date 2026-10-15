import 'package:ee_study/state/progress_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late DateTime now;

  Future<ProgressStore> store() async {
    final prefs = await SharedPreferences.getInstance();
    return ProgressStore(prefs, clock: () => now);
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 3, 10, 12);
  });

  test('streak counts consecutive days with XP', () async {
    final s = await store();
    expect(s.streak, 0);
    s.addXp(10);
    expect(s.streak, 1);
    now = DateTime(2026, 3, 11, 9);
    expect(s.streak, 1, reason: 'yesterday still counts until today ends');
    s.addXp(5);
    expect(s.streak, 2);
    now = DateTime(2026, 3, 13, 9);
    expect(s.streak, 0);
    expect(s.longestStreak, 2);
  });

  test('lessons and XP persist', () async {
    final s = await store();
    final xp = s.completeLesson('l1', accuracy: 1, questions: 6);
    expect(xp, ProgressStore.xpFor(accuracy: 1, questions: 6));
    expect(s.isCompleted('l1'), isTrue);
    // Saving is async; let it finish, then reload from preferences.
    await Future<void>.delayed(Duration.zero);
    final reloaded = await store();
    expect(reloaded.isCompleted('l1'), isTrue);
    expect(reloaded.xp, xp);
    expect(reloaded.todayXp, xp);
  });

  test('spaced repetition moves items through the boxes', () async {
    final s = await store();
    s.recordAnswer('l1/q1', correct: false);
    expect(s.reviewCount, 1);
    expect(s.dueReviewCount, 1);
    // Retrying in the same lesson (not a first try) does not promote.
    s.recordAnswer('l1/q1', correct: true, firstTry: false);
    expect(s.reviews['l1/q1']!.box, 0);
    // Correct review: box 1, due tomorrow.
    s.recordAnswer('l1/q1', correct: true);
    expect(s.reviews['l1/q1']!.box, 1);
    expect(s.dueReviewCount, 0);
    // Answering early (not due) changes nothing.
    s.recordAnswer('l1/q1', correct: true);
    expect(s.reviews['l1/q1']!.box, 1);
    // Walk through all boxes until mastered.
    for (final days in ProgressStore.reviewIntervals) {
      now = now.add(Duration(days: days));
      expect(s.dueReviewCount, 1);
      s.recordAnswer('l1/q1', correct: true);
    }
    expect(s.reviewCount, 0);
    expect(s.masteredCount, 1);
    // A mistake on a mastered-then-wrong item starts over.
    s.recordAnswer('l1/q1', correct: false);
    expect(s.reviews['l1/q1']!.box, 0);
    expect(s.reviews['l1/q1']!.lapses, 1);
  });

  test('old saves with a streak field are migrated', () async {
    SharedPreferences.setMockInitialValues({
      'progress.v1': '{"xp":5,"mistakes":{"a/b":{"n":2,"t":"2026-03-09T10:00:00.000","s":1}}}',
    });
    final s = await store();
    expect(s.reviews['a/b']!.box, 1);
    expect(s.dueReviewCount, 1, reason: 'migrated items are due immediately');
  });

  test('backup round trip and invalid files', () async {
    final s = await store();
    s.completeLesson('l1', accuracy: 0.5, questions: 4);
    s.recordAnswer('l1/q1', correct: false);
    final backup = s.exportBackup();

    await s.reset();
    expect(s.xp, 0);
    await s.importBackup(backup);
    expect(s.isCompleted('l1'), isTrue);
    expect(s.reviewCount, 1);

    expect(() => s.importBackup('{"app":"other"}'), throwsA(isA<BackupException>()));
    expect(() => s.importBackup('not json'), throwsA(isA<BackupException>()));
    expect(s.isCompleted('l1'), isTrue, reason: 'a failed import keeps progress');
  });
}
