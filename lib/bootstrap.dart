import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import 'app/config/environment_config.dart';
import 'core/database/app_database.dart';
import 'core/database/encrypted_executor.dart';
import 'core/logging/redacting_logger.dart';
import 'core/network/api_client.dart';
import 'core/notifications/local_notification_service.dart';
import 'core/security/backup_crypto.dart';
import 'core/security/key_manager.dart';
import 'core/security/privacy_screen_service.dart';
import 'core/sync/sync_coordinator.dart';
import 'core/utilities/clock.dart';
import 'core/utilities/id_generator.dart';
import 'core/utilities/profile_scope_controller.dart';
import 'features/accounts/data/repositories/drift_account_repository.dart';
import 'features/accounts/domain/repositories/account_repository.dart';
import 'features/authentication/data/repositories/auth_repository.dart';
import 'features/backup_restore/data/backup_restore_service.dart';
import 'features/budgets/data/repositories/drift_budget_repository.dart';
import 'features/budgets/domain/repositories/budget_repository.dart';
import 'features/categories/data/repositories/drift_category_repository.dart';
import 'features/categories/domain/repositories/category_repository.dart';
import 'features/dashboard/data/repositories/drift_analytics_repository.dart';
import 'features/dashboard/domain/repositories/analytics_repository.dart';
import 'features/import_export/data/repositories/drift_csv_import_repository.dart';
import 'features/loans/data/repositories/drift_loan_repository.dart';
import 'features/notifications/data/financial_alerts_coordinator.dart';
import 'features/profiles/data/repositories/drift_profile_repository.dart';
import 'features/profiles/domain/repositories/profile_repository.dart';
import 'features/recurring/data/repositories/drift_recurring_repository.dart';
import 'features/savings_goals/data/repositories/drift_savings_goal_repository.dart';
import 'features/savings_goals/domain/repositories/savings_goal_repository.dart';
import 'features/security_lock/data/app_lock_service.dart';
import 'features/settings/data/settings_repository.dart';
import 'features/transactions/data/repositories/drift_transaction_repository.dart';
import 'features/transactions/domain/repositories/transaction_repository.dart';

final getIt = GetIt.instance;

