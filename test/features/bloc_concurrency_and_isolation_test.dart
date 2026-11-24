import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pocket_money/core/database/app_database.dart';
import 'package:pocket_money/core/database/encrypted_executor.dart';
import 'package:pocket_money/core/errors/failures.dart';
import 'package:pocket_money/core/financial_engine/money.dart';
import 'package:pocket_money/core/logging/redacting_logger.dart';
import 'package:pocket_money/core/network/api_client.dart';
import 'package:pocket_money/core/security/key_manager.dart';
import 'package:pocket_money/core/security/privacy_screen_service.dart';
import 'package:pocket_money/core/sync/sync_coordinator.dart';
import 'package:pocket_money/core/utilities/clock.dart';
import 'package:pocket_money/core/utilities/id_generator.dart';
import 'package:pocket_money/core/utilities/profile_scope_controller.dart';
import 'package:pocket_money/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:pocket_money/features/dashboard/domain/repositories/analytics_repository.dart';
import 'package:pocket_money/features/dashboard/presentation/bloc/dashboard_bloc.dart';
import 'package:pocket_money/features/security_lock/data/app_lock_service.dart';
import 'package:pocket_money/features/security_lock/presentation/bloc/app_lock_cubit.dart';
import 'package:pocket_money/features/settings/data/settings_repository.dart';

class _MockAnalyticsRepo extends Mock implements AnalyticsRepository {}

class _MockApiClient extends Mock implements ApiClient {}

class _FailingBiometricsAppLockService extends AppLockService {
  _FailingBiometricsAppLockService({
    required super.keyManager,
    required super.settings,
    required super.privacyScreen,
  });

  @override
  Future<bool> canUseBiometrics() async => true;

  @override
  Future<bool> authenticateWithBiometrics() async => false;
}

