import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/progress_store.dart';
import '../ui/theme.dart';
import '../widgets/chunky_button.dart';
import 'lesson_session.dart';

class LessonCompleteScreen extends StatelessWidget {
  const LessonCompleteScreen({super.key, required this.session, required this.xpEarned});

  final LessonSession session;
  final int xpEarned;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ProgressStore>();
    final elapsed = DateTime.now().difference(session.started);
    final mm = elapsed.inMinutes;
    final ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    final pct = (session.accuracy * 100).round();
    final perfect = pct == 100;
    final title = switch (session.kind) {
      SessionKind.lesson => perfect ? 'Perfect lesson!' : 'Lesson complete!',
      SessionKind.review => 'Review complete!',
      SessionKind.practice => 'Practice complete!',
    };
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.4, end: 1),
                duration: const Duration(milliseconds: 600),
                curve: Curves.elasticOut,
                builder: (_, v, child) => Transform.scale(scale: v, child: child),
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    color: (perfect ? AppColors.gold : AppColors.green).withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    perfect ? Icons.emoji_events_rounded : Icons.bolt_rounded,
                    size: 80,
                    color: perfect ? AppColors.gold : AppColors.green,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(title,
                  textAlign: TextAlign.center,
                  style: context.text.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: perfect ? AppColors.orange : AppColors.greenDark,
                  )),
              const SizedBox(height: 6),
              Text(session.title, style: context.text.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 28),
              Row(
                children: [
                  _Stat(label: 'TOTAL XP', value: '+$xpEarned', color: AppColors.gold, icon: Icons.bolt_rounded),
                  const SizedBox(width: 10),
                  _Stat(
                    label: 'ACCURACY',
                    value: '$pct%',
                    color: AppColors.green,
                    icon: Icons.track_changes_rounded,
                  ),
                  const SizedBox(width: 10),
                  _Stat(label: 'TIME', value: '$mm:$ss', color: AppColors.blue, icon: Icons.timer_rounded),
                ],
              ),
              const SizedBox(height: 20),
              if (store.streak > 0)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.local_fire_department_rounded, color: AppColors.orange),
                    const SizedBox(width: 6),
                    Text('${store.streak} day streak',
                        style: context.text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800, color: AppColors.orange)),
                  ],
                ),
              if (session.mistakes > 0) ...[
                const SizedBox(height: 10),
                Text(
                  '${session.mistakes} question${session.mistakes == 1 ? '' : 's'} added to your review queue.',
                  textAlign: TextAlign.center,
                  style: context.text.bodyMedium?.copyWith(color: AppColors.greyDark),
                ),
              ],
              const Spacer(),
              ChunkyButton(label: 'Continue', onPressed: () => Navigator.of(context).pop()),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color, required this.icon});

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.all(2),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(label,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 4),
                  Text(value,
                      style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 18)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
