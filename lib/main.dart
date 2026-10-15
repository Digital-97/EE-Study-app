import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'content/content_repository.dart';
import 'screens/learn_tab.dart';
import 'screens/practice_tab.dart';
import 'screens/profile_tab.dart';
import 'screens/study_tab.dart';
import 'state/progress_store.dart';
import 'state/reminder_service.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final results = await Future.wait([ContentRepository.load(), ProgressStore.load()]);
  final progress = results[1] as ProgressStore;
  final reminders = ReminderService(progress);
  runApp(EeStudyApp(
    content: results[0] as ContentRepository,
    progress: progress,
    reminders: reminders,
  ));
  // Scheduling needs the platform channels, so start it after runApp.
  reminders.init();
}

class EeStudyApp extends StatelessWidget {
  const EeStudyApp({super.key, required this.content, required this.progress, this.reminders});

  final ContentRepository content;
  final ProgressStore progress;
  final ReminderService? reminders;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider.value(value: content),
        ChangeNotifierProvider.value(value: progress),
        Provider<ReminderService?>.value(value: reminders),
      ],
      child: MaterialApp(
        title: 'EE Study',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: const HomeShell(),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final reviewCount = context.watch<ProgressStore>().dueReviewCount;
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [LearnTab(), StudyTab(), PracticeTab(), ProfileTab()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Learn',
          ),
          const NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book_rounded),
            label: 'Study',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: reviewCount > 0,
              label: Text('$reviewCount'),
              child: const Icon(Icons.fitness_center_outlined),
            ),
            selectedIcon: const Icon(Icons.fitness_center_rounded),
            label: 'Practice',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
