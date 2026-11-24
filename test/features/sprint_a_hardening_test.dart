import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_money/app/config/environment_config.dart';
import 'package:pocket_money/app/theme/app_theme.dart';
import 'package:pocket_money/bootstrap.dart';
import 'package:pocket_money/core/database/app_database.dart';
import 'package:pocket_money/core/database/encrypted_executor.dart';
import 'package:pocket_money/core/financial_engine/loan_amortizer.dart';
import 'package:pocket_money/core/logging/redacting_logger.dart';
import 'package:pocket_money/core/security/key_manager.dart';
import 'package:pocket_money/core/security/privacy_screen_service.dart';
import 'package:pocket_money/core/utilities/clock.dart';
import 'package:pocket_money/core/utilities/id_generator.dart';
import 'package:pocket_money/features/accounts/data/repositories/drift_account_repository.dart';
import 'package:pocket_money/features/accounts/domain/entities/financial_account_entity.dart';
import 'package:pocket_money/features/authentication/presentation/bloc/auth_cubit.dart';
import 'package:pocket_money/features/budgets/data/repositories/drift_budget_repository.dart';
import 'package:pocket_money/features/budgets/domain/entities/budget_entity.dart';
import 'package:pocket_money/features/categories/data/repositories/drift_category_repository.dart';
import 'package:pocket_money/features/categories/domain/entities/category_entity.dart';
import 'package:pocket_money/features/categories/presentation/pages/categories_page.dart';
import 'package:pocket_money/features/dashboard/presentation/bloc/dashboard_bloc.dart';
import 'package:pocket_money/features/loans/data/repositories/drift_loan_repository.dart';
import 'package:pocket_money/features/loans/presentation/pages/loans_page.dart';
import 'package:pocket_money/features/profiles/data/repositories/drift_profile_repository.dart';
import 'package:pocket_money/features/profiles/domain/entities/profile_entity.dart';
import 'package:pocket_money/features/profiles/presentation/bloc/active_profile_cubit.dart';
import 'package:pocket_money/features/recurring/data/repositories/drift_recurring_repository.dart';
import 'package:pocket_money/features/recurring/domain/entities/recurring_rule_entity.dart';
import 'package:pocket_money/features/savings_goals/domain/entities/savings_goal_entity.dart';
import 'package:pocket_money/features/savings_goals/domain/repositories/savings_goal_repository.dart';
import 'package:pocket_money/features/savings_goals/presentation/pages/savings_goals_page.dart';
import 'package:pocket_money/features/security_lock/data/app_lock_service.dart';
import 'package:pocket_money/features/security_lock/presentation/bloc/app_lock_cubit.dart';
import 'package:pocket_money/features/settings/data/settings_repository.dart';
import 'package:pocket_money/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:pocket_money/features/settings/presentation/pages/settings_page.dart';
import 'package:pocket_money/features/transactions/data/repositories/drift_transaction_repository.dart';
import 'package:pocket_money/features/transactions/domain/entities/transaction_entity.dart';

class _NoBioAppLockService extends AppLockService {
  _NoBioAppLockService({
    required super.keyManager,
    required super.settings,
    required super.privacyScreen,
  });

  @override
  Future<bool> canUseBiometrics() async => false;
}

