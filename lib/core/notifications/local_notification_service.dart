import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../financial_engine/alert_evaluation_engine.dart';

/// Platform-agnostic notification channel constants.
abstract final class NotificationChannels {
  static const String budgetAlerts = 'pocket_cfo_budget_alerts';
  static const String accountAlerts = 'pocket_cfo_account_alerts';
  static const String milestones = 'pocket_cfo_milestones';
  static const String reminders = 'pocket_cfo_reminders';
  static const int dailyReminderId = 990001;
}

/// Recorded dispatch entry used by [InMemoryNotificationDispatcher] in tests.
@immutable
final class DispatchedNotificationRecord {
  const DispatchedNotificationRecord({
    required this.id,
    required this.channelId,
    required this.title,
    required this.body,
    required this.severity,
    this.payloadRoute,
  });

  final int id;
  final String channelId;
  final String title;
  final String body;
  final AlertSeverity severity;
  final String? payloadRoute;
}

/// Testable interface decoupling financial alert orchestration from OS plugin channels.
abstract interface class DeviceNotificationDispatcher {
  Future<void> initialize({required void Function(String? route) onTap});

  Future<bool> requestPermission();

  Future<void> showNotification({
    required int id,
    required String channelId,
    required String title,
    required String body,
    required AlertSeverity severity,
    String? payloadRoute,
  });

  Future<void> scheduleDailyReminder({
    required bool enabled,
    required int hour,
    required int minute,
  });

  Future<void> scheduleOneShotReminder({
    required int id,
    required String title,
    required String body,
    required DateTime atUtc,
    String? payloadRoute,
  });

  Future<void> cancelScheduledReminder(int id);

  Future<void> cancelAll();
}

/// Production OS local notification dispatcher powered by `flutter_local_notifications`.
final class FlutterLocalNotificationDispatcher
    implements DeviceNotificationDispatcher {
  FlutterLocalNotificationDispatcher({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
  bool _tzInitialized = false;

  void _ensureTimeZone() {
    if (_tzInitialized) return;
    tz_data.initializeTimeZones();
    _tzInitialized = true;
  }

  @override
  Future<void> initialize({required void Function(String? route) onTap}) async {
    if (_initialized || kIsWeb) return;
    try {
      const androidInit = AndroidInitializationSettings('ic_stat_pocket_cfo');
      const darwinInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const linuxInit = LinuxInitializationSettings(
        defaultActionName: 'Open Pocket CFO',
      );
      const settings = InitializationSettings(
        android: androidInit,
        iOS: darwinInit,
        macOS: darwinInit,
        linux: linuxInit,
      );

      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: (resp) {
          onTap(resp.payload);
        },
      );

      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        if (android != null) {
          await android.createNotificationChannel(
            const AndroidNotificationChannel(
              NotificationChannels.budgetAlerts,
              'Budget & Limit Alerts',
              description:
                  'Heads-up warnings when spending approaches or crosses a budget limit.',
              importance: Importance.high,
            ),
          );
          await android.createNotificationChannel(
            const AndroidNotificationChannel(
              NotificationChannels.accountAlerts,
              'Account & Balance Alerts',
              description:
                  'Alerts when liquid accounts drop below your safety floor.',
              importance: Importance.defaultImportance,
            ),
          );
          await android.createNotificationChannel(
            const AndroidNotificationChannel(
              NotificationChannels.milestones,
              'Savings Milestones',
              description: 'Celebrations when savings goals pass 50% or 100%.',
              importance: Importance.defaultImportance,
            ),
          );
          await android.createNotificationChannel(
            const AndroidNotificationChannel(
              NotificationChannels.reminders,
              'Daily Expense Reminders',
              description: 'Optional daily check-in reminder to log expenses.',
              importance: Importance.defaultImportance,
            ),
          );
        }
      }
      _initialized = true;
    } catch (_) {
      // Gracefully degrade if running in a headless or unsupported runtime.
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        return (await android?.requestNotificationsPermission()) ?? true;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final ios = _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        return (await ios?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            )) ??
            true;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> showNotification({
    required int id,
    required String channelId,
    required String title,
    required String body,
    required AlertSeverity severity,
    String? payloadRoute,
  }) async {
    if (kIsWeb) return;
    if (!_initialized) {
      await initialize(onTap: (_) {});
    }
    try {
      final isCritical = severity == AlertSeverity.critical;
      final isWarning = severity == AlertSeverity.warning;
      final channelName = switch (channelId) {
        NotificationChannels.budgetAlerts => 'Budget & Limit Alerts',
        NotificationChannels.accountAlerts => 'Account & Balance Alerts',
        NotificationChannels.milestones => 'Savings Milestones',
        _ => 'Pocket CFO Alerts',
      };

      final accentColor = switch (severity) {
        AlertSeverity.critical => const Color(0xFFE11D48),
        AlertSeverity.warning => const Color(0xFFD97706),
        AlertSeverity.celebration => const Color(0xFF059669),
        AlertSeverity.info => const Color(0xFF4F46E5),
      };

      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          icon: 'ic_stat_pocket_cfo',
          color: accentColor,
          importance: isCritical || isWarning
              ? Importance.high
              : Importance.defaultImportance,
          priority: isCritical || isWarning
              ? Priority.high
              : Priority.defaultPriority,
          styleInformation: BigTextStyleInformation(body),
          enableVibration: true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payloadRoute,
      );
    } catch (_) {
      // Never crash financial writes if an OS notification channel is unavailable.
    }
  }

  @override
  Future<void> scheduleDailyReminder({
    required bool enabled,
    required int hour,
    required int minute,
  }) async {
    if (kIsWeb) return;
    if (!_initialized) {
      await initialize(onTap: (_) {});
    }
    try {
      await _plugin.cancel(id: NotificationChannels.dailyReminderId);
      if (!enabled) return;

      _ensureTimeZone();
      final now = tz.TZDateTime.now(tz.local);
      var scheduled = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        hour,
        minute,
      );
      if (!scheduled.isAfter(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }

      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationChannels.reminders,
          'Daily Expense Reminders',
          icon: 'ic_stat_pocket_cfo',
          color: Color(0xFF4F46E5),
          channelDescription:
              'Optional daily check-in reminder to log expenses.',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: true,
        ),
      );

      await _plugin.zonedSchedule(
        id: NotificationChannels.dailyReminderId,
        title: 'Daily Expense Check-In',
        body:
            'Take 15 seconds to log today’s expenses and keep your budget pace on track.',
        scheduledDate: scheduled,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: '/transactions',
      );
    } catch (_) {
      // Gracefully ignore scheduling failures on unsupported desktop hosts.
    }
  }

  @override
  Future<void> scheduleOneShotReminder({
    required int id,
    required String title,
    required String body,
    required DateTime atUtc,
    String? payloadRoute,
  }) async {
    if (kIsWeb) return;
    if (!atUtc.isAfter(DateTime.now().toUtc())) return;
    if (!_initialized) {
      await initialize(onTap: (_) {});
    }
    try {
      _ensureTimeZone();
      final scheduled = tz.TZDateTime.from(atUtc.toUtc(), tz.UTC);
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationChannels.reminders,
          'Daily Expense Reminders',
          icon: 'ic_stat_pocket_cfo',
          color: Color(0xFF4F46E5),
          channelDescription:
              'Optional daily check-in reminder to log expenses.',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduled,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payloadRoute,
      );
    } catch (_) {
      // Ignore scheduling failures on unsupported hosts.
    }
  }

  @override
  Future<void> cancelScheduledReminder(int id) async {
    if (kIsWeb) return;
    try {
      await _plugin.cancel(id: id);
    } catch (_) {}
  }

  @override
  Future<void> cancelAll() async {
    if (kIsWeb) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }
}

