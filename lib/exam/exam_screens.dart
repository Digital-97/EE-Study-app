import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../content/content_repository.dart';
import '../engine/step_instance.dart';
import '../lesson/exercises.dart';
import '../lesson/lesson_screen.dart';
import '../lesson/lesson_session.dart';
import '../lesson/worked_solution_screen.dart';
import '../models/content.dart';
import '../screens/common.dart';
import '../state/progress_store.dart';
import '../ui/theme.dart';
import '../widgets/chunky_button.dart';
import '../widgets/circuit_diagram.dart';
import '../widgets/graph_view.dart';
import '../widgets/plot_view.dart';
import '../widgets/rich_content.dart';
import 'exam_session.dart';

// ---------------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------------

class ExamSetupScreen extends StatefulWidget {
  const ExamSetupScreen({super.key});

  @override
  State<ExamSetupScreen> createState() => _ExamSetupScreenState();
}

class _ExamSetupScreenState extends State<ExamSetupScreen> {
  Set<String>? _selected;
  int _count = 20;
  bool _timed = true;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ContentRepository>();
    final level = currentLevel(context);
    final subjects = repo.subjectsFor(level);
    final selected = _selected ??= {for (final s in subjects) s.id};
    // Drop selections from another level after switching levels.
    selected.removeWhere((id) => !subjects.any((s) => s.id == id));
    final chosen = [for (final s in subjects) if (selected.contains(s.id)) s];
    final minutes = (_count * ExamSession.secondsPerQuestion / 60).round();

