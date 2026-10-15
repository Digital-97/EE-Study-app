import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../content/content_repository.dart';
import '../models/content.dart';
import '../state/progress_store.dart';
import '../ui/theme.dart';

IconData subjectIcon(String name) => switch (name) {
      'bolt' => Icons.bolt_rounded,
      'memory' => Icons.memory_rounded,
      'timeline' => Icons.timeline_rounded,
      'waves' => Icons.waves_rounded,
      'developer_board' => Icons.developer_board_rounded,
      'settings_input_component' => Icons.settings_input_component_rounded,
      'show_chart' => Icons.show_chart_rounded,
      'electrical_services' => Icons.electrical_services_rounded,
      'calculate' => Icons.calculate_rounded,
      'tune' => Icons.tune_rounded,
      'graphic_eq' => Icons.graphic_eq_rounded,
      'functions' => Icons.functions_rounded,
      'flare' => Icons.flare_rounded,
      'cable' => Icons.cable_rounded,
      'code' => Icons.code_rounded,
      'speed' => Icons.speed_rounded,
      'sensors' => Icons.sensors_rounded,
      'bar_chart' => Icons.bar_chart_rounded,
      'speaker' => Icons.speaker_rounded,
      'shield' => Icons.shield_rounded,
      'cell_tower' => Icons.cell_tower_rounded,
      'power' => Icons.power_rounded,
      'equalizer' => Icons.equalizer_rounded,
      'account_tree' => Icons.account_tree_rounded,
      'casino' => Icons.casino_rounded,
      'electric_meter' => Icons.electric_meter_rounded,
      'settings_input_antenna' => Icons.settings_input_antenna_rounded,
      'grain' => Icons.grain_rounded,
      'data_object' => Icons.data_object_rounded,
      _ => Icons.school_rounded,
    };

IconData lessonIcon(LessonKind kind) => switch (kind) {
      LessonKind.learn => Icons.auto_stories_rounded,
      LessonKind.practice => Icons.fitness_center_rounded,
      LessonKind.challenge => Icons.emoji_events_rounded,
    };

String lessonKindLabel(LessonKind kind) => switch (kind) {
      LessonKind.learn => 'Learn',
      LessonKind.practice => 'Practice',
      LessonKind.challenge => 'Challenge',
    };

/// Returns the level currently selected by the user (or the first).
Level currentLevel(BuildContext context) {
  final repo = context.read<ContentRepository>();
  final id = context.watch<ProgressStore>().lastLevelId;
  return repo.levels.firstWhere((l) => l.id == id, orElse: () => repo.levels.first);
}

/// Streak / XP / review counters shown in the top bar.
class StatsBar extends StatelessWidget {
  const StatsBar({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ProgressStore>();
    final streak = store.streak;
    final doneToday = store.todayXp > 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Counter(
          icon: Icons.local_fire_department_rounded,
          color: doneToday ? AppColors.orange : AppColors.greyDark,
          value: '$streak',
          tooltip: '$streak day streak',
        ),
        const SizedBox(width: 14),
        _Counter(
          icon: Icons.bolt_rounded,
          color: AppColors.gold,
          value: '${store.xp}',
          tooltip: '${store.xp} XP total',
        ),
      ],
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({required this.icon, required this.color, required this.value, required this.tooltip});

  final IconData icon;
  final Color color;
  final String value;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Row(children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 2),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 16)),
      ]),
    );
  }
}

/// A rounded progress bar.
class ProgressPill extends StatelessWidget {
  const ProgressPill({super.key, required this.value, required this.color, this.height = 10});

  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Stack(children: [
        Container(height: height, color: context.border),
        FractionallySizedBox(
          widthFactor: value.clamp(0.0, 1.0),
          child: Container(height: height, color: color),
        ),
      ]),
    );
  }
}

/// A bordered card with a chunky bottom edge, used for lists.
class ChunkyCard extends StatelessWidget {
  const ChunkyCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border(
              top: BorderSide(color: context.border, width: 2),
              left: BorderSide(color: context.border, width: 2),
              right: BorderSide(color: context.border, width: 2),
              bottom: BorderSide(color: context.border, width: 4),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Bottom sheet to switch between levels.
Future<void> showLevelPicker(BuildContext context) {
  final repo = context.read<ContentRepository>();
  final store = context.read<ProgressStore>();
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    // Let the sheet grow past the default 9/16 height cap; the level list
    // scrolls when it still doesn't fit.
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Choose your level',
                style: ctx.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final level in repo.levels)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _LevelOption(
                          level: level,
                          selected: level.id == (store.lastLevelId ?? repo.levels.first.id),
                          progress: store.completion(repo
                              .subjectsFor(level)
                              .expand((s) => s.lessons)
                              .map((l) => l.id)),
                          onTap: () {
                            store.lastLevelId = level.id;
                            Navigator.pop(ctx);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _LevelOption extends StatelessWidget {
  const _LevelOption({
    required this.level,
    required this.selected,
    required this.progress,
    required this.onTap,
  });

  final Level level;
  final bool selected;
  final double progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChunkyCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: (selected ? AppColors.blue : AppColors.greyDark).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.school_rounded, color: selected ? AppColors.blue : AppColors.greyDark),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(level.title,
                    style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                Text(level.subtitle, style: context.text.bodyMedium),
                const SizedBox(height: 8),
                ProgressPill(value: progress, color: AppColors.blue, height: 8),
              ],
            ),
          ),
          if (selected) ...[
            const SizedBox(width: 10),
            const Icon(Icons.check_circle_rounded, color: AppColors.blue),
          ],
        ],
      ),
    );
  }
}
