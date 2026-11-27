import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_money/app/config/environment_config.dart';
import 'package:pocket_money/app/theme/app_theme.dart';
import 'package:pocket_money/bootstrap.dart';
import 'package:pocket_money/core/database/app_database.dart';
import 'package:pocket_money/core/database/encrypted_executor.dart';
import 'package:pocket_money/core/financial_engine/alert_evaluation_engine.dart';
import 'package:pocket_money/core/financial_engine/monthly_tracker_engine.dart';
import 'package:pocket_money/core/notifications/local_notification_service.dart';
import 'package:pocket_money/core/security/backup_crypto.dart';
import 'package:pocket_money/core/security/key_manager.dart';
import 'package:pocket_money/core/security/privacy_screen_service.dart';
import 'package:pocket_money/core/utilities/clock.dart';
import 'package:pocket_money/features/accounts/domain/entities/financial_account_entity.dart';
import 'package:pocket_money/features/accounts/domain/repositories/account_repository.dart';
import 'package:pocket_money/features/backup_restore/data/backup_restore_service.dart';
import 'package:pocket_money/features/budgets/domain/repositories/budget_repository.dart';
import 'package:pocket_money/features/categories/domain/entities/category_entity.dart';
import 'package:pocket_money/features/categories/domain/repositories/category_repository.dart';
import 'package:pocket_money/features/dashboard/presentation/bloc/dashboard_bloc.dart';
import 'package:pocket_money/features/monthly_tracker/data/monthly_tracker_service.dart';
import 'package:pocket_money/features/monthly_tracker/domain/entities/bucket_list_item_entity.dart';
import 'package:pocket_money/features/monthly_tracker/domain/repositories/bucket_list_repository.dart';
import 'package:pocket_money/features/monthly_tracker/presentation/pages/monthly_tracker_page.dart';
import 'package:pocket_money/features/profiles/domain/entities/profile_entity.dart';
import 'package:pocket_money/features/profiles/presentation/bloc/active_profile_cubit.dart';
import 'package:pocket_money/features/savings_goals/domain/repositories/savings_goal_repository.dart';
import 'package:pocket_money/features/settings/data/settings_repository.dart';
import 'package:pocket_money/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:pocket_money/features/transactions/domain/entities/transaction_entity.dart';
import 'package:pocket_money/features/transactions/domain/repositories/transaction_repository.dart';

