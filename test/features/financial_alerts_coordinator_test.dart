import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_money/app/config/environment_config.dart';
import 'package:pocket_money/bootstrap.dart';
import 'package:pocket_money/core/database/app_database.dart';
import 'package:pocket_money/core/database/encrypted_executor.dart';
import 'package:pocket_money/core/financial_engine/alert_evaluation_engine.dart';
import 'package:pocket_money/core/notifications/local_notification_service.dart';
import 'package:pocket_money/core/security/key_manager.dart';
import 'package:pocket_money/core/utilities/clock.dart';
import 'package:pocket_money/features/accounts/domain/entities/financial_account_entity.dart';
import 'package:pocket_money/features/accounts/domain/repositories/account_repository.dart';
import 'package:pocket_money/features/budgets/domain/entities/budget_entity.dart';
import 'package:pocket_money/features/budgets/domain/repositories/budget_repository.dart';
import 'package:pocket_money/features/categories/domain/entities/category_entity.dart';
import 'package:pocket_money/features/categories/domain/repositories/category_repository.dart';
import 'package:pocket_money/features/notifications/data/financial_alerts_coordinator.dart';
import 'package:pocket_money/features/profiles/domain/entities/profile_entity.dart';
import 'package:pocket_money/features/profiles/domain/repositories/profile_repository.dart';
import 'package:pocket_money/features/savings_goals/domain/entities/savings_goal_entity.dart';
import 'package:pocket_money/features/savings_goals/domain/repositories/savings_goal_repository.dart';
import 'package:pocket_money/features/settings/data/settings_repository.dart';
import 'package:pocket_money/features/transactions/domain/entities/transaction_entity.dart';
import 'package:pocket_money/features/transactions/domain/repositories/transaction_repository.dart';

