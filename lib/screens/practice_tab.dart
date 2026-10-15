import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../content/content_repository.dart';
import '../exam/exam_screens.dart';
import '../lesson/lesson_screen.dart';
import '../lesson/lesson_session.dart';
import '../state/progress_store.dart';
import '../ui/theme.dart';
import '../widgets/chunky_button.dart';
import 'common.dart';

/// Spaced-repetition review and mixed practice.
class PracticeTab extends StatelessWidget {
  const PracticeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ContentRepository>();
    final store = context.watch<ProgressStore>();
    final level = currentLevel(context);
    final subjects = repo.subjectsFor(level);
    final dueCount = store.dueReviewKeys.where((k) => repo.step(k) != null).length;
    final completedLessons = [
      for (final s in subjects)
        for (final l in s.lessons)
          if (store.isCompleted(l.id)) l,
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Practice'),
        actions: const [StatsBar(), SizedBox(width: 16)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _PracticeCard(
            icon: Icons.replay_rounded,
            color: AppColors.red,
            title: 'Review',
            subtitle: _reviewSubtitle(store, dueCount),
            footer: store.reviewCount == 0 && store.masteredCount == 0
                ? null
                : _ReviewBoxes(store: store),
            buttonLabel: dueCount == 0 ? 'Nothing due' : 'Review $dueCount',
            onPressed: dueCount == 0
                ? null
                : () {
                    final s = LessonSession.review(repo, store);
                    if (s != null) LessonScreen.open(context, s, accent: AppColors.red);
                  },
          ),
          const SizedBox(height: 12),
          _PracticeCard(
            icon: Icons.assignment_rounded,
            color: AppColors.blue,
            title: 'Exam mode',
            subtitle: store.exams.isEmpty
                ? 'A timed mock exam with mixed questions. See your score per unit at the end.'
                : 'Last results: ${store.exams.reversed.take(3).map((e) => '${(e.score * 100).round()}%').join(', ')}.',
            buttonLabel: 'Set up exam',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ExamSetupScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _PracticeCard(
            icon: Icons.shuffle_rounded,
            color: AppColors.orange,
            title: 'Mixed practice',
            subtitle: completedLessons.isEmpty
                ? 'Complete a lesson first; then practise random questions from everything you have learned in ${level.title}.'
                : 'Random questions from the ${completedLessons.length} lesson${completedLessons.length == 1 ? '' : 's'} you have completed in ${level.title}.',
            buttonLabel: 'Start practice',
            onPressed: completedLessons.isEmpty
                ? null
                : () {
                    final s = LessonSession.practice('Mixed practice', completedLessons, count: 10);
                    if (s != null) LessonScreen.open(context, s, accent: AppColors.orange);
                  },
          ),
          const SizedBox(height: 20),
          Text('Practise a subject',
              style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          for (final s in subjects)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ChunkyCard(
                onTap: () {
                  final session = LessonSession.practice('${s.title} practice', s.lessons, count: 10);
                  if (session != null) LessonScreen.open(context, session, accent: s.color);
                },
                child: Row(children: [
                  Icon(subjectIcon(s.icon), color: s.color, size: 30),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(s.title,
                        style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  const Icon(Icons.play_arrow_rounded, color: AppColors.greyDark),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

class _PracticeCard extends StatelessWidget {
  const _PracticeCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onPressed,
    this.footer,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback? onPressed;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return ChunkyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title,
                  style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(subtitle, style: context.text.bodyMedium),
          if (footer != null) ...[const SizedBox(height: 12), footer!],
          const SizedBox(height: 12),
          ChunkyButton(label: buttonLabel, color: color, onPressed: onPressed),
        ],
      ),
    );
  }
}

String _reviewSubtitle(ProgressStore store, int due) {
  if (store.reviewCount == 0) {
    return 'Questions you get wrong come back here for review, spaced out over days and weeks '
        'so they stick. Nothing to review yet.';
  }
  final parts = <String>[];
  if (due > 0) {
    parts.add('$due question${due == 1 ? ' is' : 's are'} due now.');
  } else {
    final next = store.nextReviewDue;
    if (next != null) parts.add('Nothing due. Next review ${_when(store.now, next)}.');
  }
  parts.add('Each correct review pushes a question further out '
      '(1, 3, 7, 16, 35 days); a mistake brings it back.');
  return parts.join(' ');
}

String _when(DateTime now, DateTime t) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final days = day.difference(today).inDays;
  if (days <= 0) return 'later today';
  if (days == 1) return 'tomorrow';
  return 'in $days days';
}

/// How many questions sit in each review box, plus mastered ones.
class _ReviewBoxes extends StatelessWidget {
  const _ReviewBoxes({required this.store});

  final ProgressStore store;

  @override
  Widget build(BuildContext context) {
    final counts = List<int>.filled(ProgressStore.reviewIntervals.length + 1, 0);
    for (final r in store.reviews.values) {
      counts[r.box.clamp(0, counts.length - 1)]++;
    }
    Widget cell(String label, int n, Color c) => Expanded(
          child: Column(children: [
            Text('$n', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: c)),
            Text(label,
                textAlign: TextAlign.center,
                style: context.text.labelSmall?.copyWith(color: AppColors.greyDark)),
          ]),
        );
    return Row(children: [
      cell('new', counts[0], AppColors.red),
      for (var b = 1; b < counts.length; b++)
        cell('${ProgressStore.reviewIntervals[b - 1]}d', counts[b], AppColors.orange),
      cell('mastered', store.masteredCount, AppColors.green),
    ]);
  }
}
