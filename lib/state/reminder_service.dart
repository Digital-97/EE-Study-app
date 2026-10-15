import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'progress_store.dart';

/// Schedules the daily study reminder (Android only).
///
/// Reminders are scheduled one by one for the coming days instead of as a
/// repeating notification, so today's reminder can be skipped once you have
/// already studied today. The schedule is refreshed whenever progress or the
/// reminder settings change.
class ReminderService {
  ReminderService(this._store);

  final ProgressStore _store;
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  String? _scheduledFor;

  static const _daysAhead = 10;
  static const _channel = AndroidNotificationDetails(
    'daily_reminder',
    'Daily reminder',
    channelDescription: 'A daily nudge to keep your study streak going',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    icon: 'ic_notification',
  );

  static bool get supported => !kIsWeb && Platform.isAndroid;

  Future<void> init() async {
    if (!supported) return;
    try {
      tzdata.initializeTimeZones();
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_notification'),
        ),
      );
      _ready = true;
      _store.addListener(_sync);
      await _sync();
    } catch (e) {
      debugPrint('Reminders unavailable: $e');
    }
  }

  /// Asks for notification permission (Android 13+). Returns whether granted.
  Future<bool> requestPermission() async {
    if (!supported) return false;
    final android =
        _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? true;
  }

  Future<void> _sync() async {
    if (!_ready) return;
    final now = tz.TZDateTime.now(tz.local);
    final studiedToday = _store.todayXp > 0;
    // Only reschedule when something relevant changed.
    final signature = [
      _store.reminderEnabled,
      _store.reminderMinutes,
      dayKey(now),
      studiedToday,
      _store.streak,
    ].join('|');
    if (signature == _scheduledFor) return;
    _scheduledFor = signature;

    try {
      await _plugin.cancelAll();
      if (!_store.reminderEnabled) return;
      final hour = _store.reminderMinutes ~/ 60;
      final minute = _store.reminderMinutes % 60;
      for (var i = 0; i < _daysAhead; i++) {
        final at = tz.TZDateTime(tz.local, now.year, now.month, now.day + i, hour, minute);
        if (!at.isAfter(now)) continue;
        if (i == 0 && studiedToday) continue;
        final (title, body) = _message(i);
        await _plugin.zonedSchedule(
          id: i,
          scheduledDate: at,
          title: title,
          body: body,
          notificationDetails: const NotificationDetails(android: _channel),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (e) {
      debugPrint('Could not schedule reminders: $e');
    }
  }

  (String, String) _message(int daysFromNow) {
    final streak = _store.streak;
    if (daysFromNow == 0 && streak > 0) {
      return (
        'Keep your $streak-day streak going 🔥',
        "You haven't studied today yet. A 3-minute lesson is enough.",
      );
    }
    final due = _store.dueReviewCount;
    if (daysFromNow == 0 && due > 0) {
      return ('Time to review ⚡', '$due question${due == 1 ? ' is' : 's are'} waiting for review.');
    }
    const tips = [
      ('Time for a quick lesson ⚡', 'Five minutes of circuits a day adds up fast.'),
      ('Your study streak is waiting 🔥', 'Open EE Study for a short lesson.'),
      ('Ready for a Circuit Lab problem? 🔌', 'New values every time. Can you find V_R3?'),
    ];
    return tips[daysFromNow % tips.length];
  }
}
