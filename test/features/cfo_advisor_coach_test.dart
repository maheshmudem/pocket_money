import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_money/app/config/environment_config.dart';
import 'package:pocket_money/app/theme/app_theme.dart';
import 'package:pocket_money/bootstrap.dart';
import 'package:pocket_money/core/database/app_database.dart';
import 'package:pocket_money/core/database/encrypted_executor.dart';
import 'package:pocket_money/core/financial_engine/cfo_advisor_engine.dart';
import 'package:pocket_money/core/security/key_manager.dart';
import 'package:pocket_money/core/security/privacy_screen_service.dart';
import 'package:pocket_money/core/utilities/clock.dart';
import 'package:pocket_money/features/accounts/domain/entities/financial_account_entity.dart';
import 'package:pocket_money/features/accounts/domain/repositories/account_repository.dart';
import 'package:pocket_money/features/ai_coach/data/cfo_advisor_service.dart';
import 'package:pocket_money/features/ai_coach/presentation/pages/ai_coach_page.dart';
import 'package:pocket_money/features/budgets/domain/repositories/budget_repository.dart';
import 'package:pocket_money/features/categories/domain/entities/category_entity.dart';
import 'package:pocket_money/features/categories/domain/repositories/category_repository.dart';
import 'package:pocket_money/features/dashboard/presentation/bloc/dashboard_bloc.dart';
import 'package:pocket_money/features/profiles/domain/entities/profile_entity.dart';
import 'package:pocket_money/features/profiles/presentation/bloc/active_profile_cubit.dart';
import 'package:pocket_money/features/settings/data/settings_repository.dart';
import 'package:pocket_money/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:pocket_money/features/transactions/domain/entities/transaction_entity.dart';
import 'package:pocket_money/features/transactions/domain/repositories/transaction_repository.dart';

