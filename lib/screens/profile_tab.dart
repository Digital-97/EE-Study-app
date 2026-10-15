import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../content/content_repository.dart';
import '../state/backup_actions.dart';
import '../state/progress_store.dart';
import '../state/reminder_service.dart';
import '../ui/theme.dart';
import 'common.dart';

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ProgressStore>();
    final repo = context.read<ContentRepository>();
    final totalLessons = repo.subjects.values.fold<int>(0, (s, x) => s + x.lessons.length);
    final accuracy = store.questionsAnswered == 0
        ? '–'
        : '${(store.questionsCorrect / store.questionsAnswered * 100).round()}%';
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Statistics', style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.2,
            children: [
              _StatTile(Icons.local_fire_department_rounded, AppColors.orange, '${store.streak}', 'Day streak'),
              _StatTile(Icons.bolt_rounded, AppColors.gold, '${store.xp}', 'Total XP'),
              _StatTile(Icons.check_circle_rounded, AppColors.green, '${store.lessonsCompleted}/$totalLessons',
                  'Lessons done'),
              _StatTile(Icons.track_changes_rounded, AppColors.blue, accuracy, 'Accuracy'),
              _StatTile(Icons.military_tech_rounded, AppColors.orange, '${store.longestStreak}', 'Longest streak'),
              _StatTile(Icons.quiz_rounded, AppColors.blue, '${store.questionsAnswered}', 'Questions answered'),
            ],
          ),
          const SizedBox(height: 20),
          Text('This week', style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          ChunkyCard(child: _WeekChart(xpByDay: store.xpByDay, goal: store.dailyGoal)),
          const SizedBox(height: 20),
          Text('Settings', style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          ChunkyCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Daily goal', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 20, label: Text('Casual')),
                    ButtonSegment(value: 30, label: Text('Regular')),
                    ButtonSegment(value: 50, label: Text('Serious')),
                    ButtonSegment(value: 80, label: Text('Intense')),
                  ],
                  selected: {store.dailyGoal},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => store.dailyGoal = v.first,
                ),
                const SizedBox(height: 4),
                Text('${store.dailyGoal} XP per day', style: context.text.bodySmall),
                const SizedBox(height: 8),
                const Divider(),
                const _ReminderTile(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.school_rounded),
                  title: const Text('Level'),
                  subtitle: Text(currentLevel(context).title),
                  onTap: () => showLevelPicker(context),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_forever_rounded, color: AppColors.red),
                  title: const Text('Reset progress'),
                  onTap: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Reset all progress?'),
                        content: const Text('This deletes your XP, streak, completed lessons and review list.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
                        ],
                      ),
                    );
                    if (ok == true) await store.reset();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Backup', style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            'Progress is stored on this phone only. Save a backup to move it to a new phone '
            'or to keep it safe when reinstalling.',
            style: context.text.bodyMedium,
          ),
          const SizedBox(height: 10),
          ChunkyCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.save_alt_rounded),
                title: const Text('Save backup to a file'),
                onTap: () => BackupActions(context, store).saveToFile(),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.share_rounded),
                title: const Text('Share backup'),
                subtitle: const Text('Send it to Google Drive, mail or a chat'),
                onTap: () => BackupActions(context, store).share(),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.restore_rounded),
                title: const Text('Restore from backup'),
                onTap: () => BackupActions(context, store).restore(),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          Text(
            'Content follows Hambley, Electrical Engineering: Principles and Applications; '
            'Phillips, Parr & Riskin, Signals, Systems, and Transforms; '
            'Horowitz & Hill, The Art of Electronics; '
            'Ott, Electromagnetic Compatibility Engineering; and '
            'Frenzel, Principles of Electronic Communication Systems.',
            textAlign: TextAlign.center,
            style: context.text.bodySmall?.copyWith(color: AppColors.greyDark),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile(this.icon, this.color, this.value, this.label);

  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ChunkyCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                child: Text(value, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              ),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
            ],
          ),
        ),
      ]),
    );
  }
}

class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.xpByDay, required this.goal});

  final Map<String, int> xpByDay;
  final int goal;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final days = [for (var i = 6; i >= 0; i--) DateTime(today.year, today.month, today.day - i)];
    final values = [for (final d in days) xpByDay[dayKey(d)] ?? 0];
    final maxV = math.max(goal, values.fold<int>(0, math.max)).toDouble();
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('${values[i]}', style: context.text.labelSmall),
                    const SizedBox(height: 4),
                    Container(
                      height: 100 * values[i] / maxV + 4,
                      decoration: BoxDecoration(
                        color: values[i] >= goal ? AppColors.gold : AppColors.orange.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(names[days[i].weekday - 1],
                        style: context.text.labelSmall?.copyWith(
                          fontWeight: i == 6 ? FontWeight.w900 : FontWeight.w500,
                        )),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Daily reminder on/off switch and time.
class _ReminderTile extends StatelessWidget {
  const _ReminderTile();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ProgressStore>();
    final service = context.read<ReminderService?>();
    final time = TimeOfDay(hour: store.reminderMinutes ~/ 60, minute: store.reminderMinutes % 60);
    final supported = ReminderService.supported && service != null;
    return Column(children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        secondary: const Icon(Icons.notifications_active_rounded),
        title: const Text('Daily reminder'),
        subtitle: Text(!supported
            ? 'Available in the Android app'
            : store.reminderEnabled
                ? 'Every day at ${time.format(context)}, unless you already studied'
                : 'Off'),
        value: store.reminderEnabled,
        onChanged: !supported
            ? null
            : (on) async {
                if (on && !await service.requestPermission()) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Allow notifications for EE Study in Android settings first.'),
                    ));
                  }
                  return;
                }
                store.setReminder(enabled: on);
              },
      ),
      if (supported && store.reminderEnabled)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule_rounded),
          title: const Text('Reminder time'),
          trailing: Text(time.format(context),
              style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          onTap: () async {
            final picked = await showTimePicker(context: context, initialTime: time);
            if (picked != null) {
              store.setReminder(enabled: true, minutes: picked.hour * 60 + picked.minute);
            }
          },
        ),
    ]);
  }
}
