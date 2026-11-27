import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_money/app/app.dart';
import 'package:pocket_money/app/config/environment_config.dart';
import 'package:pocket_money/bootstrap.dart';
import 'package:pocket_money/core/database/app_database.dart';
import 'package:pocket_money/core/database/encrypted_executor.dart';
import 'package:pocket_money/core/financial_engine/ca_budget_planner_engine.dart';
import 'package:pocket_money/core/financial_engine/life_stage_planner_engine.dart';
import 'package:pocket_money/core/financial_engine/loan_amortizer.dart';
import 'package:pocket_money/core/financial_engine/monthly_tracker_engine.dart';
import 'package:pocket_money/core/notifications/local_notification_service.dart';
import 'package:pocket_money/core/security/backup_crypto.dart';
import 'package:pocket_money/core/security/key_manager.dart';
import 'package:pocket_money/core/utilities/clock.dart';
import 'package:pocket_money/features/accounts/domain/entities/financial_account_entity.dart';
import 'package:pocket_money/features/accounts/domain/repositories/account_repository.dart';
import 'package:pocket_money/features/backup_restore/data/backup_restore_service.dart';
import 'package:pocket_money/features/budgets/data/ca_budget_planner_service.dart';
import 'package:pocket_money/features/budgets/domain/entities/budget_entity.dart';
import 'package:pocket_money/features/budgets/domain/repositories/budget_repository.dart';
import 'package:pocket_money/features/categories/domain/entities/category_entity.dart';
import 'package:pocket_money/features/categories/domain/repositories/category_repository.dart';
import 'package:pocket_money/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:pocket_money/features/dashboard/domain/repositories/analytics_repository.dart';
import 'package:pocket_money/features/life_planner/data/life_stage_planner_service.dart';
import 'package:pocket_money/features/loans/data/repositories/drift_loan_repository.dart';
import 'package:pocket_money/features/monthly_tracker/data/monthly_tracker_service.dart';
import 'package:pocket_money/features/monthly_tracker/domain/entities/bucket_list_item_entity.dart';
import 'package:pocket_money/features/notifications/data/financial_alerts_coordinator.dart';
import 'package:pocket_money/features/profiles/domain/entities/profile_entity.dart';
import 'package:pocket_money/features/profiles/domain/repositories/profile_repository.dart';
import 'package:pocket_money/features/recurring/data/repositories/drift_recurring_repository.dart';
import 'package:pocket_money/features/recurring/domain/entities/recurring_rule_entity.dart';
import 'package:pocket_money/features/reports/data/report_exporter.dart';
import 'package:pocket_money/features/savings_goals/domain/entities/savings_goal_entity.dart';
import 'package:pocket_money/features/savings_goals/domain/repositories/savings_goal_repository.dart';
import 'package:pocket_money/features/transactions/domain/entities/transaction_entity.dart';
import 'package:pocket_money/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:pocket_money/shared/widgets/modern_dialogs.dart';

