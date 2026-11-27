import 'dart:convert';
import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import '../../../core/errors/failures.dart';
import '../../../core/financial_engine/alert_evaluation_engine.dart';
import '../../../core/financial_engine/life_stage_planner_engine.dart';
import '../../../core/financial_engine/money.dart';
import '../../../core/financial_engine/monthly_tracker_engine.dart';
import '../../../core/notifications/local_notification_service.dart';
import '../../../core/utilities/clock.dart';
import '../../../core/utilities/id_generator.dart';
import '../../accounts/domain/entities/financial_account_entity.dart';
import '../../accounts/domain/repositories/account_repository.dart';
import '../../budgets/data/ca_budget_planner_service.dart';
import '../../budgets/domain/entities/budget_entity.dart';
import '../../budgets/domain/repositories/budget_repository.dart';
import '../../categories/domain/entities/category_entity.dart';
import '../../categories/domain/repositories/category_repository.dart';
import '../../life_planner/data/life_stage_planner_service.dart';
import '../../loans/data/repositories/drift_loan_repository.dart';
import '../../notifications/data/financial_alerts_coordinator.dart';
import '../../profiles/domain/entities/profile_entity.dart';
import '../../recurring/data/repositories/drift_recurring_repository.dart';
import '../../recurring/domain/entities/recurring_rule_entity.dart';
import '../../savings_goals/domain/entities/savings_goal_entity.dart';
import '../../savings_goals/domain/repositories/savings_goal_repository.dart';
import '../../settings/data/settings_repository.dart';
import '../../transactions/domain/entities/transaction_entity.dart';
import '../../transactions/domain/repositories/transaction_repository.dart';
import '../domain/entities/bucket_list_item_entity.dart';
import '../domain/repositories/bucket_list_repository.dart';

/// Persisted extra / windfall income split history entry for a month.
final class WindfallRecord extends Equatable {
  const WindfallRecord({
    required this.txId,
    required this.amountMinor,
    required this.sourceLabel,
    required this.toSavingsMinor,
    required this.toBucketMinor,
    required this.toSpendMinor,
    required this.createdAtUtc,
    this.goalId,
  });

  final String txId;
  final int amountMinor;
  final String sourceLabel;
  final int toSavingsMinor;
  final int toBucketMinor;
  final int toSpendMinor;
  final String? goalId;
  final String createdAtUtc;

  Map<String, dynamic> toJsonMap() => {
    'txId': txId,
    'amount': amountMinor,
    'source': sourceLabel,
    'toSavings': toSavingsMinor,
    'toBucket': toBucketMinor,
    'toSpend': toSpendMinor,
    'goalId': goalId,
    'createdAt': createdAtUtc,
  };

  factory WindfallRecord.fromJsonMap(Map<String, dynamic> m) => WindfallRecord(
    txId: (m['txId'] as String?) ?? '',
    amountMinor: (m['amount'] as int?) ?? 0,
    sourceLabel: (m['source'] as String?) ?? 'Extra Income',
    toSavingsMinor: (m['toSavings'] as int?) ?? 0,
    toBucketMinor: (m['toBucket'] as int?) ?? 0,
    toSpendMinor: (m['toSpend'] as int?) ?? 0,
    goalId: m['goalId'] as String?,
    createdAtUtc: (m['createdAt'] as String?) ?? '',
  );

  @override
  List<Object?> get props => [
    txId,
    amountMinor,
    sourceLabel,
    toSavingsMinor,
    toBucketMinor,
    toSpendMinor,
    goalId,
    createdAtUtc,
  ];
}

/// Compact pulse summary shown on the Dashboard entry card.
final class MonthlyPulseSummary extends Equatable {
  const MonthlyPulseSummary({
    required this.currencyCode,
    required this.year,
    required this.month,
    required this.incomeMinor,
    required this.spentMinor,
    required this.savedMinor,
    required this.freeToSpendMinor,
    required this.savingsRatePct,
    required this.healthLabel,
    required this.plannedBucketCount,
    required this.dueSoonBucketCount,
    this.safeDailySpendMinor = 0,
  });

  final String currencyCode;
  final int year;
  final int month;
  final int incomeMinor;
  final int spentMinor;
  final int savedMinor;
  final int freeToSpendMinor;
  final double savingsRatePct;
  final String healthLabel;
  final int plannedBucketCount;
  final int dueSoonBucketCount;
  final int safeDailySpendMinor;

  @override
  List<Object?> get props => [
    currencyCode,
    year,
    month,
    incomeMinor,
    spentMinor,
    savedMinor,
    freeToSpendMinor,
    savingsRatePct,
    healthLabel,
    plannedBucketCount,
    dueSoonBucketCount,
    safeDailySpendMinor,
  ];
}

/// Complete profile-scoped view state for [MonthlyTrackerPage].
final class MonthlyTrackerViewData {
  const MonthlyTrackerViewData({
    required this.profileId,
    required this.snapshot,
    required this.thisMonthItems,
    required this.upcomingItems,
    required this.purchasedThisMonthItems,
    required this.planById,
    required this.upcomingCommitments,
    required this.incomeTransactions,
    required this.windfalls,
    required this.activeGoals,
    required this.liquidAccounts,
    required this.expenseCategories,
    required this.masterBudget,
    this.preferredSalaryAccountId,
    this.salaryCreditedThisMonth = false,
  });

