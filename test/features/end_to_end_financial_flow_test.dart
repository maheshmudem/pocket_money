import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_money/app/config/environment_config.dart';
import 'package:pocket_money/app/theme/app_theme.dart';
import 'package:pocket_money/bootstrap.dart';
import 'package:pocket_money/core/database/app_database.dart';
import 'package:pocket_money/core/database/encrypted_executor.dart';
import 'package:pocket_money/core/errors/failures.dart';
import 'package:pocket_money/core/financial_engine/life_stage_planner_engine.dart';
import 'package:pocket_money/core/financial_engine/monthly_tracker_engine.dart';
import 'package:pocket_money/core/notifications/local_notification_service.dart';
import 'package:pocket_money/core/security/key_manager.dart';
import 'package:pocket_money/core/security/privacy_screen_service.dart';
import 'package:pocket_money/core/utilities/clock.dart';
import 'package:pocket_money/features/accounts/domain/entities/financial_account_entity.dart';
import 'package:pocket_money/features/accounts/domain/repositories/account_repository.dart';
import 'package:pocket_money/features/budgets/data/ca_budget_planner_service.dart';
import 'package:pocket_money/features/categories/domain/entities/category_entity.dart';
import 'package:pocket_money/features/categories/domain/repositories/category_repository.dart';
import 'package:pocket_money/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:pocket_money/features/dashboard/domain/repositories/analytics_repository.dart';
import 'package:pocket_money/features/dashboard/presentation/bloc/dashboard_bloc.dart';
import 'package:pocket_money/features/life_planner/data/life_stage_planner_service.dart';
import 'package:pocket_money/features/life_planner/presentation/pages/life_stage_planner_page.dart';
import 'package:pocket_money/features/loans/data/repositories/drift_loan_repository.dart';
import 'package:pocket_money/features/monthly_tracker/data/monthly_tracker_service.dart';
import 'package:pocket_money/features/monthly_tracker/domain/entities/bucket_list_item_entity.dart';
import 'package:pocket_money/features/monthly_tracker/presentation/pages/monthly_tracker_page.dart';
import 'package:pocket_money/features/profiles/domain/entities/profile_entity.dart';
import 'package:pocket_money/features/profiles/domain/repositories/profile_repository.dart';
import 'package:pocket_money/features/profiles/presentation/bloc/active_profile_cubit.dart';
import 'package:pocket_money/features/recurring/data/repositories/drift_recurring_repository.dart';
import 'package:pocket_money/features/savings_goals/domain/entities/savings_goal_entity.dart';
import 'package:pocket_money/features/savings_goals/domain/repositories/savings_goal_repository.dart';
import 'package:pocket_money/features/settings/data/settings_repository.dart';
import 'package:pocket_money/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:pocket_money/features/transactions/domain/entities/transaction_entity.dart';
import 'package:pocket_money/features/transactions/domain/repositories/transaction_repository.dart';