/// Composition root wiring all services, encrypted database, repositories,
/// and sync/security controllers (`ARCH-002`).
Future<void> configureDependencies({
  EnvironmentConfig? config,
  QueryExecutor? databaseExecutorOverride,
  SecureKeyValueStore? secureStoreOverride,
  UtcClock? clockOverride,
  DeviceNotificationDispatcher? notificationDispatcherOverride,
}) async {
  await getIt.reset();

  final env = config ?? EnvironmentConfig.fromDartDefines();
  final clock = clockOverride ?? const SystemUtcClock();
  const idGen = UuidV4Generator();
  final logger = RedactingLogger(
    sink: kDebugMode ? (line) => debugPrint(line) : null,
  );
  final keyManager = KeyManager(
    secureStoreOverride ?? PlatformSecureKeyValueStore(),
  );
  const privacyScreen = PrivacyScreenService();
  final scopeController = ProfileScopeController();

  final dbExecutor =
      databaseExecutorOverride ??
      EncryptedDatabaseExecutor.openAppDatabase(
        keyManager: keyManager,
        requireEncryption: kReleaseMode || env.requireEncryptedDatabase,
      );
  final db = AppDatabase(dbExecutor);

  final apiClient = ApiClient(
    config: env,
    keyManager: keyManager,
    idGenerator: idGen,
    logger: logger,
  );

  final settingsRepo = SettingsRepository(db: db, clock: clock);
  final authRepo = AuthRepository(
    apiClient: apiClient,
    keyManager: keyManager,
    settingsRepository: settingsRepo,
    appVersion: env.appVersion,
  );
  final appLockService = AppLockService(
    keyManager: keyManager,
    settings: settingsRepo,
    privacyScreen: privacyScreen,
  );

  final profileRepo = DriftProfileRepository(
    db: db,
    idGenerator: idGen,
    clock: clock,
    logger: logger,
  );
  final accountRepo = DriftAccountRepository(
    db: db,
    idGenerator: idGen,
    clock: clock,
  );
  final categoryRepo = DriftCategoryRepository(
    db: db,
    idGenerator: idGen,
    clock: clock,
  );
  final txRepo = DriftTransactionRepository(
    db: db,
    idGenerator: idGen,
    clock: clock,
    logger: logger,
  );
  final analyticsRepo = DriftAnalyticsRepository(
    db: db,
    accountRepository: accountRepo,
    transactionRepository: txRepo,
    clock: clock,
  );
  final budgetRepo = DriftBudgetRepository(
    db: db,
    idGenerator: idGen,
    clock: clock,
  );
  final goalRepo = DriftSavingsGoalRepository(
    db: db,
    transactionRepository: txRepo,
    idGenerator: idGen,
    clock: clock,
  );
  final notificationDispatcher =
      notificationDispatcherOverride ??
      (databaseExecutorOverride != null
          ? InMemoryNotificationDispatcher()
          : FlutterLocalNotificationDispatcher());
  final alertsCoordinator = FinancialAlertsCoordinator(
    db: db,
    budgetRepository: budgetRepo,
    accountRepository: accountRepo,
    savingsGoalRepository: goalRepo,
    settingsRepository: settingsRepo,
    dispatcher: notificationDispatcher,
    clock: clock,
  );
  final recurringRepo = DriftRecurringRepository(
    db: db,
    transactionRepository: txRepo,
    idGenerator: idGen,
    clock: clock,
    alertsCoordinator: alertsCoordinator,
    notificationDispatcher: notificationDispatcher,
    settingsRepository: settingsRepo,
  );
  final loanRepo = DriftLoanRepository(
    db: db,
    accountRepository: accountRepo,
    idGenerator: idGen,
    clock: clock,
  );
  final csvRepo = DriftCsvImportRepository(
    db: db,
    transactionRepository: txRepo,
    idGenerator: idGen,
    clock: clock,
  );
  final syncCoordinator = SyncCoordinator(
    db: db,
    apiClient: apiClient,
    keyManager: keyManager,
    idGenerator: idGen,
    clock: clock,
    logger: logger,
  );
  final backupService = BackupRestoreService(
    db: db,
    crypto: const BackupCrypto(),
    clock: clock,
    appVersion: env.appVersion,
  );

  getIt
    ..registerSingleton<EnvironmentConfig>(env)
    ..registerSingleton<UtcClock>(clock)
    ..registerSingleton<IdGenerator>(idGen)
    ..registerSingleton<RedactingLogger>(logger)
    ..registerSingleton<KeyManager>(keyManager)
    ..registerSingleton<PrivacyScreenService>(privacyScreen)
    ..registerSingleton<ProfileScopeController>(
      scopeController,
      dispose: (c) => c.dispose(),
    )
    ..registerSingleton<AppDatabase>(db)
    ..registerSingleton<ApiClient>(apiClient)
    ..registerSingleton<SettingsRepository>(settingsRepo)
    ..registerSingleton<AuthRepository>(authRepo)
    ..registerSingleton<AppLockService>(appLockService)
    ..registerSingleton<ProfileRepository>(profileRepo)
    ..registerSingleton<AccountRepository>(accountRepo)
    ..registerSingleton<CategoryRepository>(categoryRepo)
    ..registerSingleton<TransactionRepository>(txRepo)
    ..registerSingleton<AnalyticsRepository>(analyticsRepo)
    ..registerSingleton<BudgetRepository>(budgetRepo)
    ..registerSingleton<SavingsGoalRepository>(goalRepo)
    ..registerSingleton<DeviceNotificationDispatcher>(notificationDispatcher)
    ..registerSingleton<FinancialAlertsCoordinator>(
      alertsCoordinator,
      dispose: (c) => c.dispose(),
    )
    ..registerSingleton<DriftRecurringRepository>(recurringRepo)
    ..registerSingleton<DriftLoanRepository>(loanRepo)
    ..registerSingleton<DriftCsvImportRepository>(csvRepo)
    ..registerSingleton<SyncCoordinator>(syncCoordinator)
    ..registerSingleton<BackupRestoreService>(backupService);

  logger.info(
    'bootstrap',
    'dependencies_initialized',
    metadata: {'env': env.environment.name},
  );
}
