import 'dart:async';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/financial_engine/alert_evaluation_engine.dart';
import '../../../core/notifications/local_notification_service.dart';
import '../../../core/utilities/clock.dart';
import '../../../core/utilities/id_generator.dart';
import '../../accounts/domain/repositories/account_repository.dart';
import '../../budgets/domain/repositories/budget_repository.dart';
import '../../savings_goals/domain/repositories/savings_goal_repository.dart';
import '../../settings/data/settings_repository.dart';

/// Live alert event emitted to the active UI for frosted in-app banners and celebrations.
final class ProfileAlertEvent {
  const ProfileAlertEvent({required this.profileId, required this.alert});

  final ProfileId profileId;
  final EvaluatedAlert alert;
}

/// Evaluates budget limits (`80%`, `100%`, `>100%` + `+25%` escalation),
/// category caps, low account balances, and savings goal milestones,
/// persists deduplicated entries into `local_notifications`, and dispatches OS notifications.
final class FinancialAlertsCoordinator {
  FinancialAlertsCoordinator({
    required AppDatabase db,
    required BudgetRepository budgetRepository,
    required AccountRepository accountRepository,
    required SavingsGoalRepository savingsGoalRepository,
    required SettingsRepository settingsRepository,
    required DeviceNotificationDispatcher dispatcher,
    required UtcClock clock,
  }) : _db = db,
       _budgetRepo = budgetRepository,
       _accountRepo = accountRepository,
       _goalRepo = savingsGoalRepository,
       _settingsRepo = settingsRepository,
       _dispatcher = dispatcher,
       _clock = clock;

  final AppDatabase _db;
  final BudgetRepository _budgetRepo;
  final AccountRepository _accountRepo;
  final SavingsGoalRepository _goalRepo;
  final SettingsRepository _settingsRepo;
  final DeviceNotificationDispatcher _dispatcher;
  final UtcClock _clock;

  final StreamController<ProfileAlertEvent> _liveAlertCtrl =
      StreamController<ProfileAlertEvent>.broadcast();
  final StreamController<ProfileId> _inboxChangedCtrl =
      StreamController<ProfileId>.broadcast();

  Stream<ProfileAlertEvent> get liveAlerts => _liveAlertCtrl.stream;

  /// Emits [ProfileId] whenever unread notifications for that profile change.
  /// Avoids Drift's `query.watch()` `StreamQueryStore` timers for deterministic
  /// zero-leak lifecycle across production and `FakeAsync` widget tests.
  Stream<ProfileId> get inboxChanges => _inboxChangedCtrl.stream;

  void notifyInboxChanged(ProfileId profileId) {
    if (!_inboxChangedCtrl.isClosed) {
      _inboxChangedCtrl.add(profileId);
    }
  }

  Future<void> initialize({required void Function(String? route) onTap}) =>
      _dispatcher.initialize(onTap: onTap);

  Future<bool> requestPermission() => _dispatcher.requestPermission();

  /// Returns current unread notification count scoped strictly to [profileId].
  Future<int> countUnread(ProfileId profileId) async {
    final rows =
        await (_db.select(_db.localNotifications)..where(
              (n) =>
                  n.profileId.equals(profileId.value) & n.isRead.equals(false),
            ))
            .get();
    return rows.length;
  }

  /// Reactive unread notification counter scoped strictly to [profileId].
  Stream<int> watchUnreadCount(ProfileId profileId) async* {
    yield await countUnread(profileId);
    await for (final changedProfile in _inboxChangedCtrl.stream) {
      if (changedProfile == profileId) {
        yield await countUnread(profileId);
      }
    }
  }

  /// Deletes all already-read notifications for [profileId].
  Future<int> clearReadNotifications(ProfileId profileId) async {
    final deleted =
        await (_db.delete(_db.localNotifications)..where(
              (n) =>
                  n.profileId.equals(profileId.value) & n.isRead.equals(true),
            ))
            .go();
    notifyInboxChanged(profileId);
    return deleted;
  }