void main() {
  group('Sprint A domain, repository, and security hardening', () {
    late AppDatabase db;
    late FixedUtcClock clock;
    late UuidV4Generator idGen;
    late RedactingLogger logger;
    late DriftProfileRepository profileRepo;
    late DriftAccountRepository accountRepo;
    late DriftCategoryRepository categoryRepo;
    late DriftTransactionRepository txRepo;
    late DriftBudgetRepository budgetRepo;
    late DriftRecurringRepository recurringRepo;
    late DriftLoanRepository loanRepo;

    setUp(() {
      db = AppDatabase(EncryptedDatabaseExecutor.openInMemory());
      clock = FixedUtcClock(DateTime.utc(2026, 11, 15, 10, 0));
      idGen = const UuidV4Generator();
      logger = RedactingLogger();

      profileRepo = DriftProfileRepository(
        db: db,
        idGenerator: idGen,
        clock: clock,
        logger: logger,
      );
      accountRepo = DriftAccountRepository(
        db: db,
        idGenerator: idGen,
        clock: clock,
      );
      categoryRepo = DriftCategoryRepository(
        db: db,
        idGenerator: idGen,
        clock: clock,
      );
      txRepo = DriftTransactionRepository(
        db: db,
        idGenerator: idGen,
        clock: clock,
        logger: logger,
      );
      budgetRepo = DriftBudgetRepository(
        db: db,
        idGenerator: idGen,
        clock: clock,
      );
      recurringRepo = DriftRecurringRepository(
        db: db,
        transactionRepository: txRepo,
        idGenerator: idGen,
        clock: clock,
      );
      loanRepo = DriftLoanRepository(
        db: db,
        accountRepository: accountRepo,
        idGenerator: idGen,
        clock: clock,
      );
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'Recurring advanceDate clamps month-ends and leap years, and processDueRules catches up idempotently',
      () async {
        // Non-leap year: Jan 31 + 1 month -> Feb 28 (not March 3!).
        expect(
          DriftRecurringRepository.advanceDate(
            DateTime.utc(2026, 1, 31, 9, 0),
            RecurringCadence.monthly,
            1,
          ),
          DateTime.utc(2026, 2, 28, 9, 0),
        );
        // Leap year: Jan 31, 2028 + 1 month -> Feb 29, 2028.
        expect(
          DriftRecurringRepository.advanceDate(
            DateTime.utc(2028, 1, 31, 9, 0),
            RecurringCadence.monthly,
            1,
          ),
          DateTime.utc(2028, 2, 29, 9, 0),
        );
        // Leap day + 1 year -> Feb 28, 2029.
        expect(
          DriftRecurringRepository.advanceDate(
            DateTime.utc(2028, 2, 29, 9, 0),
            RecurringCadence.yearly,
            1,
          ),
          DateTime.utc(2029, 2, 28, 9, 0),
        );

        final profile = (await profileRepo.createProfile(
          userId: 'u1',
          ownerDisplayName: 'Riya',
          name: 'Personal',
          profileType: ProfileType.personal,
          baseCurrencyCode: 'INR',
        )).valueOrNull!;
        final bank = (await accountRepo.createAccountWithOpeningBalance(
          profileId: profile.id,
          name: 'Salary Bank',
          accountType: FinancialAccountType.bank,
          currencyCode: 'INR',
          openingBalanceMinor: 5000000,
        )).valueOrNull!;
        final cats = (await categoryRepo.listCategories(
          profile.id,
          type: CategoryType.expense,
        )).valueOrNull!;

        // Rule started 3 months ago (Aug 31, 2026); current clock is Nov 15, 2026.
        // Due occurrences: Aug 31, Sep 30, Oct 30 -> 3 caught-up entries!
        final createRes = await recurringRepo.createRule(
          profileId: profile.id,
          name: 'Cloud Hosting',
          transactionType: TransactionType.expense,
          amountMinor: 100000,
          currencyCode: 'INR',
          cadence: RecurringCadence.monthly,
          nextDueAtUtc: DateTime.utc(2026, 8, 31, 8, 0).toIso8601String(),
          sourceAccountId: bank.id,
          categoryId: cats.first.id,
          autoCreateDraft: true,
        );
        expect(createRes.isSuccess, isTrue);

        final firstRun = await recurringRepo.processDueRules(profile.id);
        expect(firstRun.valueOrNull, 3);

        // Re-running immediately must produce 0 duplicates.
        final secondRun = await recurringRepo.processDueRules(profile.id);
        expect(secondRun.valueOrNull, 0);

        final rules = (await recurringRepo.listRules(profile.id)).valueOrNull!;
        expect(
          DateTime.parse(rules.first.nextDueAtUtc).isAfter(clock.nowUtc()),
          isTrue,
        );
      },
    );

    test(
      'Budget rollover carries forward unspent prior-month allowance and aggregate avoids double-counting',
      () async {
        // Set clock to Oct 5, 2026 to create budget and spend 40% in October.
        clock.set(DateTime.utc(2026, 10, 5, 10, 0));
        final profile = (await profileRepo.createProfile(
          userId: 'u1',
          ownerDisplayName: 'Riya',
          name: 'Budget Profile',
          profileType: ProfileType.personal,
          baseCurrencyCode: 'INR',
        )).valueOrNull!;
        final bank = (await accountRepo.createAccountWithOpeningBalance(
          profileId: profile.id,
          name: 'Bank',
          accountType: FinancialAccountType.bank,
          currencyCode: 'INR',
          openingBalanceMinor: 5000000,
        )).valueOrNull!;
        final expCats = (await categoryRepo.listCategories(
          profile.id,
          type: CategoryType.expense,
        )).valueOrNull!;

        await budgetRepo.createBudget(
          profileId: profile.id,
          name: 'Monthly Master',
          periodType: BudgetPeriodType.monthly,
          overallLimitMinor: 1000000, // ₹10,000
          currencyCode: 'INR',
          categoryLimitsMinor: const {},
          rolloverEnabled: true,
        );

        // Spend ₹4,000 in October.
        await txRepo.createTransaction(
          profile.id,
          CreateTransactionCommand(
            type: TransactionType.expense,
            amountMinor: 400000,
            currencyCode: 'INR',
            transactionDateUtc: DateTime.utc(
              2026,
              10,
              12,
              10,
              0,
            ).toIso8601String(),
            sourceAccountId: bank.id,
            categoryId: expCats.first.id,
            description: 'Oct Groceries',
          ),
        );

        // Move to November 15, 2026 -> ₹6,000 unspent should roll over!
        clock.set(DateTime.utc(2026, 11, 15, 10, 0));
        final novBudgets = (await budgetRepo.listBudgetsWithProgress(
          profile.id,
        )).valueOrNull!;
        expect(novBudgets.length, 1);
        expect(novBudgets.first.overallLimit.amountMinor, 1600000); // ₹16,000
        expect(
          novBudgets.first.remainingDaysAt(clock.nowUtc()),
          16,
        ); // Nov 15..30 inclusive

        // Also create a category sub-cap and verify BudgetHealthAggregate does NOT double-count!
        await budgetRepo.createBudget(
          profileId: profile.id,
          name: 'Food Cap',
          periodType: BudgetPeriodType.weekly,
          overallLimitMinor: 300000,
          currencyCode: 'INR',
          categoryLimitsMinor: {expCats.first.id: 300000},
          rolloverEnabled: false,
        );
        final allBudgets = (await budgetRepo.listBudgetsWithProgress(
          profile.id,
        )).valueOrNull!;
        final agg = BudgetHealthAggregate.compute(allBudgets, clock.nowUtc());
        expect(agg.totalLimitMinor, 1600000); // Not 19,00,000!
        expect(agg.safePerDayMinor, 1600000 ~/ 16);
      },
    );

    test(
      'Loan paying final EMI with fee auto-marks loan paid_off, balances ledger, and supports >24 terms',
      () async {
        final profile = (await profileRepo.createProfile(
          userId: 'u1',
          ownerDisplayName: 'Riya',
          name: 'Loan Profile',
          profileType: ProfileType.personal,
          baseCurrencyCode: 'INR',
        )).valueOrNull!;
        final bank = (await accountRepo.createAccountWithOpeningBalance(
          profileId: profile.id,
          name: 'Main Bank',
          accountType: FinancialAccountType.bank,
          currencyCode: 'INR',
          openingBalanceMinor: 50000000,
        )).valueOrNull!;

        // 1. Short 2-month loan -> pay both installments -> status must become 'paid_off'.
        final shortLoan = (await loanRepo.createLoan(
          profileId: profile.id,
          name: 'Short Bridge Loan',
          principalMinor: 200000,
          currencyCode: 'INR',
          annualInterestRateBps: 1200,
          termMonths: 2,
          startDateUtc: clock.nowUtc(),
          method: LoanInterestMethod.reducingBalance,
          fundingAccountId: bank.id,
        )).valueOrNull!;
        expect(shortLoan.status, 'active');
        expect(shortLoan.installments.length, 2);

        final pay1 = await loanRepo.payInstallment(
          profileId: profile.id,
          loanId: shortLoan.id,
          installmentId: shortLoan.installments[0].id,
          sourceBankAccountId: bank.id,
          feeMinor: 5000,
        );
        expect(pay1.isSuccess, isTrue);

        var refreshed = (await loanRepo.listLoans(
          profile.id,
        )).valueOrNull!.firstWhere((l) => l.id == shortLoan.id);
        expect(refreshed.status, 'active');

        final pay2 = await loanRepo.payInstallment(
          profileId: profile.id,
          loanId: shortLoan.id,
          installmentId: shortLoan.installments[1].id,
          sourceBankAccountId: bank.id,
        );
        expect(pay2.isSuccess, isTrue);

        refreshed = (await loanRepo.listLoans(
          profile.id,
        )).valueOrNull!.firstWhere((l) => l.id == shortLoan.id);
        expect(refreshed.status, 'paid_off');
        expect(refreshed.remainingPrincipalMinor, 0);

        final recon = (await txRepo.runReconciliationCheck(
          profile.id,
        )).valueOrNull!;
        expect(recon.isHealthy, isTrue);

        // 2. Long 36-month loan persists all 36 installments.
        final longLoan = (await loanRepo.createLoan(
          profileId: profile.id,
          name: '3-Year Auto Loan',
          principalMinor: 3600000,
          currencyCode: 'INR',
          annualInterestRateBps: 950,
          termMonths: 36,
          startDateUtc: clock.nowUtc(),
        )).valueOrNull!;
        expect(longLoan.installments.length, 36);
      },
    );

    test(
      'Account archive/unarchive restores active state and queryTransactions hydrates splits',
      () async {
        final profile = (await profileRepo.createProfile(
          userId: 'u1',
          ownerDisplayName: 'Riya',
          name: 'Ledger Profile',
          profileType: ProfileType.personal,
          baseCurrencyCode: 'INR',
        )).valueOrNull!;
        final bank = (await accountRepo.createAccountWithOpeningBalance(
          profileId: profile.id,
          name: 'Checking',
          accountType: FinancialAccountType.bank,
          currencyCode: 'INR',
          openingBalanceMinor: 1000000,
        )).valueOrNull!;
        final expCats = (await categoryRepo.listCategories(
          profile.id,
          type: CategoryType.expense,
        )).valueOrNull!;

        // Create split transaction and confirm queryTransactions hydrates splits!
        await txRepo.createTransaction(
          profile.id,
          CreateTransactionCommand(
            type: TransactionType.expense,
            amountMinor: 100000,
            currencyCode: 'INR',
            transactionDateUtc: clock.nowIsoUtc(),
            sourceAccountId: bank.id,
            description: 'Supermarket Run',
            splits: [
              SplitCommandLine(categoryId: expCats[0].id, amountMinor: 60000),
              SplitCommandLine(categoryId: expCats[1].id, amountMinor: 40000),
            ],
          ),
        );

        final queried = (await txRepo.queryTransactions(
          profile.id,
        )).valueOrNull!;
        final supermarket = queried.items.firstWhere(
          (t) => t.description == 'Supermarket Run',
        );
        expect(supermarket.splits.length, 2);
        expect(
          supermarket.splits.fold<int>(0, (s, sp) => s + sp.amountMinor),
          100000,
        );

        // Archive then restore account.
        final archRes = await accountRepo.archiveAccount(
          profileId: profile.id,
          accountId: bank.id,
        );
        expect(archRes.isSuccess, isTrue);
        final activeAfterArch = (await accountRepo.listAccounts(
          profile.id,
          includeArchived: false,
        )).valueOrNull!;
        expect(activeAfterArch.any((a) => a.id == bank.id), isFalse);

        final unarchRes = await accountRepo.unarchiveAccount(
          profileId: profile.id,
          accountId: bank.id,
        );
        expect(unarchRes.isSuccess, isTrue);
        final activeAfterRestore = (await accountRepo.listAccounts(
          profile.id,
          includeArchived: false,
        )).valueOrNull!;
        expect(activeAfterRestore.any((a) => a.id == bank.id), isTrue);
      },
    );

    test(
      'AppLockCubit enforces progressive lockout after 5 wrong PINs and supports verifyCurrentPin & changePin',
      () async {
        final store = InMemorySecureKeyValueStore();
        final keyManager = KeyManager(store);
        final settingsRepo = SettingsRepository(db: db, clock: clock);
        final service = AppLockService(
          keyManager: keyManager,
          settings: settingsRepo,
          privacyScreen: const PrivacyScreenService(),
        );
        final cubit = AppLockCubit(service: service, clock: clock);
        addTearDown(cubit.close);

        await cubit.configureLock(
          fallbackPin: '1234',
          useBiometrics: false,
          timeoutSeconds: 30,
        );
        expect(cubit.state.isEnabled, isTrue);
        expect(await cubit.verifyCurrentPin('1234'), isTrue);
        expect(await cubit.verifyCurrentPin('9999'), isFalse);

        // Change PIN cleanly.
        expect(
          await cubit.changePin(currentPin: '9999', newPin: '5678'),
          isFalse,
        );
        expect(
          await cubit.changePin(currentPin: '1234', newPin: '5678'),
          isTrue,
        );

        // Lock and submit 5 wrong PINs -> progressive cooldown engages.
        cubit.lockNow();
        expect(cubit.state.isLocked, isTrue);

        for (var i = 0; i < 5; i++) {
          final ok = await cubit.unlockWithPin('0000');
          expect(ok, isFalse);
        }
        expect(cubit.state.failedAttempts, 5);
        expect(cubit.state.isLockedOutAt(clock.nowUtc()), isTrue);
        expect(cubit.state.remainingLockoutSeconds(clock.nowUtc()), 30);

        // Even the right PIN is blocked during cooldown!
        expect(await cubit.unlockWithPin('5678'), isFalse);

        // After 31 seconds cooldown expires -> valid new PIN unlocks cleanly.
        clock.advance(const Duration(seconds: 31));
        expect(await cubit.unlockWithPin('5678'), isTrue);
        expect(cubit.state.isLocked, isFalse);
        expect(cubit.state.failedAttempts, 0);
      },
    );
  });

  group('Sprint A Privacy Curtain & Responsive UI Parity', () {
    Future<void> initTestApp() async {
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
        clockOverride: FixedUtcClock(DateTime.utc(2026, 11, 19, 10, 0)),
      );
    }

    tearDown(() async {
      if (getIt.isRegistered<AppDatabase>()) {
        await getIt<AppDatabase>().close();
      }
      await getIt.reset();
    });

    testWidgets(
      'SettingsCubit separates App Switcher Privacy Curtain from native Block Screenshots FLAG_SECURE and ActiveProfileCubit targets non-active profile currency cleanly',
      (tester) async {
        await initTestApp();
        final calls = <bool>[];
        const channel = MethodChannel('com.pocketcfo.app/privacy_screen');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'setSecureScreen') {
                final map = call.arguments as Map<dynamic, dynamic>;
                calls.add(map['enabled'] as bool);
              }
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });

        final cubit = SettingsCubit(
          getIt<SettingsRepository>(),
          privacyScreen: getIt<PrivacyScreenService>(),
        );
        addTearDown(cubit.close);

        // Initial load enforces default blockScreenshotsEnabled = true via FLAG_SECURE.
        await cubit.load();
        expect(cubit.state.blockScreenshotsEnabled, isTrue);
        expect(calls, [true]);

        // Toggling recent-apps Privacy Curtain must NOT touch native FLAG_SECURE.
        await cubit.setPrivacyCurtain(false);
        await cubit.setPrivacyCurtain(true);
        expect(calls, [true]);

        // Toggling Block Screenshots directly controls native FLAG_SECURE & persists.
        await cubit.setBlockScreenshots(false);
        expect(cubit.state.blockScreenshotsEnabled, isFalse);
        await cubit.setBlockScreenshots(true);
        expect(cubit.state.blockScreenshotsEnabled, isTrue);
        expect(calls, [true, false, true]);

        // Verify changeProfileBaseCurrency updates a NON-active profile without mutating activeProfile!
        final profileCubit = ActiveProfileCubit(
          repository: getIt(),
          scopeController: getIt(),
          settings: getIt(),
        );
        addTearDown(profileCubit.close);

        final p1 = (await profileCubit.createProfile(
          ownerDisplayName: 'Owner',
          name: 'Personal INR',
          profileType: ProfileType.personal,
          baseCurrencyCode: 'INR',
        )).valueOrNull!;
        final p2 = (await profileCubit.createProfile(
          ownerDisplayName: 'Owner',
          name: 'Business USD',
          profileType: ProfileType.business,
          baseCurrencyCode: 'USD',
        )).valueOrNull!;
        // Active is currently p2 (USD). Update p1 (non-active) to EUR!
        expect(profileCubit.state.activeProfile?.id, p2.id);
        final changed = await profileCubit.changeProfileBaseCurrency(
          profileId: p1.id,
          newCurrencyCode: 'EUR',
        );
        expect(changed.isSuccess, isTrue);
        final updatedP1 = profileCubit.state.profiles.firstWhere(
          (p) => p.id == p1.id,
        );
        final updatedP2 = profileCubit.state.profiles.firstWhere(
          (p) => p.id == p2.id,
        );
        expect(updatedP1.baseCurrencyCode, 'EUR');
        expect(updatedP2.baseCurrencyCode, 'USD');
      },
    );

    testWidgets(
      'SettingsPage Block Screenshots & Recording toggle enforces confirmation dialog (unlocked) and PIN verification (App Lock ON) at 360x800 + 1.5x Dark Mode',
      (tester) async {
        await initTestApp();
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final secureCalls = <bool>[];
        const channel = MethodChannel('com.pocketcfo.app/privacy_screen');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'setSecureScreen') {
                final map = call.arguments as Map<dynamic, dynamic>;
                secureCalls.add(map['enabled'] as bool);
              }
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });

        final settingsCubit = SettingsCubit(
          getIt<SettingsRepository>(),
          privacyScreen: getIt<PrivacyScreenService>(),
        );
        final appLockCubit = AppLockCubit(
          service: _NoBioAppLockService(
            keyManager: getIt<KeyManager>(),
            settings: getIt<SettingsRepository>(),
            privacyScreen: getIt<PrivacyScreenService>(),
          ),
          clock: getIt<UtcClock>(),
        );
        final authCubit = AuthCubit(getIt());
        final activeProfileCubit = ActiveProfileCubit(
          repository: getIt(),
          scopeController: getIt(),
          settings: getIt(),
        );
        addTearDown(() async {
          await settingsCubit.close();
          await appLockCubit.close();
          await authCubit.close();
          await activeProfileCubit.close();
        });

        await settingsCubit.load();
        await appLockCubit.initialize();
        await activeProfileCubit.createProfile(
          ownerDisplayName: 'Owner',
          name: 'Vault',
          profileType: ProfileType.personal,
          baseCurrencyCode: 'INR',
        );

        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider.value(value: settingsCubit),
              BlocProvider.value(value: appLockCubit),
              BlocProvider.value(value: authCubit),
              BlocProvider.value(value: activeProfileCubit),
            ],
            child: MaterialApp(
              theme: AppTheme.dark(),
              builder: (context, w) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.5)),
                child: w!,
              ),
              home: const SettingsPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final toggleFinder = find.byKey(
          const Key('settings_block_screenshots_switch'),
        );
        expect(toggleFinder, findsOneWidget);
        expect(settingsCubit.state.blockScreenshotsEnabled, isTrue);

        // 1. App Lock OFF -> disabling opens confirmation modal.
        await tester.ensureVisible(toggleFinder);
        await tester.pumpAndSettle();
        await tester.tap(toggleFinder);
        await tester.pumpAndSettle();
        expect(find.text('Allow Screenshots & Recording?'), findsOneWidget);

        await tester.tap(find.text('Allow Screenshots'));
        await tester.pumpAndSettle();
        expect(settingsCubit.state.blockScreenshotsEnabled, isFalse);
        expect(secureCalls.last, isFalse);

        // 2. Turning back ON happens immediately without confirmation friction.
        await tester.tap(toggleFinder);
        await tester.pumpAndSettle();
        expect(settingsCubit.state.blockScreenshotsEnabled, isTrue);
        expect(secureCalls.last, isTrue);

        // 3. Enable App Lock -> disabling now requires PIN verification!
        await tester.runAsync(
          () => appLockCubit.configureLock(
            fallbackPin: '1234',
            useBiometrics: false,
            timeoutSeconds: 30,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(toggleFinder);
        await tester.pumpAndSettle();
        expect(find.text('Verify PIN to Allow Screenshots'), findsOneWidget);

        // Wrong PIN keeps protection ON.
        await tester.enterText(find.byType(TextField), '0000');
        await tester.tap(find.text('Allow Screenshots'));
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 500)),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Incorrect PIN. Protection remains active.'),
          findsOneWidget,
        );
        expect(settingsCubit.state.blockScreenshotsEnabled, isTrue);

        // Correct PIN disables screenshot blocking cleanly.
        await tester.enterText(find.byType(TextField), '1234');
        await tester.tap(find.text('Allow Screenshots'));
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 500)),
        );
        await tester.pumpAndSettle();
        expect(settingsCubit.state.blockScreenshotsEnabled, isFalse);
        expect(secureCalls.last, isFalse);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'LoansPage (36-month term), SavingsGoalsPage, and CategoriesPage pass 360x800 + 1.5x Dark Mode privacy & pagination checks',
      (tester) async {
        await initTestApp();
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final activeProfileCubit = ActiveProfileCubit(
          repository: getIt(),
          scopeController: getIt(),
          settings: getIt(),
        );
        final settingsCubit = SettingsCubit(
          getIt<SettingsRepository>(),
          privacyScreen: getIt<PrivacyScreenService>(),
        );
        final dashboardBloc = DashboardBloc(
          analyticsRepository: getIt(),
          scopeController: getIt(),
          budgetRepository: getIt(),
        );
        addTearDown(() async {
          await activeProfileCubit.close();
          await settingsCubit.close();
          await dashboardBloc.close();
        });

        await activeProfileCubit.createProfile(
          ownerDisplayName: 'QA User',
          name: 'QA Vault',
          profileType: ProfileType.personal,
          baseCurrencyCode: 'INR',
        );
        final profile = activeProfileCubit.state.activeProfile!;

        // Seed 36-month loan & savings goal.
        await getIt<DriftLoanRepository>().createLoan(
          profileId: profile.id,
          name: 'Home Solar Loan',
          principalMinor: 3600000,
          currencyCode: 'INR',
          annualInterestRateBps: 900,
          termMonths: 36,
          startDateUtc: DateTime.utc(2026, 11, 19),
        );
        await getIt<SavingsGoalRepository>().createGoal(
          profileId: profile.id,
          name: 'Emergency Reserve',
          targetAmountMinor: 5000000,
          currencyCode: 'INR',
          fundingMode: GoalFundingMode.allocated,
        );

        Widget wrap(Widget child) => MultiBlocProvider(
          providers: [
            BlocProvider.value(value: activeProfileCubit),
            BlocProvider.value(value: settingsCubit),
            BlocProvider.value(value: dashboardBloc),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            builder: (context, w) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: w!,
            ),
            home: child,
          ),
        );

        // 1. LoansPage: expand 36-month loan, switch to Year 3 -> EMI #25 and EMI #36 visible!
        await tester.pumpWidget(wrap(const LoansPage()));
        await tester.pumpAndSettle();
        expect(find.text('Home Solar Loan'), findsOneWidget);

        await tester.tap(find.text('Home Solar Loan'));
        await tester.pumpAndSettle();
        expect(find.text('Year 3'), findsOneWidget);

        await tester.ensureVisible(find.text('Year 3'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Year 3'));
        await tester.pumpAndSettle();
        expect(find.textContaining('EMI #25'), findsOneWidget);
        expect(find.textContaining('EMI #36'), findsOneWidget);

        // Enable hideBalances -> verify masking on LoansPage!
        await settingsCubit.toggleHideBalances();
        await tester.pumpAndSettle();
        expect(find.textContaining('Remaining: ••••'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // 2. SavingsGoalsPage: verify hideBalances masks target, saved, and percentage!
        await tester.pumpWidget(wrap(const SavingsGoalsPage()));
        await tester.pumpAndSettle();
        expect(find.text('Emergency Reserve'), findsOneWidget);
        expect(find.text('••%'), findsOneWidget);
        expect(find.textContaining('••••••'), findsWidgets);
        expect(find.textContaining('50,000'), findsNothing);
        expect(tester.takeException(), isNull);

        // 3. CategoriesPage: verify FintechSegmentedControl switches Expense -> Income cleanly!
        await tester.pumpWidget(wrap(const CategoriesPage()));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('categories_segmented_filter')),
          findsOneWidget,
        );
        await tester.tap(find.text('Income'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Income Categories'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Unmount Drift StreamBuilder cleanly inside FakeAsync and advance clock
        // so StreamQueryStore.markAsClosed zero-duration timer fires before tearDown.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 50));
      },
    );
  });
}