    return Scaffold(
      appBar: AppBar(title: const Text('Exam mode')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'A mock exam with random questions from the subjects you pick. You only see '
            'how you did at the end, with a score per unit so you know what to practise. '
            'Questions you get wrong go to your review queue.',
            style: context.text.bodyLarge,
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: Text('Subjects',
                  style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ),
            TextButton.icon(
              onPressed: () async {
                await showLevelPicker(context);
                setState(() => _selected = null);
              },
              icon: const Icon(Icons.school_rounded),
              label: Text(level.title),
            ),
          ]),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in subjects)
                FilterChip(
                  avatar: Icon(subjectIcon(s.icon), color: s.color, size: 18),
                  label: Text(s.title),
                  selected: selected.contains(s.id),
                  onSelected: (on) => setState(() => on ? selected.add(s.id) : selected.remove(s.id)),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Questions', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 10, label: Text('10')),
              ButtonSegment(value: 20, label: Text('20')),
              ButtonSegment(value: 30, label: Text('30')),
            ],
            selected: {_count},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => _count = v.first),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Timed'),
            subtitle: Text(_timed ? '$minutes minutes (1.5 min per question)' : 'No time limit'),
            value: _timed,
            onChanged: (v) => setState(() => _timed = v),
          ),
          const SizedBox(height: 16),
          ChunkyButton(
            label: 'Start exam',
            color: AppColors.blue,
            icon: Icons.assignment_rounded,
            onPressed: chosen.isEmpty
                ? null
                : () {
                    final exam = ExamSession.create(repo, chosen, count: _count, timed: _timed);
                    if (exam == null) return;
                    Navigator.of(context).pushReplacement(MaterialPageRoute(
                      fullscreenDialog: true,
                      builder: (_) => ExamScreen(exam: exam),
                    ));
                  },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Exam
// ---------------------------------------------------------------------------

class ExamScreen extends StatefulWidget {
  const ExamScreen({super.key, required this.exam});

  final ExamSession exam;

  @override
  State<ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends State<ExamScreen> {
  int _index = 0;
  ExerciseController _controller = ExerciseController();
  Timer? _timer;
  final _scroll = ScrollController();

  ExamSession get exam => widget.exam;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onController);
    if (exam.timeLimit != null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_remaining <= Duration.zero) {
          _finish();
        } else {
          setState(() {});
        }
      });
    }
  }

  Duration get _remaining =>
      exam.timeLimit == null ? Duration.zero : exam.timeLimit! - DateTime.now().difference(exam.started);

  void _onController() => setState(() {});

  void _next({bool skip = false}) {
    if (_handingIn) return;
    final q = exam.questions[_index];
    final store = context.read<ProgressStore>();
    final ok = skip ? false : _controller.check();
    if (skip) _controller.check(); // fills in the correct answer text
    q
      ..correct = ok
      ..answer = skip ? null : _controller.answerText
      ..correctAnswer = _controller.correctAnswerText;
    store.recordAnswer(q.instance.spec.key, correct: ok);
    if (_index + 1 >= exam.questions.length) {
      // Checking just disabled the exercise (e.g. a Slider); replacing the
      // route in that same frame trips a semantics assertion, so let the
      // checked state build first.
      _handingIn = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _finish();
      });
      return;
    }
    setState(() {
      _index++;
      _controller.removeListener(_onController);
      _controller.dispose();
      _controller = ExerciseController()..addListener(_onController);
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  bool _finished = false;
  bool _handingIn = false;

  void _finish() {
    if (_finished) return;
    _finished = true;
    _timer?.cancel();
    final store = context.read<ProgressStore>();
    for (final q in exam.questions.where((q) => !q.answered)) {
      q.correct = false;
    }
    final seconds = DateTime.now().difference(exam.started).inSeconds;
    store.addExam(ExamRecord(
      date: DateTime.now(),
      title: exam.title,
      correct: exam.correctCount,
      total: exam.questions.length,
      seconds: seconds,
    ));
    final xp = ProgressStore.xpFor(
      accuracy: exam.correctCount / exam.questions.length,
      questions: exam.questions.length,
    );
    store.addXp(xp);
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ExamResultScreen(exam: exam, xp: xp, seconds: seconds),
    ));
  }

  Future<void> _confirmQuit() async {
    final quit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop the exam?'),
        content: const Text('You can hand in now and see your result, or keep going.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep going')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hand in')),
        ],
      ),
    );
    if (quit == true && mounted) _finish();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = exam.questions[_index];
    final step = q.instance;
    final remaining = _remaining;
    final lowTime = exam.timeLimit != null && remaining.inSeconds < 60;
    String mmss(Duration d) =>
        '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmQuit();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
              child: Row(children: [
                IconButton(
                  onPressed: _confirmQuit,
                  icon: const Icon(Icons.close_rounded, size: 28),
                  color: AppColors.greyDark,
                  tooltip: 'Hand in',
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Question ${_index + 1} of ${exam.questions.length}',
                        style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    ProgressPill(value: _index / exam.questions.length, color: AppColors.blue),
                  ]),
                ),
                if (exam.timeLimit != null) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.timer_rounded, color: lowTime ? AppColors.red : AppColors.greyDark),
                  const SizedBox(width: 4),
                  Text(mmss(remaining.isNegative ? Duration.zero : remaining),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: lowTime ? AppColors.red : null,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      )),
                ],
              ]),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: KeyedSubtree(
                  key: ValueKey(step),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(q.unit.title.toUpperCase(),
                          style: context.text.labelLarge
                              ?.copyWith(color: AppColors.greyDark, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      RichContent(step.prompt,
                          style: context.text.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700, fontSize: 20)),
                      if (step.circuit != null && step.type != StepType.tapCircuit) ...[
                        const SizedBox(height: 12),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 240),
                          child: CircuitDiagram(step.circuit!),
                        ),
                      ],
                      if (step.spec.plot != null && step.type != StepType.slider) ...[
                        const SizedBox(height: 12),
                        GraphView(spec: step.spec.plot!, vars: step.vars),
                      ],
                      const SizedBox(height: 20),
                      ExerciseView(instance: step, controller: _controller),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration:
                  BoxDecoration(border: Border(top: BorderSide(color: context.border, width: 2))),
              child: Row(children: [
                TextButton(onPressed: () => _next(skip: true), child: const Text('SKIP')),
                const SizedBox(width: 12),
                Expanded(
                  child: ChunkyButton(
                    label: _index + 1 == exam.questions.length ? 'Hand in' : 'Next',
                    color: AppColors.blue,
                    onPressed: _controller.ready ? () => _next() : null,
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Results
// ---------------------------------------------------------------------------

class ExamResultScreen extends StatelessWidget {
  const ExamResultScreen({super.key, required this.exam, required this.xp, required this.seconds});

  final ExamSession exam;
  final int xp;
  final int seconds;

  @override
  Widget build(BuildContext context) {
    final total = exam.questions.length;
    final correct = exam.correctCount;
    final pct = (correct / total * 100).round();
    final color = pct >= 80
        ? AppColors.green
        : pct >= 55
            ? AppColors.orange
            : AppColors.red;
    final units = exam.byUnit.entries.toList()
      ..sort((a, b) {
        double score(List<ExamQuestion> qs) => qs.where((q) => q.correct == true).length / qs.length;
        return score(a.value).compareTo(score(b.value));
      });
    final verdict = pct >= 80
        ? 'Exam-ready on these topics. 🎉'
        : pct >= 55
            ? 'Passed, with room to improve. Practise the weakest units below.'
            : 'Not there yet. Start with the weakest units below.';

    return Scaffold(
      appBar: AppBar(
        title: Text(exam.title),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('DONE')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: SizedBox(
              width: 140,
              height: 140,
              child: Stack(alignment: Alignment.center, children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: correct / total,
                    strokeWidth: 12,
                    color: color,
                    backgroundColor: context.border,
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('$pct%',
                      style: context.text.headlineMedium?.copyWith(fontWeight: FontWeight.w900, color: color)),
                  Text('$correct / $total', style: context.text.bodyMedium),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Text(verdict, textAlign: TextAlign.center, style: context.text.titleMedium),
          const SizedBox(height: 4),
          Text(
            '${seconds ~/ 60} min ${seconds % 60} s · +$xp XP',
            textAlign: TextAlign.center,
            style: context.text.bodyMedium?.copyWith(color: AppColors.greyDark),
          ),
          const SizedBox(height: 20),
          Text('Per unit', style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (final MapEntry(key: unit, value: qs) in units)
            _UnitScore(unit: unit, questions: qs),
          const SizedBox(height: 20),
          Text('Your answers', style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (final (i, q) in exam.questions.indexed) _AnswerTile(number: i + 1, question: q),
        ],
      ),
    );
  }
}

class _UnitScore extends StatelessWidget {
  const _UnitScore({required this.unit, required this.questions});

  final Unit unit;
  final List<ExamQuestion> questions;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ContentRepository>();
    final subject = repo.subjects[unit.subjectId]!;
    final ok = questions.where((q) => q.correct == true).length;
    final frac = ok / questions.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ChunkyCard(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(unit.title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: ProgressPill(
                    value: frac,
                    color: frac >= 0.8 ? AppColors.green : (frac >= 0.5 ? AppColors.orange : AppColors.red),
                    height: 8,
                  ),
                ),
                const SizedBox(width: 8),
                Text('$ok/${questions.length}', style: context.text.labelMedium),
              ]),
            ]),
          ),
          IconButton(
            tooltip: 'Practise ${unit.title}',
            icon: Icon(Icons.fitness_center_rounded, color: subject.color),
            onPressed: () {
              final s = LessonSession.practice('${unit.title} practice', unit.lessons);
              if (s != null) LessonScreen.open(context, s, accent: subject.color);
            },
          ),
        ]),
      ),
    );
  }
}