/// Deterministic in-memory dispatcher used by automated unit & widget tests.
final class InMemoryNotificationDispatcher
    implements DeviceNotificationDispatcher {
  final List<DispatchedNotificationRecord> dispatched = [];
  final Map<int, String> scheduledReminders = {};
  bool dailyReminderScheduled = false;
  int? dailyReminderHour;
  int? dailyReminderMinute;
  bool permissionGranted = true;
  void Function(String? route)? _onTap;

  void simulateTap(String? route) => _onTap?.call(route);

  @override
  Future<void> initialize({required void Function(String? route) onTap}) async {
    _onTap = onTap;
  }

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<void> showNotification({
    required int id,
    required String channelId,
    required String title,
    required String body,
    required AlertSeverity severity,
    String? payloadRoute,
  }) async {
    dispatched.add(
      DispatchedNotificationRecord(
        id: id,
        channelId: channelId,
        title: title,
        body: body,
        severity: severity,
        payloadRoute: payloadRoute,
      ),
    );
  }

  @override
  Future<void> scheduleDailyReminder({
    required bool enabled,
    required int hour,
    required int minute,
  }) async {
    dailyReminderScheduled = enabled;
    dailyReminderHour = enabled ? hour : null;
    dailyReminderMinute = enabled ? minute : null;
  }

  @override
  Future<void> scheduleOneShotReminder({
    required int id,
    required String title,
    required String body,
    required DateTime atUtc,
    String? payloadRoute,
  }) async {
    scheduledReminders[id] = title;
  }

  @override
  Future<void> cancelScheduledReminder(int id) async {
    scheduledReminders.remove(id);
  }

  @override
  Future<void> cancelAll() async {
    dispatched.clear();
    scheduledReminders.clear();
    dailyReminderScheduled = false;
  }
}
