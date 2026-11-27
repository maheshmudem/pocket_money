import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_money/app/config/environment_config.dart';
import 'package:pocket_money/app/theme/app_theme.dart';
import 'package:pocket_money/bootstrap.dart';
import 'package:pocket_money/core/database/app_database.dart';
import 'package:pocket_money/core/database/encrypted_executor.dart';
import 'package:pocket_money/core/financial_engine/ca_budget_planner_engine.dart';
import 'package:pocket_money/core/security/key_manager.dart';
import 'package:pocket_money/core/security/privacy_screen_service.dart';
import 'package:pocket_money/core/utilities/clock.dart';
import 'package:pocket_money/core/utilities/id_generator.dart';
import 'package:pocket_money/features/accounts/domain/entities/financial_account_entity.dart';
import 'package:pocket_money/features/accounts/domain/repositories/account_repository.dart';
import 'package:pocket_money/features/budgets/data/ca_budget_planner_service.dart';
import 'package:pocket_money/features/budgets/domain/entities/budget_entity.dart';
import 'package:pocket_money/features/budgets/domain/repositories/budget_repository.dart';
import 'package:pocket_money/features/budgets/presentation/pages/budgets_page.dart';
import 'package:pocket_money/features/categories/domain/entities/category_entity.dart';
import 'package:pocket_money/features/categories/domain/repositories/category_repository.dart';
import 'package:pocket_money/features/dashboard/presentation/bloc/dashboard_bloc.dart';
import 'package:pocket_money/features/loans/data/repositories/drift_loan_repository.dart';
import 'package:pocket_money/features/profiles/domain/entities/profile_entity.dart';
import 'package:pocket_money/features/profiles/presentation/bloc/active_profile_cubit.dart';
import 'package:pocket_money/features/recurring/data/repositories/drift_recurring_repository.dart';
import 'package:pocket_money/features/recurring/domain/entities/recurring_rule_entity.dart';
import 'package:pocket_money/features/reports/data/report_exporter.dart';
import 'package:pocket_money/features/savings_goals/domain/entities/savings_goal_entity.dart';
import 'package:pocket_money/features/savings_goals/domain/repositories/savings_goal_repository.dart';
import 'package:pocket_money/features/settings/data/settings_repository.dart';
import 'package:pocket_money/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:pocket_money/features/transactions/domain/entities/transaction_entity.dart';
import 'package:pocket_money/features/transactions/domain/repositories/transaction_repository.dart';