void main() {
  group('MonthlyTrackerEngine pure-Dart algorithms', () {
    test(
      'computes snapshot cash flow, daily heatmap, no-spend streak, projections & category deltas',
      () {
        final now = DateTime.utc(2026, 11, 15, 10, 0);
        final snap = MonthlyTrackerEngine.buildSnapshot(
          MonthlyTrackerInput(
            currencyCode: 'INR',
            year: 2026,
            month: 11,
            nowUtc: now,
            incomeMinor: 8000000, // ₹80,000
            expenses: const [
              MonthSpendEntry(
                dateUtc: '2026-11-02T10:00:00Z',
                amountMinor: 1500000, // ₹15,000 Rent
                categoryName: 'Housing & Rent',
                isEssential: true,
              ),
              MonthSpendEntry(
                dateUtc: '2026-11-05T14:00:00Z',
                amountMinor: 500000, // ₹5,000 Groceries
                categoryName: 'Groceries',
                isEssential: true,
              ),
              MonthSpendEntry(
                dateUtc: '2026-11-09T19:00:00Z',
                amountMinor: 400000, // ₹4,000 Dining
                categoryName: 'Dining & Food',
                isEssential: false,
              ),
            ],
            refundsMinor: 100000, // ₹1,000 refund
            previousSpendMinor: 3000000,
            previousSpendByCategory: const {'Groceries': 400000},
            upcoming: const [
              UpcomingCommitment(
                label: 'Internet Bill',
                dueDateUtc: '2026-11-22T09:00:00Z',
                amountMinor: 100000, // ₹1,000
                kind: 'bill',
              ),
            ],
            savingsTargetPct: 20, // ₹16,000
            wantsCapPct: 30,
          ),
        );

        expect(snap.isCurrentMonth, isTrue);
        expect(snap.daysElapsed, 15);
        expect(snap.daysLeft, 16);
        expect(snap.grossSpendMinor, 2400000);
        expect(snap.spentMinor, 2300000); // ₹23,000 net of ₹1k refund
        expect(snap.needsSpentMinor, 2000000);
        expect(snap.wantsSpentMinor, 300000);
        expect(snap.savedMinor, 5700000); // ₹57,000
        expect(snap.savingsRatePct, closeTo(71.25, 0.01));
        expect(
          snap.dailySpendMinor.fold<int>(0, (s, v) => s + v),
          snap.grossSpendMinor,
        );
        expect(snap.noSpendDays, 12); // 15 elapsed - 3 active days
        expect(snap.noSpendStreak, 6); // Days 10..15 have ₹0 spend!
        expect(snap.biggestDayNumber, 2);
        expect(snap.biggestDayMinor, 1500000);
        expect(snap.committedRemainingMinor, 100000);
        expect(snap.savingsTargetMinor, 1600000);
        // 80k - 23k - 1k - 16k = ₹40,000 free
        expect(snap.freeToSpendMinor, 4000000);
        expect(snap.safeDailySpendMinor, 4000000 ~/ 16);
        expect(snap.projectedMonthEndSpendMinor, (2300000 * 30) ~/ 15);
        expect(snap.healthLabel, 'On Track');
        expect(snap.insights, isNotEmpty);
      },
    );

    test(
      'plans priority-ranked Bucket List (urgent savings borrow, urgent shortfall, essential partial, nice defer + cooling-off, dream saveUp, future scheduled, overdue)',
      () {
        final now = DateTime.utc(2026, 11, 15, 10, 0);
        final plan = MonthlyTrackerEngine.planBucketList(
          monthKey: '2026-11',
          nowUtc: now,
          availablePoolMinor: 1000000, // ₹10,000 pool
          savingsFloorMinor: 500000, // ₹5,000 savings floor
          wantsHeadroomMinor: 200000, // ₹2,000 wants headroom
          effectiveIncomeMinor: 5000000, // ₹50,000 (5% = ₹2,500)
          items: [
            BucketPlanInput(
              id: 'u1',
              name: 'Car Brake Repair',
              priority: 'urgent',
              estimatedMinor: 1200000, // ₹12k -> ₹10k pool + ₹2k savings floor
              savedMinor: 0,
              targetYearMonth: '2026-10', // Overdue month!
              createdAtUtc: '2026-10-20T00:00:00Z',
            ),
            BucketPlanInput(
              id: 'u2',
              name: 'Laptop Emergency Replace',
              priority: 'urgent',
              estimatedMinor:
                  600000, // ₹6k -> ₹3k left in savings -> ₹3k shortfall!
              savedMinor: 0,
              targetYearMonth: '2026-11',
              dueDateUtc: '2026-11-17T00:00:00Z', // Due in 2 days!
              createdAtUtc: '2026-11-10T00:00:00Z',
            ),
            BucketPlanInput(
              id: 'n1',
              name: 'Gaming Console',
              priority: 'nice',
              estimatedMinor: 400000, // >5% of ₹50k and created 2 days ago!
              savedMinor: 0,
              targetYearMonth: '2026-11',
              createdAtUtc: '2026-11-13T00:00:00Z',
            ),
            BucketPlanInput(
              id: 'd1',
              name: 'Japan Trip',
              priority: 'dream',
              estimatedMinor: 10000000, // ₹1,00,000
              savedMinor: 1000000, // ₹10k saved -> ₹90k / 4 mo = ₹22,500/mo
              targetYearMonth: '2026-11',
              dueDateUtc: '2027-03-01T00:00:00Z',
              createdAtUtc: '2026-11-01T00:00:00Z',
            ),
            BucketPlanInput(
              id: 'f1',
              name: 'Annual Insurance',
              priority: 'essential',
              estimatedMinor: 900000, // ₹9k for 2027-01 (+2 mo => 3 mo divisor)
              savedMinor: 0,
              targetYearMonth: '2027-01',
              createdAtUtc: '2026-11-01T00:00:00Z',
            ),
          ],
        );

        expect(plan.byItemId['u1']!.verdict, BucketVerdict.buyNow);
        expect(plan.byItemId['u1']!.usesSavingsMinor, 200000);
        expect(plan.byItemId['u1']!.isOverdue, isTrue);

        expect(plan.byItemId['u2']!.verdict, BucketVerdict.urgentShortfall);
        expect(plan.byItemId['u2']!.isDueSoon, isTrue);
        expect(plan.urgentShortfallMinor, 300000);

        expect(plan.byItemId['n1']!.verdict, BucketVerdict.defer);
        expect(plan.byItemId['n1']!.coolingOffSuggested, isTrue);

        expect(plan.byItemId['d1']!.verdict, BucketVerdict.saveUp);
        expect(plan.byItemId['d1']!.monthsToSave, 4);
        expect(plan.byItemId['d1']!.suggestedMonthlySavingMinor, 2250000);

        expect(plan.byItemId['f1']!.verdict, BucketVerdict.scheduled);
        expect(plan.byItemId['f1']!.suggestedMonthlySavingMinor, 300000);

        // Also verify essential partial verdict when pool covers part of essential item
        final partialPlan = MonthlyTrackerEngine.planBucketList(
          monthKey: '2026-11',
          nowUtc: now,
          availablePoolMinor: 400000,
          savingsFloorMinor: 500000,
          wantsHeadroomMinor: 200000,
          effectiveIncomeMinor: 5000000,
          items: const [
            BucketPlanInput(
              id: 'e1',
              name: 'Washing Machine',
              priority: 'essential',
              estimatedMinor: 1000000,
              savedMinor: 0,
              targetYearMonth: '2026-11',
              createdAtUtc: '2026-11-01T00:00:00Z',
            ),
          ],
        );
        expect(partialPlan.byItemId['e1']!.verdict, BucketVerdict.partial);
        expect(partialPlan.byItemId['e1']!.allocatedThisMonthMinor, 400000);
        expect(partialPlan.essentialUnfundedMinor, 600000);
      },
    );

    test(
      'computes exact zero-remainder windfall splits and deterministic bucket reminder dedupe keys',
      () {
        final cases = [
          (amt: 1000000, gap: 200000, urgent: 300000, ess: 200000),
          (amt: 500000, gap: 0, urgent: 0, ess: 250000),
          (amt: 750000, gap: 0, urgent: 0, ess: 0),
          (amt: 300000, gap: 500000, urgent: 100000, ess: 100000),
        ];
        for (final c in cases) {
          final split = MonthlyTrackerEngine.suggestWindfallSplit(
            amountMinor: c.amt,
            monthGapMinor: c.gap,
            urgentShortfallMinor: c.urgent,
            essentialUnfundedMinor: c.ess,
          );
          expect(split.totalMinor, c.amt);
          expect(split.toSavingsMinor, greaterThanOrEqualTo(0));
          expect(split.toBucketMinor, greaterThanOrEqualTo(0));
          expect(split.toSpendMinor, greaterThanOrEqualTo(0));
        }

        final p50 = MonthlyTrackerEngine.presetSplit(123456, 50, 30);
        expect(p50.totalMinor, 123456);
        final p100 = MonthlyTrackerEngine.presetSplit(100000, 100, 0);
        expect(p100.toSavingsMinor, 100000);
        expect(p100.toBucketMinor, 0);
        expect(p100.toSpendMinor, 0);

        final remAlerts = AlertEvaluationEngine.evaluateBucketReminders(
          nowUtc: DateTime.utc(2026, 11, 15, 10, 0),
          currencyCode: 'INR',
          items: const [
            BucketPlanInput(
              id: 'item-1',
              name: 'Headphones',
              priority: 'nice',
              estimatedMinor: 500000,
              savedMinor: 0,
              targetYearMonth: '2026-11',
              reminderAtUtc: '2026-11-15T09:00:00Z',
              dueDateUtc: '2026-11-17T12:00:00Z',
              createdAtUtc: '2026-11-01T00:00:00Z',
            ),
          ],
        );
        expect(remAlerts.length, 2);
        expect(remAlerts[0].dedupeKey, 'bucket_reminder:item-1:2026-11-15');
        expect(remAlerts[1].dedupeKey, 'bucket_due:item-1:2026-11-17');
        expect(remAlerts[0].deepLinkRoute, '/monthly?tab=1');
      },
    );

    test(
      'computes MonthScorecard grades and live PurchaseAffordabilityPreview verdicts',
      () {
        final now = DateTime.utc(2026, 11, 15, 10, 0);
        final strongSnap = MonthlyTrackerEngine.buildSnapshot(
          MonthlyTrackerInput(
            currencyCode: 'INR',
            year: 2026,
            month: 11,
            nowUtc: now,
            incomeMinor: 10000000,
            expenses: const [
              MonthSpendEntry(
                dateUtc: '2026-11-02T10:00:00Z',
                amountMinor: 1500000,
                categoryName: 'Rent',
                isEssential: true,
              ),
            ],
            savingsTargetPct: 20,
          ),
        );
        final eliteCard = MonthlyTrackerEngine.buildScorecard(
          strongSnap,
          boughtBucketCount: 1,
        );
        expect(eliteCard.score, inInclusiveRange(80, 100));
        expect(eliteCard.grade, anyOf('A+', 'A'));
        expect(eliteCard.shareSummary, contains('Pocket CFO Recap (2026-11)'));

        final previewSafe = MonthlyTrackerEngine.previewPurchaseAffordability(
          snapshot: strongSnap,
          amountMinor: 200000,
          priority: 'essential',
        );
        expect(previewSafe.tone, 'safe');

        final previewCool = MonthlyTrackerEngine.previewPurchaseAffordability(
          snapshot: strongSnap,
          amountMinor: 800000, // 8% > 5% threshold
          priority: 'nice',
        );
        expect(previewCool.coolingOffWarning, isTrue);
        expect(previewCool.tone, 'caution');

        final previewDream = MonthlyTrackerEngine.previewPurchaseAffordability(
          snapshot: strongSnap,
          amountMinor: 9000000,
          priority: 'dream',
        );
        expect(previewDream.tone, 'goal');

        final deficitSnap = MonthlyTrackerEngine.buildSnapshot(
          MonthlyTrackerInput(
            currencyCode: 'INR',
            year: 2026,
            month: 11,
            nowUtc: now,
            incomeMinor: 2000000,
            expenses: const [
              MonthSpendEntry(
                dateUtc: '2026-11-02T10:00:00Z',
                amountMinor: 2500000,
                categoryName: 'Rent',
                isEssential: true,
              ),
            ],
          ),
        );
        final lowCard = MonthlyTrackerEngine.buildScorecard(deficitSnap);
        expect(lowCard.grade, anyOf('C', 'D'));
      },
    );
  });

  group('MonthlyTrackerService, Repository, Reminders & Responsive UI', () {
    late InMemoryNotificationDispatcher dispatcher;

    Future<void> initTestApp() async {
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

    test(
      'verifies profile isolation, budget reservation idempotency, goal conversion, windfall routing, reminder scheduling & dedupe, and encrypted backup payload',
      () async {
        await initTestApp();

        final activeProfileCubit = ActiveProfileCubit(
          repository: getIt(),
          scopeController: getIt(),
          settings: getIt(),
        );
        addTearDown(activeProfileCubit.close);

        final profB = (await activeProfileCubit.createProfile(
          ownerDisplayName: 'Owner',
          name: 'Other Profile',
          profileType: ProfileType.business,
          baseCurrencyCode: 'INR',
        )).valueOrNull!;
        final profA = (await activeProfileCubit.createProfile(
          ownerDisplayName: 'Owner',
          name: 'Main Vault',
          profileType: ProfileType.personal,
          baseCurrencyCode: 'INR',
        )).valueOrNull!;

        final bankA =
            (await getIt<AccountRepository>().createAccountWithOpeningBalance(
              profileId: profA.id,
              name: 'Salary Bank',
              accountType: FinancialAccountType.bank,
              currencyCode: 'INR',
              openingBalanceMinor: 5000000,
            )).valueOrNull!;

        final expCatsA = (await getIt<CategoryRepository>().listCategories(
          profA.id,
          type: CategoryType.expense,
        )).valueOrNull!;
        final grocCat = expCatsA.first;

        final svc = getIt<MonthlyTrackerService>();
        final repo = getIt<BucketListRepository>();

        // Profile isolation + future reminder scheduling
        await svc.saveItem(
          profile: profB,
          name: 'Secret Server Rack',
          estimatedAmountMinor: 9000000,
          priority: BucketPriority.urgent,
          targetYearMonth: '2026-11',
        );

        final savedItem = (await svc.saveItem(
          profile: profA,
          name: 'Winter Coat',
          estimatedAmountMinor: 800000,
          priority: BucketPriority.essential,
          targetYearMonth: '2026-11',
          categoryId: grocCat.id,
          reminderAtUtc: '2026-11-20T09:00:00Z',
        )).valueOrNull!;

        expect(
          dispatcher.scheduledReminders.containsKey(
            MonthlyTrackerService.reminderIdForItem(savedItem.id),
          ),
          isTrue,
        );
        final listA = (await repo.listItems(profA.id)).valueOrNull!;
        expect(listA.length, 1);
        expect(listA.first.name, 'Winter Coat');

        // Reserve in budget (idempotent on 2nd call)
        final resBudget1 = (await svc.reserveInBudget(
          profile: profA,
          item: savedItem,
        )).valueOrNull!;
        expect(resBudget1.reservedInBudgetMinor, 800000);
        final resBudget2 = (await svc.reserveInBudget(
          profile: profA,
          item: resBudget1,
        )).valueOrNull!;
        expect(resBudget2.reservedInBudgetMinor, 800000);

        final budgetsAfterReserve =
            (await getIt<BudgetRepository>().listBudgetsWithProgress(
              profA.id,
            )).valueOrNull!;
        expect(budgetsAfterReserve.length, 1);
        expect(budgetsAfterReserve.first.overallLimit.amountMinor, 800000);

        // Convert Dream item to Savings Goal
        final dreamItem = (await svc.saveItem(
          profile: profA,
          name: 'Bali Trip',
          estimatedAmountMinor: 6000000,
          savedAmountMinor: 500000,
          priority: BucketPriority.dream,
          targetYearMonth: '2026-11',
        )).valueOrNull!;
        final linkedDream = (await svc.convertToGoal(
          profile: profA,
          item: dreamItem,
        )).valueOrNull!;
        expect(linkedDream.linkedGoalId, isNotNull);
        final goals = (await getIt<SavingsGoalRepository>().listGoals(
          profA.id,
        )).valueOrNull!;
        expect(goals.any((g) => g.name == 'Bali Trip'), isTrue);

        // Record Extra Income & Split across Goal, Bucket Item, and Spend Cap
        final windfallRes = (await svc.recordExtraIncome(
          profile: profA,
          amountMinor: 2000000, // ₹20,000
          sourceLabel: 'Annual Bonus',
          accountId: bankA.id,
          dateUtc: DateTime.utc(2026, 11, 15, 11, 0),
          split: const WindfallSplit(
            toSavingsMinor: 1000000,
            toBucketMinor: 600000,
            toSpendMinor: 400000,
            rationale: 'Test split',
          ),
        )).valueOrNull!;
        expect(windfallRes.toBucketMinor, 600000);

        final coatUpdated = (await repo.listItems(
          profA.id,
        )).valueOrNull!.firstWhere((b) => b.id == savedItem.id);
        expect(coatUpdated.savedAmountMinor, 600000);

        final budgetsAfterWindfall =
            (await getIt<BudgetRepository>().listBudgetsWithProgress(
              profA.id,
            )).valueOrNull!;
        expect(budgetsAfterWindfall.first.overallLimit.amountMinor, 1200000);

        // Due reminder inbox evaluation inserts strictly once across 2 calls
        await svc.saveItem(
          profile: profA,
          name: 'Due Item',
          estimatedAmountMinor: 200000,
          priority: BucketPriority.urgent,
          targetYearMonth: '2026-11',
          dueDateUtc: '2026-11-16T12:00:00Z',
        );
        final fired1 = await svc.evaluateDueReminders(profA);
        final fired2 = await svc.evaluateDueReminders(profA);
        expect(fired1.length, 1);
        expect(fired2, isEmpty);

        // Encrypted backup includes bucket_list_items
        final archiveRes = await getIt<BackupRestoreService>()
            .exportEncryptedBackup(
              passphrase: 'StrongBackup!2026',
              scopeProfileId: profA.id,
            );
        expect(archiveRes.isSuccess, isTrue);
        final decrypted = await const BackupCrypto().decryptBackup(
          rawArchive: archiveRes.valueOrNull!,
          passphrase: 'StrongBackup!2026',
        );
        expect(decrypted.payloadJson['bucket_list_items'], isNotEmpty);
      },
    );

    testWidgets(
      'passes 360x800 + 1.5x Dark Mode E2E (Overview -> Month Switch -> Add & Buy Bucket Item -> Windfall Split -> Masking) and 1280x840 Light Mode',
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

        final prof = (await activeProfileCubit.createProfile(
          ownerDisplayName: 'Owner',
          name: 'My Month Vault',
          profileType: ProfileType.personal,
          baseCurrencyCode: 'INR',
        )).valueOrNull!;
        final bank =
            (await getIt<AccountRepository>().createAccountWithOpeningBalance(
              profileId: prof.id,
              name: 'HDFC Bank',
              accountType: FinancialAccountType.bank,
              currencyCode: 'INR',
              openingBalanceMinor: 10000000,
            )).valueOrNull!;
        final incCats = (await getIt<CategoryRepository>().listCategories(
          prof.id,
          type: CategoryType.income,
        )).valueOrNull!;
        final expCats = (await getIt<CategoryRepository>().listCategories(
          prof.id,
          type: CategoryType.expense,
        )).valueOrNull!;

        await getIt<TransactionRepository>().createTransaction(
          prof.id,
          CreateTransactionCommand(
            type: TransactionType.income,
            amountMinor: 8000000,
            currencyCode: 'INR',
            transactionDateUtc: DateTime.utc(2026, 11, 1).toIso8601String(),
            destinationAccountId: bank.id,
            categoryId: incCats.first.id,
            description: 'Monthly Salary',
          ),
        );
        await getIt<TransactionRepository>().createTransaction(
          prof.id,
          CreateTransactionCommand(
            type: TransactionType.expense,
            amountMinor: 1200000,
            currencyCode: 'INR',
            transactionDateUtc: DateTime.utc(2026, 11, 5).toIso8601String(),
            sourceAccountId: bank.id,
            categoryId: expCats.first.id,
            description: 'Monthly Groceries',
          ),
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
              home: const MonthlyTrackerPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Overview Hero, Heatmap, Insights, Scorecard Recap & Month Switching + Today Jump
        expect(find.byKey(const Key('monthly_hero_card')), findsOneWidget);
        expect(find.byKey(const Key('monthly_heatmap')), findsOneWidget);
        expect(find.byKey(const Key('monthly_insights_card')), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const Key('monthly_recap_btn')));
        await tester.pumpAndSettle();
        expect(find.text('Monthly CFO Scorecard'), findsOneWidget);
        expect(find.byKey(const Key('monthly_recap_copy_btn')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('monthly_month_prev')));
        await tester.pumpAndSettle();
        expect(find.text('October 2026'), findsOneWidget);
        expect(find.byKey(const Key('monthly_month_today')), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const Key('monthly_month_today')));
        await tester.pumpAndSettle();
        expect(find.text('November 2026'), findsOneWidget);

        // 2. Bucket List Tab: Horizontal Pill Filter, Quick Affordability Preview & Inline Actions
        final modeTabs = find.byKey(const Key('monthly_tracker_tabs'));
        await tester.tap(
          find.descendant(of: modeTabs, matching: find.text('Bucket List')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('bucket_priority_filter_bar')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        final addBucketBtn = find.byKey(const Key('bucket_add_btn'));
        await tester.ensureVisible(addBucketBtn);
        await tester.tap(addBucketBtn);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('bucket_name_field')),
          'Helmet',
        );
        await tester.enterText(
          find.byKey(const Key('bucket_amount_field')),
          '3500',
        );
        final urgentCard = find.byKey(const Key('bucket_priority_urgent'));
        await tester.ensureVisible(urgentCard);
        await tester.tap(urgentCard);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final saveBucketBtn = find.byKey(const Key('bucket_save_btn'));
        await tester.ensureVisible(saveBucketBtn);
        await tester.tap(saveBucketBtn);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('bucket_plan_summary_card')),
          findsOneWidget,
        );
        expect(find.text('Helmet'), findsOneWidget);
        expect(find.text('+ Fund'), findsOneWidget);
        expect(find.text('Buy'), findsOneWidget);
        expect(tester.takeException(), isNull);

        final itemsAfterSave = (await getIt<BucketListRepository>().listItems(
          prof.id,
        )).valueOrNull!;
        expect(itemsAfterSave.length, 1);

        final menuBtn = find.byKey(
          Key('bucket_menu_${itemsAfterSave.first.id}'),
        );
        await tester.ensureVisible(menuBtn);
        await tester.tap(menuBtn);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Mark as bought'));
        await tester.pumpAndSettle();

        final boughtConfirm = find.byKey(
          const Key('bucket_bought_confirm_btn'),
        );
        await tester.ensureVisible(boughtConfirm);
        await tester.tap(boughtConfirm);
        await tester.pumpAndSettle();

        final txsAfterBuy =
            (await getIt<TransactionRepository>().queryTransactions(
              prof.id,
            )).valueOrNull!.items;
        expect(
          txsAfterBuy.any((t) => t.description == 'Bucket: Helmet'),
          isTrue,
        );

        // 3. Extra Income Tab: Simulator + Quick-Apply + Manual Split!
        await tester.tap(
          find.descendant(of: modeTabs, matching: find.text('Extra Income')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('windfall_simulator_card')),
          findsOneWidget,
        );
        final simApplyBtn = find.byKey(const Key('windfall_sim_apply_btn'));
        await tester.ensureVisible(simApplyBtn);
        await tester.tap(simApplyBtn);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('windfall_confirm_btn')), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        final addIncomeBtn = find.byKey(const Key('extra_income_add_btn'));
        await tester.ensureVisible(addIncomeBtn);
        await tester.tap(addIncomeBtn);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('extra_income_amount_field')),
          '10000',
        );
        await tester.pumpAndSettle();

        final smartPreset = find.byKey(const Key('windfall_preset_smart'));
        await tester.ensureVisible(smartPreset);
        await tester.tap(smartPreset);
        await tester.pumpAndSettle();

        final confirmWindfall = find.byKey(const Key('windfall_confirm_btn'));
        await tester.ensureVisible(confirmWindfall);
        await tester.tap(confirmWindfall);
        await tester.pumpAndSettle();

        final txsAfterWindfall =
            (await getIt<TransactionRepository>().queryTransactions(
              prof.id,
            )).valueOrNull!.items;
        expect(
          txsAfterWindfall.any(
            (t) =>
                t.type == TransactionType.income &&
                t.baseAmount.amountMinor == 1000000,
          ),
          isTrue,
        );

        // 4. Masking & Desktop 1280x840 Light Mode check
        await settingsCubit.toggleHideBalances();
        await tester.pumpAndSettle();
        expect(find.textContaining('••••••'), findsWidgets);
        expect(tester.takeException(), isNull);

        await tester.binding.setSurfaceSize(const Size(1280, 840));
        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider.value(value: activeProfileCubit),
              BlocProvider.value(value: settingsCubit),
              BlocProvider.value(value: dashboardBloc),
            ],
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const MonthlyTrackerPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });
}