class _AnswerTile extends StatelessWidget {
  const _AnswerTile({required this.number, required this.question});

  final int number;
  final ExamQuestion question;

  @override
  Widget build(BuildContext context) {
    final ok = question.correct == true;
    final step = question.instance;
    final style = context.text.bodyMedium;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: context.border, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: ok ? AppColors.green : AppColors.red),
        title: Text('Question $number · ${question.unit.title}',
            style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RichContent(step.prompt, style: style?.copyWith(fontWeight: FontWeight.w600)),
          if (step.circuit != null) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: CircuitDiagram(step.circuit!),
            ),
          ],
          if (step.spec.plot != null) ...[
            const SizedBox(height: 8),
            PlotView(step.spec.plot!.resolve(step.vars, StepInstance.fill, revealed: true)),
          ],
          const SizedBox(height: 8),
          _labelled(context, 'Your answer', question.answer ?? '(not answered)',
              ok ? AppColors.green : AppColors.red),
          if (!ok && question.correctAnswer != null)
            _labelled(context, 'Correct answer', question.correctAnswer!, AppColors.green),
          if (step.explanation != null) ...[
            const SizedBox(height: 6),
            RichContent(step.explanation!, style: style),
          ],
          if (step.hasWorkedSolution)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => WorkedSolutionScreen.open(
                  context,
                  circuit: step.circuit!,
                  report: step.workedSolution(),
                  question: step.prompt,
                ),
                icon: const Icon(Icons.functions_rounded),
                label: const Text('See worked solution'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _labelled(BuildContext context, String label, String value, Color color) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: context.text.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w800)),
          RichContent(value),
        ]),
      );
}
