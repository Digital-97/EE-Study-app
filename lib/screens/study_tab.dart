import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../content/content_repository.dart';
import '../models/content.dart';
import '../ui/theme.dart';
import 'common.dart';
import 'unit_study_screen.dart';

/// Study material overview: all units of the selected level, grouped by subject.
class StudyTab extends StatelessWidget {
  const StudyTab({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ContentRepository>();
    final level = currentLevel(context);
    final subjects = repo.subjectsFor(level);
    return DefaultTabController(
      length: subjects.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Study material'),
          actions: [
            TextButton.icon(
              onPressed: () => showLevelPicker(context),
              icon: const Icon(Icons.school_rounded),
              label: Text(level.title),
            ),
            const SizedBox(width: 8),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelStyle: const TextStyle(fontWeight: FontWeight.w800),
            tabs: [for (final s in subjects) Tab(text: s.title)],
          ),
        ),
        body: TabBarView(
          children: [for (final s in subjects) _SubjectStudyList(subject: s)],
        ),
      ),
    );
  }
}

class _SubjectStudyList extends StatelessWidget {
  const _SubjectStudyList({required this.subject});

  final Subject subject;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (subject.reference.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('Textbook: ${subject.reference}',
                style: context.text.bodyMedium?.copyWith(color: AppColors.greyDark)),
          ),
        for (var i = 0; i < subject.units.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ChunkyCard(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => UnitStudyScreen(subject: subject, unit: subject.units[i]),
              )),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: subject.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${i + 1}',
                        style: TextStyle(color: subject.color, fontWeight: FontWeight.w900, fontSize: 18)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(subject.units[i].title,
                            style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        Text(
                          [
                            '${subject.units[i].study.length} cards',
                            if (subject.units[i].reference.isNotEmpty) subject.units[i].reference,
                          ].join(' · '),
                          style: context.text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.greyDark),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