  /// Marks all notifications for [profileId] as read in a single query.
  Future<void> markAllRead(ProfileId profileId) async {
    await (_db.update(_db.localNotifications)
          ..where((n) => n.profileId.equals(profileId.value)))
        .write(const LocalNotificationsCompanion(isRead: Value(true)));
    notifyInboxChanged(profileId);
  }

  /// Evaluates budgets, category caps, and liquid account low-balance floors
  /// after a posted transaction or draft posting. Returns newly fired alerts.
  Future<List<EvaluatedAlert>> evaluateAfterTransaction(
    ProfileId profileId,
  ) async {
    final notificationsOn = await _settingsRepo.getBool(
      'alerts.notifications_enabled',
      defaultValue: true,
    );
    final budgetAlertsOn = await _settingsRepo.getBool(
      'alerts.budget_enabled',
      defaultValue: true,
    );
    final lowBalOn = await _settingsRepo.getBool(
      'alerts.low_balance_enabled',
      defaultValue: true,
    );
    final thresholdRaw = await _settingsRepo.getString(
      'alerts.low_balance_threshold_minor',
    );
    final thresholdMinor = int.tryParse(thresholdRaw ?? '') ?? 100000;
    final hideBalances = await _settingsRepo.getBool('ui.hide_balances');

    final candidates = <EvaluatedAlert>[];

    if (budgetAlertsOn) {
      final budgetsRes = await _budgetRepo.listBudgetsWithProgress(profileId);
      final budgets = budgetsRes.valueOrNull ?? const [];
      candidates.addAll(AlertEvaluationEngine.evaluateBudgets(budgets));
    }

    if (lowBalOn && thresholdMinor > 0) {
      final accountsRes = await _accountRepo.listAccounts(profileId);
      final accounts = accountsRes.valueOrNull ?? const [];
      final dateKey = _clock.nowIsoUtc().substring(0, 10);
      candidates.addAll(
        AlertEvaluationEngine.evaluateLowBalances(
          accounts,
          thresholdMinor: thresholdMinor,
          dateKey: dateKey,
        ),
      );
    }

    return _persistAndDispatch(
      profileId: profileId,
      candidates: candidates,
      dispatchOs: notificationsOn,
      hideBalances: hideBalances,
    );
  }

  /// Evaluates Savings Goal 50% / 100% milestones after recording a deposit.
  Future<List<EvaluatedAlert>> evaluateAfterGoalContribution(
    ProfileId profileId,
  ) async {
    final notificationsOn = await _settingsRepo.getBool(
      'alerts.notifications_enabled',
      defaultValue: true,
    );
    final goalAlertsOn = await _settingsRepo.getBool(
      'alerts.goal_milestones_enabled',
      defaultValue: true,
    );
    if (!goalAlertsOn) return const [];

    final hideBalances = await _settingsRepo.getBool('ui.hide_balances');
    final goalsRes = await _goalRepo.listGoals(profileId);
    final goals = goalsRes.valueOrNull ?? const [];
    final candidates = AlertEvaluationEngine.evaluateGoalMilestones(goals);

    return _persistAndDispatch(
      profileId: profileId,
      candidates: candidates,
      dispatchOs: notificationsOn,
      hideBalances: hideBalances,
    );
  }

  /// Syncs optional daily expense check-in reminder with the OS scheduler.
  Future<void> syncDailyReminder({
    required bool enabled,
    required int hour,
    required int minute,
  }) async {
    if (enabled) {
      await _dispatcher.requestPermission();
    }
    await _dispatcher.scheduleDailyReminder(
      enabled: enabled,
      hour: hour,
      minute: minute,
    );
  }

