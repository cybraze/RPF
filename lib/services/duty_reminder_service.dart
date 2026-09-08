import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Schedules a local "your duty time has started, please login" reminder
/// for each upcoming duty returned by /duty/list.
///
/// Notifications are keyed by deployment id, so re-scheduling on every duty
/// list refresh naturally cancels/updates stale reminders (duty time
/// changed, or the officer already logged in) without leaving duplicates.
class DutyReminderService {
  DutyReminderService._();

  static const _channelId = 'duty_reminder_channel';
  static const _channelName = 'Duty Reminders';
  static const _channelDescription =
      'Reminds you when your assigned duty time starts';
  static const _fallbackHour = 11; // duties with no start time -> 11:00 AM

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    try {
      // The app is used by India-based railway protection staff on devices
      // already set to IST, so a fixed zone is used instead of pulling the
      // device timezone name via an extra plugin.
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    } catch (_) {}

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.high,
        ),
      );
      try {
        await androidPlugin?.requestNotificationsPermission();
      } catch (_) {}
    }

    _initialized = true;
  }

  /// Reads deployment/duty_date/start_time out of a /duty/list item the same
  /// defensive way today_duty_screen.dart does, then (re)schedules or
  /// cancels its reminder.
  static Future<void> scheduleFromDutyList(List<dynamic> duties) async {
    try {
      await init();
    } catch (error) {
      debugPrint('DutyReminderService init failed: $error');
      return;
    }

    for (final raw in duties) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      await _scheduleForDuty(item);
    }
  }

  static Future<void> _scheduleForDuty(Map<String, dynamic> item) async {
    final dep = item['deployment'] as Map? ?? {};
    final ui = item['ui'] as Map? ?? {};

    final deploymentId = _readInt(dep['id'] ?? item['deployment_id']);
    if (deploymentId == null) return;
    final notificationId = _notificationIdFor(deploymentId);

    // Always cancel first: handles "duty time changed" and "officer already
    // logged in" cases without leaving a stale reminder behind.
    await _plugin.cancel(notificationId);

    final status = _readInt(ui['status'] ?? item['status']) ?? 0;
    if (status != 0) {
      return; // already logged in / duty already progressed
    }

    final reminderTime = _resolveReminderTime(item);
    if (reminderTime == null) return;

    final scheduled = tz.TZDateTime.from(reminderTime, tz.local);
    if (!scheduled.isAfter(tz.TZDateTime.now(tz.local))) {
      return; // don't fire immediately for a time that's already passed
    }

    try {
      await _plugin.zonedSchedule(
        notificationId,
        'Duty Reminder - TRINETRA',
        'Your duty time has started. Please login on TRINETRA now.',
        scheduled,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (error) {
      debugPrint('DutyReminderService schedule failed for '
          '$deploymentId: $error');
    }
  }

  /// Deployment ids are already small server-side auto-increment ints, so
  /// they double as stable, unique notification ids.
  static int _notificationIdFor(int deploymentId) => 20000 + deploymentId;

  static DateTime? _resolveReminderTime(Map<String, dynamic> item) {
    final dep = item['deployment'] as Map? ?? {};
    final dutyDateStr =
        _firstText([dep['duty_date'], item['duty_date']], fallback: '');
    final startTimeStr = _firstText(
      [dep['start_time'], item['start_time'], item['duty_start_time']],
      fallback: '',
    );

    if (startTimeStr.isNotEmpty) {
      final parsed = DateTime.tryParse(startTimeStr);
      if (parsed != null) {
        return parsed.isUtc ? parsed.toLocal() : parsed;
      }
      if (dutyDateStr.isNotEmpty) {
        final combined = DateTime.tryParse('$dutyDateStr $startTimeStr');
        if (combined != null) return combined;
      }
    }

    if (dutyDateStr.isNotEmpty) {
      final datePart = DateTime.tryParse(dutyDateStr);
      if (datePart != null) {
        return DateTime(
          datePart.year,
          datePart.month,
          datePart.day,
          _fallbackHour,
        );
      }
    }

    return null;
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static String _firstText(List<Object?> values, {String fallback = ''}) {
    for (final value in values) {
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return fallback;
  }
}
