import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../lesson/lesson_screen.dart';
import '../lesson/lesson_session.dart';
import '../models/content.dart';
import '../state/progress_store.dart';
import '../ui/theme.dart';
import '../widgets/chunky_button.dart';
import 'common.dart';
import 'unit_study_screen.dart';

/// The Duolingo-style path of units and lessons for a subject.
class SubjectScreen extends StatelessWidget {
  const SubjectScreen({super.key, required this.subject});

  final Subject subject;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ProgressStore>();
    // The first incomplete lesson is highlighted as "next".
    final nextId = subject.lessons
        .firstWhere((l) => !store.isCompleted(l.id), orElse: () => subject.lessons.first)
        .id;
    return Scaffold(
      appBar: AppBar(
        title: Text(subject.title),
        actions: const [StatsBar(), SizedBox(width: 16)],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.only(bottom: 40),
        itemCount: subject.units.length,
        itemBuilder: (context, i) => _UnitSection(
          subject: subject,
          unit: subject.units[i],
          index: i,
          nextLessonId: nextId,
        ),
      ),
    );
  }
}

class _UnitSection extends StatelessWidget {
  const _UnitSection({
    required this.subject,
    required this.unit,
    required this.index,
    required this.nextLessonId,
  });

  final Subject subject;
  final Unit unit;
  final int index;
  final String nextLessonId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ProgressStore>();
    final color = subject.color;
    final done = unit.lessons.where((l) => store.isCompleted(l.id)).length;
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
            border: Border(bottom: BorderSide(color: AppColors.darken(color), width: 4)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('UNIT ${index + 1} · $done/${unit.lessons.length}',
                        style: const TextStyle(
                            color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 12)),
                    const SizedBox(height: 2),
                    Text(unit.title,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w900, fontSize: 19)),
                    if (unit.description.isNotEmpty)
                      Text(unit.description,
                          style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => UnitStudyScreen(subject: subject, unit: unit),
                  )),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.menu_book_rounded, color: Colors.white),
                        SizedBox(height: 2),
                        Text('STUDY',
                            style: TextStyle(
                                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < unit.lessons.length; i++)
          _LessonNode(
            lesson: unit.lessons[i],
            color: color,
            // Zig-zag offset like a winding path.
            offset: math.sin((i + index) * 1.1) * 70,
            isNext: unit.lessons[i].id == nextLessonId,
            completed: store.isCompleted(unit.lessons[i].id),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _LessonNode extends StatelessWidget {
  const _LessonNode({
    required this.lesson,
    required this.color,
    required this.offset,
    required this.isNext,
    required this.completed,
  });

  final Lesson lesson;
  final Color color;
  final double offset;
  final bool isNext;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final active = completed || isNext;
    final face = completed
        ? AppColors.gold
        : isNext
            ? color
            : (context.isDark ? const Color(0xFF37464F) : AppColors.grey);
    final edge = active ? AppColors.darken(face) : AppColors.darken(face, 0.12);
    final iconColor = active ? Colors.white : AppColors.greyDark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Transform.translate(
        offset: Offset(offset, 0),
        child: Column(
          children: [
            if (isNext)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.border, width: 2),
                ),
                child: Text(completed ? 'AGAIN' : 'START',
                    style: TextStyle(color: color, fontWeight: FontWeight.w900)),
              ),
            Semantics(
              button: true,
              label: '${lessonKindLabel(lesson.kind)}: ${lesson.title}',
              child: GestureDetector(
                onTap: () => _showLessonSheet(context),
                child: Container(
                  width: 74,
                  height: 70,
                  decoration: BoxDecoration(
                    color: face,
                    shape: BoxShape.circle,
                    border: Border(bottom: BorderSide(color: edge, width: 7)),
                    boxShadow: isNext
                        ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 0, spreadRadius: 6)]
                        : null,
                  ),
                  child: Icon(
                    completed ? Icons.check_rounded : lessonIcon(lesson.kind),
                    color: iconColor,
                    size: 34,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 140,
              child: Text(
                lesson.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLessonSheet(BuildContext context) {
    final record = context.read<ProgressStore>().lesson(lesson.id);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Icon(lessonIcon(lesson.kind), color: color),
                const SizedBox(width: 8),
                Text(lessonKindLabel(lesson.kind).toUpperCase(),
                    style: TextStyle(color: color, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 6),
              Text(lesson.title,
                  style: ctx.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('${lesson.questionCount} questions · about ${math.max(2, (lesson.steps.length * 0.5).round())} min',
                  style: ctx.text.bodyMedium),
              if (record != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Completed ${record.completions}× · best ${(record.bestAccuracy * 100).round()}%',
                  style: ctx.text.bodyMedium?.copyWith(color: AppColors.greenDark, fontWeight: FontWeight.w700),
                ),
              ],
              const SizedBox(height: 18),
              ChunkyButton(
                label: record == null ? 'Start' : 'Practice again',
                color: color,
                onPressed: () {
                  Navigator.pop(ctx);
                  LessonScreen.open(context, LessonSession.forLesson(lesson), accent: color);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
