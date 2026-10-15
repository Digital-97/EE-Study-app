import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../engine/step_instance.dart';
import '../models/content.dart';
import '../state/progress_store.dart';
import '../ui/theme.dart';
import '../widgets/chunky_button.dart';
import '../widgets/circuit_diagram.dart';
import '../widgets/graph_view.dart';
import '../widgets/rich_content.dart';
import 'exercises.dart';
import 'lesson_complete_screen.dart';
import 'lesson_session.dart';
import 'worked_solution_screen.dart';

class LessonScreen extends StatefulWidget {
  const LessonScreen({super.key, required this.session, this.accent = AppColors.green});

  final LessonSession session;
  final Color accent;

  static Future<void> open(BuildContext context, LessonSession session, {Color? accent}) {
    return Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => LessonScreen(session: session, accent: accent ?? AppColors.green),
    ));
  }

  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  LessonSession get session => widget.session;
  ExerciseController _controller = ExerciseController();
  bool _showHint = false;
  final _scroll = ScrollController();
  final _random = math.Random();

  static const _praise = ['Nice!', 'Correct!', 'Great job!', 'Excellent!', 'You got it!', 'Spot on!'];
  static const _encourage = ['Not quite', 'Almost…', 'Incorrect', 'Keep going'];
  late String _feedbackTitle;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onController);
  }

  void _onController() => setState(() {});

  void _check() {
    final ok = _controller.check();
    ok ? HapticFeedback.mediumImpact() : HapticFeedback.heavyImpact();
    _feedbackTitle = ok
        ? _praise[_random.nextInt(_praise.length)]
        : _encourage[_random.nextInt(_encourage.length)];
  }

  void _continue() {
    final store = context.read<ProgressStore>();
    final step = session.current!;
    if (step.type == StepType.info) {
      session.next();
    } else {
      session.answer(_controller.result ?? false, store);
    }
    if (session.finished) {
      _finish();
      return;
    }
    setState(() {
      _controller.removeListener(_onController);
      _controller.dispose();
      _controller = ExerciseController()..addListener(_onController);
      _showHint = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _finish() {
    final store = context.read<ProgressStore>();
    final int xp;
    if (session.lesson != null) {
      xp = store.completeLesson(
        session.lesson!.id,
        accuracy: session.accuracy,
        questions: session.totalQuestions,
      );
    } else {
      xp = ProgressStore.xpFor(accuracy: session.accuracy, questions: session.totalQuestions);
      store.addXp(xp);
    }
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => LessonCompleteScreen(session: session, xpEarned: xp),
    ));
  }

  Future<void> _confirmQuit() async {
    final quit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quit this lesson?'),
        content: const Text('Your progress in this lesson will be lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep learning')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Quit')),
        ],
      ),
    );
    if (quit == true && mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final step = session.current;
    if (step == null) return const Scaffold();
    final isInfo = step.type == StepType.info;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmQuit();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _TopBar(progress: session.progress, onClose: _confirmQuit, color: widget.accent),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween(begin: const Offset(0.08, 0), end: Offset.zero)
                            .animate(anim),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(
                      key: ValueKey(step),
                      child: isInfo ? _InfoStep(step: step) : _questionBody(step),
                    ),
                  ),
                ),
              ),
              _bottom(step),
            ],
          ),
        ),
      ),
    );
  }

  Widget _questionBody(StepInstance step) {
    final circuit = step.circuit;
    final hint = step.hint;
    final retry = !session.isFirstTry(step);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (retry)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              const Icon(Icons.replay_rounded, color: AppColors.orange, size: 18),
              const SizedBox(width: 6),
              Text('PREVIOUS MISTAKE',
                  style: context.text.labelMedium
                      ?.copyWith(color: AppColors.orange, fontWeight: FontWeight.w800)),
            ]),
          ),
        Text(_typeLabel(step.type),
            style: context.text.labelLarge
                ?.copyWith(color: AppColors.greyDark, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        RichContent(step.prompt,
            style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 20)),
        if (circuit != null && step.type != StepType.tapCircuit) ...[
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: CircuitDiagram(circuit),
          ),
        ],
        if (step.spec.plot != null && step.type != StepType.slider) ...[
          const SizedBox(height: 12),
          GraphView(spec: step.spec.plot!, vars: step.vars),
        ],
        if (hint != null && !_controller.checked) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: _showHint
                ? Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: RichContent('💡 $hint'),
                  )
                : TextButton.icon(
                    onPressed: () => setState(() => _showHint = true),
                    icon: const Icon(Icons.lightbulb_outline_rounded),
                    label: const Text('Show hint'),
                  ),
          ),
        ],
        const SizedBox(height: 20),
        ExerciseView(instance: step, controller: _controller),
      ],
    );
  }

  String _typeLabel(StepType t) => switch (t) {
        StepType.multipleChoice => 'SELECT THE CORRECT ANSWER',
        StepType.trueFalse => 'TRUE OR FALSE?',
        StepType.numeric => 'CALCULATE',
        StepType.matchPairs => 'MATCH THE PAIRS',
        StepType.orderSteps => 'PUT IN ORDER',
        StepType.tapCircuit => 'TAP THE SCHEMATIC',
        StepType.slider => 'ADJUST THE GRAPH',
        StepType.info => '',
      };

  Widget _bottom(StepInstance step) {
    if (step.type == StepType.info) {
      return _BottomBar(
        child: ChunkyButton(label: 'Continue', color: widget.accent, onPressed: _continue),
      );
    }
    if (!_controller.checked) {
      return _BottomBar(
        child: ChunkyButton(
          label: 'Check',
          color: AppColors.green,
          onPressed: _controller.ready ? _check : null,
        ),
      );
    }
    final ok = _controller.result!;
    return _FeedbackPanel(
      correct: ok,
      title: _feedbackTitle,
      correctAnswer: ok ? null : _controller.correctAnswerText,
      explanation: step.explanation,
      onContinue: _continue,
      onWorkedSolution: step.hasWorkedSolution
          ? () => WorkedSolutionScreen.open(
                context,
                circuit: step.circuit!,
                report: step.workedSolution(),
                question: step.prompt,
              )
          : null,
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.progress, required this.onClose, required this.color});

  final double progress;
  final VoidCallback onClose;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 20, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, size: 28),
            color: AppColors.greyDark,
            tooltip: 'Quit',
          ),
          Expanded(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: progress),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(children: [
                  Container(height: 16, color: context.border),
                  FractionallySizedBox(
                    widthFactor: v.clamp(0.0, 1.0),
                    child: Container(
                      height: 16,
                      decoration: BoxDecoration(
                        color: AppColors.green,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.topCenter,
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: context.border, width: 2))),
      child: child,
    );
  }
}