void main() {
  setUpAll(() {
    registerFallbackValue(const ProfileId('fallback'));
    registerFallbackValue(DashboardPeriodPreset.thisMonth);
  });

  test(
    'TC-FIN-017 DashboardBloc discards stale in-flight response after rapid profile switch',
    () async {
      final repo = _MockAnalyticsRepo();
      final scope = ProfileScopeController();
      final slowProfileACompleter = Completer<Result<DashboardSummary>>();

      DashboardSummary makeSummary(ProfileId pid, int netWorthMinor) =>
          DashboardSummary(
            profileId: pid,
            baseCurrencyCode: 'INR',
            periodPreset: DashboardPeriodPreset.thisMonth,
            valuationTimestampUtc: '2026-11-19T00:00:00Z',
            totalAssets: Money(amountMinor: netWorthMinor, currencyCode: 'INR'),
            totalLiabilities: Money.zero('INR'),
            netWorth: Money(amountMinor: netWorthMinor, currencyCode: 'INR'),
            periodIncome: Money.zero('INR'),
            periodGrossExpense: Money.zero('INR'),
            periodNetExpense: Money.zero('INR'),
            periodNetCashFlow: Money.zero('INR'),
            accounts: const [],
            recentTransactions: const [],
            categoryBreakdown: const [],
            monthlyCashFlow: const [],
            pendingSyncCount: 0,
          );

      when(
        () => repo.computeDashboardSummary(
          const ProfileId('prof-a'),
          period: any(named: 'period'),
        ),
      ).thenAnswer((_) => slowProfileACompleter.future);

      when(
        () => repo.computeDashboardSummary(
          const ProfileId('prof-b'),
          period: any(named: 'period'),
        ),
      ).thenAnswer(
        (_) async => Success(makeSummary(const ProfileId('prof-b'), 77700)),
      );

      final bloc = DashboardBloc(
        analyticsRepository: repo,
        scopeController: scope,
      );

      // Switch to Profile A (starts slow request).
      scope.switchTo(
        profileId: const ProfileId('prof-a'),
        role: 'owner',
        baseCurrencyCode: 'INR',
        timezone: 'Asia/Kolkata',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Switch immediately to Profile B BEFORE Profile A completes.
      scope.switchTo(
        profileId: const ProfileId('prof-b'),
        role: 'owner',
        baseCurrencyCode: 'INR',
        timezone: 'Asia/Kolkata',
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));

      // Now Profile A's stale request finishes late!
      slowProfileACompleter.complete(
        Success(makeSummary(const ProfileId('prof-a'), 99999999)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));

      // State MUST still show Profile B (77700), NEVER Profile A!
      expect(bloc.state.summary?.profileId, const ProfileId('prof-b'));
      expect(bloc.state.summary?.netWorth.amountMinor, 77700);

      await bloc.close();
      await scope.dispose();
    },
  );

  test(
    'AC-SEC-001 AppLockCubit keeps data locked when biometrics fail and unlocks via salted PIN fallback',
    () async {
      final db = AppDatabase(EncryptedDatabaseExecutor.openInMemory());
      final clock = FixedUtcClock(DateTime.utc(2026, 11, 19, 10, 0));
      final keyManager = KeyManager(InMemorySecureKeyValueStore());
      final settings = SettingsRepository(db: db, clock: clock);
      final lockSvc = _FailingBiometricsAppLockService(
        keyManager: keyManager,
        settings: settings,
        privacyScreen: const PrivacyScreenService(),
      );

      final cubit = AppLockCubit(service: lockSvc, clock: clock);
      await cubit.configureLock(
        fallbackPin: '2580',
        useBiometrics: true,
        timeoutSeconds: 30,
      );
      cubit.lockNow();
      expect(cubit.state.isLocked, isTrue);

      // Biometric failure keeps app locked with safe fallback prompt.
      final bioOk = await cubit.unlockWithBiometrics();
      expect(bioOk, isFalse);
      expect(cubit.state.isLocked, isTrue);
      expect(cubit.state.errorMessage, contains('fallback PIN'));

      // Wrong PIN keeps app locked.
      expect(await cubit.unlockWithPin('0000'), isFalse);
      expect(cubit.state.isLocked, isTrue);

      // Valid PIN unlocks cleanly.
      expect(await cubit.unlockWithPin('2580'), isTrue);
      expect(cubit.state.isLocked, isFalse);

      await cubit.close();
      await db.close();
    },
  );

  test(
    'AC-SYNC-001 & TC-FIN-009 SyncCoordinator handles idempotent duplicate replay, conflicts, and cursor pull',
    () async {
      final db = AppDatabase(EncryptedDatabaseExecutor.openInMemory());
      final clock = FixedUtcClock(DateTime.utc(2026, 11, 19, 10, 0));
      final keyManager = KeyManager(InMemorySecureKeyValueStore());
      final api = _MockApiClient();
      const profileId = ProfileId('prof-sync-1');
      const now = '2026-11-19T10:00:00Z';

      await db
          .into(db.profiles)
          .insert(
            ProfilesCompanion.insert(
              id: profileId.value,
              name: 'Sync Test',
              profileType: 'personal',
              baseCurrencyCode: 'INR',
              createdAtUtc: now,
              updatedAtUtc: now,
            ),
          );
      await db
          .into(db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              operationId: 'op-dup-1',
              profileId: profileId.value,
              entityType: 'transaction',
              entityId: 'tx-1',
              operationType: 'create',
              payloadJson: '{"id":"tx-1"}',
              idempotencyKey: 'op-dup-1',
              createdAtUtc: now,
              status: 'pending',
            ),
          );
      await db
          .into(db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              operationId: 'op-conf-2',
              profileId: profileId.value,
              entityType: 'profile',
              entityId: profileId.value,
              operationType: 'update',
              baseVersion: const Value(1),
              payloadJson: '{"name":"Local"}',
              idempotencyKey: 'op-conf-2',
              createdAtUtc: now,
              status: 'pending',
            ),
          );

      when(() => api.hasAccessToken).thenReturn(true);
      when(
        () => api.postJson(
          '/sync/push/',
          body: any(named: 'body'),
          extraHeaders: any(named: 'extraHeaders'),
        ),
      ).thenAnswer(
        (_) async => const Success({
          'data': {
            'results': [
              {
                'operation_id': 'op-dup-1',
                'outcome': 'duplicate',
                'server_version': 1,
                'error_code': null,
              },
              {
                'operation_id': 'op-conf-2',
                'outcome': 'conflict',
                'server_version': 2,
                'error_code': 'VERSION_CONFLICT',
                'server_payload': {'name': 'Server Updated'},
              },
            ],
          },
          'meta': {'request_id': 'req-1'},
        }),
      );
      when(
        () => api.getJson(
          '/sync/pull/',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => const Success({
          'data': {
            'changes': [
              {'seq': 42, 'entity_type': 'profile'},
            ],
            'next_cursor': 'seq:42',
            'has_more': false,
          },
          'meta': {'request_id': 'req-2'},
        }),
      );

      final sync = SyncCoordinator(
        db: db,
        apiClient: api,
        keyManager: keyManager,
        idGenerator: const UuidV4Generator(),
        clock: clock,
        logger: RedactingLogger(),
      );

      final run = (await sync.synchronizeProfile(profileId)).valueOrNull!;
      expect(run.pushedDuplicates, 1);
      expect(run.pushedConflicts, 1);
      expect(run.pulledChanges, 1);

      final snap = (await sync.getQueueSnapshot(profileId)).valueOrNull!;
      expect(snap.syncedCount, 1);
      expect(snap.conflictCount, 1);
      expect(snap.openConflicts.single.operationId, 'op-conf-2');

      // Resolve conflict explicitly.
      await sync.resolveConflict(
        profileId: profileId,
        conflictId: snap.openConflicts.single.id,
        resolution: 'accepted_server',
      );
      final afterResolve = (await sync.getQueueSnapshot(
        profileId,
      )).valueOrNull!;
      expect(afterResolve.conflictCount, 0);
      expect(afterResolve.syncedCount, 2);

      await db.close();
    },
  );
}
