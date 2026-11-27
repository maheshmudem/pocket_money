import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_money/app/config/environment_config.dart';
import 'package:pocket_money/app/theme/app_theme.dart';
import 'package:pocket_money/bootstrap.dart';
import 'package:pocket_money/core/database/app_database.dart';
import 'package:pocket_money/core/database/encrypted_executor.dart';
import 'package:pocket_money/core/financial_engine/cfo_advisor_engine.dart';
import 'package:pocket_money/core/financial_engine/life_stage_planner_engine.dart';
import 'package:pocket_money/core/security/key_manager.dart';
import 'package:pocket_money/core/security/privacy_screen_service.dart';
import 'package:pocket_money/core/utilities/clock.dart';
import 'package:pocket_money/features/accounts/domain/entities/financial_account_entity.dart';
import 'package:pocket_money/features/accounts/domain/repositories/account_repository.dart';
import 'package:pocket_money/features/budgets/domain/repositories/budget_repository.dart';
import 'package:pocket_money/features/categories/domain/entities/category_entity.dart';
import 'package:pocket_money/features/categories/domain/repositories/category_repository.dart';
import 'package:pocket_money/features/dashboard/presentation/bloc/dashboard_bloc.dart';
import 'package:pocket_money/features/life_planner/data/life_stage_planner_service.dart';
import 'package:pocket_money/features/life_planner/presentation/pages/life_stage_planner_page.dart';
import 'package:pocket_money/features/loans/data/repositories/drift_loan_repository.dart';
import 'package:pocket_money/features/profiles/domain/entities/profile_entity.dart';
import 'package:pocket_money/features/profiles/presentation/bloc/active_profile_cubit.dart';
import 'package:pocket_money/features/recurring/data/repositories/drift_recurring_repository.dart';
import 'package:pocket_money/features/recurring/domain/entities/recurring_rule_entity.dart';
import 'package:pocket_money/features/savings_goals/domain/repositories/savings_goal_repository.dart';
import 'package:pocket_money/features/settings/data/settings_repository.dart';
import 'package:pocket_money/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:pocket_money/features/transactions/domain/entities/transaction_entity.dart';
import 'package:pocket_money/features/transactions/domain/repositories/transaction_repository.dart';

