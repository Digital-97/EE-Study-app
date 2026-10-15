import 'package:flutter/material.dart';

import '../engine/step_instance.dart';
import '../lesson/lesson_screen.dart';
import '../lesson/lesson_session.dart';
import '../models/content.dart';
import '../ui/theme.dart';
import '../widgets/chunky_button.dart';
import '../widgets/circuit_diagram.dart';
import '../widgets/graph_view.dart';
import '../widgets/rich_content.dart';

/// The study material (cheat sheet) for one unit.
class UnitStudyScreen extends StatelessWidget {
  const UnitStudyScreen({super.key, required this.subject, required this.unit});

  final Subject subject;
  final Unit unit;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(unit.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Row(children: [
            Icon(Icons.menu_book_rounded, color: subject.color, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                [subject.title, if (unit.reference.isNotEmpty) unit.reference].join(' · '),
                style: context.text.labelLarge?.copyWith(color: subject.color, fontWeight: FontWeight.w800),
              ),
            ),
          ]),
          if (unit.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(unit.description, style: context.text.bodyLarge),
          ],
          const SizedBox(height: 16),
          for (var i = 0; i < unit.study.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: StudyCardView(card: unit.study[i], index: i + 1, color: subject.color),
            ),
          const SizedBox(height: 8),
          ChunkyButton(
            label: 'Practice this unit',
            icon: Icons.fitness_center_rounded,
            color: subject.color,
            onPressed: () {
              final s = LessonSession.practice('${unit.title} practice', unit.lessons);
              if (s != null) LessonScreen.open(context, s, accent: subject.color);
            },
          ),
        ],
      ),
    );
  }
}

class StudyCardView extends StatelessWidget {
  const StudyCardView({super.key, required this.card, required this.index, required this.color});

  final StudyCard card;
  final int index;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.border, width: 2),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$index', style: TextStyle(color: color, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: RichContent(card.title,
                    style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          RichContent(card.body),
          if (card.formula != null)
            Container(
              margin: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DisplayMath(card.formula!),
            ),
          if (card.plot != null) ...[
            const SizedBox(height: 12),
            GraphView(spec: card.plot!),
          ],
          if (card.circuit != null) ...[
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: CircuitDiagram(StepInstance.resolveCircuit(card.circuit!, const {})),
            ),
          ],
        ],
      ),
    );
  }
}