  final ProfileId profileId;
  final MonthlyTrackerSnapshot snapshot;
  final List<BucketListItemEntity> thisMonthItems;
  final List<BucketListItemEntity> upcomingItems;
  final List<BucketListItemEntity> purchasedThisMonthItems;
  final Map<String, BucketItemPlan> planById;
  final List<UpcomingCommitment> upcomingCommitments;
  final List<TransactionEntity> incomeTransactions;
  final List<WindfallRecord> windfalls;
  final List<SavingsGoalEntity> activeGoals;
  final List<FinancialAccountEntity> liquidAccounts;
  final List<CategoryEntity> expenseCategories;
  final BudgetEntity? masterBudget;
  final String? preferredSalaryAccountId;
  final bool salaryCreditedThisMonth;
}

/// Coordinates Monthly Tracker snapshots, Bucket List actions, Budget/Goal links,
/// Extra-Income splits, and one-shot purchase reminders across local repositories.
final class MonthlyTrackerService {
  MonthlyTrackerService({
    required TransactionRepository transactionRepository,
    required CategoryRepository categoryRepository,
    required AccountRepository accountRepository,
    required BudgetRepository budgetRepository,
    required CaBudgetPlannerService caBudgetPlannerService,
    required SavingsGoalRepository savingsGoalRepository,
    required DriftRecurringRepository recurringRepository,
    required DriftLoanRepository loanRepository,
    required BucketListRepository bucketListRepository,
    required LifeStagePlannerService lifeStagePlannerService,
    required FinancialAlertsCoordinator alertsCoordinator,
    required DeviceNotificationDispatcher notificationDispatcher,
    required SettingsRepository settingsRepository,
    required UtcClock clock,
  }) : _txRepo = transactionRepository,
       _catRepo = categoryRepository,
       _accountRepo = accountRepository,
       _budgetRepo = budgetRepository,
       _caBudgetService = caBudgetPlannerService,
       _goalRepo = savingsGoalRepository,
       _recurringRepo = recurringRepository,
       _loanRepo = loanRepository,
       _bucketRepo = bucketListRepository,
       _lifeService = lifeStagePlannerService,
       _alerts = alertsCoordinator,
       _dispatcher = notificationDispatcher,
       _settings = settingsRepository,
       _clock = clock;

  final TransactionRepository _txRepo;
  final CategoryRepository _catRepo;
  final AccountRepository _accountRepo;
  final BudgetRepository _budgetRepo;
  final CaBudgetPlannerService _caBudgetService;
  final SavingsGoalRepository _goalRepo;
  final DriftRecurringRepository _recurringRepo;
  final DriftLoanRepository _loanRepo;
  final BucketListRepository _bucketRepo;
  final LifeStagePlannerService _lifeService;
  final FinancialAlertsCoordinator _alerts;
  final DeviceNotificationDispatcher _dispatcher;
  final SettingsRepository _settings;
  final UtcClock _clock;

  static int reminderIdForItem(String id) => 'bucket:$id'.hashCode & 0x7FFFFFFF;

  static String _windfallKey(ProfileId id, String ym) =>
      'monthly_tracker.${id.value}.windfalls.$ym';