void main() {
  group('LifeStagePlannerEngine pure-Dart CFP/CA algorithms', () {
    test(
      'resolves all 7 statuses with Dependents & Housing adjustments, exact zero-remainder blueprints, EMI DTI, Avalanche vs Snowball, Affordability & Emergency Shield',
      () {
        // 1. All 7 personas always sum strictly to 100% across all housing & dependent combinations.
        for (final st in LifeStageStatus.values) {
          for (final h in HousingMode.values) {
            final t = LifeStagePlannerEngine.resolveEffectiveTargets(
              status: st,
              dependentsCount: 2,
              housingMode: h,
            );
            expect(
              t.needsPct + t.wantsPct + t.savingsPct + t.taxPct,
              100,
              reason: '${st.name} + ${h.name} must sum to 100%',
            );
          }
        }

        // Bachelor vs Family with Kids (2 dependents) contrast:
        final bachelor = LifeStagePlannerEngine.resolveEffectiveTargets(
          status: LifeStageStatus.bachelor,
        );
        final family = LifeStagePlannerEngine.resolveEffectiveTargets(
          status: LifeStageStatus.familyWithKids,
          dependentsCount: 2,
        );
        expect(bachelor.needsPct, 40);
        expect(bachelor.savingsPct, 35);
        expect(bachelor.emergencyMonths, 6);
        expect(family.needsPct, 59); // 55% + 4% for 2 dependents
        expect(family.wantsPct, 11); // 15% - 4%
        expect(family.maxSafeDtiPct, 28);
        expect(family.emergencyMonths, 9); // 8 + 1 for 2 dependents

        // Own / Family Home boosts Savings by +8% from Needs.
        final ownedBachelor = LifeStagePlannerEngine.resolveEffectiveTargets(
          status: LifeStageStatus.bachelor,
          housingMode: HousingMode.ownedOrFamily,
        );
        expect(ownedBachelor.needsPct, 32);
        expect(ownedBachelor.savingsPct, 43);

        // 2. Category Blueprint exact zero-remainder accounting!
        final bp = LifeStagePlannerEngine.buildCategoryBlueprint(
          currencyCode: 'INR',
          incomePoolMinor: 10000000, // ₹1,00,000
          targets: family,
          categories: const [
            LifeStageCategoryInput(
              categoryId: 'c-rent',
              categoryName: 'Housing & Rent',
              currentMonthSpendMinor: 2000000,
            ),
            LifeStageCategoryInput(
              categoryId: 'c-groc',
              categoryName: 'Groceries',
              currentMonthSpendMinor: 1200000,
            ),
            LifeStageCategoryInput(
              categoryId: 'c-edu',
              categoryName: 'Education',
              currentMonthSpendMinor: 800000,
            ),
            LifeStageCategoryInput(
              categoryId: 'c-dine',
              categoryName: 'Dining & Food',
              currentMonthSpendMinor: 500000,
            ),
          ],
        );
        expect(
          bp.totalRecommendedCategoriesMinor +
              bp.taxTargetMinor +
              bp.savingsTargetMinor,
          10000000,
        );

        // 3. EMI Health, Bad Debt Flagging & Debt Avalanche vs Snowball Simulation!
        final loans = const [
          ActiveLoanSnapshot(
            loanId: 'l-high',
            name: 'Personal High-Rate Loan',
            remainingPrincipalMinor: 30000000, // ₹3,00,000
            monthlyEmiMinor: 1100000, // ₹11,000/mo
            annualInterestRateBps: 1800, // 18% APR -> High-Interest Bad Debt!
            remainingMonths: 36,
          ),
          ActiveLoanSnapshot(
            loanId: 'l-small',
            name: 'Low-Rate Appliance Loan',
            remainingPrincipalMinor: 10000000, // ₹1,00,000 (smaller balance!)
            monthlyEmiMinor: 500000, // ₹5,000/mo
            annualInterestRateBps: 800, // 8% APR
            remainingMonths: 22,
          ),
        ];

        final emiHealth = LifeStagePlannerEngine.analyzeEmiHealth(
          currencyCode: 'INR',
          monthlyIncomeMinor:
              10000000, // ₹1,00,000 -> 16% DTI <= 28% family cap
          targets: family,
          loans: loans,
        );
        expect(emiHealth.totalMonthlyEmiMinor, 1600000);
        expect(emiHealth.dtiPercent, closeTo(16.0, 0.1));
        expect(emiHealth.dtiStatus, 'healthy');
        expect(emiHealth.availableNewEmiHeadroomMinor, 1200000); // ₹12k left
        expect(emiHealth.hasHighInterestDebt, isTrue);

        final sim = LifeStagePlannerEngine.simulateDebtPayoff(
          loans: loans,
          extraMonthlyPrepaymentMinor: 500000, // +₹5,000/mo prepayment
        );
        expect(sim.avalanche.monthsToDebtFree, lessThan(sim.baselineMonths));
        expect(sim.avalanche.interestSavedVsBaselineMinor, greaterThan(0));
        // Avalanche pays 18% loan before 8% loan, saving more total interest than Snowball!
        expect(
          sim.avalanche.totalInterestMinor,
          lessThanOrEqualTo(sim.snowball.totalInterestMinor),
        );

        // 4. "Can I Afford This EMI?" Guard
        final safeNew = LifeStagePlannerEngine.evaluateNewEmiAffordability(
          currencyCode: 'INR',
          monthlyIncomeMinor: 10000000,
          existingMonthlyEmiMinor: 1600000,
          targets: family,
          directMonthlyEmiMinor: 500000, // 21% total <= 28%
        );
        expect(safeNew.verdictCode, 'safe');

        final riskyNew = LifeStagePlannerEngine.evaluateNewEmiAffordability(
          currencyCode: 'INR',
          monthlyIncomeMinor: 10000000,
          existingMonthlyEmiMinor: 1600000,
          targets: family,
          directMonthlyEmiMinor: 2000000, // 36% > 28% family cap!
        );
        expect(riskyNew.verdictCode, 'risky');

        // 5. Essential-Outgo Emergency Shield & Playbook
        final pack = LifeStagePlannerEngine.buildProtectionAndPlaybook(
          currencyCode: 'INR',
          targets: family,
          blueprint: bp,
          emiHealth: emiHealth,
          liquidCashMinor: 15000000, // ₹1.5L liquid cash
        );
        expect(pack.shield.targetMonths, 9);
        expect(pack.shield.targetCorpusMinor, greaterThan(0));
        expect(pack.protection, isNotEmpty);
        expect(pack.playbook, isNotEmpty);

        // 6. Smart CFO Coach EMI/Life-Stage Q&A + privacy masking
        final advisorReport = CfoAdvisorEngine.analyze(
          CfoAdvisorInput(
            currencyCode: 'INR',
            nowUtc: DateTime.utc(2026, 11, 15),
            expenses: const [],
            incomes: [
              AdvisorIncomeEntry(
                dateUtc: DateTime.utc(2026, 11, 1),
                amountMinor: 10000000,
                categoryName: 'Salary',
              ),
            ],
            activeBudgets: const [],
          ),
        );
        final emiReply = CfoAdvisorEngine.answerQuestion(
          advisorReport,
          'How should I manage EMIs for a family man?',
          monthlyEmiMinor: 1600000,
        );
        expect(emiReply.headline, contains('Family with Kids'));
        final maskedReply = CfoAdvisorEngine.answerQuestion(
          advisorReport,
          'How should I manage EMIs for a family man?',
          maskBalances: true,
          monthlyEmiMinor: 1600000,
        );
        expect(maskedReply.metrics.first.value, contains('••••••'));
      },
    );

    test(
      'computes Bottom-Up CFP Cash-Flow Waterfall (Family, Bachelor, Deficit Rescue, Under-Insurance & Subscription Creep) with zero-remainder precision',
      () {
        // 1. estimateTypicalExpenses works for all 7 statuses cleanly.
        for (final st in LifeStageStatus.values) {
          final t = LifeStagePlannerEngine.resolveEffectiveTargets(
            status: st,
            dependentsCount: st == LifeStageStatus.familyWithKids ? 2 : 0,
          );
          final est = LifeStagePlannerEngine.estimateTypicalExpenses(
            primaryIncomeMinor: 10000000, // ₹1,00,000
            targets: t,
            currencyCode: 'INR',
          );
          expect(est.totalIncomeMinor, 10000000);
          expect(est.hasAnyEnteredExpenses, isTrue);
          expect(est.totalEnteredExpensesMinor, lessThan(10000000));
        }

        // 2. Family with Kids (₹75,000 combined income, ₹60,500 real bills + EMIs -> ₹14,500 surplus)
        final familyTargets = LifeStagePlannerEngine.resolveEffectiveTargets(
          status: LifeStageStatus.familyWithKids,
          dependentsCount: 2,
        );
        const familyExpenses = MonthlyExpenseProfile(
          primaryIncomeMinor: 5500000, // ₹55,000
          secondaryIncomeMinor: 2000000, // ₹20,000 spouse
          rentOrHousingMinor: 1500000, // ₹15,000
          groceriesMinor: 1200000, // ₹12,000
          schoolFeesMinor: 750000, // ₹7,500
          utilitiesMinor: 400000, // ₹4,000
          transportFuelMinor: 400000, // ₹4,000
          insuranceMinor: 350000, // ₹3,500
          medicalMinor: 250000, // ₹2,500
          subscriptionsMinor: 100000, // ₹1,000
          manualEmiMinor: 300000, // ₹3,000 other EMI
        );
        final famPlan = LifeStagePlannerEngine.buildBottomUpCashFlowPlan(
          currencyCode: 'INR',
          targets: familyTargets,
          expenses: familyExpenses,
          trackedLoanEmiMinor: 800000, // ₹8,000 tracked loan EMI
          liquidCashMinor: 15000000, // ₹1.5L cash (shield gap exists)
          hasHighInterestDebt: true,
        );
        expect(famPlan.totalIncomeMinor, 7500000);
        expect(famPlan.totalEmiMinor, 1100000); // ₹8k tracked + ₹3k manual
        expect(famPlan.totalCommittedOutgoMinor, 6050000); // ₹60,500
        expect(famPlan.netSurplusMinor, 1450000); // ₹14,500 exact surplus!
        expect(famPlan.planMode, 'wealth_waterfall');
        expect(famPlan.essentialOutgoForShieldMinor, 5950000); // excl. ₹1k subs
        final famWaterfallSum = famPlan.waterfallSteps.fold<int>(
          0,
          (s, step) => s + step.amountMinor,
        );
        expect(famWaterfallSum, famPlan.netSurplusMinor);
        expect(famPlan.recommendedPrepayMinor, greaterThan(0));
        expect(
          famPlan.guiltFreeWeeklyMinor,
          famPlan.guiltFreeMonthlyMinor ~/ 4,
        );

        // 3. Bachelor (₹45,000 income, ₹26,700 commitments + EMI -> ₹18,300 surplus)
        final bachTargets = LifeStagePlannerEngine.resolveEffectiveTargets(
          status: LifeStageStatus.bachelor,
        );
        const bachExpenses = MonthlyExpenseProfile(
          primaryIncomeMinor: 4500000,
          rentOrHousingMinor: 900000,
          groceriesMinor: 500000,
          utilitiesMinor: 150000,
          transportFuelMinor: 200000,
          insuranceMinor: 120000,
          subscriptionsMinor: 100000,
        );
        final bachPlan = LifeStagePlannerEngine.buildBottomUpCashFlowPlan(
          currencyCode: 'INR',
          targets: bachTargets,
          expenses: bachExpenses,
          trackedLoanEmiMinor: 700000,
          liquidCashMinor: 5000000,
        );
        expect(bachPlan.netSurplusMinor, 1830000);
        expect(bachPlan.planMode, 'wealth_waterfall');
        expect(
          bachPlan.waterfallSteps.fold<int>(0, (s, x) => s + x.amountMinor),
          bachPlan.netSurplusMinor,
        );

        // 4. Deficit Rescue Mode (₹50,000 income, ₹55,000 real commitments + EMIs)
        const deficitExpenses = MonthlyExpenseProfile(
          primaryIncomeMinor: 5000000,
          rentOrHousingMinor: 2000000, // 40% high housing
          groceriesMinor: 1200000,
          utilitiesMinor: 500000,
          subscriptionsMinor: 300000, // 6% subscription creep!
          manualEmiMinor: 1500000, // 30% EMI
        );
        final defPlan = LifeStagePlannerEngine.buildBottomUpCashFlowPlan(
          currencyCode: 'INR',
          targets: familyTargets,
          expenses: deficitExpenses,
          trackedLoanEmiMinor: 0,
          liquidCashMinor: 0,
        );
        expect(defPlan.planMode, 'deficit_rescue');
        expect(defPlan.isDeficit, isTrue);
        expect(defPlan.shortfallMinor, 500000);
        expect(defPlan.waterfallSteps, isEmpty);
        expect(defPlan.deficitRescueSteps.length, greaterThanOrEqualTo(3));

        // 5. Under-Insurance + Subscription Creep + High Housing Audit Flags!
        expect(
          defPlan.benchmarkFlags.any(
            (f) =>
                f.title.contains('Zero Insurance Provision') &&
                f.severity == 'danger',
          ),
          isTrue,
        );
        expect(
          defPlan.benchmarkFlags.any(
            (f) => f.title.contains('Subscription Creep'),
          ),
          isTrue,
        );
        expect(
          defPlan.benchmarkFlags.any(
            (f) => f.title.contains('High Housing Cost'),
          ),
          isTrue,
        );
      },
    );
  });

  group('LifeStagePlannerService & Responsive 3-Tab UI', () {
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
      'isolates profiles and passes 360x800 + 1.5x Dark Mode E2E: Switch Status -> Apply Budget -> EMI Simulator -> Create Emergency Goal -> Mask Balances',
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

        // Profile B (Business) with huge loan — verify zero leak into Profile A!
        final profB = (await activeProfileCubit.createProfile(
          ownerDisplayName: 'Owner',
          name: 'Other Biz',
          profileType: ProfileType.business,
          baseCurrencyCode: 'INR',
        )).valueOrNull!;
        await getIt<DriftLoanRepository>().createLoan(
          profileId: profB.id,
          name: 'Secret Machinery Loan',
          principalMinor: 50000000,
          currencyCode: 'INR',
          annualInterestRateBps: 1500,
          termMonths: 36,
          startDateUtc: DateTime.utc(2026, 10, 1),
        );

        // Active Profile A (Personal)
        final profA = (await activeProfileCubit.createProfile(
          ownerDisplayName: 'Owner',
          name: 'My Home Vault',
          profileType: ProfileType.personal,
          baseCurrencyCode: 'INR',
        )).valueOrNull!;
        final bankA =
            (await getIt<AccountRepository>().createAccountWithOpeningBalance(
              profileId: profA.id,
              name: 'Salary Bank',
              accountType: FinancialAccountType.bank,
              currencyCode: 'INR',
              openingBalanceMinor: 12000000, // ₹1.2L liquid cash
            )).valueOrNull!;
        final incCatsA = (await getIt<CategoryRepository>().listCategories(
          profA.id,
          type: CategoryType.income,
        )).valueOrNull!;
        await getIt<TransactionRepository>().createTransaction(
          profA.id,
          CreateTransactionCommand(
            type: TransactionType.income,
            amountMinor: 8000000, // ₹80,000 monthly income
            currencyCode: 'INR',
            transactionDateUtc: DateTime.utc(2026, 11, 1).toIso8601String(),
            destinationAccountId: bankA.id,
            categoryId: incCatsA.first.id,
            description: 'Monthly Salary',
          ),
        );
        await getIt<DriftLoanRepository>().createLoan(
          profileId: profA.id,
          name: 'Personal Bike Loan',
          principalMinor: 15000000, // ₹1.5L
          currencyCode: 'INR',
          annualInterestRateBps: 1400, // 14% high-interest!
          termMonths: 24,
          startDateUtc: DateTime.utc(2026, 10, 1),
        );

        // Seed real expense transactions & a recurring Subscription to verify ledger auto-fill!
        final expCatsA = (await getIt<CategoryRepository>().listCategories(
          profA.id,
          type: CategoryType.expense,
        )).valueOrNull!;
        final rentCat = expCatsA.firstWhere(
          (c) => c.name.toLowerCase().contains('rent'),
        );
        final grocCat = expCatsA.firstWhere(
          (c) => c.name.toLowerCase().contains('grocer'),
        );
        await getIt<TransactionRepository>().createTransaction(
          profA.id,
          CreateTransactionCommand(
            type: TransactionType.expense,
            amountMinor: 1400000, // ₹14,000 Rent
            currencyCode: 'INR',
            transactionDateUtc: DateTime.utc(2026, 11, 2).toIso8601String(),
            sourceAccountId: bankA.id,
            categoryId: rentCat.id,
            description: 'House Rent',
          ),
        );
        await getIt<TransactionRepository>().createTransaction(
          profA.id,
          CreateTransactionCommand(
            type: TransactionType.expense,
            amountMinor: 950000, // ₹9,500 Groceries
            currencyCode: 'INR',
            transactionDateUtc: DateTime.utc(2026, 11, 4).toIso8601String(),
            sourceAccountId: bankA.id,
            categoryId: grocCat.id,
            description: 'Monthly Groceries',
          ),
        );
        await getIt<DriftRecurringRepository>().createRule(
          profileId: profA.id,
          name: 'Netflix & Cloud Subscription',
          transactionType: TransactionType.expense,
          amountMinor: 120000, // ₹1,200/mo recurring subscription
          currencyCode: 'INR',
          cadence: RecurringCadence.monthly,
          nextDueAtUtc: DateTime.utc(2026, 12, 1).toIso8601String(),
          sourceAccountId: bankA.id,
        );

        final autoFilled =
            (await getIt<LifeStagePlannerService>().autoFillExpensesFromLedger(
              profile: profA,
            )).valueOrNull!;
        expect(autoFilled.primaryIncomeMinor, 8000000);
        expect(autoFilled.rentOrHousingMinor, 1400000);
        expect(autoFilled.groceriesMinor, 950000);
        expect(autoFilled.subscriptionsMinor, 120000);

        // Verify strict profile isolation in service!
        final ws = (await getIt<LifeStagePlannerService>().loadWorkspace(
          profile: profA,
        )).valueOrNull!;
        expect(ws.emiHealth.loans.length, 1);
        expect(ws.emiHealth.loans.first.name, 'Personal Bike Loan');
        expect(ws.emiHealth.hasHighInterestDebt, isTrue);

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
              home: const LifeStagePlannerPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Switch from Bachelor -> Family with Kids -> Estimate Typical Expenses -> Enter Other EMI -> Apply Custom Budget!
        await tester.drag(
          find.byKey(const Key('life_status_list')),
          const Offset(-420, 0),
        );
        await tester.pumpAndSettle();
        final familyCard = find.byKey(const Key('life_card_family_with_kids'));
        await tester.tap(familyCard);
        await tester.pumpAndSettle();

        final estBtn = find.byKey(const Key('life_estimate_typical_btn'));
        await tester.ensureVisible(estBtn);
        await tester.tap(estBtn);
        await tester.pumpAndSettle();

        // Add ₹5,000 Other Manual EMI and rebuild CFP plan!
        final manualEmiField = find.byKey(
          const Key('life_exp_manual_emi_field'),
        );
        await tester.ensureVisible(manualEmiField);
        await tester.enterText(manualEmiField, '5000');
        await tester.pumpAndSettle();

        final savePlanBtn = find.byKey(const Key('life_save_plan_inputs_btn'));
        await tester.ensureVisible(savePlanBtn);
        await tester.tap(savePlanBtn);
        await tester.pumpAndSettle();

        // Verify Personalized CFP Plan & 5-Stage Surplus Allocation Waterfall rendered!
        final cfpCard = find.byKey(const Key('life_cfp_plan_card'));
        await tester.ensureVisible(cfpCard);
        expect(cfpCard, findsOneWidget);
        expect(find.byKey(const Key('life_waterfall_heading')), findsOneWidget);

        // 1-Tap Apply Budget -> verifies Master Budget saved AND Insurance + Subscriptions auto-created!
        final applyBtn = find.byKey(const Key('life_apply_budget_btn'));
        await tester.scrollUntilVisible(
          applyBtn,
          280,
          scrollable: find
              .descendant(
                of: find.byKey(const Key('life_tab_status')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle(const Duration(seconds: 4));
        await tester.tap(applyBtn);
        await tester.pumpAndSettle();
        expect(find.text('Apply Family Budget?'), findsOneWidget);

        await tester.tap(find.textContaining('Apply ₹'));
        await tester.pumpAndSettle();

        final budgets =
            (await getIt<BudgetRepository>().listBudgetsWithProgress(
              profA.id,
            )).valueOrNull!;
        expect(budgets.length, 1);
        expect(budgets.first.name, 'Family Master Budget');

        final catsAfter = (await getIt<CategoryRepository>().listCategories(
          profA.id,
          type: CategoryType.expense,
        )).valueOrNull!;
        expect(
          catsAfter.any((c) => c.name.toLowerCase() == 'insurance'),
          isTrue,
          reason: 'Missing Insurance category must be auto-created on Apply',
        );
        expect(
          catsAfter.any((c) => c.name.toLowerCase() == 'subscriptions'),
          isTrue,
          reason:
              'Missing Subscriptions category must be auto-created on Apply',
        );

        // 2. Switch to EMI & Debt tab -> verify DTI speedometer combines Tracked + Manual EMIs, CFP Prepay chip & Snowball toggle!
        final modeTabs = find.byKey(const Key('life_mode_tabs'));
        await tester.tap(
          find.descendant(of: modeTabs, matching: find.text('EMI & Debt')),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('life_dti_hero_card')), findsOneWidget);
        expect(find.textContaining('Personal Bike Loan'), findsWidgets);
        expect(find.textContaining('other EMIs'), findsOneWidget);
        expect(find.textContaining('Secret Machinery Loan'), findsNothing);

        final cfpPrepayBtn = find.byKey(const Key('life_use_cfp_prepay_btn'));
        if (cfpPrepayBtn.evaluate().isNotEmpty) {
          await tester.ensureVisible(cfpPrepayBtn);
          await tester.tap(cfpPrepayBtn);
          await tester.pumpAndSettle();
        }

        final strategyTabs = find.byKey(const Key('life_debt_strategy_tabs'));
        await tester.ensureVisible(strategyTabs);
        await tester.tap(
          find.descendant(
            of: strategyTabs,
            matching: find.textContaining('Snowball'),
          ),
        );
        await tester.pumpAndSettle();

        // 3. Switch to Save & Shield tab -> verify real essential-outgo Shield & 1-Tap Create Emergency Shield Goal!
        await tester.tap(
          find.descendant(of: modeTabs, matching: find.text('Save & Shield')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('life_emergency_shield_card')),
          findsOneWidget,
        );
        expect(find.textContaining('Based on your real'), findsOneWidget);

        final createGoalBtn = find.byKey(
          const Key('life_create_emergency_goal_btn'),
        );
        await tester.ensureVisible(createGoalBtn);
        await tester.tap(createGoalBtn);
        await tester.pumpAndSettle();

        final goals = (await getIt<SavingsGoalRepository>().listGoals(
          profA.id,
        )).valueOrNull!;
        expect(goals.any((g) => g.name.startsWith('Emergency Shield')), isTrue);

        // 4. Verify hideBalances masks figures cleanly across both Tab 2 & Tab 0 with zero layout overflow!
        await settingsCubit.toggleHideBalances();
        await tester.pumpAndSettle();
        expect(find.textContaining('••••••'), findsWidgets);

        await tester.tap(
          find.descendant(of: modeTabs, matching: find.text('My Status')),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('••••••'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
