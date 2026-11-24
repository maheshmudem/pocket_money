import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/financial_engine/alert_evaluation_engine.dart';
import '../../../../core/financial_engine/money.dart';
import '../../../../core/notifications/local_notification_service.dart';
import '../../../../core/utilities/clock.dart';
import '../../../../core/utilities/id_generator.dart';
import '../../../notifications/data/financial_alerts_coordinator.dart';
import '../../../settings/data/settings_repository.dart';
import '../../../transactions/domain/entities/transaction_entity.dart';
import '../../../transactions/domain/repositories/transaction_repository.dart';
import '../../domain/entities/recurring_rule_entity.dart';

/// Recurring rule & local notification manager with deterministic occurrence keys
/// preventing silent duplicate generation (`FR-017`).
final class DriftRecurringRepository {
  DriftRecurringRepository({
    required AppDatabase db,
    required TransactionRepository transactionRepository,
    required IdGenerator idGenerator,
    required UtcClock clock,
    FinancialAlertsCoordinator? alertsCoordinator,
    DeviceNotificationDispatcher? notificationDispatcher,
    SettingsRepository? settingsRepository,
  }) : _db = db,
       _txRepo = transactionRepository,
       _idGen = idGenerator,
       _clock = clock,
       _alertsCoordinator = alertsCoordinator,
       _notificationDispatcher = notificationDispatcher,
       _settingsRepo = settingsRepository;

  final AppDatabase _db;
  final TransactionRepository _txRepo;
  final IdGenerator _idGen;
  final UtcClock _clock;
  final FinancialAlertsCoordinator? _alertsCoordinator;
  final DeviceNotificationDispatcher? _notificationDispatcher;
  final SettingsRepository? _settingsRepo;