class _FeedbackPanel extends StatelessWidget {
  const _FeedbackPanel({
    required this.correct,
    required this.title,
    required this.correctAnswer,
    required this.explanation,
    required this.onContinue,
    this.onWorkedSolution,
  });

  final bool correct;
  final String title;
  final String? correctAnswer;
  final String? explanation;
  final VoidCallback onContinue;
  final VoidCallback? onWorkedSolution;

  @override
  Widget build(BuildContext context) {
    final color = correct ? AppColors.green : AppColors.red;
    final fg = correct ? AppColors.greenDark : AppColors.redDark;
    final bg = context.isDark
        ? const Color(0xFF202F36)
        : (correct ? const Color(0xFFD7FFB8) : const Color(0xFFFFDFE0));
    final style = context.text.bodyMedium?.copyWith(
      color: context.isDark ? Colors.white70 : fg,
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 0),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      builder: (context, v, child) => Transform.translate(offset: Offset(0, 60 * v), child: child),
      child: Container(
        width: double.infinity,
        color: bg,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Icon(correct ? Icons.check_circle_rounded : Icons.cancel_rounded, color: color, size: 30),
              const SizedBox(width: 10),
              Text(title,
                  style: context.text.titleLarge
                      ?.copyWith(color: context.isDark ? color : fg, fontWeight: FontWeight.w800)),
            ]),
            if (correctAnswer != null || explanation != null)
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.3),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (correctAnswer != null) ...[
                        Text('Correct answer:',
                            style: style?.copyWith(fontWeight: FontWeight.w800)),
                        RichContent(correctAnswer!, style: style),
                        const SizedBox(height: 8),
                      ],
                      if (explanation != null) RichContent(explanation!, style: style),
                    ],
                  ),
                ),
              ),
            if (onWorkedSolution != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onWorkedSolution,
                  icon: Icon(Icons.functions_rounded, color: fg),
                  label: Text('See worked solution',
                      style: TextStyle(color: context.isDark ? Colors.white : fg, fontWeight: FontWeight.w800)),
                ),
              ),
            const SizedBox(height: 12),
            ChunkyButton(
              label: correct ? 'Continue' : 'Got it',
              color: color,
              onPressed: onContinue,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoStep extends StatelessWidget {
  const _InfoStep({required this.step});

  final StepInstance step;

  @override
  Widget build(BuildContext context) {
    final formula = step.formula;
    final circuit = step.circuit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          const Icon(Icons.auto_stories_rounded, color: AppColors.blue),
          const SizedBox(width: 8),
          Text('NEW CONCEPT',
              style: context.text.labelLarge
                  ?.copyWith(color: AppColors.blue, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 10),
        RichContent(step.title,
            style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        RichContent(step.body, style: context.text.bodyLarge?.copyWith(fontSize: 17)),
        if (formula != null)
          Container(
            margin: const EdgeInsets.only(top: 16),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.border, width: 2),
            ),
            child: DisplayMath(formula),
          ),
        if (circuit != null) ...[
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: CircuitDiagram(circuit),
          ),
        ],
        if (step.spec.plot != null) ...[
          const SizedBox(height: 16),
          GraphView(spec: step.spec.plot!, vars: step.vars),
        ],
      ],
    );
  }
}