void main() {
  group('CfoAdvisorEngine pure-Dart algorithms', () {
    test(
      'classifies Needs/Wants/Savings, detects category spikes, money leaks, weekend burn, and computes 50/30/20 plan',
      () {
        expect(
          CfoAdvisorEngine.classifyCategory('Housing & Rent'),
          SpendBucket.needs,
        );
        expect(
          CfoAdvisorEngine.classifyCategory('Dining & Food'),
          SpendBucket.wants,
        );
        expect(
          CfoAdvisorEngine.classifyCategory('SIP Investments'),
          SpendBucket.savingsDebt,
        );

        final now = DateTime.utc(2026, 11, 20, 12, 0);
        final expenses = <AdvisorExpenseEntry>[
          // Prior months (Sep & Oct) baseline: Dining ₹5,000/mo, Rent ₹20,000/mo.
          AdvisorExpenseEntry(
            dateUtc: DateTime.utc(2026, 9, 5),
            amountMinor: 2000000,
            categoryId: 'cat-rent',
            categoryName: 'Housing & Rent',
            merchantLabel: 'Monthly Rent',
          ),
          AdvisorExpenseEntry(
            dateUtc: DateTime.utc(2026, 9, 12),
            amountMinor: 500000,
            categoryId: 'cat-dining',
            categoryName: 'Dining & Food',
            merchantLabel: 'Swiggy',
          ),
          AdvisorExpenseEntry(
            dateUtc: DateTime.utc(2026, 10, 5),
            amountMinor: 2000000,
            categoryId: 'cat-rent',
            categoryName: 'Housing & Rent',
            merchantLabel: 'Monthly Rent',
          ),
          AdvisorExpenseEntry(
            dateUtc: DateTime.utc(2026, 10, 14),
            amountMinor: 500000,
            categoryId: 'cat-dining',
            categoryName: 'Dining & Food',
            merchantLabel: 'Swiggy',
          ),
          // Current month (Nov 2026):
          // Rent ₹20,000 (weekday Thu Nov 5)
          AdvisorExpenseEntry(
            dateUtc: DateTime.utc(2026, 11, 5),
            amountMinor: 2000000,
            categoryId: 'cat-rent',
            categoryName: 'Housing & Rent',
            merchantLabel: 'Monthly Rent',
          ),
          // Dining spike: ₹9,000 total (+80% vs ₹5,000 trailing avg!)
          // Including 4x frequent cafe micro-spends of ₹500 on weekends!
          for (final day in [6, 7, 13, 14]) // Fri/Sat
            AdvisorExpenseEntry(
              dateUtc: DateTime.utc(2026, 11, day),
              amountMinor: 50000,
              categoryId: 'cat-dining',
              categoryName: 'Dining & Food',
              merchantLabel: 'Artisan Coffee',
            ),
          AdvisorExpenseEntry(
            dateUtc: DateTime.utc(2026, 11, 15), // Sunday
            amountMinor: 700000,
            categoryId: 'cat-dining',
            categoryName: 'Dining & Food',
            merchantLabel: 'Weekend Brunch & Bistro',
          ),
          // Shopping ₹15,000 (Saturday Nov 14 -> heavy weekend spend!)
          AdvisorExpenseEntry(
            dateUtc: DateTime.utc(2026, 11, 14),
            amountMinor: 1500000,
            categoryId: 'cat-shop',
            categoryName: 'Shopping',
            merchantLabel: 'Mall Apparel',
          ),
        ];

        final incomes = <AdvisorIncomeEntry>[
          AdvisorIncomeEntry(
            dateUtc: DateTime.utc(2026, 11, 1),
            amountMinor: 5000000, // ₹50,000 income -> 80% rule cap = ₹40,000
            categoryName: 'Salary',
          ),
        ];

        final report = CfoAdvisorEngine.analyze(
          CfoAdvisorInput(
            currencyCode: 'INR',
            nowUtc: now,
            expenses: expenses,
            incomes: incomes,
            activeBudgets: const [],
          ),
        );

        expect(report.selectedYearMonth, '2026-11');
        expect(report.availableMonths.length, 6);
        expect(report.monthSpendMinor, 4400000); // ₹44,000
        expect(report.monthIncomeMinor, 5000000); // ₹50,000
        expect(report.previousMonthSpendMinor, 2500000); // ₹25,000
        expect(report.momSpendDeltaPercent, closeTo(76.0, 0.5));

        // Dining must be flagged as a spike (+80% over ₹5,000 avg).
        final dining = report.categories.firstWhere(
          (c) => c.categoryName == 'Dining & Food',
        );
        expect(dining.isSpike, isTrue);
        expect(dining.deltaVsAvgPercent, closeTo(80.0, 0.5));

        // Artisan Coffee (4x ₹500 = ₹2,000/mo -> ₹24,000/yr) flagged as Money Leak.
        expect(
          report.moneyLeaks.any((l) => l.label == 'Artisan Coffee'),
          isTrue,
        );
        final coffeeLeak = report.moneyLeaks.firstWhere(
          (l) => l.label == 'Artisan Coffee',
        );
        expect(coffeeLeak.txCount, 4);
        expect(coffeeLeak.annualizedMinor, 2400000);

        // Weekend burn is heavier than weekday burn.
        expect(report.weekendBurn.isWeekendHeavy, isTrue);

        // 50/30/20 rule caps ₹50,000 income at ₹40,000 spending -> ₹10,000 savings.
        expect(report.budgetPlan.methodologyLabel, '50 / 30 / 20 Income Rule');
        expect(report.budgetPlan.recommendedOverallLimitMinor, 4000000);
        expect(report.budgetPlan.estimatedMonthlySavingsMinor, 1000000);
        expect(report.maintenanceTips, isNotEmpty);

        // Selecting a historical month ('2026-10') computes October cleanly!
        final octReport = CfoAdvisorEngine.analyze(
          CfoAdvisorInput(
            currencyCode: 'INR',
            nowUtc: now,
            selectedYearMonth: '2026-10',
            expenses: expenses,
            incomes: incomes,
            activeBudgets: const [],
          ),
        );
        expect(octReport.isCurrentMonth, isFalse);
        expect(octReport.monthSpendMinor, 2500000);

        // Offline Q&A intents + strict privacy masking!
        final saveReply = CfoAdvisorEngine.answerQuestion(
          report,
          'How can I save 5000 every month?',
        );
        expect(saveReply.headline, contains('5,000'));
        expect(saveReply.actionSteps, isNotEmpty);
        expect(saveReply.budgetAction, isNotNull);

        final budgetReply = CfoAdvisorEngine.answerQuestion(
          report,
          'Suggest a monthly budget for me',
        );
        expect(budgetReply.budgetAction?.limitMinor, 4000000);

        final diningReply = CfoAdvisorEngine.answerQuestion(
          report,
          'How much did I spend on dining?',
        );
        expect(diningReply.headline, contains('Dining & Food'));

        final maskedReply = CfoAdvisorEngine.answerQuestion(
          report,
          'Where is my money going?',
          maskBalances: true,
        );
        expect(maskedReply.summary, contains('••••••'));
        expect(maskedReply.summary, isNot(contains('44,000')));
      },
    );
  });

  group('CfoAdvisorService & Responsive AiCoachPage UI', () {
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
        clockOverride: FixedUtcClock(DateTime.utc(2026, 11, 20, 10, 0)),
      );
    }

    tearDown(() async {
      if (getIt.isRegistered<AppDatabase>()) {
        await getIt<AppDatabase>().close();
      }
      await getIt.reset();
    });

    testWidgets(
      'CfoAdvisorService isolates profiles, nets refunds & splits, and AiCoachPage passes 360x800 + 1.5x Dark Mode Audit -> 1-Tap Apply Budget -> Chat Q&A',
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

        // Create two isolated profiles; put huge spend in Profile B to verify zero leak!
        final profB = (await activeProfileCubit.createProfile(
          ownerDisplayName: 'Owner',
          name: 'Other Business',
          profileType: ProfileType.business,
          baseCurrencyCode: 'INR',
        )).valueOrNull!;
        final accB =
            (await getIt<AccountRepository>().createAccountWithOpeningBalance(
              profileId: profB.id,
              name: 'Biz Bank',
              accountType: FinancialAccountType.bank,
              currencyCode: 'INR',
              openingBalanceMinor: 50000000,
            )).valueOrNull!;
        final catsB = (await getIt<CategoryRepository>().listCategories(
          profB.id,
          type: CategoryType.expense,
        )).valueOrNull!;
        await getIt<TransactionRepository>().createTransaction(
          profB.id,
          CreateTransactionCommand(
            type: TransactionType.expense,
            amountMinor: 9900000,
            currencyCode: 'INR',
            transactionDateUtc: DateTime.utc(2026, 11, 10).toIso8601String(),
            sourceAccountId: accB.id,
            categoryId: catsB.first.id,
            description: 'Secret Business Machinery',
          ),
        );

        // Active Profile A
        final profA = (await activeProfileCubit.createProfile(
          ownerDisplayName: 'Owner',
          name: 'My Personal Vault',
          profileType: ProfileType.personal,
          baseCurrencyCode: 'INR',
        )).valueOrNull!;
        final bankA =
            (await getIt<AccountRepository>().createAccountWithOpeningBalance(
              profileId: profA.id,
              name: 'HDFC Bank',
              accountType: FinancialAccountType.bank,
              currencyCode: 'INR',
              openingBalanceMinor: 10000000,
            )).valueOrNull!;
        final expCatsA = (await getIt<CategoryRepository>().listCategories(
          profA.id,
          type: CategoryType.expense,
        )).valueOrNull!;
        final incCatsA = (await getIt<CategoryRepository>().listCategories(
          profA.id,
          type: CategoryType.income,
        )).valueOrNull!;

        // Income ₹60,000
        await getIt<TransactionRepository>().createTransaction(
          profA.id,
          CreateTransactionCommand(
            type: TransactionType.income,
            amountMinor: 6000000,
            currencyCode: 'INR',
            transactionDateUtc: DateTime.utc(2026, 11, 1).toIso8601String(),
            destinationAccountId: bankA.id,
            categoryId: incCatsA.first.id,
            description: 'Monthly Salary',
          ),
        );
        // Split expense ₹10,000 (₹6,000 + ₹4,000)
        await getIt<TransactionRepository>().createTransaction(
          profA.id,
          CreateTransactionCommand(
            type: TransactionType.expense,
            amountMinor: 1000000,
            currencyCode: 'INR',
            transactionDateUtc: DateTime.utc(2026, 11, 12).toIso8601String(),
            sourceAccountId: bankA.id,
            description: 'Weekend Mall Run',
            splits: [
              SplitCommandLine(categoryId: expCatsA[0].id, amountMinor: 600000),
              SplitCommandLine(categoryId: expCatsA[1].id, amountMinor: 400000),
            ],
          ),
        );

        // Verify strict profile isolation in service report!
        final serviceReport = (await getIt<CfoAdvisorService>().buildReport(
          profileId: profA.id,
          baseCurrencyCode: 'INR',
        )).valueOrNull!;
        expect(serviceReport.monthSpendMinor, 1000000);
        expect(
          serviceReport.topMerchants.any(
            (m) => m.label.contains('Secret Business'),
          ),
          isFalse,
        );

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
              home: const AiCoachPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Monthly Audit tab shows real spend & zero Business leak.
        expect(find.text('Smart CFO Coach'), findsOneWidget);
        expect(find.text('Weekend Mall Run'), findsOneWidget);
        expect(find.text('Secret Business Machinery'), findsNothing);

        // 2. Switch to Budget Plan tab -> 1-Tap Apply Monthly Budget!
        final segmentedTabs = find.byKey(const Key('coach_segmented_tabs'));
        await tester.tap(
          find.descendant(
            of: segmentedTabs,
            matching: find.text('Budget Plan'),
          ),
        );
        await tester.pumpAndSettle();
        final applyBtn = find.byKey(
          const Key('coach_apply_overall_budget_btn'),
        );
        expect(applyBtn, findsOneWidget);
        await tester.ensureVisible(applyBtn);
        await tester.tap(applyBtn);
        await tester.pumpAndSettle();
        expect(find.text('Apply Suggested Budget?'), findsOneWidget);

        await tester.tap(find.textContaining('Apply ₹'));
        await tester.pumpAndSettle();

        final createdBudgets =
            (await getIt<BudgetRepository>().listBudgetsWithProgress(
              profA.id,
            )).valueOrNull!;
        expect(createdBudgets.length, 1);

        // 3. Switch to Ask Coach tab -> ask a live question!
        await tester.tap(
          find.descendant(of: segmentedTabs, matching: find.text('Ask Coach')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('coach_chat_input')),
          'How can I save 3000?',
        );
        await tester.tap(find.byKey(const Key('coach_chat_send_btn')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Savings Roadmap'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