  Future<Result<List<RecurringRuleEntity>>> listRules(
    ProfileId profileId,
  ) async {
    try {
      final rows =
          await (_db.select(_db.recurringRules)
                ..where((r) => r.profileId.equals(profileId.value))
                ..orderBy([(r) => OrderingTerm.asc(r.nextDueAtUtc)]))
              .get();
      return Success(rows.map(_mapRule).toList());
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  Future<Result<RecurringRuleEntity>> createRule({
    required ProfileId profileId,
    required String name,
    required TransactionType transactionType,
    required int amountMinor,
    required String currencyCode,
    required RecurringCadence cadence,
    required String nextDueAtUtc,
    int intervalCount = 1,
    String? sourceAccountId,
    String? destinationAccountId,
    String? categoryId,
    bool autoCreateDraft = true,
  }) async {
    if (name.trim().isEmpty || amountMinor <= 0) {
      return const FailureResult(
        ValidationFailure(
          message: 'Rule name and positive amount are required.',
        ),
      );
    }

    final id = _idGen.nextUuid();
    final now = _clock.nowIsoUtc();
    try {
      await _db
          .into(_db.recurringRules)
          .insert(
            RecurringRulesCompanion.insert(
              id: id,
              profileId: profileId.value,
              name: name.trim(),
              transactionType: transactionType.wireValue,
              amountMinor: amountMinor,
              currencyCode: currencyCode.toUpperCase(),
              sourceAccountId: Value(sourceAccountId),
              destinationAccountId: Value(destinationAccountId),
              categoryId: Value(categoryId),
              cadence: cadence.wireValue,
              intervalCount: Value(intervalCount),
              nextDueAtUtc: nextDueAtUtc,
              autoCreateDraft: Value(autoCreateDraft),
              status: 'active',
              createdAtUtc: now,
              updatedAtUtc: now,
            ),
          );
      final row = await (_db.select(
        _db.recurringRules,
      )..where((r) => r.id.equals(id))).getSingle();
      return Success(_mapRule(row));
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  Future<Result<void>> toggleStatus(
    ProfileId profileId,
    String ruleId,
    String newStatus,
  ) async {
    try {
      await (_db.update(_db.recurringRules)..where(
            (r) => r.id.equals(ruleId) & r.profileId.equals(profileId.value),
          ))
          .write(
            RecurringRulesCompanion(
              status: Value(newStatus),
              updatedAtUtc: Value(_clock.nowIsoUtc()),
            ),
          );
      return const Success(null);
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  /// Processes due recurring rules idempotently using deterministic `occurrenceKey`.
  /// Never silently duplicates a due occurrence (`FR-017`).
  Future<Result<int>> processDueRules(ProfileId profileId) async {
    try {
      final now = _clock.nowUtc();
      final nowIso = now.toIso8601String();
      final dueRules =
          await (_db.select(_db.recurringRules)..where(
                (r) =>
                    r.profileId.equals(profileId.value) &
                    r.status.equals('active') &
                    r.nextDueAtUtc.isSmallerOrEqualValue(nowIso),
              ))
              .get();

      var generatedCount = 0;
      for (final rule in dueRules) {
        final cadence = RecurringCadence.fromWire(rule.cadence);
        final interval = rule.intervalCount < 1 ? 1 : rule.intervalCount;
        var dueDate = DateTime.parse(rule.nextDueAtUtc).toUtc();
        var lastKey = rule.lastGeneratedOccurrenceKey;
        var steps = 0;

        while (!dueDate.isAfter(now) && steps < 24) {
          steps++;
          final dueIso = dueDate.toIso8601String();
          final occurrenceKey = 'rec:${rule.id}:${dueIso.substring(0, 10)}';

          if (lastKey != occurrenceKey) {
            // Check existing externalRef to guarantee absolute idempotency.
            final existing =
                await (_db.select(_db.transactions)..where(
                      (t) =>
                          t.profileId.equals(profileId.value) &
                          t.externalRef.equals(occurrenceKey),
                    ))
                    .getSingleOrNull();

            if (existing == null) {
              final created = await _txRepo.createTransaction(
                profileId,
                CreateTransactionCommand(
                  type: TransactionType.fromWire(rule.transactionType),
                  amountMinor: rule.amountMinor,
                  currencyCode: rule.currencyCode,
                  transactionDateUtc: dueIso,
                  sourceAccountId: rule.sourceAccountId,
                  destinationAccountId: rule.destinationAccountId,
                  categoryId: rule.categoryId,
                  externalRef: occurrenceKey,
                  description: 'Recurring: ${rule.name}',
                  saveAsDraft: rule.autoCreateDraft,
                ),
              );
              if (created.isSuccess) {
                generatedCount++;
                final notifId = _idGen.nextUuid();
                final title = rule.autoCreateDraft
                    ? 'Draft created: ${rule.name}'
                    : 'Posted recurring: ${rule.name}';
                final body = rule.autoCreateDraft
                    ? 'Review and post this scheduled transaction.'
                    : 'Scheduled recurring transaction has been posted.';
                await _db
                    .into(_db.localNotifications)
                    .insert(
                      LocalNotificationsCompanion.insert(
                        id: notifId,
                        profileId: profileId.value,
                        notificationType: 'recurring_due',
                        title: title,
                        body: body,
                        deepLinkRoute: const Value('/transactions'),
                        createdAtUtc: nowIso,
                      ),
                    );
                _alertsCoordinator?.notifyInboxChanged(profileId);
                final alertsOn =
                    await _settingsRepo?.getBool(
                      'alerts.notifications_enabled',
                      defaultValue: true,
                    ) ??
                    true;
                if (alertsOn) {
                  await _notificationDispatcher?.showNotification(
                    id: notifId.hashCode & 0x7FFFFFFF,
                    channelId: NotificationChannels.reminders,
                    title: title,
                    body: body,
                    severity: AlertSeverity.info,
                    payloadRoute: '/transactions',
                  );
                }
                if (!rule.autoCreateDraft) {
                  await _alertsCoordinator?.evaluateAfterTransaction(profileId);
                }
              }
            }
          }

          lastKey = occurrenceKey;
          dueDate = advanceDate(dueDate, cadence, interval);
        }

        await (_db.update(
          _db.recurringRules,
        )..where((r) => r.id.equals(rule.id))).write(
          RecurringRulesCompanion(
            nextDueAtUtc: Value(dueDate.toIso8601String()),
            lastGeneratedOccurrenceKey: Value(lastKey),
            updatedAtUtc: Value(nowIso),
          ),
        );
      }

      return Success(generatedCount);
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  Future<Result<List<LocalNotificationEntity>>> listNotifications(
    ProfileId profileId,
  ) async {
    try {
      final rows =
          await (_db.select(_db.localNotifications)
                ..where((n) => n.profileId.equals(profileId.value))
                ..orderBy([(n) => OrderingTerm.desc(n.createdAtUtc)])
                ..limit(50))
              .get();
      return Success(
        rows
            .map(
              (r) => LocalNotificationEntity(
                id: r.id,
                profileId: ProfileId(r.profileId),
                notificationType: r.notificationType,
                title: r.title,
                body: r.body,
                isRead: r.isRead,
                createdAtUtc: r.createdAtUtc,
                deepLinkRoute: r.deepLinkRoute,
              ),
            )
            .toList(),
      );
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  Future<void> markNotificationRead(ProfileId profileId, String id) async {
    await (_db.update(_db.localNotifications)
          ..where((n) => n.id.equals(id) & n.profileId.equals(profileId.value)))
        .write(const LocalNotificationsCompanion(isRead: Value(true)));
    _alertsCoordinator?.notifyInboxChanged(profileId);
  }

  /// Advances a UTC recurrence date safely, clamping month-end days
  /// (e.g., Jan 31 + 1 month -> Feb 28/29 instead of overflowing into March).
  static DateTime advanceDate(
    DateTime from,
    RecurringCadence cadence,
    int interval,
  ) {
    final step = interval < 1 ? 1 : interval;
    return switch (cadence) {
      RecurringCadence.daily => from.add(Duration(days: step)),
      RecurringCadence.weekly => from.add(Duration(days: 7 * step)),
      RecurringCadence.monthly => _addClampedMonths(from, step),
      RecurringCadence.yearly => _addClampedMonths(from, step * 12),
    };
  }

  static DateTime _addClampedMonths(DateTime from, int monthsToAdd) {
    final totalMonths = (from.year * 12 + (from.month - 1)) + monthsToAdd;
    final targetYear = totalMonths ~/ 12;
    final targetMonth = (totalMonths % 12) + 1;
    final maxDay = DateTime.utc(targetYear, targetMonth + 1, 0).day;
    final clampedDay = from.day > maxDay ? maxDay : from.day;
    return DateTime.utc(
      targetYear,
      targetMonth,
      clampedDay,
      from.hour,
      from.minute,
      from.second,
    );
  }

  RecurringRuleEntity _mapRule(RecurringRule r) => RecurringRuleEntity(
    id: r.id,
    profileId: ProfileId(r.profileId),
    name: r.name,
    transactionType: TransactionType.fromWire(r.transactionType),
    amount: Money(amountMinor: r.amountMinor, currencyCode: r.currencyCode),
    cadence: RecurringCadence.fromWire(r.cadence),
    intervalCount: r.intervalCount,
    nextDueAtUtc: r.nextDueAtUtc,
    autoCreateDraft: r.autoCreateDraft,
    status: r.status,
    sourceAccountId: r.sourceAccountId,
    destinationAccountId: r.destinationAccountId,
    categoryId: r.categoryId,
    lastGeneratedOccurrenceKey: r.lastGeneratedOccurrenceKey,
  );
}