void main() {
  group('CaBudgetPlannerEngine pure-Dart Chartered Accountant algorithms', () {
    test(
      'classifies cost classes, resolves Indian FY & Calendar periods, computes Safe-to-Spend, Zero-Based blueprints, BvA variance & exports',
      () async {
        // 1. Cost classification
        expect(
          CaBudgetPlannerEngine.classifyCostClass('Housing & Rent'),
          CaCostClass.fixedNeed,
        );
        expect(
          CaBudgetPlannerEngine.classifyCostClass('Dining & Cafe'),
          CaCostClass.variableWant,
        );
        expect(
          CaBudgetPlannerEngine.classifyCostClass('GST & Income Tax'),
          CaCostClass.taxStatutory,
        );
        expect(
          CaBudgetPlannerEngine.classifyCostClass('SIP Investments'),
          CaCostClass.savingsCapex,
        );

        // 2. Indian Financial Year (Apr-Mar) vs Calendar Year (Jan-Dec)
        final now = DateTime.utc(2026, 11, 15, 12, 0);
        final inQ = CaBudgetPlannerEngine.resolveFiscalWindow(
          nowUtc: now,
          preset: CaFiscalPeriodPreset.currentQuarter,
          fyStartMonth: 4,
        );
        expect(inQ.label, 'Q3 FY27 (Oct–Dec)');
        expect(inQ.monthlyBudgetMultiplier, 3);

        final inYtd = CaBudgetPlannerEngine.resolveFiscalWindow(
          nowUtc: now,
          preset: CaFiscalPeriodPreset.yearToDate,
          fyStartMonth: 4,
        );
        expect(inYtd.label, 'FY27 YTD (8 mo)');
        expect(inYtd.monthlyBudgetMultiplier, 8);

        final calQ = CaBudgetPlannerEngine.resolveFiscalWindow(
          nowUtc: now,
          preset: CaFiscalPeriodPreset.currentQuarter,
          fyStartMonth: 1,
        );
        expect(calQ.label, 'Q4 2026 (Oct–Dec)');

        // 3. True Safe-to-Spend Waterfall (comfortable & cash crunch)
        final safe = CaBudgetPlannerEngine.computeSafeToSpend(
          currencyCode: 'INR',
          liquidCashMinor: 10000000, // ₹1,00,000
          upcomingBillsMinor: 1500000, // ₹15,000
          upcomingEmisMinor: 2000000, // ₹20,000
          taxProvisionMinor: 1000000, // ₹10,000
          sinkingFundAccrualsMinor: 500000, // ₹5,000
          remainingDaysInMonth: 10,
        );
        expect(safe.committedObligationsMinor, 5000000);
        expect(safe.safeToSpendMinor, 5000000); // ₹50,000 truly free
        expect(safe.dailySafeToSpendMinor, 500000); // ₹5,000/day
        expect(safe.liquidityStatus, 'comfortable');

        final crunch = CaBudgetPlannerEngine.computeSafeToSpend(
          currencyCode: 'INR',
          liquidCashMinor: 1000000,
          upcomingBillsMinor: 1500000,
          upcomingEmisMinor: 500000,
          taxProvisionMinor: 0,
          sinkingFundAccrualsMinor: 0,
          remainingDaysInMonth: 10,
        );
        expect(crunch.isCashCrunch, isTrue);
        expect(crunch.safeToSpendMinor, 0);
        expect(crunch.shortfallMinor, 1000000);
        expect(crunch.liquidityStatus, 'crunch');

        // 4. Sinking Fund Monthly Accrual (ceiling division)
        final sinking = CaBudgetPlannerEngine.computeSinkingFundAccrual(
          goalId: 'g1',
          name: 'Annual Car Insurance',
          targetMinor: 1200000, // ₹12,000
          contributedMinor: 200000, // ₹2,000 saved -> ₹10,000 left
          targetDateUtc: DateTime.utc(
            2027,
            4,
            15,
          ).toIso8601String(), // 5 months
          nowUtc: now,
        )!;
        expect(sinking.monthsRemaining, 5);
        expect(sinking.monthlyAccrualMinor, 200000); // ₹2,000/mo

        // 5. All 5 Zero-Based Budgeting Blueprints enforce EXACT zero remainder
        final seeds = const [
          ZbbCategorySeed(
            categoryId: 'c-rent',
            categoryName: 'Housing & Rent',
            trailingSpendMinor: 2000000,
            previousMonthSpendMinor: 2000000,
          ),
          ZbbCategorySeed(
            categoryId: 'c-groc',
            categoryName: 'Groceries',
            trailingSpendMinor: 800000,
            previousMonthSpendMinor: 800000,
          ),
          ZbbCategorySeed(
            categoryId: 'c-dine',
            categoryName: 'Dining & Cafe',
            trailingSpendMinor: 600000,
            previousMonthSpendMinor: 700000,
          ),
          ZbbCategorySeed(
            categoryId: 'c-shop',
            categoryName: 'Shopping',
            trailingSpendMinor: 500000,
            previousMonthSpendMinor: 500000,
          ),
        ];

        for (final bp in CaBudgetBlueprint.values) {
          final plan = CaBudgetPlannerEngine.generateZeroBasedPlan(
            blueprint: bp,
            incomePoolMinor: 6000000, // ₹60,000
            categories: seeds,
            currencyCode: 'INR',
          );
          expect(
            plan.unallocatedMinor,
            0,
            reason: 'Blueprint ${bp.name} must achieve exact zero remainder',
          );
          expect(plan.totalAssignedMinor, 6000000);
        }

        // 6. CA Budget vs. Actual (BvA) Variance + Smart Rebalance + Formula-Safe Exports
        final monthWin = CaBudgetPlannerEngine.resolveFiscalWindow(
          nowUtc: now,
          preset: CaFiscalPeriodPreset.currentMonth,
          fyStartMonth: 4,
        );
        final bva = CaBudgetPlannerEngine.buildVarianceStatement(
          currencyCode: 'INR',
          window: monthWin,
          periodIncomeMinor: 6000000,
          budgetLines: const [
            CaBudgetLineInput(
              budgetId: 'b-master',
              budgetName: 'Master ZBB',
              categoryId: 'c-rent',
              categoryName: 'Housing & Rent',
              monthlyEquivalentLimitMinor: 2000000,
            ),
            CaBudgetLineInput(
              budgetId: 'b-master',
              budgetName: 'Master ZBB',
              categoryId: 'c-dine',
              categoryName: 'Dining & Cafe',
              monthlyEquivalentLimitMinor: 500000,
            ),
            CaBudgetLineInput(
              budgetId: 'b-master',
              budgetName: 'Master ZBB',
              categoryId: 'c-shop',
              categoryName: 'Shopping',
              monthlyEquivalentLimitMinor: 800000,
            ),
          ],
          actualSpends: const [
            CaActualSpendInput(
              categoryId: 'c-rent',
              categoryName: 'Housing & Rent',
              actualMinor: 2000000, // On budget (F)
            ),
            CaActualSpendInput(
              categoryId: 'c-dine',
              categoryName: 'Dining & Cafe',
              actualMinor: 700000, // Over by ₹2,000 (U)
            ),
            CaActualSpendInput(
              categoryId: 'c-shop',
              categoryName: 'Shopping',
              actualMinor: 200000, // Under by ₹6,000 (F) -> donor!
            ),
            CaActualSpendInput(
              categoryId: 'c-mal',
              categoryName: '=SUM(A1:A2) Uncapped',
              actualMinor: 150000, // Unbudgeted spend!
            ),
          ],
        );

        expect(bva.totalBudgetedMinor, 3300000);
        expect(bva.totalActualMinor, 3050000);
        expect(bva.isNetFavorable, isTrue);
        expect(bva.unbudgetedSpendMinor, 150000);
        expect(bva.unbudgetedCategoryCount, 1);

        final diningLine = bva.lines.firstWhere(
          (l) => l.categoryId == 'c-dine',
        );
        expect(diningLine.isFavorable, isFalse);
        expect(diningLine.caCode, 'U');
        expect(diningLine.varianceMinor, -200000);

        // Smart rebalance pairs Shopping (+₹6,000 surplus) -> Dining (-₹2,000 deficit).
        expect(bva.rebalanceSuggestions, isNotEmpty);
        final sug = bva.rebalanceSuggestions.first;
        expect(sug.fromCategoryId, 'c-shop');
        expect(sug.toCategoryId, 'c-dine');
        expect(sug.suggestedTransferMinor, 200000);

        // Formula-injection-sanitized BvA CSV + valid A4 PDF bytes
        final profile = FinancialProfile(
          id: const ProfileId('p-ca'),
          name: '=CMD() Test Vault',
          profileType: ProfileType.business,
          baseCurrencyCode: 'INR',
          timezone: 'Asia/Kolkata',
          role: ProfileRole.owner,
          editorsCanPost: true,
          version: 1,
          syncStatus: 'local_only',
          createdAtUtc: now.toIso8601String(),
          updatedAtUtc: now.toIso8601String(),
        );
        final csv = ReportExporter.generateBudgetVarianceCsv(
          profile: profile,
          statement: bva,
        );
        expect(csv, contains("'=CMD() Test Vault"));
        expect(csv, contains("'=SUM(A1:A2) Uncapped"));
        expect(csv, contains('TOTAL'));

        final pdfBytes = await ReportExporter.generateBudgetVariancePdf(
          profile: profile,
          statement: bva,
          safeToSpend: safe,
          sinkingFunds: [sinking],
          generatedAtUtc: now.toIso8601String(),
        );
        expect(pdfBytes.length, greaterThan(500));
        expect(String.fromCharCodes(pdfBytes.take(4)), '%PDF');
      },
    );
  });

  group('CA Budget Repository, Service & Responsive 3-Tab UI', () {
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
        clockOverride: FixedUtcClock(DateTime.utc(2026, 11, 15, 10, 0)),
      );
    }

    tearDown(() async {
      if (getIt.isRegistered<AppDatabase>()) {
        await getIt<AppDatabase>().close();
      }
      await getIt.reset();
    });

    testWidgets(
      'updateBudget & reallocateCategoryLimit work atomically, CaBudgetPlannerService isolates profiles, and 3-tab BudgetsPage passes 360x800 + 1.5x Dark Mode E2E',
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

        // Profile B (Business) — verify strict isolation (zero data leaks into Personal).
        final profB = (await activeProfileCubit.createProfile(
          ownerDisplayName: 'Owner',
          name: 'Secret Corp',
          profileType: ProfileType.business,
          baseCurrencyCode: 'INR',
        )).valueOrNull!;
        final bankB =
            (await getIt<AccountRepository>().createAccountWithOpeningBalance(
              profileId: profB.id,
              name: 'Corp Bank',
              accountType: FinancialAccountType.bank,
              currencyCode: 'INR',
              openingBalanceMinor: 90000000,
            )).valueOrNull!;
        final catsB = (await getIt<CategoryRepository>().listCategories(
          profB.id,
          type: CategoryType.expense,
        )).valueOrNull!;
        await getIt<TransactionRepository>().createTransaction(
          profB.id,
          CreateTransactionCommand(
            type: TransactionType.expense,
            amountMinor: 5000000,
            currencyCode: 'INR',
            transactionDateUtc: DateTime.utc(2026, 11, 5).toIso8601String(),
            sourceAccountId: bankB.id,
            categoryId: catsB.first.id,
            description: 'Corp Expense',
          ),
        );

        // Active Profile A (Personal)
        final profA = (await activeProfileCubit.createProfile(
          ownerDisplayName: 'Owner',
          name: 'Personal Vault',
          profileType: ProfileType.personal,
          baseCurrencyCode: 'INR',
        )).valueOrNull!;
        final bankA =
            (await getIt<AccountRepository>().createAccountWithOpeningBalance(
              profileId: profA.id,
              name: 'Salary Bank',
              accountType: FinancialAccountType.bank,
              currencyCode: 'INR',
              openingBalanceMinor: 8000000, // ₹80,000 liquid cash
            )).valueOrNull!;
        final expCatsA = (await getIt<CategoryRepository>().listCategories(
          profA.id,
          type: CategoryType.expense,
        )).valueOrNull!;
        final incCatsA = (await getIt<CategoryRepository>().listCategories(
          profA.id,
          type: CategoryType.income,
        )).valueOrNull!;

        // Income ₹60,000 + Expense ₹7,000 in expCatsA[0] + Upcoming Bill ₹5,000 + Loan EMI + Sinking Goal
        await getIt<TransactionRepository>().createTransaction(
          profA.id,
          CreateTransactionCommand(
            type: TransactionType.income,
            amountMinor: 6000000,
            currencyCode: 'INR',
            transactionDateUtc: DateTime.utc(2026, 11, 1).toIso8601String(),
            destinationAccountId: bankA.id,
            categoryId: incCatsA.first.id,
            description: 'Nov Salary',
          ),
        );
        await getIt<TransactionRepository>().createTransaction(
          profA.id,
          CreateTransactionCommand(
            type: TransactionType.expense,
            amountMinor: 700000,
            currencyCode: 'INR',
            transactionDateUtc: DateTime.utc(2026, 11, 10).toIso8601String(),
            sourceAccountId: bankA.id,
            categoryId: expCatsA[0].id,
            description: 'Category 0 Spend',
          ),
        );
        await getIt<DriftRecurringRepository>().createRule(
          profileId: profA.id,
          name: 'Broadband Bill',
          transactionType: TransactionType.expense,
          amountMinor: 500000, // ₹5,000 due Nov 25
          currencyCode: 'INR',
          cadence: RecurringCadence.monthly,
          nextDueAtUtc: DateTime.utc(2026, 11, 25).toIso8601String(),
          sourceAccountId: bankA.id,
          categoryId: expCatsA[1].id,
        );
        await getIt<DriftLoanRepository>().createLoan(
          profileId: profA.id,
          name: 'Laptop EMI',
          principalMinor: 1200000,
          currencyCode: 'INR',
          annualInterestRateBps: 0,
          termMonths: 12,
          startDateUtc: DateTime.utc(2026, 10, 20), // EMI #1 due Nov 20!
        );
        await getIt<SavingsGoalRepository>().createGoal(
          profileId: profA.id,
          name: 'Annual Tax Buffer',
          targetAmountMinor: 1200000,
          currencyCode: 'INR',
          fundingMode: GoalFundingMode.allocated,
          targetDateUtc: DateTime.utc(2027, 5, 15).toIso8601String(),
        );

        // Verify atomic updateBudget & reallocateCategoryLimit directly!
        final repo = getIt<BudgetRepository>();
        final created = (await repo.createBudget(
          profileId: profA.id,
          name: 'Initial Master',
          periodType: BudgetPeriodType.monthly,
          overallLimitMinor: 1500000,
          currencyCode: 'INR',
          categoryLimitsMinor: {
            expCatsA[0].id: 500000, // Overspent (₹7,000 vs ₹5,000)
            expCatsA[1].id: 1000000, // Surplus (₹0 vs ₹10,000)
          },
        )).valueOrNull!;

        final updated = (await repo.updateBudget(
          profileId: profA.id,
          budgetId: created.id,
          name: 'Monthly Zero-Based Plan',
          periodType: BudgetPeriodType.monthly,
          overallLimitMinor: 1500000,
          categoryLimitsMinor: {
            expCatsA[0].id: 500000,
            expCatsA[1].id: 1000000,
          },
          rolloverEnabled: true,
        )).valueOrNull!;
        expect(updated.name, 'Monthly Zero-Based Plan');
        expect(updated.rolloverEnabled, isTrue);

        // Atomic intra-budget reallocation: shift ₹2,000 from expCatsA[1] -> expCatsA[0]!
        final reallocRes = await repo.reallocateCategoryLimit(
          profileId: profA.id,
          fromBudgetId: created.id,
          fromCategoryId: expCatsA[1].id,
          toBudgetId: created.id,
          toCategoryId: expCatsA[0].id,
          amountMinor: 200000,
        );
        expect(reallocRes.isSuccess, isTrue);

        final afterRealloc = (await repo.listBudgetsWithProgress(
          profA.id,
        )).valueOrNull!.first;
        final c0Cap = afterRealloc.allocations
            .firstWhere((a) => a.categoryId == expCatsA[0].id)
            .limitMinor;
        final c1Cap = afterRealloc.allocations
            .firstWhere((a) => a.categoryId == expCatsA[1].id)
            .limitMinor;
        expect(c0Cap, 700000);
        expect(c1Cap, 800000);

        // Verify CaBudgetPlannerService isolates Profile A from Profile B!
        final ws = (await getIt<CaBudgetPlannerService>().loadWorkspace(
          profile: profA,
        )).valueOrNull!;
        expect(ws.safeToSpend.liquidCashMinor, 13300000); // 80k + 60k - 7k
        expect(ws.safeToSpend.upcomingBillsMinor, 500000);
        expect(ws.safeToSpend.upcomingEmisMinor, greaterThan(0));
        expect(ws.sinkingFunds.length, 1);
        expect(ws.varianceStatement.totalActualMinor, 700000); // Zero Corp leak

        // Mount 3-tab BudgetsPage at 360x800 + 1.5x text scale + Obsidian Dark Mode!
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
              home: const BudgetsPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Overview tab renders Safe-to-Spend & Active Envelopes with zero overflow.
        expect(
          find.byKey(const Key('budgets_safe_to_spend_card')),
          findsOneWidget,
        );
        expect(find.text('Monthly Zero-Based Plan'), findsOneWidget);

        // 2. Switch to Zero-Based tab -> tap 50/30/20 blueprint -> Balanced -> Save!
        final modeTabs = find.byKey(const Key('budgets_mode_tabs'));
        await tester.tap(
          find.descendant(of: modeTabs, matching: find.text('Zero-Based')),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('budgets_zbb_meter')), findsOneWidget);

        final bp503020 = find.byKey(const Key('zbb_blueprint_balanced503020'));
        await tester.ensureVisible(bp503020);
        await tester.tap(bp503020);
        await tester.pumpAndSettle();
        expect(find.text('Zero-Based Balanced'), findsOneWidget);

        final saveZbbBtn = find.byKey(const Key('budgets_zbb_save_btn'));
        await tester.ensureVisible(saveZbbBtn);
        await tester.tap(saveZbbBtn);
        await tester.pumpAndSettle();

        // 3. Switch to CA Variance tab -> toggle FY cycle -> verify BvA & privacy masking!
        await tester.tap(
          find.descendant(of: modeTabs, matching: find.text('CA Variance')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('budgets_bva_summary_card')),
          findsOneWidget,
        );
        expect(find.text('FY Apr–Mar'), findsOneWidget);

        await tester.tap(find.byKey(const Key('budgets_fy_toggle_btn')));
        await tester.pumpAndSettle();
        expect(find.text('Jan–Dec'), findsOneWidget);

        // Verify hideBalances masks all monetary figures in CA Variance cleanly.
        await settingsCubit.toggleHideBalances();
        await tester.pumpAndSettle();
        expect(find.textContaining('••••••'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
