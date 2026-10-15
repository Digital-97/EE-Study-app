import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../content/content_repository.dart';
import '../lesson/lesson_screen.dart';
import '../lesson/lesson_session.dart';
import '../models/content.dart';
import '../state/progress_store.dart';
import '../ui/theme.dart';
import '../widgets/chunky_button.dart';
import 'common.dart';
import 'subject_screen.dart';

/// Home tab: choose a level, see daily progress and pick a subject.
class LearnTab extends StatelessWidget {
  const LearnTab({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ContentRepository>();
    final store = context.watch<ProgressStore>();
    final level = currentLevel(context);
    final subjects = repo.subjectsFor(level);
    final next = _nextLesson(subjects, store);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: _LevelButton(level: level),
        actions: const [StatsBar(), SizedBox(width: 16)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _DailyGoalCard(xp: store.todayXp, goal: store.dailyGoal),
          if (next != null) ...[
            const SizedBox(height: 12),
            _ContinueCard(subject: next.$1, lesson: next.$2),
          ],
          const SizedBox(height: 20),
          Text('Subjects',
              style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(level.description, style: context.text.bodyMedium),
          const SizedBox(height: 12),
          for (final s in subjects)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SubjectCard(subject: s),
            ),
        ],
      ),
    );
  }

  /// The first not-yet-completed lesson, preferring subjects already started.
  static (Subject, Lesson)? _nextLesson(List<Subject> subjects, ProgressStore store) {
    final started = subjects.where((s) => s.lessons.any((l) => store.isCompleted(l.id)));
    for (final s in [...started, ...subjects]) {
      for (final l in s.lessons) {
        if (!store.isCompleted(l.id)) return (s, l);
      }
    }
    return null;
  }
}

class _LevelButton extends StatelessWidget {
  const _LevelButton({required this.level});

  final Level level;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showLevelPicker(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.school_rounded, color: AppColors.blue),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                level.title,
                overflow: TextOverflow.ellipsis,
                style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            const Icon(Icons.expand_more_rounded),
          ],
        ),
      ),
    );
  }
}

class _DailyGoalCard extends StatelessWidget {
  const _DailyGoalCard({required this.xp, required this.goal});

  final int xp;
  final int goal;

  @override
  Widget build(BuildContext context) {
    final done = xp >= goal;
    return ChunkyCard(
      child: Row(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: (xp / goal).clamp(0.0, 1.0),
                  strokeWidth: 7,
                  backgroundColor: context.border,
                  color: done ? AppColors.gold : AppColors.orange,
                  strokeCap: StrokeCap.round,
                ),
                Icon(done ? Icons.emoji_events_rounded : Icons.local_fire_department_rounded,
                    color: done ? AppColors.gold : AppColors.orange),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(done ? 'Daily goal reached!' : 'Daily goal',
                    style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('$xp / $goal XP today', style: context.text.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.subject, required this.lesson});

  final Subject subject;
  final Lesson lesson;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ContentRepository>();
    final unit = repo.unit(lesson.unitId)!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: subject.color,
        borderRadius: BorderRadius.circular(16),
        border: Border(bottom: BorderSide(color: AppColors.darken(subject.color), width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('UP NEXT · ${subject.title.toUpperCase()}',
              style: const TextStyle(
                  color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.6)),
          const SizedBox(height: 6),
          Text(unit.title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20)),
          Text('${lessonKindLabel(lesson.kind)}: ${lesson.title}',
              style: const TextStyle(color: Colors.white, fontSize: 15)),
          const SizedBox(height: 14),
          ChunkyButton(
            label: 'Start lesson',
            color: Colors.white,
            textColor: subject.color,
            onPressed: () => LessonScreen.open(
              context,
              LessonSession.forLesson(lesson),
              accent: subject.color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SubjectCard extends StatelessWidget {
  const _SubjectCard({required this.subject});

  final Subject subject;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ProgressStore>();
    final ids = subject.lessons.map((l) => l.id).toList();
    final progress = store.completion(ids);
    final done = ids.where(store.isCompleted).length;
    return ChunkyCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SubjectScreen(subject: subject)),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: subject.color,
              borderRadius: BorderRadius.circular(14),
              border: Border(bottom: BorderSide(color: AppColors.darken(subject.color), width: 4)),
            ),
            child: Icon(subjectIcon(subject.icon), color: Colors.white, size: 32),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(subject.title,
                    style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                Text(subject.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: ProgressPill(value: progress, color: subject.color, height: 8)),
                  const SizedBox(width: 8),
                  Text('$done/${ids.length}',
                      style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                ]),
              ],
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, color: AppColors.greyDark),
        ],
      ),
    );
  }
}