void main() {
  Future<void> initTestDeps() async {
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
      clockOverride: FixedUtcClock(DateTime.utc(2026, 11, 15, 10, 0)),
      notificationDispatcherOverride: InMemoryNotificationDispatcher(),
    );
    addTearDown(() => getIt<AppDatabase>().close());
  }

  group('End-to-End Financial Flows & Cross-Module Interlinks', () {
    test(
      'verifies opening balances, salary-to-bank interlink, expenses, EMI outflow parity, bucket-goal sync, windfalls & double-entry reconciliation',
      () async {
        await initTestDeps();

        final profileRepo = getIt<ProfileRepository>();
        final accountRepo = getIt<AccountRepository>();
        final catRepo = getIt<CategoryRepository>();
        final txRepo = getIt<TransactionRepository>();
        final analyticsRepo = getIt<AnalyticsRepository>();
        final lifeService = getIt<LifeStagePlannerService>();
        final caBudgetService = getIt<CaBudgetPlannerService>();
        final recurringRepo = getIt<DriftRecurringRepository>();
        final loanRepo = getIt<DriftLoanRepository>();
        final goalRepo = getIt<SavingsGoalRepository>();
        final monthlyService = getIt<MonthlyTrackerService>();

        // -------------------------------------------------------------------
        // CASE 1: Profile + Bank Opening Balances NEVER inflate Monthly Income
        // -------------------------------------------------------------------
        final prof = (await profileRepo.createProfile(
          userId: 'local-owner',
          ownerDisplayName: 'Owner',
          name: 'Household CFO',
          profileType: ProfileType.family,
          baseCurrencyCode: 'INR',
        )).valueOrNull!;

        var hdfc = (await accountRepo.createAccountWithOpeningBalance(
          profileId: prof.id,
          name: 'HDFC Salary Bank',
          accountType: FinancialAccountType.bank,
          currencyCode: 'INR',
          openingBalanceMinor: 5000000, // ₹50,000
          openingDateUtc: DateTime.utc(2026, 11, 1, 9).toIso8601String(),
        )).valueOrNull!;

        var sbi = (await accountRepo.createAccountWithOpeningBalance(
          profileId: prof.id,
          name: 'SBI Savings',
          accountType: FinancialAccountType.bank,
          currencyCode: 'INR',
          openingBalanceMinor: 2500000, // ₹25,000
          openingDateUtc: DateTime.utc(2026, 11, 1, 9).toIso8601String(),
        )).valueOrNull!;

        expect(hdfc.balance.amountMinor, 5000000);
        expect(sbi.balance.amountMinor, 2500000);

        var dash = (await analyticsRepo.computeDashboardSummary(
          prof.id,
          period: DashboardPeriodPreset.thisMonth,
        )).valueOrNull!;
        expect(dash.netWorth.amountMinor, 7500000); // ₹75,000
        expect(dash.periodIncome.amountMinor, 0);

        var monthView = (await monthlyService.loadMonth(
          profile: prof,
          year: 2026,
          month: 11,
        )).valueOrNull!;
        expect(monthView.snapshot.incomeMinor, 0);
        expect(monthView.salaryCreditedThisMonth, isFalse);

        // -------------------------------------------------------------------
        // CASE 2: Life Stage + Planned Salary + Real Expenses + Budget Sync
        // Planned salary MUST NOT fake bank balances until credited.
        // -------------------------------------------------------------------
        await lifeService.savePreferences(
          profileId: prof.id,
          status: LifeStageStatus.familyWithKids,
          dependentsCount: 2,
          housingMode: HousingMode.renting,
          plannedMonthlyIncomeMinor: 10000000, // ₹1,00,000
        );
        await lifeService.saveExpenseProfile(
          profileId: prof.id,
          expenseProfile: const MonthlyExpenseProfile(
            primaryIncomeMinor: 10000000, // ₹1,00,000
            rentOrHousingMinor: 2200000, // ₹22,000
            groceriesMinor: 1200000, // ₹12,000
            utilitiesMinor: 450000, // ₹4,500
            schoolFeesMinor: 800000, // ₹8,000
            insuranceMinor: 300000, // ₹3,000
            subscriptionsMinor: 150000, // ₹1,500
            otherFixedMinor: 350000, // ₹3,500 Society Maintenance
          ),
        );

        final budgetBeforeApply = (await caBudgetService.loadWorkspace(
          profile: prof,
        )).valueOrNull!;
        expect(budgetBeforeApply.suggestedIncomePoolMinor, 10000000);

        var lifeSnap = (await lifeService.loadWorkspace(
          profile: prof,
        )).valueOrNull!;
        expect(lifeSnap.incomePoolMinor, 10000000);
        expect(lifeSnap.salaryCreditedThisMonth, isFalse);

        final appliedBudget = await lifeService.applyLifeStageBudget(
          profile: prof,
          snapshot: lifeSnap,
        );
        expect(appliedBudget.isSuccess, isTrue);

        hdfc = (await accountRepo.getAccount(prof.id, hdfc.id)).valueOrNull!;
        expect(hdfc.balance.amountMinor, 5000000); // Still ₹50,000

        // -------------------------------------------------------------------
        // CASE 3: Credit Monthly Salary -> Bank Account + Duplicate Guard
        // -------------------------------------------------------------------
        final salaryCredit = await lifeService.creditMonthlySalaryToAccount(
          profile: prof,
          accountId: hdfc.id,
          amountMinor: 10000000, // ₹1,00,000
          year: 2026,
          month: 11,
          createRecurringRule: true,
        );
        expect(salaryCredit.isSuccess, isTrue);

        // Idempotent guard blocks accidental double salary credit for same month
        final duplicateSalary = await lifeService.creditMonthlySalaryToAccount(
          profile: prof,
          accountId: hdfc.id,
          amountMinor: 10000000,
          year: 2026,
          month: 11,
        );
        expect(duplicateSalary.isFailure, isTrue);
        expect(duplicateSalary.failureOrNull, isA<ValidationFailure>());

        hdfc = (await accountRepo.getAccount(prof.id, hdfc.id)).valueOrNull!;
        expect(hdfc.balance.amountMinor, 15000000); // ₹1,50,000

        dash = (await analyticsRepo.computeDashboardSummary(
          prof.id,
          period: DashboardPeriodPreset.thisMonth,
        )).valueOrNull!;
        expect(dash.periodIncome.amountMinor, 10000000);
        expect(dash.netWorth.amountMinor, 17500000); // ₹1,75,000

        lifeSnap = (await lifeService.loadWorkspace(
          profile: prof,
        )).valueOrNull!;
        expect(lifeSnap.salaryCreditedThisMonth, isTrue);
        expect(lifeSnap.currentMonthActualIncomeMinor, 10000000);
        expect(lifeSnap.salaryAccountId, hdfc.id);

        final rules = (await recurringRepo.listRules(prof.id)).valueOrNull!;
        expect(
          rules.any(
            (r) =>
                r.status == 'active' &&
                r.transactionType == TransactionType.income &&
                r.name == 'Monthly Salary' &&
                r.destinationAccountId == hdfc.id,
          ),
          isTrue,
        );

        // -------------------------------------------------------------------
        // CASE 4: Real Expenses (Rent, Groceries, Utilities, Society Maint.)
        // -------------------------------------------------------------------
        final expCats = (await catRepo.listCategories(
          prof.id,
          type: CategoryType.expense,
        )).valueOrNull!;

        CategoryEntity findOrErrCat(String keyword) => expCats.firstWhere(
          (c) => c.name.toLowerCase().contains(keyword.toLowerCase()),
        );

        final rentCat = findOrErrCat('rent');
        final groceriesCat = findOrErrCat('grocer');
        final utilCat = findOrErrCat('util');
        final maintCat = (await catRepo.createCategory(
          profileId: prof.id,
          name: 'Society Maintenance',
          categoryType: CategoryType.expense,
          iconKey: 'build',
        )).valueOrNull!;

        for (final exp in [
          (cat: rentCat.id, amt: 2200000, desc: 'November Rent'),
          (cat: groceriesCat.id, amt: 1200000, desc: 'Supermarket Groceries'),
          (cat: utilCat.id, amt: 450000, desc: 'Power & Fiber Wi-Fi'),
          (cat: maintCat.id, amt: 350000, desc: 'Society Maintenance'),
        ]) {
          final res = await txRepo.createTransaction(
            prof.id,
            CreateTransactionCommand(
              type: TransactionType.expense,
              amountMinor: exp.amt,
              currencyCode: 'INR',
              transactionDateUtc: DateTime.utc(
                2026,
                11,
                5,
                12,
              ).toIso8601String(),
              sourceAccountId: hdfc.id,
              categoryId: exp.cat,
              description: exp.desc,
            ),
          );
          expect(res.isSuccess, isTrue);
        }

        // Total expenses = ₹22,000 + ₹12,000 + ₹4,500 + ₹3,500 = ₹42,000
        hdfc = (await accountRepo.getAccount(prof.id, hdfc.id)).valueOrNull!;
        expect(hdfc.balance.amountMinor, 10800000); // ₹1,08,000

        dash = (await analyticsRepo.computeDashboardSummary(
          prof.id,
          period: DashboardPeriodPreset.thisMonth,
        )).valueOrNull!;
        expect(dash.periodNetExpense.amountMinor, 4200000);

        monthView = (await monthlyService.loadMonth(
          profile: prof,
          year: 2026,
          month: 11,
        )).valueOrNull!;
        expect(monthView.snapshot.incomeMinor, 10000000);
        expect(monthView.snapshot.spentMinor, 4200000);
        expect(monthView.snapshot.savedMinor, 5800000);

        // Verify 'Society Maintenance' is cleanly classified under otherFixedMinor
        final autoFilled = (await lifeService.autoFillExpensesFromLedger(
          profile: prof,
        )).valueOrNull!;
        expect(autoFilled.rentOrHousingMinor, 2200000);
        expect(autoFilled.groceriesMinor, 1200000);
        expect(autoFilled.utilitiesMinor, 450000);
        expect(autoFilled.otherFixedMinor, 350000);

        // -------------------------------------------------------------------
        // CASE 5: Loan EMI Payment Integrity (Zero Phantom Free-to-Spend Jump)
        // -------------------------------------------------------------------
        final loan = (await loanRepo.createLoan(
          profileId: prof.id,
          name: 'Home Bike Loan',
          principalMinor: 12000000, // ₹1,20,000
          currencyCode: 'INR',
          annualInterestRateBps: 1200, // 12%
          termMonths: 12,
          startDateUtc: DateTime.utc(2026, 10, 20), // #1 due 2026-11-20
          fundingAccountId: hdfc.id,
        )).valueOrNull!;
        final firstInst = loan.installments.first;
        final emiAmount = firstInst.totalDueMinor;
        final interestPortion = firstInst.interestDueMinor;

        final beforeEmiMonth = (await monthlyService.loadMonth(
          profile: prof,
          year: 2026,
          month: 11,
        )).valueOrNull!;
        expect(beforeEmiMonth.snapshot.committedRemainingMinor, emiAmount);
        final dashBeforeEmi = (await analyticsRepo.computeDashboardSummary(
          prof.id,
          period: DashboardPeriodPreset.thisMonth,
        )).valueOrNull!;

        final payEmiRes = await loanRepo.payInstallment(
          profileId: prof.id,
          loanId: loan.id,
          installmentId: firstInst.id,
          sourceBankAccountId: hdfc.id,
        );
        expect(payEmiRes.isSuccess, isTrue);

        hdfc = (await accountRepo.getAccount(prof.id, hdfc.id)).valueOrNull!;
        expect(hdfc.balance.amountMinor, 10800000 - emiAmount);

        final afterEmiMonth = (await monthlyService.loadMonth(
          profile: prof,
          year: 2026,
          month: 11,
        )).valueOrNull!;
        expect(afterEmiMonth.snapshot.spentMinor, 4200000 + emiAmount);
        expect(afterEmiMonth.snapshot.committedRemainingMinor, 0);
        expect(
          afterEmiMonth.snapshot.freeToSpendMinor,
          beforeEmiMonth.snapshot.freeToSpendMinor,
        );
        expect(
          afterEmiMonth.snapshot.topCategories.any(
            (c) => c.name == 'Loan EMIs' && c.amountMinor == emiAmount,
          ),
          isTrue,
        );

        final dashAfterEmi = (await analyticsRepo.computeDashboardSummary(
          prof.id,
          period: DashboardPeriodPreset.thisMonth,
        )).valueOrNull!;
        // Net Worth drops ONLY by the interest portion (principal lowers Asset & Liability equally)
        expect(
          dashBeforeEmi.netWorth.amountMinor -
              dashAfterEmi.netWorth.amountMinor,
          interestPortion,
        );

        // -------------------------------------------------------------------
        // CASE 6: Bucket List (+ Fund ring-fenced, Convert to Goal sync, Buy debit)
        // -------------------------------------------------------------------
        final acRepair = (await monthlyService.saveItem(
          profile: prof,
          name: 'AC Repair',
          estimatedAmountMinor: 400000, // ₹4,000
          priority: BucketPriority.urgent,
          targetYearMonth: '2026-11',
        )).valueOrNull!;
        final laptopUpgrade = (await monthlyService.saveItem(
          profile: prof,
          name: 'Laptop Upgrade',
          estimatedAmountMinor: 3000000, // ₹30,000
          priority: BucketPriority.dream,
          targetYearMonth: '2026-11',
        )).valueOrNull!;

        // + Fund ₹1,000 ring-fences in Tracker without debiting HDFC Bank
        final bankBalBeforeFund = (await accountRepo.getAccount(
          prof.id,
          hdfc.id,
        )).valueOrNull!.balance.amountMinor;
        await monthlyService.addFunds(prof, acRepair, 100000);
        expect(
          (await accountRepo.getAccount(
            prof.id,
            hdfc.id,
          )).valueOrNull!.balance.amountMinor,
          bankBalBeforeFund,
        );

        // Convert Laptop Upgrade to Goal & contribute ₹5,000 -> Bucket plan sees ₹5,000 funded
        final converted = await monthlyService.convertToGoal(
          profile: prof,
          item: laptopUpgrade,
        );
        expect(converted.isSuccess, isTrue);
        final linkedGoalId = converted.valueOrNull!.linkedGoalId!;
        await goalRepo.recordContribution(
          profileId: prof.id,
          goalId: linkedGoalId,
          amountMinor: 500000, // ₹5,000
        );
        final viewAfterGoalSync = (await monthlyService.loadMonth(
          profile: prof,
          year: 2026,
          month: 11,
        )).valueOrNull!;
        final syncedLaptop = viewAfterGoalSync.thisMonthItems.firstWhere(
          (b) => b.id == laptopUpgrade.id,
        );
        expect(syncedLaptop.savedAmountMinor, 500000);

        // Buy AC Repair for actual ₹3,800 from HDFC -> debits HDFC & logs expense
        final buyRes = await monthlyService.markPurchased(
          profile: prof,
          item: acRepair,
          actualAmountMinor: 380000,
          accountId: hdfc.id,
          categoryId: utilCat.id,
          dateUtc: DateTime.utc(2026, 11, 15, 11),
        );
        expect(buyRes.isSuccess, isTrue);
        hdfc = (await accountRepo.getAccount(prof.id, hdfc.id)).valueOrNull!;
        expect(hdfc.balance.amountMinor, bankBalBeforeFund - 380000);

        final viewAfterBuy = (await monthlyService.loadMonth(
          profile: prof,
          year: 2026,
          month: 11,
        )).valueOrNull!;
        expect(viewAfterBuy.snapshot.spentMinor, 4200000 + emiAmount + 380000);

        // -------------------------------------------------------------------
        // CASE 7: Extra Income Splits (Cross-Account Goal Transfer + Same-Account Direct Deposit)
        // -------------------------------------------------------------------
        final sbiTransferGoal = (await goalRepo.createGoal(
          profileId: prof.id,
          name: 'SBI Emergency Vault',
          targetAmountMinor: 5000000, // ₹50,000
          currencyCode: 'INR',
          fundingMode: GoalFundingMode.accountTransfer,
          linkedAccountId: sbi.id,
        )).valueOrNull!;

        final hdfcBeforeBonus = hdfc.balance.amountMinor;
        final sbiBeforeBonus = (await accountRepo.getAccount(
          prof.id,
          sbi.id,
        )).valueOrNull!.balance.amountMinor;

        // 7a: ₹20,000 Bonus into HDFC -> 50% (₹10,000) transfers to SBI Vault Goal
        final bonusSplit = MonthlyTrackerEngine.presetSplit(2000000, 50, 30);
        final bonusRes = await monthlyService.recordExtraIncome(
          profile: prof,
          amountMinor: 2000000,
          sourceLabel: 'Annual Bonus',
          accountId: hdfc.id,
          dateUtc: DateTime.utc(2026, 11, 15, 12),
          split: bonusSplit,
          goalId: sbiTransferGoal.id,
        );
        expect(bonusRes.isSuccess, isTrue);

        hdfc = (await accountRepo.getAccount(prof.id, hdfc.id)).valueOrNull!;
        sbi = (await accountRepo.getAccount(prof.id, sbi.id)).valueOrNull!;
        expect(hdfc.balance.amountMinor, hdfcBeforeBonus + 2000000 - 1000000);
        expect(sbi.balance.amountMinor, sbiBeforeBonus + 1000000);

        // 7b: ₹5,000 Cashback deposited directly into SBI Savings & earmarked 100%
        // to the SAME SBI Savings account_transfer goal (must not fail same-account transfer!)
        final cashbackSplit = MonthlyTrackerEngine.presetSplit(500000, 100, 0);
        final cashbackRes = await monthlyService.recordExtraIncome(
          profile: prof,
          amountMinor: 500000,
          sourceLabel: 'Bank Cashback',
          accountId: sbi.id,
          dateUtc: DateTime.utc(2026, 11, 15, 13),
          split: cashbackSplit,
          goalId: sbiTransferGoal.id,
        );
        expect(cashbackRes.isSuccess, isTrue);

        sbi = (await accountRepo.getAccount(prof.id, sbi.id)).valueOrNull!;
        expect(sbi.balance.amountMinor, sbiBeforeBonus + 1000000 + 500000);
        final goalsAfter = (await goalRepo.listGoals(prof.id)).valueOrNull!;
        final sbiGoalAfter = goalsAfter.firstWhere(
          (g) => g.id == sbiTransferGoal.id,
        );
        expect(sbiGoalAfter.contributedAmount.amountMinor, 1500000); // ₹15,000

        // -------------------------------------------------------------------
        // CASE 8: Full Double-Entry Ledger Reconciliation (Debits == Credits)
        // -------------------------------------------------------------------
        final recon = (await txRepo.runReconciliationCheck(
          prof.id,
        )).valueOrNull!;
        expect(recon.isHealthy, isTrue);
        expect(recon.unbalancedJournalIds, isEmpty);
        expect(recon.orphanPostingCount, 0);
        expect(recon.totalDebitsMinor, recon.totalCreditsMinor);
      },
    );

    testWidgets(
      'Credit Salary interlink card & dialog work seamlessly at 360x800 + 1.5x text scale in Light and Dark themes',
      (tester) async {
        await initTestDeps();

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

        final prof = (await activeProfileCubit.createProfile(
          ownerDisplayName: 'Owner',
          name: 'UI Salary Test',
          profileType: ProfileType.personal,
          baseCurrencyCode: 'INR',
        )).valueOrNull!;
        final bank =
            (await getIt<AccountRepository>().createAccountWithOpeningBalance(
              profileId: prof.id,
              name: 'HDFC Bank',
              accountType: FinancialAccountType.bank,
              currencyCode: 'INR',
              openingBalanceMinor: 1000000, // ₹10,000
            )).valueOrNull!;

        await getIt<LifeStagePlannerService>().savePreferences(
          profileId: prof.id,
          status: LifeStageStatus.bachelor,
          dependentsCount: 0,
          housingMode: HousingMode.renting,
          plannedMonthlyIncomeMinor: 7500000, // ₹75,000
        );

        // 1. Check Monthly Tracker 1-tap Credit Salary button at 360x800 + 1.5x Dark Mode
        await tester.pumpWidget(
          MultiBlocProvider(
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
              home: const MonthlyTrackerPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('monthly_credit_salary_btn')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const Key('monthly_credit_salary_btn')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('credit_salary_confirm_btn')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const Key('credit_salary_confirm_btn')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final updatedBank = (await getIt<AccountRepository>().getAccount(
          prof.id,
          bank.id,
        )).valueOrNull!;
        expect(updatedBank.balance.amountMinor, 8500000); // ₹10k + ₹75k

        // 2. Check Life & EMI Planner Salary-Bank Link Card in Light Mode at 360x800 + 1.5x
        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider.value(value: activeProfileCubit),
              BlocProvider.value(value: settingsCubit),
              BlocProvider.value(value: dashboardBloc),
            ],
            child: MaterialApp(
              theme: AppTheme.light(),
              builder: (context, w) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.5)),
                child: w!,
              ),
              home: const LifeStagePlannerPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final cardFinder = find.byKey(const Key('life_salary_bank_card'));
        await tester.scrollUntilVisible(
          cardFinder,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(cardFinder, findsOneWidget);
        expect(find.text('Credited'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