void main() {
  late InMemoryNotificationDispatcher dispatcher;

  setUp(() async {
    dispatcher = InMemoryNotificationDispatcher();
    await configureDependencies(
      config: const EnvironmentConfig(
        environment: AppEnvironment.dev,
        apiBaseUrl: 'http://localhost:8000/api/v1',
        appVersion: '1.0.0+1',
        requireEncryptedDatabase: false,
        analyticsEnabledByDefault: false,
      ),
      databaseExecutorOverride: EncryptedDatabaseExecutor.openInMemory(),
      secureStoreOverride: InMemorySecureKeyValueStore(),
      clockOverride: FixedUtcClock(DateTime.utc(2026, 11, 20, 10, 0)),
      notificationDispatcherOverride: dispatcher,
    );
  });

  tearDown(() async {
    if (getIt.isRegistered<AppDatabase>()) {
      await getIt<AppDatabase>().close();
    }
    await getIt.reset();
  });

  test(
    'FinancialAlertsCoordinator deduplicates 80%/exceeded alerts, masks lock-screen privacy, and isolates profiles',
    () async {
      final profRepo = getIt<ProfileRepository>();
      final accRepo = getIt<AccountRepository>();
      final catRepo = getIt<CategoryRepository>();
      final txRepo = getIt<TransactionRepository>();
      final budgetRepo = getIt<BudgetRepository>();
      final goalRepo = getIt<SavingsGoalRepository>();
      final settingsRepo = getIt<SettingsRepository>();
      final coordinator = getIt<FinancialAlertsCoordinator>();

      final pA = (await profRepo.createProfile(
        userId: 'u1',
        ownerDisplayName: 'Owner',
        name: 'Profile A',
        profileType: ProfileType.personal,
        baseCurrencyCode: 'INR',
      )).valueOrNull!;
      final pB = (await profRepo.createProfile(
        userId: 'u1',
        ownerDisplayName: 'Owner',
        name: 'Profile B',
        profileType: ProfileType.business,
        baseCurrencyCode: 'INR',
      )).valueOrNull!;

      final acc = (await accRepo.createAccountWithOpeningBalance(
        profileId: pA.id,
        name: 'Main Bank',
        accountType: FinancialAccountType.bank,
        currencyCode: 'INR',
        openingBalanceMinor: 500000, // ₹ 5,000
      )).valueOrNull!;

      final cats = (await catRepo.listCategories(
        pA.id,
        type: CategoryType.expense,
      )).valueOrNull!;
      final foodCat = cats.first;

      await budgetRepo.createBudget(
        profileId: pA.id,
        name: 'Monthly Cap',
        periodType: BudgetPeriodType.monthly,
        overallLimitMinor: 100000, // ₹ 1,000
        currencyCode: 'INR',
        categoryLimitsMinor: const {},
      );

      // 1. Spend ₹ 850 (85%) -> fires 80% warning once.
      await txRepo.createTransaction(
        pA.id,
        CreateTransactionCommand(
          type: TransactionType.expense,
          amountMinor: 85000,
          currencyCode: 'INR',
          transactionDateUtc: '2026-11-20T10:00:00Z',
          sourceAccountId: acc.id,
          categoryId: foodCat.id,
          description: 'Groceries',
        ),
      );
      final fired1 = await coordinator.evaluateAfterTransaction(pA.id);
      expect(fired1.map((a) => a.kind), [AlertKind.budgetWarning80]);
      expect(dispatcher.dispatched, hasLength(1));

      // 2. Spend ₹ 50 more (90%) -> same 80% tier MUST be deduplicated (0 new alerts).
      await txRepo.createTransaction(
        pA.id,
        CreateTransactionCommand(
          type: TransactionType.expense,
          amountMinor: 5000,
          currencyCode: 'INR',
          transactionDateUtc: '2026-11-20T10:05:00Z',
          sourceAccountId: acc.id,
          categoryId: foodCat.id,
          description: 'Tea',
        ),
      );
      final fired2 = await coordinator.evaluateAfterTransaction(pA.id);
      expect(fired2, isEmpty);
      expect(dispatcher.dispatched, hasLength(1));

      // 3. Turn on Hide Balances & spend ₹ 200 (110% crossed!) -> fires masked OS alert!
      await settingsRepo.setBool('ui.hide_balances', true);
      await txRepo.createTransaction(
        pA.id,
        CreateTransactionCommand(
          type: TransactionType.expense,
          amountMinor: 20000,
          currencyCode: 'INR',
          transactionDateUtc: '2026-11-20T10:10:00Z',
          sourceAccountId: acc.id,
          categoryId: foodCat.id,
          description: 'Dinner',
        ),
      );
      final fired3 = await coordinator.evaluateAfterTransaction(pA.id);
      expect(fired3.map((a) => a.kind), [AlertKind.budgetExceeded]);
      expect(dispatcher.dispatched, hasLength(2));
      expect(dispatcher.dispatched.last.body, isNot(contains('₹')));
      expect(dispatcher.dispatched.last.payloadRoute, '/budgets');

      // 4. Profile isolation: Profile A has 2 unread alerts, Profile B has 0.
      expect(await coordinator.watchUnreadCount(pA.id).first, 2);
      expect(await coordinator.watchUnreadCount(pB.id).first, 0);

      // 5. Goal 100% completion milestone fires celebration alert.
      final goal = (await goalRepo.createGoal(
        profileId: pA.id,
        name: 'Bike Fund',
        targetAmountMinor: 50000,
        currencyCode: 'INR',
        fundingMode: GoalFundingMode.allocated,
      )).valueOrNull!;
      await goalRepo.recordContribution(
        profileId: pA.id,
        goalId: goal.id,
        amountMinor: 50000,
      );
      final goalFired = await coordinator.evaluateAfterGoalContribution(pA.id);
      expect(goalFired.map((a) => a.kind), [AlertKind.goalCompleted100]);
      expect(await coordinator.watchUnreadCount(pA.id).first, 3);

      // 6. Mark all read + clear read cleans inbox cleanly.
      await coordinator.markAllRead(pA.id);
      expect(await coordinator.watchUnreadCount(pA.id).first, 0);
      final cleared = await coordinator.clearReadNotifications(pA.id);
      expect(cleared, 3);
    },
  );
}