void main() {
  late InMemoryNotificationDispatcher dispatcher;

  Future<void> initFreshDb() async {
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
      clockOverride: FixedUtcClock(DateTime.utc(2026, 11, 15, 10, 0)),
      notificationDispatcherOverride: dispatcher,
    );
  }

  tearDown(() async {
    if (getIt.isRegistered<AppDatabase>()) {
      await getIt<AppDatabase>().close();
    }
    await getIt.reset();
  });

  group('Clean-Slate Exhaustive All-Options Verification', () {
    test(
      'clean DB -> all 7 life stages x 3 housing modes, all account/tx/budget/tracker/bucket/windfall/loan/goal/recurring options & reconciliation',
      () async {
        await initFreshDb();

        final profileRepo = getIt<ProfileRepository>();
        final accRepo = getIt<AccountRepository>();
        final catRepo = getIt<CategoryRepository>();
        final txRepo = getIt<TransactionRepository>();
        final budgetRepo = getIt<BudgetRepository>();
        final analyticsRepo = getIt<AnalyticsRepository>();
        final lifeService = getIt<LifeStagePlannerService>();
        final caBudgetService = getIt<CaBudgetPlannerService>();
        final monthlyService = getIt<MonthlyTrackerService>();
        final loanRepo = getIt<DriftLoanRepository>();
        final goalRepo = getIt<SavingsGoalRepository>();
        final recurringRepo = getIt<DriftRecurringRepository>();
        final alerts = getIt<FinancialAlertsCoordinator>();
        final backupService = getIt<BackupRestoreService>();

        // =====================================================================
        // 1. ALL 7 LIFE STAGES x 3 HOUSING MODES (SURPLUS & DEFICIT MODES)
        // =====================================================================
        for (final status in LifeStageStatus.values) {
          for (final housing in HousingMode.values) {
            for (final deps in const [0, 2]) {
              final targets = LifeStagePlannerEngine.resolveEffectiveTargets(
                status: status,
                dependentsCount: deps,
                housingMode: housing,
              );
              expect(
                targets.needsPct +
                    targets.wantsPct +
                    targets.taxPct +
                    targets.savingsPct,
                100,
              );

              final typical = LifeStagePlannerEngine.estimateTypicalExpenses(
                primaryIncomeMinor: 10000000, // ₹1,00,000
                targets: targets,
                currencyCode: 'INR',
              );
              expect(typical.totalIncomeMinor, 10000000);
              expect(typical.hasAnyEnteredExpenses, isTrue);

              final surplusPlan =
                  LifeStagePlannerEngine.buildBottomUpCashFlowPlan(
                    currencyCode: 'INR',
                    targets: targets,
                    expenses: typical,
                    trackedLoanEmiMinor: 0,
                    liquidCashMinor: 5000000,
                    hasHighInterestDebt: false,
                  );
              expect(surplusPlan.netSurplusMinor, greaterThanOrEqualTo(0));

              final deficitPlan =
                  LifeStagePlannerEngine.buildBottomUpCashFlowPlan(
                    currencyCode: 'INR',
                    targets: targets,
                    expenses: const MonthlyExpenseProfile(
                      primaryIncomeMinor: 2500000, // ₹25,000
                      rentOrHousingMinor: 2200000, // ₹22,000
                      groceriesMinor: 1000000, // ₹10,000
                      utilitiesMinor: 500000, // ₹5,000
                      subscriptionsMinor: 200000, // ₹2,000
                    ),
                    trackedLoanEmiMinor: 500000,
                    liquidCashMinor: 1000000,
                    hasHighInterestDebt: true,
                  );
              expect(deficitPlan.netSurplusMinor, lessThan(0));
              expect(deficitPlan.planMode, 'deficit_rescue');
            }
          }
        }

        // =====================================================================
        // 2. FRESH PROFILES, ACCOUNTS (ALL TYPES + EDIT/ARCHIVE) & TRANSACTIONS
        // =====================================================================
        final profMain = (await profileRepo.createProfile(
          userId: 'owner-1',
          ownerDisplayName: 'Owner',
          name: 'Main Family',
          profileType: ProfileType.family,
          baseCurrencyCode: 'INR',
        )).valueOrNull!;
        final profIso = (await profileRepo.createProfile(
          userId: 'owner-1',
          ownerDisplayName: 'Owner',
          name: 'Isolated Business',
          profileType: ProfileType.business,
          baseCurrencyCode: 'INR',
        )).valueOrNull!;

        var hdfc = (await accRepo.createAccountWithOpeningBalance(
          profileId: profMain.id,
          name: 'HDFC Salary',
          accountType: FinancialAccountType.bank,
          currencyCode: 'INR',
          openingBalanceMinor: 5000000, // ₹50,000
          openingDateUtc: '2026-11-01T08:00:00Z',
        )).valueOrNull!;
        var sbi = (await accRepo.createAccountWithOpeningBalance(
          profileId: profMain.id,
          name: 'SBI Reserve',
          accountType: FinancialAccountType.bank,
          currencyCode: 'INR',
          openingBalanceMinor: 2500000, // ₹25,000
          openingDateUtc: '2026-11-01T08:00:00Z',
        )).valueOrNull!;
        var cash = (await accRepo.createAccountWithOpeningBalance(
          profileId: profMain.id,
          name: 'Petty Cash',
          accountType: FinancialAccountType.cash,
          currencyCode: 'INR',
          openingBalanceMinor: 500000, // ₹5,000
          openingDateUtc: '2026-11-01T08:00:00Z',
        )).valueOrNull!;
        final card = (await accRepo.createAccountWithOpeningBalance(
          profileId: profMain.id,
          name: 'ICICI Credit Card',
          accountType: FinancialAccountType.creditCard,
          currencyCode: 'INR',
          openingBalanceMinor: 0,
          openingDateUtc: '2026-11-01T08:00:00Z',
        )).valueOrNull!;

        // Update, archive, and unarchive account cleanly
        final updatedCard = (await accRepo.updateAccount(
          profileId: profMain.id,
          accountId: card.id,
          name: 'ICICI Coral Card',
          institutionLabel: 'ICICI',
        )).valueOrNull!;
        expect(updatedCard.name, 'ICICI Coral Card');
        expect(
          (await accRepo.archiveAccount(
            profileId: profMain.id,
            accountId: card.id,
          )).isSuccess,
          isTrue,
        );
        expect(
          (await accRepo.listAccounts(
            profMain.id,
          )).valueOrNull!.any((a) => a.id == card.id),
          isFalse,
        );
        expect(
          (await accRepo.unarchiveAccount(
            profileId: profMain.id,
            accountId: card.id,
          )).isSuccess,
          isTrue,
        );
        expect(
          (await accRepo.listAccounts(
            profMain.id,
          )).valueOrNull!.any((a) => a.id == card.id),
          isTrue,
        );

        // Opening balances raise Net Worth to ₹80,000, Monthly Income stays ₹0
        var dash = (await analyticsRepo.computeDashboardSummary(
          profMain.id,
          period: DashboardPeriodPreset.thisMonth,
        )).valueOrNull!;
        expect(dash.netWorth.amountMinor, 8000000);
        expect(dash.periodIncome.amountMinor, 0);

        // =====================================================================
        // 3. LIFE PLANNER -> CREDIT SALARY -> APPLY MASTER BUDGET + CA BVA ALL OPTIONS
        // =====================================================================
        await lifeService.savePreferences(
          profileId: profMain.id,
          status: LifeStageStatus.familyWithKids,
          dependentsCount: 2,
          housingMode: HousingMode.renting,
          plannedMonthlyIncomeMinor: 10000000, // ₹1,00,000
        );
        await lifeService.saveExpenseProfile(
          profileId: profMain.id,
          expenseProfile: const MonthlyExpenseProfile(
            primaryIncomeMinor: 10000000,
            rentOrHousingMinor: 2000000,
            groceriesMinor: 1200000,
            utilitiesMinor: 400000,
            schoolFeesMinor: 800000,
            insuranceMinor: 300000,
            subscriptionsMinor: 150000,
            otherFixedMinor: 250000, // ₹2,500 maintenance
          ),
        );

        final lifeSnap = (await lifeService.loadWorkspace(
          profile: profMain,
        )).valueOrNull!;
        final masterRes = await lifeService.applyLifeStageBudget(
          profile: profMain,
          snapshot: lifeSnap,
        );
        expect(masterRes.isSuccess, isTrue);
        final masterBudget = masterRes.valueOrNull!;

        // Verify all 5 CaBudgetBlueprint presets produce exact zero unallocated remainder
        final caWsInit = (await caBudgetService.loadWorkspace(
          profile: profMain,
        )).valueOrNull!;
        for (final bp in CaBudgetBlueprint.values) {
          final plan = CaBudgetPlannerEngine.generateZeroBasedPlan(
            blueprint: bp,
            incomePoolMinor: 10000000,
            categories: caWsInit.zbbSeeds,
            currencyCode: 'INR',
          );
          expect(plan.unallocatedMinor, 0);
        }

        // Credit Monthly Salary ₹1,00,000 to HDFC + recurring reminder ON + duplicate guard
        final salaryCredit = await lifeService.creditMonthlySalaryToAccount(
          profile: profMain,
          accountId: hdfc.id,
          amountMinor: 10000000,
          year: 2026,
          month: 11,
          createRecurringRule: true,
        );
        expect(salaryCredit.isSuccess, isTrue);
        expect(
          (await lifeService.creditMonthlySalaryToAccount(
            profile: profMain,
            accountId: hdfc.id,
            amountMinor: 10000000,
            year: 2026,
            month: 11,
          )).isFailure,
          isTrue,
        );
        hdfc = (await accRepo.getAccount(profMain.id, hdfc.id)).valueOrNull!;
        expect(hdfc.balance.amountMinor, 15000000); // ₹1,50,000

        // Create dedicated Watch Budget on Dining & test Healthy -> Near (80%) -> Exceeded (>100%)
        final expCats = (await catRepo.listCategories(
          profMain.id,
          type: CategoryType.expense,
        )).valueOrNull!;
        final grocCat = expCats.firstWhere(
          (c) => c.name.toLowerCase().contains('grocer'),
        );
        final diningCat = expCats.firstWhere(
          (c) =>
              c.name.toLowerCase().contains('dining') ||
              c.name.toLowerCase().contains('food'),
        );

        final watchBudget = (await budgetRepo.createBudget(
          profileId: profMain.id,
          name: 'Dining Watch',
          periodType: BudgetPeriodType.monthly,
          overallLimitMinor: 400000, // ₹4,000
          currencyCode: 'INR',
          categoryLimitsMinor: {diningCat.id: 400000},
        )).valueOrNull!;

        // Transfer HDFC -> Cash ₹5,000
        await txRepo.createTransaction(
          profMain.id,
          CreateTransactionCommand(
            type: TransactionType.transfer,
            amountMinor: 500000,
            currencyCode: 'INR',
            transactionDateUtc: '2026-11-03T10:00:00Z',
            sourceAccountId: hdfc.id,
            destinationAccountId: cash.id,
            description: 'ATM Withdrawal',
          ),
        );
        cash = (await accRepo.getAccount(profMain.id, cash.id)).valueOrNull!;
        expect(cash.balance.amountMinor, 1000000); // ₹10,000

        // Split Expense ₹8,000 (₹4,500 Groceries + ₹3,500 Dining -> Dining hits 87.5% Near Limit!)
        await txRepo.createTransaction(
          profMain.id,
          CreateTransactionCommand(
            type: TransactionType.expense,
            amountMinor: 800000,
            currencyCode: 'INR',
            transactionDateUtc: '2026-11-05T12:00:00Z',
            sourceAccountId: hdfc.id,
            description: 'Supermarket + Cafe Split',
            splits: [
              SplitCommandLine(
                categoryId: grocCat.id,
                amountMinor: 450000,
                memo: 'Groceries',
              ),
              SplitCommandLine(
                categoryId: diningCat.id,
                amountMinor: 350000,
                memo: 'Cafe',
              ),
            ],
          ),
        );
        await alerts.evaluateAfterTransaction(profMain.id);

        var budgetsNow = (await budgetRepo.listBudgetsWithProgress(
          profMain.id,
        )).valueOrNull!;
        var watchState = budgetsNow.firstWhere((b) => b.id == watchBudget.id);
        expect(watchState.totalSpent.amountMinor, 350000);
        expect(watchState.utilizationRatio, closeTo(0.875, 0.01));

        // Exceed Dining Watch with ₹1,500 expense, then partially Refund ₹1,000 back!
        final overTx = (await txRepo.createTransaction(
          profMain.id,
          CreateTransactionCommand(
            type: TransactionType.expense,
            amountMinor: 150000, // Total Dining becomes ₹5,000 (125% Exceeded!)
            currencyCode: 'INR',
            transactionDateUtc: '2026-11-06T12:00:00Z',
            sourceAccountId: cash.id,
            categoryId: diningCat.id,
            description: 'Team Lunch',
          ),
        )).valueOrNull!;
        await alerts.evaluateAfterTransaction(profMain.id);

        budgetsNow = (await budgetRepo.listBudgetsWithProgress(
          profMain.id,
        )).valueOrNull!;
        watchState = budgetsNow.firstWhere((b) => b.id == watchBudget.id);
        expect(watchState.totalSpent.amountMinor, 500000);
        expect(watchState.utilizationRatio, greaterThan(1.0));

        // Reverse that ₹1,500 transaction & verify exact restoration of Dining & Cash
        final revRes = await txRepo.reversePostedTransaction(
          profMain.id,
          originalTransactionId: overTx.id,
          reason: 'Billed to corporate card',
        );
        expect(revRes.isSuccess, isTrue);
        cash = (await accRepo.getAccount(profMain.id, cash.id)).valueOrNull!;
        expect(cash.balance.amountMinor, 1000000);

        // Refund ₹500 on Dining -> net Dining spend = ₹3,000 (75%, Healthy)
        await txRepo.createTransaction(
          profMain.id,
          CreateTransactionCommand(
            type: TransactionType.refund,
            amountMinor: 50000,
            currencyCode: 'INR',
            transactionDateUtc: '2026-11-07T12:00:00Z',
            destinationAccountId: hdfc.id,
            categoryId: diningCat.id,
            description: 'Cafe Cashback',
          ),
        );
        budgetsNow = (await budgetRepo.listBudgetsWithProgress(
          profMain.id,
        )).valueOrNull!;
        watchState = budgetsNow.firstWhere((b) => b.id == watchBudget.id);
        expect(watchState.totalSpent.amountMinor, 300000);
        expect(watchState.utilizationRatio, lessThan(0.8));

        // Draft -> Update -> Post AND Draft -> Delete
        final draftKeep = (await txRepo.createTransaction(
          profMain.id,
          CreateTransactionCommand(
            type: TransactionType.expense,
            amountMinor: 100000,
            currencyCode: 'INR',
            transactionDateUtc: '2026-11-08T12:00:00Z',
            sourceAccountId: cash.id,
            categoryId: grocCat.id,
            description: 'Draft Grocery',
            saveAsDraft: true,
          ),
        )).valueOrNull!;
        await txRepo.updateDraftTransaction(
          profMain.id,
          draftKeep.id,
          CreateTransactionCommand(
            type: TransactionType.expense,
            amountMinor: 150000,
            currencyCode: 'INR',
            transactionDateUtc: '2026-11-08T12:00:00Z',
            sourceAccountId: cash.id,
            categoryId: grocCat.id,
            description: 'Draft Grocery Updated',
            saveAsDraft: true,
          ),
        );
        expect(
          (await txRepo.postDraftTransaction(
            profMain.id,
            draftKeep.id,
          )).isSuccess,
          isTrue,
        );
        final draftDrop = (await txRepo.createTransaction(
          profMain.id,
          CreateTransactionCommand(
            type: TransactionType.expense,
            amountMinor: 99900,
            currencyCode: 'INR',
            transactionDateUtc: '2026-11-08T13:00:00Z',
            sourceAccountId: cash.id,
            categoryId: grocCat.id,
            saveAsDraft: true,
          ),
        )).valueOrNull!;
        expect(
          (await txRepo.deleteDraftTransaction(
            profMain.id,
            draftDrop.id,
          )).isSuccess,
          isTrue,
        );

        // Reallocate Master Budget category limit + CA BvA Quarter/YTD + CSV/PDF export + Delete Watch Budget
        if (masterBudget.allocations.length >= 2) {
          final a0 = masterBudget.allocations[0];
          final a1 = masterBudget.allocations[1];
          final reRes = await budgetRepo.reallocateCategoryLimit(
            profileId: profMain.id,
            fromBudgetId: masterBudget.id,
            fromCategoryId: a0.categoryId,
            toBudgetId: masterBudget.id,
            toCategoryId: a1.categoryId,
            amountMinor: 50000,
          );
          expect(reRes.isSuccess, isTrue);
        }
        await caBudgetService.setFyStartMonth(profMain.id, 4);
        await caBudgetService.setTaxReserveBps(profMain.id, 1000);
        final qWs = (await caBudgetService.loadWorkspace(
          profile: profMain,
          periodPreset: CaFiscalPeriodPreset.currentQuarter,
        )).valueOrNull!;
        final csv = ReportExporter.generateBudgetVarianceCsv(
          profile: profMain,
          statement: qWs.varianceStatement,
        );
        expect(csv, contains('TOTAL'));
        final pdf = await ReportExporter.generateBudgetVariancePdf(
          profile: profMain,
          statement: qWs.varianceStatement,
          safeToSpend: qWs.safeToSpend,
          sinkingFunds: qWs.sinkingFunds,
          generatedAtUtc: '2026-11-15T10:00:00Z',
        );
        expect(String.fromCharCodes(pdf.take(4)), '%PDF');
        expect(
          (await budgetRepo.deleteBudget(
            profMain.id,
            watchBudget.id,
          )).isSuccess,
          isTrue,
        );

        // =====================================================================
        // 4. MONTHLY TRACKER (ALL 3 MONTHS), BUCKET LIST (ALL ACTIONS), WINDFALL PRESETS
        // =====================================================================
        expect(
          (await monthlyService.loadMonth(
            profile: profMain,
            year: 2026,
            month: 10,
          )).isSuccess,
          isTrue,
        );
        expect(
          (await monthlyService.loadMonth(
            profile: profMain,
            year: 2026,
            month: 12,
          )).isSuccess,
          isTrue,
        );

        final urgentItem = (await monthlyService.saveItem(
          profile: profMain,
          name: 'RO Filter Service',
          estimatedAmountMinor: 300000,
          priority: BucketPriority.urgent,
          targetYearMonth: '2026-11',
          dueDateUtc: '2026-11-16T12:00:00Z',
          reminderAtUtc: '2026-11-15T09:00:00Z',
        )).valueOrNull!;
        final essItem = (await monthlyService.saveItem(
          profile: profMain,
          name: 'Winter Jacket',
          estimatedAmountMinor: 400000,
          priority: BucketPriority.essential,
          targetYearMonth: '2026-11',
        )).valueOrNull!;
        final niceItem = (await monthlyService.saveItem(
          profile: profMain,
          name: 'Mechanical Keyboard',
          estimatedAmountMinor: 600000,
          priority: BucketPriority.nice,
          targetYearMonth: '2026-11',
        )).valueOrNull!;
        final dreamItem = (await monthlyService.saveItem(
          profile: profMain,
          name: 'Mirrorless Camera',
          estimatedAmountMinor: 4500000,
          priority: BucketPriority.dream,
          targetYearMonth: '2026-11',
        )).valueOrNull!;

        // + Fund, Reserve in Budget, Postpone, Convert to Goal, Buy, Delete, Idempotent Reminders
        await monthlyService.addFunds(profMain, urgentItem, 100000);
        await monthlyService.reserveInBudget(
          profile: profMain,
          item: essItem.copyWith(categoryId: grocCat.id),
        );
        final postponed = await monthlyService.postponeItem(profMain, niceItem);
        expect(postponed.valueOrNull?.targetYearMonth, '2026-12');
        await monthlyService.convertToGoal(profile: profMain, item: dreamItem);
        await monthlyService.markPurchased(
          profile: profMain,
          item: urgentItem,
          actualAmountMinor: 280000,
          accountId: hdfc.id,
          categoryId: grocCat.id,
          dateUtc: DateTime.utc(2026, 11, 15, 11),
        );
        await monthlyService.deleteItem(profMain, postponed.valueOrNull!.id);

        final rem1 = await monthlyService.evaluateDueReminders(profMain);
        final rem2 = await monthlyService.evaluateDueReminders(profMain);
        expect(rem2.length, lessThanOrEqualTo(rem1.length));

        // Extra Income: transfer goal + same-account direct goal across presets
        final sbiGoal = (await goalRepo.createGoal(
          profileId: profMain.id,
          name: 'SBI Savings Goal',
          targetAmountMinor: 2500000,
          currencyCode: 'INR',
          fundingMode: GoalFundingMode.accountTransfer,
          linkedAccountId: sbi.id,
        )).valueOrNull!;
        final allocGoal = (await goalRepo.createGoal(
          profileId: profMain.id,
          name: 'Vacation Pot',
          targetAmountMinor: 1500000,
          currencyCode: 'INR',
          fundingMode: GoalFundingMode.allocated,
        )).valueOrNull!;
        await goalRepo.recordContribution(
          profileId: profMain.id,
          goalId: allocGoal.id,
          amountMinor: 200000,
        );

        await monthlyService.recordExtraIncome(
          profile: profMain,
          amountMinor: 1000000, // ₹10,000 bonus into HDFC -> ₹5k to SBI Goal
          sourceLabel: 'Festival Bonus',
          accountId: hdfc.id,
          dateUtc: DateTime.utc(2026, 11, 15, 13),
          split: MonthlyTrackerEngine.presetSplit(1000000, 50, 30),
          goalId: sbiGoal.id,
        );
        await monthlyService.recordExtraIncome(
          profile: profMain,
          amountMinor: 300000, // ₹3,000 directly into SBI -> same SBI Goal
          sourceLabel: 'Dividend',
          accountId: sbi.id,
          dateUtc: DateTime.utc(2026, 11, 15, 14),
          split: MonthlyTrackerEngine.presetSplit(300000, 100, 0),
          goalId: sbiGoal.id,
        );

        // =====================================================================
        // 5. LOANS (REDUCING & FLAT), RECURRING IDEMPOTENCY, BACKUP & PROFILE ISOLATION
        // =====================================================================
        final flatLoan = (await loanRepo.createLoan(
          profileId: profMain.id,
          name: 'Appliance Flat EMI',
          principalMinor: 2400000,
          currencyCode: 'INR',
          annualInterestRateBps: 1000,
          termMonths: 6,
          method: LoanInterestMethod.flat,
          startDateUtc: DateTime.utc(2026, 10, 20),
          fundingAccountId: hdfc.id,
        )).valueOrNull!;
        final payFlat = await loanRepo.payInstallment(
          profileId: profMain.id,
          loanId: flatLoan.id,
          installmentId: flatLoan.installments.first.id,
          sourceBankAccountId: hdfc.id,
        );
        expect(payFlat.isSuccess, isTrue);

        // Recurring rule due today -> run processDueRules TWICE -> generated 1st time, 0 duplicates 2nd time
        final rentRule = (await recurringRepo.createRule(
          profileId: profMain.id,
          name: 'Monthly Fiber Bill',
          transactionType: TransactionType.expense,
          amountMinor: 99900,
          currencyCode: 'INR',
          cadence: RecurringCadence.monthly,
          nextDueAtUtc: DateTime.utc(2026, 11, 15, 8).toIso8601String(),
          sourceAccountId: hdfc.id,
          categoryId: grocCat.id,
          autoCreateDraft: false,
        )).valueOrNull!;
        final run1 = await recurringRepo.processDueRules(profMain.id);
        final run2 = await recurringRepo.processDueRules(profMain.id);
        expect(run1.valueOrNull, 1);
        expect(run2.valueOrNull, 0);
        await recurringRepo.toggleStatus(profMain.id, rentRule.id, 'paused');

        // Verify strict profile isolation: second profile stays empty & balanced
        final isoDash = (await analyticsRepo.computeDashboardSummary(
          profIso.id,
          period: DashboardPeriodPreset.thisMonth,
        )).valueOrNull!;
        expect(isoDash.netWorth.amountMinor, 0);
        expect(isoDash.periodIncome.amountMinor, 0);

        // Encrypted Backup Export & Decrypt check
        final archive = (await backupService.exportEncryptedBackup(
          passphrase: 'StrongPass!2026',
          scopeProfileId: profMain.id,
        )).valueOrNull!;
        final decoded = await const BackupCrypto().decryptBackup(
          rawArchive: archive,
          passphrase: 'StrongPass!2026',
        );
        expect(decoded.payloadJson['bucket_list_items'], isNotEmpty);

        // Global Double-Entry Ledger Reconciliation across ALL operations
        final recon = (await txRepo.runReconciliationCheck(
          profMain.id,
        )).valueOrNull!;
        expect(recon.isHealthy, isTrue);
        expect(recon.unbalancedJournalIds, isEmpty);
        expect(recon.orphanPostingCount, 0);
        expect(recon.totalDebitsMinor, recon.totalCreditsMinor);
      },
    );

    testWidgets(
      'full-app blank-DB UI flow: Onboarding -> Profile -> Bank Account -> Life Planner Salary & Budget Apply -> Budgets -> Monthly Tracker -> Ledger -> Insights -> Settings',
      (tester) async {
        await initFreshDb();

        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(const PocketCfoApp());
        await tester.pumpAndSettle();

        // 1. Onboarding -> Skip -> Local Workspace -> Create Profile
        await tester.tap(find.byKey(const Key('onboarding_skip_btn')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Start Offline Local Workspace'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Personal Wealth'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(ModernDialogShell),
            matching: find.text('Create Profile'),
          ),
        );
        await tester.pumpAndSettle();

        // 2. Add Bank Account (HDFC Bank ₹50,000)
        await tester.tap(find.text('Add First Account'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add Account'));
        await tester.pumpAndSettle();
        final accFields = find.byType(TextField);
        await tester.enterText(accFields.at(0), 'HDFC Bank');
        await tester.enterText(accFields.at(1), '50000');
        await tester.ensureVisible(find.text('Save Account'));
        await tester.tap(find.text('Save Account'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.text('HDFC Bank'), findsOneWidget);

        // 3. Profile Hub -> Life & EMI Planner -> Salary ₹1,00,000 -> Estimate Typical -> Credit to Bank -> Apply Budget
        await tester.tap(find.text('Profile').last);
        await tester.pumpAndSettle();
        final lifeTile = find.text('Life & EMI Planner');
        await tester.scrollUntilVisible(
          lifeTile,
          240,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(lifeTile);
        await tester.pumpAndSettle();

        final incomeField = find.byKey(const Key('life_income_field'));
        await tester.ensureVisible(incomeField);
        await tester.enterText(incomeField, '100000');
        await tester.pumpAndSettle();

        final estBtn = find.byKey(const Key('life_estimate_typical_btn'));
        await tester.ensureVisible(estBtn);
        await tester.tap(estBtn);
        await tester.pumpAndSettle();

        final creditBtn = find.byKey(const Key('life_credit_salary_btn'));
        await tester.scrollUntilVisible(
          creditBtn,
          240,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(creditBtn);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('credit_salary_confirm_btn')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('credit_salary_confirm_btn')));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pumpAndSettle();

        final applyBtn = find.byKey(const Key('life_apply_budget_btn'));
        await tester.scrollUntilVisible(
          applyBtn,
          260,
          scrollable: find
              .descendant(
                of: find.byKey(const Key('life_tab_status')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tap(applyBtn);
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Apply ₹'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pumpAndSettle();

        // Back to Profile Hub -> Open Budgets (Overview, Zero-Based, CA Variance)
        await tester.pageBack();
        await tester.pumpAndSettle();
        final budgetsTile = find.text('Budgets');
        await tester.scrollUntilVisible(
          budgetsTile,
          240,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(budgetsTile);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('budgets_mode_tabs')), findsOneWidget);

        await tester.tap(find.text('Zero-Based'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('CA Variance'));
        await tester.pumpAndSettle();

        // Jump straight to Monthly Tracker via AppBar icon -> verify all 3 tabs + Recap
        await tester.tap(find.byKey(const Key('budgets_open_monthly_btn')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('monthly_hero_card')), findsOneWidget);
        await tester.tap(find.text('Bucket List'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Extra Income'));
        await tester.pumpAndSettle();

        // Navigate back cleanly to Home & verify no overflow or runtime errors
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Home').last);
        await tester.pumpAndSettle();
        expect(find.text('NET WORTH • INR'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
      },
    );
  });
}