  Future<Result<MonthlyTrackerViewData>> loadMonth({
    required FinancialProfile profile,
    required int year,
    required int month,
  }) async {
    try {
      final nowUtc = _clock.nowUtc();
      final ccy = profile.baseCurrencyCode;
      final mk = MonthlyTrackerEngine.monthKey(year, month);
      final nowMk = MonthlyTrackerEngine.monthKey(nowUtc.year, nowUtc.month);
      final isCurrentMonth = mk == nowMk;
      final isFutureMonth = mk.compareTo(nowMk) > 0;

      final monthStart = DateTime.utc(year, month, 1);
      final monthEnd = DateTime.utc(year, month + 1, 0, 23, 59, 59);
      final prevStart = DateTime.utc(year, month - 1, 1);
      final prevEnd = DateTime.utc(year, month, 0, 23, 59, 59);
      final midMonth = DateTime.utc(year, month, 15, 12);

      // 1. Recurring rules, loans & transactions covering previous + selected month
      final rulesRes = await _recurringRepo.listRules(profile.id);
      final rules = rulesRes.valueOrNull ?? const <RecurringRuleEntity>[];
      final loansRes = await _loanRepo.listLoans(profile.id);
      final loans = loansRes.valueOrNull ?? const [];
      final loanAccountIds = loans.map((l) => l.loanAccountId).toSet();

      final txRes = await _txRepo.queryTransactions(
        profile.id,
        filter: TransactionFilter(
          status: TransactionStatus.posted,
          fromUtc: prevStart.toIso8601String(),
          toUtc: monthEnd.toIso8601String(),
        ),
        limit: 5000,
      );
      final txs = txRes.valueOrNull?.items ?? const <TransactionEntity>[];

      final expectedSalaryRef = 'salary:${profile.id.value}:$mk';
      var salaryCreditedThisMonth = false;
      var incomeMinor = 0;
      var refundsMinor = 0;
      var prevIncomeMinor = 0;
      var prevSpendMinor = 0;
      var prevRefundsMinor = 0;
      final prevSpendByCat = <String, int>{};
      final expenses = <MonthSpendEntry>[];
      final incomeTxs = <TransactionEntity>[];

      for (final tx in txs) {
        if (tx.isReversed || tx.status != TransactionStatus.posted) continue;
        final dt = DateTime.tryParse(tx.transactionDateUtc)?.toUtc();
        if (dt == null) continue;

        final inSelected = !dt.isBefore(monthStart) && !dt.isAfter(monthEnd);
        final inPrev = !dt.isBefore(prevStart) && !dt.isAfter(prevEnd);
        if (!inSelected && !inPrev) continue;

        if (tx.type == TransactionType.income) {
          if (inSelected) {
            incomeMinor += tx.baseAmount.amountMinor;
            incomeTxs.add(tx);
            if (tx.externalRef == expectedSalaryRef ||
                (tx.description ?? '').startsWith('Monthly Salary (')) {
              salaryCreditedThisMonth = true;
            }
          } else {
            prevIncomeMinor += tx.baseAmount.amountMinor;
          }
          continue;
        }
        if (tx.type == TransactionType.refund) {
          if (inSelected) {
            refundsMinor += tx.baseAmount.amountMinor;
          } else {
            prevRefundsMinor += tx.baseAmount.amountMinor;
          }
          continue;
        }

        // Paid loan EMIs post as adjustment(source=bank -> dest=loanAccountId).
        // Count the full cash outflow under essential 'Loan EMIs' so Monthly
        // Tracker never shows phantom free-to-spend headroom right after paying an EMI.
        final isPaidLoanEmi =
            tx.type == TransactionType.adjustment &&
            tx.sourceAccountId != null &&
            tx.destinationAccountId != null &&
            loanAccountIds.contains(tx.destinationAccountId);
        if (isPaidLoanEmi) {
          if (inSelected) {
            expenses.add(
              MonthSpendEntry(
                dateUtc: tx.transactionDateUtc,
                amountMinor: tx.baseAmount.amountMinor,
                categoryName: 'Loan EMIs',
                isEssential: true,
              ),
            );
          } else {
            prevSpendMinor += tx.baseAmount.amountMinor;
            prevSpendByCat['Loan EMIs'] =
                (prevSpendByCat['Loan EMIs'] ?? 0) + tx.baseAmount.amountMinor;
          }
          continue;
        }

        if (tx.type != TransactionType.expense) continue;

        if (tx.splits.isNotEmpty) {
          for (final sp in tx.splits) {
            if (inSelected) {
              expenses.add(
                MonthSpendEntry(
                  dateUtc: tx.transactionDateUtc,
                  amountMinor: sp.baseAmountMinor,
                  categoryName: sp.categoryName,
                  isEssential: LifeStagePlannerEngine.isEssentialCategory(
                    sp.categoryName,
                  ),
                ),
              );
            } else {
              prevSpendMinor += sp.baseAmountMinor;
              prevSpendByCat[sp.categoryName] =
                  (prevSpendByCat[sp.categoryName] ?? 0) + sp.baseAmountMinor;
            }
          }
        } else {
          final catName = (tx.categoryName ?? '').trim().isNotEmpty
              ? tx.categoryName!.trim()
              : 'Uncategorized';
          if (inSelected) {
            expenses.add(
              MonthSpendEntry(
                dateUtc: tx.transactionDateUtc,
                amountMinor: tx.baseAmount.amountMinor,
                categoryName: catName,
                isEssential: LifeStagePlannerEngine.isEssentialCategory(
                  catName,
                ),
              ),
            );
          } else {
            prevSpendMinor += tx.baseAmount.amountMinor;
            prevSpendByCat[catName] =
                (prevSpendByCat[catName] ?? 0) + tx.baseAmount.amountMinor;
          }
        }
      }
      prevSpendMinor = math.max<int>(0, prevSpendMinor - prevRefundsMinor);

      // 2. Upcoming recurring bills & loan EMIs within [max(today, monthStart), monthEnd]
      final todayStart = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
      final windowStart = isCurrentMonth && todayStart.isAfter(monthStart)
          ? todayStart
          : monthStart;

      final upcoming = <UpcomingCommitment>[];
      var recurringIncomeMonth = 0;

      for (final r in rules) {
        if (r.status != 'active') continue;
        final dueDt = DateTime.tryParse(r.nextDueAtUtc)?.toUtc();
        if (dueDt == null) continue;

        if (r.transactionType == TransactionType.income) {
          final monthlyEq = switch (r.cadence) {
            RecurringCadence.daily => r.amount.amountMinor * 30,
            RecurringCadence.weekly => (r.amount.amountMinor * 433) ~/ 100,
            RecurringCadence.monthly => r.amount.amountMinor,
            RecurringCadence.yearly => r.amount.amountMinor ~/ 12,
          };
          recurringIncomeMonth += monthlyEq;
          continue;
        }
        if (r.transactionType != TransactionType.expense) continue;

        final inWindow =
            !dueDt.isBefore(windowStart) && !dueDt.isAfter(monthEnd);
        if (inWindow) {
          upcoming.add(
            UpcomingCommitment(
              label: r.name,
              dueDateUtc: r.nextDueAtUtc,
              amountMinor: r.amount.amountMinor,
              kind: 'bill',
            ),
          );
        } else if (isFutureMonth &&
            r.cadence == RecurringCadence.monthly &&
            !dueDt.isAfter(monthEnd)) {
          final day = math.min<int>(
            dueDt.day,
            MonthlyTrackerEngine.daysInMonth(year, month),
          );
          final projected = DateTime.utc(year, month, day, dueDt.hour);
          upcoming.add(
            UpcomingCommitment(
              label: r.name,
              dueDateUtc: projected.toIso8601String(),
              amountMinor: r.amount.amountMinor,
              kind: 'bill',
            ),
          );
        }
      }

      for (final loan in loans) {
        if (loan.status != 'active') continue;
        for (final inst in loan.installments) {
          if (inst.status == 'paid' || inst.status == 'skipped') continue;
          final dueDt = DateTime.tryParse(inst.dueDateUtc)?.toUtc();
          if (dueDt == null) continue;
          if (!dueDt.isBefore(windowStart) && !dueDt.isAfter(monthEnd)) {
            upcoming.add(
              UpcomingCommitment(
                label: '${loan.name} #${inst.installmentNumber}',
                dueDateUtc: inst.dueDateUtc,
                amountMinor: inst.totalDueMinor,
                kind: 'emi',
              ),
            );
          }
        }
      }
      upcoming.sort((a, b) => a.dueDateUtc.compareTo(b.dueDateUtc));

      // 3. Planning basics, budgets, categories, accounts, goals & bucket items
      final basics = await _lifeService.readPlanningBasics(profile);
      final expectedIncome = math.max<int>(
        basics.plannedIncomeMinor,
        recurringIncomeMonth,
      );

      final budgetsRes = await _budgetRepo.listBudgetsWithProgress(
        profile.id,
        referenceUtc: midMonth,
      );
      final budgets = budgetsRes.valueOrNull ?? const <BudgetEntity>[];
      final monthlyBudgets =
          budgets
              .where(
                (b) => b.isActive && b.periodType == BudgetPeriodType.monthly,
              )
              .toList()
            ..sort(
              (a, b) => b.overallLimit.amountMinor.compareTo(
                a.overallLimit.amountMinor,
              ),
            );
      final masterBudget = monthlyBudgets.isNotEmpty
          ? monthlyBudgets.first
          : null;

      final goalsRes = await _goalRepo.listGoals(profile.id);
      final allGoals = goalsRes.valueOrNull ?? const <SavingsGoalEntity>[];
      final activeGoals = allGoals.where((g) => g.status == 'active').toList();
      final goalById = {for (final g in allGoals) g.id: g};

      final bucketRes = await _bucketRepo.listItems(profile.id);
      final allBucketItems =
          bucketRes.valueOrNull ?? const <BucketListItemEntity>[];

      final plannedItems = [
        for (final b in allBucketItems)
          if (b.status == BucketItemStatus.planned)
            if (b.linkedGoalId != null && goalById.containsKey(b.linkedGoalId))
              b.copyWith(
                savedAmountMinor: math.max(
                  b.savedAmountMinor,
                  goalById[b.linkedGoalId]!.contributedAmount.amountMinor,
                ),
              )
            else
              b,
      ];
      final thisMonthItems = plannedItems
          .where((b) => b.targetYearMonth.compareTo(mk) <= 0)
          .toList();
      final upcomingItems = plannedItems
          .where((b) => b.targetYearMonth.compareTo(mk) > 0)
          .toList();
      final purchasedThisMonthItems = allBucketItems.where((b) {
        if (b.status != BucketItemStatus.purchased) return false;
        if (b.targetYearMonth == mk) return true;
        final up = DateTime.tryParse(b.updatedAtUtc)?.toUtc();
        return up != null && up.year == year && up.month == month;
      }).toList();

      final bucketInputs = [
        for (final item in plannedItems)
          BucketPlanInput(
            id: item.id,
            name: item.name,
            priority: item.priority.wireValue,
            estimatedMinor: item.estimatedAmountMinor,
            savedMinor: item.savedAmountMinor,
            targetYearMonth: item.targetYearMonth,
            dueDateUtc: item.dueDateUtc,
            reminderAtUtc: item.reminderAtUtc,
            createdAtUtc: item.createdAtUtc,
          ),
      ];

      final snapshot = MonthlyTrackerEngine.buildSnapshot(
        MonthlyTrackerInput(
          currencyCode: ccy,
          year: year,
          month: month,
          nowUtc: nowUtc,
          incomeMinor: incomeMinor,
          expenses: expenses,
          refundsMinor: refundsMinor,
          previousIncomeMinor: prevIncomeMinor,
          previousSpendMinor: prevSpendMinor,
          previousSpendByCategory: prevSpendByCat,
          expectedIncomeMinor: expectedIncome,
          upcoming: upcoming,
          savingsTargetPct: basics.targets.savingsPct,
          wantsCapPct: basics.targets.wantsPct,
          budgetLimitMinor: masterBudget?.overallLimit.amountMinor,
          budgetSpentMinor: masterBudget?.totalSpent.amountMinor,
          bucketItems: bucketInputs,
        ),
      );

      // Sort thisMonthItems by plan priority rank then creation order
      final rankOrder = <String, int>{
        for (var i = 0; i < snapshot.bucketPlan.items.length; i++)
          snapshot.bucketPlan.items[i].itemId: i,
      };
      thisMonthItems.sort(
        (a, b) => (rankOrder[a.id] ?? 999).compareTo(rankOrder[b.id] ?? 999),
      );
      upcomingItems.sort(
        (a, b) => (rankOrder[a.id] ?? 999).compareTo(rankOrder[b.id] ?? 999),
      );

      // Trigger due reminders on current month view cleanly (deduped in inbox)
      if (isCurrentMonth) {
        await evaluateDueReminders(profile, preloadedItems: plannedItems);
      }

      final accRes = await _accountRepo.listAccounts(profile.id);
      final liquidAccounts =
          (accRes.valueOrNull ?? const <FinancialAccountEntity>[])
              .where(
                (a) =>
                    !a.isLiability &&
                    (a.accountType == FinancialAccountType.bank ||
                        a.accountType == FinancialAccountType.cash ||
                        a.accountType == FinancialAccountType.wallet),
              )
              .toList();

      final savedSalaryAccId = await _lifeService.getSalaryAccountId(
        profile.id,
      );
      final preferredSalaryAccountId =
          savedSalaryAccId != null &&
              liquidAccounts.any((a) => a.id == savedSalaryAccId)
          ? savedSalaryAccId
          : liquidAccounts.firstOrNull?.id;

      final catRes = await _catRepo.listCategories(
        profile.id,
        type: CategoryType.expense,
      );
      final expenseCats = catRes.valueOrNull ?? const <CategoryEntity>[];

      final windfalls = await _readWindfalls(profile.id, mk);

      return Success(
        MonthlyTrackerViewData(
          profileId: profile.id,
          snapshot: snapshot,
          thisMonthItems: thisMonthItems,
          upcomingItems: upcomingItems,
          purchasedThisMonthItems: purchasedThisMonthItems,
          planById: snapshot.bucketPlan.byItemId,
          upcomingCommitments: upcoming,
          incomeTransactions: incomeTxs,
          windfalls: windfalls,
          activeGoals: activeGoals,
          liquidAccounts: liquidAccounts,
          expenseCategories: expenseCats,
          masterBudget: masterBudget,
          preferredSalaryAccountId: preferredSalaryAccountId,
          salaryCreditedThisMonth: salaryCreditedThisMonth,
        ),
      );
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  /// Creates or updates a Bucket List item and syncs its one-shot reminder notification.
  Future<Result<BucketListItemEntity>> saveItem({
    required FinancialProfile profile,
    BucketListItemEntity? existing,
    required String name,
    required int estimatedAmountMinor,
    required BucketPriority priority,
    required String targetYearMonth,
    int? savedAmountMinor,
    String? dueDateUtc,
    String? reminderAtUtc,
    String? categoryId,
    String? note,
  }) async {
    final Result<BucketListItemEntity> res;
    if (existing == null) {
      res = await _bucketRepo.createItem(
        profileId: profile.id,
        name: name,
        estimatedAmountMinor: estimatedAmountMinor,
        currencyCode: profile.baseCurrencyCode,
        priority: priority,
        targetYearMonth: targetYearMonth,
        savedAmountMinor: savedAmountMinor ?? 0,
        dueDateUtc: dueDateUtc,
        reminderAtUtc: reminderAtUtc,
        categoryId: categoryId,
        note: note,
      );
    } else {
      res = await _bucketRepo.updateItem(
        existing.copyWith(
          name: name,
          estimatedAmountMinor: estimatedAmountMinor,
          savedAmountMinor: savedAmountMinor ?? existing.savedAmountMinor,
          priority: priority,
          targetYearMonth: targetYearMonth,
          dueDateUtc: dueDateUtc,
          clearDueDate: dueDateUtc == null,
          reminderAtUtc: reminderAtUtc,
          clearReminder: reminderAtUtc == null,
          categoryId: categoryId,
          clearCategory: categoryId == null,
          note: note,
          clearNote: note == null || note.trim().isEmpty,
        ),
      );
    }

    final saved = res.valueOrNull;
    if (saved != null) {
      await _syncItemReminder(saved);
    }
    return res;
  }

  Future<void> _syncItemReminder(BucketListItemEntity item) async {
    final notifId = reminderIdForItem(item.id);
    await _dispatcher.cancelScheduledReminder(notifId);
    if (item.status != BucketItemStatus.planned || item.reminderAtUtc == null) {
      return;
    }
    final remDt = DateTime.tryParse(item.reminderAtUtc!)?.toUtc();
    if (remDt == null || !remDt.isAfter(_clock.nowUtc())) return;

    final hideBalances = await _settings.getBool('ui.hide_balances');
    final amtStr = Money(
      amountMinor: item.estimatedAmountMinor,
      currencyCode: item.currencyCode,
    ).format();

    await _dispatcher.scheduleOneShotReminder(
      id: notifId,
      title: 'Bucket List: ${item.name}',
      body: hideBalances
          ? 'Planned purchase reminder (${item.priority.label}) — tap to review.'
          : 'Planned purchase ($amtStr • ${item.priority.label}) — tap to review.',
      atUtc: remDt,
      payloadRoute: '/monthly?tab=1',
    );
  }

  Future<Result<void>> deleteItem(FinancialProfile profile, String id) async {
    await _dispatcher.cancelScheduledReminder(reminderIdForItem(id));
    return _bucketRepo.deleteItem(profile.id, id);
  }

  Future<Result<BucketListItemEntity>> postponeItem(
    FinancialProfile profile,
    BucketListItemEntity item,
  ) async {
    final nextMonth = MonthlyTrackerEngine.shiftMonth(item.targetYearMonth, 1);
    final updated = item.copyWith(
      targetYearMonth: nextMonth,
      postponeCount: item.postponeCount + 1,
    );
    final res = await _bucketRepo.updateItem(updated);
    if (res.valueOrNull != null) {
      await _syncItemReminder(res.valueOrNull!);
    }
    return res;
  }

  Future<Result<BucketListItemEntity>> addFunds(
    FinancialProfile profile,
    BucketListItemEntity item,
    int amountMinor,
  ) => _bucketRepo.addSavedAmount(profile.id, item.id, amountMinor);

  /// Records a genuine double-entry expense for the purchased item, updates status
  /// to `purchased`, cancels its reminder, and triggers budget alerts.
  Future<Result<BucketListItemEntity>> markPurchased({
    required FinancialProfile profile,
    required BucketListItemEntity item,
    required int actualAmountMinor,
    required String accountId,
    required String categoryId,
    required DateTime dateUtc,
  }) async {
    if (actualAmountMinor <= 0) {
      return const FailureResult(
        ValidationFailure(message: 'Purchase amount must be positive.'),
      );
    }

    final txRes = await _txRepo.createTransaction(
      profile.id,
      CreateTransactionCommand(
        type: TransactionType.expense,
        amountMinor: actualAmountMinor,
        currencyCode: profile.baseCurrencyCode,
        transactionDateUtc: dateUtc.toUtc().toIso8601String(),
        sourceAccountId: accountId,
        categoryId: categoryId,
        description: 'Bucket: ${item.name}',
      ),
    );
    if (txRes.isFailure) return FailureResult(txRes.failureOrNull!);
    final tx = txRes.valueOrNull!;

    final updatedRes = await _bucketRepo.updateItem(
      item.copyWith(
        status: BucketItemStatus.purchased,
        actualAmountMinor: actualAmountMinor,
        purchasedTransactionId: tx.id,
        categoryId: categoryId,
      ),
    );

    await _dispatcher.cancelScheduledReminder(reminderIdForItem(item.id));
    await _alerts.evaluateAfterTransaction(profile.id);
    return updatedRes;
  }

  Future<BudgetEntity?> _resolveMonthlyMasterBudget(
    FinancialProfile profile,
  ) async {
    final caRes = await _caBudgetService.loadWorkspace(profile: profile);
    final zbb = caRes.valueOrNull?.masterZbbBudget;
    if (zbb != null) return zbb;

    final res = await _budgetRepo.listBudgetsWithProgress(
      profile.id,
      referenceUtc: _clock.nowUtc(),
    );
    final activeMonthly =
        (res.valueOrNull ?? const <BudgetEntity>[])
            .where(
              (b) => b.isActive && b.periodType == BudgetPeriodType.monthly,
            )
            .toList()
          ..sort(
            (a, b) => b.overallLimit.amountMinor.compareTo(
              a.overallLimit.amountMinor,
            ),
          );
    return activeMonthly.isNotEmpty ? activeMonthly.first : null;
  }

  /// Reserves this item's remaining amount into the Master Monthly Budget for its category.
  Future<Result<BucketListItemEntity>> reserveInBudget({
    required FinancialProfile profile,
    required BucketListItemEntity item,
  }) async {
    final catId = item.categoryId;
    if (catId == null || catId.isEmpty) {
      return const FailureResult(
        ValidationFailure(
          message: 'Assign an expense category to this item before reserving.',
        ),
      );
    }

    final delta = item.remainingMinor - item.reservedInBudgetMinor;
    if (delta <= 0) {
      return Success(item);
    }

    final existingMaster = await _resolveMonthlyMasterBudget(profile);

    if (existingMaster != null) {
      final catMap = <String, int>{
        for (final alloc in existingMaster.allocations)
          alloc.categoryId: alloc.limitMinor,
      };
      catMap[catId] = (catMap[catId] ?? 0) + delta;
      final bRes = await _budgetRepo.updateBudget(
        profileId: profile.id,
        budgetId: existingMaster.id,
        name: existingMaster.name,
        periodType: existingMaster.periodType,
        overallLimitMinor: existingMaster.overallLimit.amountMinor + delta,
        categoryLimitsMinor: catMap,
        rolloverEnabled: existingMaster.rolloverEnabled,
        startDateUtc: existingMaster.startDateUtc,
        endDateUtc: existingMaster.endDateUtc,
      );
      if (bRes.isFailure) return FailureResult(bRes.failureOrNull!);
    } else {
      final bRes = await _budgetRepo.createBudget(
        profileId: profile.id,
        name: 'Monthly Plan',
        periodType: BudgetPeriodType.monthly,
        overallLimitMinor: delta,
        currencyCode: profile.baseCurrencyCode,
        categoryLimitsMinor: {catId: delta},
      );
      if (bRes.isFailure) return FailureResult(bRes.failureOrNull!);
    }

    return _bucketRepo.updateItem(
      item.copyWith(reservedInBudgetMinor: item.reservedInBudgetMinor + delta),
    );
  }

  /// Converts a Dream/Long-Term Bucket item into a tracked Savings Goal.
  Future<Result<BucketListItemEntity>> convertToGoal({
    required FinancialProfile profile,
    required BucketListItemEntity item,
    BucketItemPlan? plan,
  }) async {
    if (item.linkedGoalId != null && item.linkedGoalId!.isNotEmpty) {
      return Success(item);
    }
    final months = plan != null && plan.monthsToSave > 0
        ? plan.monthsToSave
        : 6;
    final targetDate =
        item.dueDateUtc ??
        _clock.nowUtc().add(Duration(days: months * 30)).toIso8601String();

    final goalRes = await _goalRepo.createGoal(
      profileId: profile.id,
      name: item.name,
      targetAmountMinor: item.estimatedAmountMinor,
      currencyCode: profile.baseCurrencyCode,
      fundingMode: GoalFundingMode.allocated,
      targetDateUtc: targetDate,
    );
    if (goalRes.isFailure) return FailureResult(goalRes.failureOrNull!);
    final goal = goalRes.valueOrNull!;

    if (item.savedAmountMinor > 0) {
      await _goalRepo.recordContribution(
        profileId: profile.id,
        goalId: goal.id,
        amountMinor: item.savedAmountMinor,
        note: 'Transferred from Monthly Bucket List',
      );
      await _alerts.evaluateAfterGoalContribution(profile.id);
    }

    return _bucketRepo.updateItem(item.copyWith(linkedGoalId: goal.id));
  }

  /// Logs Extra / Windfall Income and executes its 3-way split across
  /// Savings Goals, Planned Bucket Items (in priority order), and This Month Spend.
  Future<Result<WindfallRecord>> recordExtraIncome({
    required FinancialProfile profile,
    required int amountMinor,
    required String sourceLabel,
    required String accountId,
    required DateTime dateUtc,
    required WindfallSplit split,
    String? goalId,
  }) async {
    if (amountMinor <= 0 || split.totalMinor != amountMinor) {
      return const FailureResult(
        ValidationFailure(
          message: 'Extra income amount and 3-way split must match exactly.',
        ),
      );
    }

    final incCatsRes = await _catRepo.listCategories(
      profile.id,
      type: CategoryType.income,
    );
    final incCats = incCatsRes.valueOrNull ?? const <CategoryEntity>[];
    String? pickedCatId;
    for (final c in incCats) {
      final l = c.name.toLowerCase();
      if (l.contains('bonus') ||
          l.contains('other') ||
          l.contains('freelance') ||
          l.contains('gift')) {
        pickedCatId = c.id;
        break;
      }
    }
    pickedCatId ??= incCats.isNotEmpty ? incCats.first.id : null;

    final txRes = await _txRepo.createTransaction(
      profile.id,
      CreateTransactionCommand(
        type: TransactionType.income,
        amountMinor: amountMinor,
        currencyCode: profile.baseCurrencyCode,
        transactionDateUtc: dateUtc.toUtc().toIso8601String(),
        destinationAccountId: accountId,
        categoryId: pickedCatId,
        description: 'Extra income: ${sourceLabel.trim()}',
      ),
    );
    if (txRes.isFailure) return FailureResult(txRes.failureOrNull!);
    final tx = txRes.valueOrNull!;

    // 1. Fund planned bucket items for this month in plan order
    final mk = MonthlyTrackerEngine.monthKey(dateUtc.year, dateUtc.month);
    var actualBucketFunded = 0;
    var bucketBudgetLeft = split.toBucketMinor;
    if (bucketBudgetLeft > 0) {
      final viewRes = await loadMonth(
        profile: profile,
        year: dateUtc.year,
        month: dateUtc.month,
      );
      final ordered =
          viewRes.valueOrNull?.thisMonthItems ?? const <BucketListItemEntity>[];
      for (final item in ordered) {
        if (bucketBudgetLeft <= 0) break;
        final need = item.remainingMinor;
        if (need <= 0) continue;
        final apply = math.min<int>(need, bucketBudgetLeft);
        final addRes = await _bucketRepo.addSavedAmount(
          profile.id,
          item.id,
          apply,
        );
        if (addRes.isSuccess) {
          bucketBudgetLeft -= apply;
          actualBucketFunded += apply;
        }
      }
    }

    // Any leftover from toBucket rolls cleanly into Future Savings so nothing disappears.
    final effectiveSavings = split.toSavingsMinor + bucketBudgetLeft;
    String? usedGoalId = goalId;

    if (effectiveSavings > 0) {
      if (usedGoalId == null || usedGoalId.isEmpty) {
        final existingGoals =
            (await _goalRepo.listGoals(profile.id)).valueOrNull ?? const [];
        SavingsGoalEntity? futureFund;
        for (final g in existingGoals) {
          if (g.status == 'active' &&
              g.name.toLowerCase().contains('future fund')) {
            futureFund = g;
            break;
          }
        }
        if (futureFund == null) {
          final created = await _goalRepo.createGoal(
            profileId: profile.id,
            name: 'Future Fund',
            targetAmountMinor: math.max<int>(10000, effectiveSavings * 4),
            currencyCode: profile.baseCurrencyCode,
            fundingMode: GoalFundingMode.allocated,
          );
          futureFund = created.valueOrNull;
        }
        usedGoalId = futureFund?.id;
      }

      if (usedGoalId != null) {
        final contribRes = await _goalRepo.recordContribution(
          profileId: profile.id,
          goalId: usedGoalId,
          amountMinor: effectiveSavings,
          sourceAccountId: accountId,
          note: 'Extra income: ${sourceLabel.trim()}',
          allowDirectDeposit: true,
        );
        if (contribRes.isFailure) {
          return FailureResult(contribRes.failureOrNull!);
        }
        await _alerts.evaluateAfterGoalContribution(profile.id);
      }
    }

    // 2. Allocate `toSpendMinor` to Master Budget ceiling if one exists
    if (split.toSpendMinor > 0) {
      final master = await _resolveMonthlyMasterBudget(profile);
      if (master != null) {
        final catMap = <String, int>{
          for (final a in master.allocations) a.categoryId: a.limitMinor,
        };
        await _budgetRepo.updateBudget(
          profileId: profile.id,
          budgetId: master.id,
          name: master.name,
          periodType: master.periodType,
          overallLimitMinor:
              master.overallLimit.amountMinor + split.toSpendMinor,
          categoryLimitsMinor: catMap,
          rolloverEnabled: master.rolloverEnabled,
          startDateUtc: master.startDateUtc,
          endDateUtc: master.endDateUtc,
        );
      }
    }

    final record = WindfallRecord(
      txId: tx.id,
      amountMinor: amountMinor,
      sourceLabel: sourceLabel.trim().isNotEmpty
          ? sourceLabel.trim()
          : 'Extra Income',
      toSavingsMinor: effectiveSavings,
      toBucketMinor: actualBucketFunded,
      toSpendMinor: split.toSpendMinor,
      goalId: usedGoalId,
      createdAtUtc: _clock.nowIsoUtc(),
    );

    final list = await _readWindfalls(profile.id, mk);
    final updatedList = [record, ...list];
    await _settings.setString(
      _windfallKey(profile.id, mk),
      jsonEncode(updatedList.map((w) => w.toJsonMap()).toList()),
    );

    return Success(record);
  }

  /// Evaluates scheduled Bucket List reminders and due-soon items into the inbox (deduped).
  Future<List<EvaluatedAlert>> evaluateDueReminders(
    FinancialProfile profile, {
    List<BucketListItemEntity>? preloadedItems,
  }) async {
    final items =
        preloadedItems ??
        (await _bucketRepo.listItems(profile.id)).valueOrNull ??
        const <BucketListItemEntity>[];
    final planned = items.where((b) => b.status == BucketItemStatus.planned);
    final inputs = [
      for (final b in planned)
        BucketPlanInput(
          id: b.id,
          name: b.name,
          priority: b.priority.wireValue,
          estimatedMinor: b.estimatedAmountMinor,
          savedMinor: b.savedAmountMinor,
          targetYearMonth: b.targetYearMonth,
          dueDateUtc: b.dueDateUtc,
          reminderAtUtc: b.reminderAtUtc,
          createdAtUtc: b.createdAtUtc,
        ),
    ];
    final candidates = AlertEvaluationEngine.evaluateBucketReminders(
      items: inputs,
      nowUtc: _clock.nowUtc(),
      currencyCode: profile.baseCurrencyCode,
    );
    if (candidates.isEmpty) return const [];
    return _alerts.dispatchExternalAlerts(
      profile.id,
      candidates,
      dispatchOs: false,
    );
  }

  /// Credits planned monthly salary into a real bank/cash account for `(year, month)`
  /// and refreshes post-transaction financial alerts.
  Future<Result<CreditSalaryResult>> creditMonthlySalary({
    required FinancialProfile profile,
    required String accountId,
    required int amountMinor,
    required int year,
    required int month,
    bool createRecurringRule = false,
    bool forceDuplicate = false,
  }) async {
    final res = await _lifeService.creditMonthlySalaryToAccount(
      profile: profile,
      accountId: accountId,
      amountMinor: amountMinor,
      year: year,
      month: month,
      createRecurringRule: createRecurringRule,
      forceDuplicate: forceDuplicate,
    );
    if (res.isSuccess) {
      await _alerts.evaluateAfterTransaction(profile.id);
    }
    return res;
  }

  /// Lightweight current-month pulse used by the Dashboard entry card.
  Future<Result<MonthlyPulseSummary>> loadPulse(
    FinancialProfile profile,
  ) async {
    final nowUtc = _clock.nowUtc();
    final res = await loadMonth(
      profile: profile,
      year: nowUtc.year,
      month: nowUtc.month,
    );
    if (res.isFailure) return FailureResult(res.failureOrNull!);
    final data = res.valueOrNull!;
    final snap = data.snapshot;
    final dueSoonCount = data.planById.values
        .where((p) => p.isOverdue || p.isDueSoon)
        .length;

    return Success(
      MonthlyPulseSummary(
        currencyCode: snap.currencyCode,
        year: snap.year,
        month: snap.month,
        incomeMinor: snap.incomeMinor,
        spentMinor: snap.spentMinor,
        savedMinor: snap.savedMinor,
        freeToSpendMinor: snap.freeToSpendMinor,
        savingsRatePct: snap.savingsRatePct,
        healthLabel: snap.healthLabel,
        plannedBucketCount: data.thisMonthItems.length,
        dueSoonBucketCount: dueSoonCount,
        safeDailySpendMinor: snap.safeDailySpendMinor,
      ),
    );
  }

  Future<List<WindfallRecord>> _readWindfalls(
    ProfileId profileId,
    String ym,
  ) async {
    final raw = await _settings.getString(_windfallKey(profileId, ym));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is List) {
        return list
            .whereType<Map<String, dynamic>>()
            .map(WindfallRecord.fromJsonMap)
            .toList();
      }
    } catch (_) {
      // Corrupt JSON falls back cleanly to empty list.
    }
    return const [];
  }
}