  /// Dispatches an immediate test notification (OS push + in-app frosted banner + inbox log).
  Future<void> sendTestNotification(ProfileId profileId) async {
    await _dispatcher.requestPermission();
    final nowIso = _clock.nowIsoUtc();
    final hideBalances = await _settingsRepo.getBool('ui.hide_balances');
    final alert = EvaluatedAlert(
      dedupeKey: 'alert:test:${profileId.value}:$nowIso',
      kind: AlertKind.testAlert,
      severity: AlertSeverity.info,
      title: 'Pocket CFO Alerts Active',
      body:
          'You will receive instant alerts when spending nears 80%, reaches 100%, or crosses a budget limit.',
      maskedBody:
          'Smart limit alerts are active with lock-screen balance privacy enabled.',
      deepLinkRoute: '/budgets',
    );

    await _persistAndDispatch(
      profileId: profileId,
      candidates: [alert],
      dispatchOs: true,
      hideBalances: hideBalances,
    );
  }

  /// Persists and emits externally evaluated alerts (e.g. Monthly Bucket List
  /// reminders) using standard dedupe and privacy masking.
  Future<List<EvaluatedAlert>> dispatchExternalAlerts(
    ProfileId profileId,
    List<EvaluatedAlert> candidates, {
    bool dispatchOs = false,
  }) async {
    if (candidates.isEmpty) return const [];
    final hideBalances = await _settingsRepo.getBool('ui.hide_balances');
    return _persistAndDispatch(
      profileId: profileId,
      candidates: candidates,
      dispatchOs: dispatchOs,
      hideBalances: hideBalances,
    );
  }

  Future<List<EvaluatedAlert>> _persistAndDispatch({
    required ProfileId profileId,
    required List<EvaluatedAlert> candidates,
    required bool dispatchOs,
    required bool hideBalances,
  }) async {
    if (candidates.isEmpty) return const [];

    final nowIso = _clock.nowIsoUtc();
    final newlyTriggered = <EvaluatedAlert>[];

    for (final alert in candidates) {
      final scopedId = '${profileId.value}|${alert.dedupeKey}';
      final existing =
          await (_db.select(_db.localNotifications)..where(
                (n) =>
                    n.id.equals(scopedId) & n.profileId.equals(profileId.value),
              ))
              .getSingleOrNull();
      if (existing != null) continue;

      final bodyText = alert.bodyForPrivacy(hideBalances: hideBalances);

      await _db
          .into(_db.localNotifications)
          .insert(
            LocalNotificationsCompanion.insert(
              id: scopedId,
              profileId: profileId.value,
              notificationType: alert.kind.wireType,
              title: alert.title,
              body: bodyText,
              deepLinkRoute: Value(alert.deepLinkRoute),
              createdAtUtc: nowIso,
            ),
            mode: InsertMode.insertOrIgnore,
          );

      newlyTriggered.add(alert);

      if (dispatchOs) {
        final channelId = switch (alert.kind) {
          AlertKind.budgetWarning80 ||
          AlertKind.budgetReached100 ||
          AlertKind.budgetExceeded ||
          AlertKind.categoryWarning80 ||
          AlertKind.categoryExceeded => NotificationChannels.budgetAlerts,
          AlertKind.lowBalance => NotificationChannels.accountAlerts,
          AlertKind.goalMilestone50 ||
          AlertKind.goalCompleted100 => NotificationChannels.milestones,
          AlertKind.bucketReminder => NotificationChannels.reminders,
          AlertKind.recurringDue ||
          AlertKind.testAlert => NotificationChannels.budgetAlerts,
        };
        await _dispatcher.showNotification(
          id: scopedId.hashCode & 0x7FFFFFFF,
          channelId: channelId,
          title: alert.title,
          body: bodyText,
          severity: alert.severity,
          payloadRoute: alert.deepLinkRoute,
        );
      }

      if (!_liveAlertCtrl.isClosed) {
        _liveAlertCtrl.add(
          ProfileAlertEvent(profileId: profileId, alert: alert),
        );
      }
    }

    if (newlyTriggered.isNotEmpty) {
      notifyInboxChanged(profileId);
    }

    return newlyTriggered;
  }

  Future<void> dispose() async {
    await _liveAlertCtrl.close();
    await _inboxChangedCtrl.close();
  }
}
