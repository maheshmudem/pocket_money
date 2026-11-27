import 'dart:math' as math;

import '../../../core/errors/failures.dart';
import '../../../core/financial_engine/ca_budget_planner_engine.dart';
import '../../../core/utilities/clock.dart';
import '../../../core/utilities/id_generator.dart';
import '../../accounts/domain/entities/financial_account_entity.dart';
import '../../accounts/domain/repositories/account_repository.dart';
import '../../categories/domain/entities/category_entity.dart';
import '../../categories/domain/repositories/category_repository.dart';
import '../../loans/data/repositories/drift_loan_repository.dart';
import '../../profiles/domain/entities/profile_entity.dart';
import '../../recurring/data/repositories/drift_recurring_repository.dart';
import '../../recurring/domain/entities/recurring_rule_entity.dart';
import '../../savings_goals/domain/repositories/savings_goal_repository.dart';
import '../../settings/data/settings_repository.dart';
import '../../transactions/domain/entities/transaction_entity.dart';
import '../../transactions/domain/repositories/transaction_repository.dart';
import '../domain/entities/budget_entity.dart';
import '../domain/repositories/budget_repository.dart';

/// Complete profile-scoped snapshot driving the 3-tab Chartered Accountant
/// Budget Planner (`Overview`, `Zero-Based`, and `CA Variance`).
final class CaBudgetWorkspaceSnapshot {
  const CaBudgetWorkspaceSnapshot({
    required this.profileId,
    required this.currencyCode,
    required this.nowUtc,
    required this.budgets,
    required this.expenseCategories,
    required this.zbbSeeds,
    required this.safeToSpend,
    required this.sinkingFunds,
    required this.varianceStatement,
    required this.fyStartMonth,
    required this.taxReserveBps,
    required this.suggestedIncomePoolMinor,
    required this.actualMonthlyIncomeMinor,
    this.masterZbbBudget,
  });

  final ProfileId profileId;
  final String currencyCode;
  final DateTime nowUtc;
  final List<BudgetEntity> budgets;
  final List<CategoryEntity> expenseCategories;
  final List<ZbbCategorySeed> zbbSeeds;
  final SafeToSpendSnapshot safeToSpend;
  final List<SinkingFundAccrual> sinkingFunds;
  final CaVarianceStatement varianceStatement;
  final int fyStartMonth;
  final int taxReserveBps;
  final int suggestedIncomePoolMinor;
  final int actualMonthlyIncomeMinor;
  final BudgetEntity? masterZbbBudget;
}

/// Profile-isolated service assembling live ledger cash, upcoming recurring bills,
/// loan EMIs, sinking fund goals, and multi-period actuals for [CaBudgetPlannerEngine].
final class CaBudgetPlannerService {
  CaBudgetPlannerService({
    required BudgetRepository budgetRepository,
    required AccountRepository accountRepository,
    required CategoryRepository categoryRepository,
    required TransactionRepository transactionRepository,
    required DriftRecurringRepository recurringRepository,
    required DriftLoanRepository loanRepository,
    required SavingsGoalRepository savingsGoalRepository,
    required SettingsRepository settingsRepository,
    required UtcClock clock,
  }) : _budgetRepo = budgetRepository,
       _accountRepo = accountRepository,
       _categoryRepo = categoryRepository,
       _txRepo = transactionRepository,
       _recurringRepo = recurringRepository,
       _loanRepo = loanRepository,
       _goalRepo = savingsGoalRepository,
       _settings = settingsRepository,
       _clock = clock;

  final BudgetRepository _budgetRepo;
  final AccountRepository _accountRepo;
  final CategoryRepository _categoryRepo;
  final TransactionRepository _txRepo;
  final DriftRecurringRepository _recurringRepo;
  final DriftLoanRepository _loanRepo;
  final SavingsGoalRepository _goalRepo;
  final SettingsRepository _settings;
  final UtcClock _clock;

  static String _fyKey(ProfileId id) => 'ca_budget.${id.value}.fy_start_month';
  static String _taxKey(ProfileId id) =>
      'ca_budget.${id.value}.tax_reserve_bps';
  static String _incomeKey(ProfileId id) =>
      'ca_budget.${id.value}.planned_income_minor';

  Future<void> setFyStartMonth(ProfileId profileId, int startMonth) async {
    final normalized = startMonth == 4 ? 4 : 1;
    await _settings.setString(_fyKey(profileId), '$normalized');
  }

  Future<void> setTaxReserveBps(ProfileId profileId, int bps) async {
    final clamped = bps.clamp(0, 5000);
    await _settings.setString(_taxKey(profileId), '$clamped');
  }

  Future<void> setPlannedMonthlyIncome(
    ProfileId profileId,
    int incomeMinor,
  ) async {
    await _settings.setString(
      _incomeKey(profileId),
      '${math.max(0, incomeMinor)}',
    );
  }

  Future<Result<CaBudgetWorkspaceSnapshot>> loadWorkspace({
    required FinancialProfile profile,
    CaFiscalPeriodPreset periodPreset = CaFiscalPeriodPreset.currentMonth,
  }) async {
    try {
      final nowUtc = _clock.nowUtc();
      final ccy = profile.baseCurrencyCode;

      // 1. Read profile-scoped CA preferences with smart currency/type defaults.
      final savedFyRaw = await _settings.getString(_fyKey(profile.id));
      final fyStartMonth = savedFyRaw != null
          ? (int.tryParse(savedFyRaw) == 4 ? 4 : 1)
          : (ccy.toUpperCase() == 'INR' ? 4 : 1);

      final savedTaxRaw = await _settings.getString(_taxKey(profile.id));
      final defaultTaxBps = profile.profileType == ProfileType.business
          ? 1500
          : 0;
      final taxReserveBps = savedTaxRaw != null
          ? (int.tryParse(savedTaxRaw) ?? defaultTaxBps).clamp(0, 5000)
          : defaultTaxBps;

      final savedIncomeRaw = await _settings.getString(_incomeKey(profile.id));
      var savedPlannedIncome = int.tryParse(savedIncomeRaw ?? '') ?? 0;
      if (savedPlannedIncome <= 0) {
        final lifeIncomeRaw = await _settings.getString(
          'life_stage.${profile.id.value}.monthly_income_minor',
        );
        savedPlannedIncome = int.tryParse(lifeIncomeRaw ?? '') ?? 0;
      }

      // 2. Resolve Fiscal Window for CA Variance (BvA) Statement.
      final fiscalWindow = CaBudgetPlannerEngine.resolveFiscalWindow(
        nowUtc: nowUtc,
        preset: periodPreset,
        fyStartMonth: fyStartMonth,
      );

      // Pull earliest needed transaction date across fiscal window & trailing 3 months.
      final trailingFrom = DateTime.utc(nowUtc.year, nowUtc.month - 3, 1);
      final queryFrom = fiscalWindow.fromUtc.isBefore(trailingFrom)
          ? fiscalWindow.fromUtc
          : trailingFrom;

      // 3. Load all profile-scoped financial records.
      final budgetsRes = await _budgetRepo.listBudgetsWithProgress(profile.id);
      if (budgetsRes.isFailure) return FailureResult(budgetsRes.failureOrNull!);
      final budgets = budgetsRes.valueOrNull ?? const <BudgetEntity>[];

      final catsRes = await _categoryRepo.listCategories(
        profile.id,
        type: CategoryType.expense,
      );
      final expenseCats = catsRes.valueOrNull ?? const <CategoryEntity>[];

      final accountsRes = await _accountRepo.listAccounts(profile.id);
      final accounts =
          accountsRes.valueOrNull ?? const <FinancialAccountEntity>[];

      final txRes = await _txRepo.queryTransactions(
        profile.id,
        filter: TransactionFilter(
          status: TransactionStatus.posted,
          fromUtc: queryFrom.toIso8601String(),
        ),
        limit: 4000,
      );
      final txs = txRes.valueOrNull?.items ?? const <TransactionEntity>[];

      final rulesRes = await _recurringRepo.listRules(profile.id);
      final rules = rulesRes.valueOrNull ?? const <RecurringRuleEntity>[];

      final loansRes = await _loanRepo.listLoans(profile.id);
      final loans = loansRes.valueOrNull ?? const [];

      final goalsRes = await _goalRepo.listGoals(profile.id);
      final goals = goalsRes.valueOrNull ?? const [];

      // 4. Compute Liquid Cash (Bank + Cash + Wallet, non-liability).
      final liquidCashMinor = accounts
          .where(
            (a) =>
                !a.isLiability &&
                (a.accountType == FinancialAccountType.bank ||
                    a.accountType == FinancialAccountType.cash ||
                    a.accountType == FinancialAccountType.wallet),
          )
          .fold<int>(0, (s, a) => s + a.baseBalance.amountMinor);

      // 5. Compute Upcoming Recurring Bills & Loan EMIs due before month end.
      final monthEndUtc = DateTime.utc(
        nowUtc.year,
        nowUtc.month + 1,
        0,
        23,
        59,
        59,
      );
      final remainingDaysInMonth = math.max(
        1,
        monthEndUtc.day - nowUtc.day + 1,
      );

      var upcomingBillsMinor = 0;
      for (final r in rules) {
        if (r.status != 'active' ||
            r.transactionType != TransactionType.expense) {
          continue;
        }
        var due = DateTime.tryParse(r.nextDueAtUtc)?.toUtc();
        var guard = 0;
        while (due != null && !due.isAfter(monthEndUtc) && guard < 31) {
          upcomingBillsMinor += r.amount.amountMinor;
          due = DriftRecurringRepository.advanceDate(
            due,
            r.cadence,
            r.intervalCount,
          );
          guard++;
        }
      }

      var upcomingEmisMinor = 0;
      for (final loan in loans) {
        if (loan.status != 'active') continue;
        for (final inst in loan.installments) {
          if (inst.status == 'paid') continue;
          final due = DateTime.tryParse(inst.dueDateUtc)?.toUtc();
          if (due != null && !due.isAfter(monthEndUtc)) {
            upcomingEmisMinor += inst.totalDueMinor;
          }
        }
      }

      // 6. Compute Sinking Fund Monthly Accruals from active Savings Goals with target dates.
      final sinkingFunds = <SinkingFundAccrual>[];
      for (final g in goals) {
        if (g.status != 'active' || g.isCompleted) continue;
        final acc = CaBudgetPlannerEngine.computeSinkingFundAccrual(
          goalId: g.id,
          name: g.name,
          targetMinor: g.targetAmount.amountMinor,
          contributedMinor: g.contributedAmount.amountMinor,
          targetDateUtc: g.targetDateUtc,
          nowUtc: nowUtc,
        );
        if (acc != null) sinkingFunds.add(acc);
      }
      sinkingFunds.sort(
        (a, b) => a.monthsRemaining.compareTo(b.monthsRemaining),
      );
      final totalSinkingAccrualMinor = sinkingFunds.fold<int>(
        0,
        (s, f) => s + f.monthlyAccrualMinor,
      );

      // 7. Process Transactions for:
      //    (a) Selected Fiscal Window Actuals & Period Income (for BvA Statement)
      //    (b) Current Month Income & Trailing 3-Month Income/Spend (for ZBB & Tax Provision)
      final currMonthStart = DateTime.utc(nowUtc.year, nowUtc.month, 1);
      final prevMonthStart = DateTime.utc(nowUtc.year, nowUtc.month - 1, 1);
      final prevMonthEnd = DateTime.utc(
        prevMonthStart.year,
        prevMonthStart.month + 1,
        0,
        23,
        59,
        59,
      );

      var periodIncomeMinor = 0;
      var currentMonthIncomeMinor = 0;
      final trailingIncomeByYm = <String, int>{};

      final windowExpByCat = <String, int>{};
      final windowRefundByCat = <String, int>{};
      final windowCatNameById = <String, String>{
        for (final c in expenseCats) c.id: c.name,
      };

      final prevMonthExpByCat = <String, int>{};
      final trailingExpByCat = <String, Map<String, int>>{};

      for (final tx in txs) {
        if (tx.isReversed || tx.status != TransactionStatus.posted) continue;
        final dt = DateTime.tryParse(tx.transactionDateUtc)?.toUtc();
        if (dt == null) continue;

        final inWindow =
            !dt.isBefore(fiscalWindow.fromUtc) &&
            !dt.isAfter(fiscalWindow.toUtc);
        final inCurrMonth =
            !dt.isBefore(currMonthStart) && !dt.isAfter(monthEndUtc);
        final inPrevMonth =
            !dt.isBefore(prevMonthStart) && !dt.isAfter(prevMonthEnd);
        final ym = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';

        if (tx.type == TransactionType.income) {
          final amt = tx.baseAmount.amountMinor;
          if (inWindow) periodIncomeMinor += amt;
          if (inCurrMonth) currentMonthIncomeMinor += amt;
          if (!dt.isBefore(trailingFrom) && dt.isBefore(currMonthStart)) {
            trailingIncomeByYm[ym] = (trailingIncomeByYm[ym] ?? 0) + amt;
          }
          continue;
        }

        if (tx.type == TransactionType.refund) {
          final catId = tx.categoryId ?? 'uncategorized';
          if (tx.categoryName != null) {
            windowCatNameById[catId] = tx.categoryName!;
          }
          if (inWindow) {
            windowRefundByCat[catId] =
                (windowRefundByCat[catId] ?? 0) + tx.baseAmount.amountMinor;
          }
          continue;
        }

        if (tx.type != TransactionType.expense) continue;

        void recordExpense(String catId, String catName, int minor) {
          windowCatNameById[catId] = catName;
          if (inWindow) {
            windowExpByCat[catId] = (windowExpByCat[catId] ?? 0) + minor;
          }
          if (inPrevMonth) {
            prevMonthExpByCat[catId] = (prevMonthExpByCat[catId] ?? 0) + minor;
          }
          if (!dt.isBefore(trailingFrom)) {
            final byYm = trailingExpByCat.putIfAbsent(catId, () => {});
            byYm[ym] = (byYm[ym] ?? 0) + minor;
          }
        }

        if (tx.splits.isNotEmpty) {
          for (final sp in tx.splits) {
            recordExpense(sp.categoryId, sp.categoryName, sp.baseAmountMinor);
          }
        } else {
          final catId = tx.categoryId ?? 'uncategorized';
          final catName = tx.categoryName ?? 'Uncategorized';
          recordExpense(catId, catName, tx.baseAmount.amountMinor);
        }
      }

      // Compute suggested income pool for Zero-Based Planner & Tax Provision basis.
      final trailingIncomeAvg = trailingIncomeByYm.isNotEmpty
          ? trailingIncomeByYm.values.fold<int>(0, (s, v) => s + v) ~/
                trailingIncomeByYm.length
          : 0;
      final effectiveIncomeBasis = currentMonthIncomeMinor > 0
          ? currentMonthIncomeMinor
          : (savedPlannedIncome > 0 ? savedPlannedIncome : trailingIncomeAvg);

      final taxProvisionMinor = taxReserveBps > 0 && effectiveIncomeBasis > 0
          ? (effectiveIncomeBasis * taxReserveBps) ~/ 10000
          : 0;

      final safeToSpend = CaBudgetPlannerEngine.computeSafeToSpend(
        currencyCode: ccy,
        liquidCashMinor: liquidCashMinor,
        upcomingBillsMinor: upcomingBillsMinor,
        upcomingEmisMinor: upcomingEmisMinor,
        taxProvisionMinor: taxProvisionMinor,
        sinkingFundAccrualsMinor: totalSinkingAccrualMinor,
        remainingDaysInMonth: remainingDaysInMonth,
      );

      // 8. Build ZBB Category Seeds across all active expense categories.
      final zbbSeeds = <ZbbCategorySeed>[];
      for (final cat in expenseCats) {
        final byYm = trailingExpByCat[cat.id];
        final avgSpend = byYm != null && byYm.isNotEmpty
            ? byYm.values.fold<int>(0, (s, v) => s + v) ~/ byYm.length
            : 0;
        zbbSeeds.add(
          ZbbCategorySeed(
            categoryId: cat.id,
            categoryName: cat.name,
            trailingSpendMinor: avgSpend,
            previousMonthSpendMinor: prevMonthExpByCat[cat.id] ?? 0,
          ),
        );
      }

      // 9. Build CA Budget vs. Actual (BvA) Statement.
      final budgetLines = <CaBudgetLineInput>[];
      var overallMonthlyLimitSum = 0;
      for (final b in budgets) {
        if (b.allocations.isEmpty) {
          overallMonthlyLimitSum += _toMonthlyEquivalent(
            b.overallLimit.amountMinor,
            b.periodType,
          );
        } else {
          for (final alloc in b.allocations) {
            budgetLines.add(
              CaBudgetLineInput(
                budgetId: b.id,
                budgetName: b.name,
                categoryId: alloc.categoryId,
                categoryName: alloc.categoryName,
                monthlyEquivalentLimitMinor: _toMonthlyEquivalent(
                  alloc.limitMinor,
                  b.periodType,
                ),
              ),
            );
          }
        }
      }

      final actualInputs = <CaActualSpendInput>[];
      for (final entry in windowExpByCat.entries) {
        final refund = windowRefundByCat[entry.key] ?? 0;
        final net = math.max(0, entry.value - refund);
        if (net > 0) {
          actualInputs.add(
            CaActualSpendInput(
              categoryId: entry.key,
              categoryName: windowCatNameById[entry.key] ?? 'Uncategorized',
              actualMinor: net,
            ),
          );
        }
      }

      final varianceStatement = CaBudgetPlannerEngine.buildVarianceStatement(
        currencyCode: ccy,
        window: fiscalWindow,
        periodIncomeMinor: periodIncomeMinor,
        budgetLines: budgetLines,
        actualSpends: actualInputs,
        overallProfileMonthlyLimitMinor: overallMonthlyLimitSum > 0
            ? overallMonthlyLimitSum
            : null,
      );

      // Identify existing multi-category Monthly ZBB master budget (if any).
      BudgetEntity? masterZbb;
      for (final b in budgets) {
        if (b.periodType == BudgetPeriodType.monthly &&
            b.allocations.length >= 2) {
          masterZbb = b;
          break;
        }
      }

      final suggestedIncomePool = savedPlannedIncome > 0
          ? savedPlannedIncome
          : (currentMonthIncomeMinor > 0
                ? currentMonthIncomeMinor
                : (trailingIncomeAvg > 0
                      ? trailingIncomeAvg
                      : (masterZbb?.overallLimit.amountMinor ??
                            overallMonthlyLimitSum)));

      return Success(
        CaBudgetWorkspaceSnapshot(
          profileId: profile.id,
          currencyCode: ccy,
          nowUtc: nowUtc,
          budgets: budgets,
          expenseCategories: expenseCats,
          zbbSeeds: zbbSeeds,
          safeToSpend: safeToSpend,
          sinkingFunds: sinkingFunds,
          varianceStatement: varianceStatement,
          fyStartMonth: fyStartMonth,
          taxReserveBps: taxReserveBps,
          suggestedIncomePoolMinor: suggestedIncomePool,
          actualMonthlyIncomeMinor: currentMonthIncomeMinor,
          masterZbbBudget: masterZbb,
        ),
      );
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  /// Commits a Zero-Based Master Monthly Budget with per-category envelopes and
  /// saves the profile's planned income & tax reserve rate atomically.
  Future<Result<BudgetEntity>> saveZeroBasedBudget({
    required FinancialProfile profile,
    required Map<String, int> categoryLimitsMinor,
    required int incomePoolMinor,
    required int taxReserveBps,
    String budgetName = 'Monthly Zero-Based Plan',
    bool rolloverEnabled = false,
    String? existingBudgetId,
  }) async {
    final cleaned = <String, int>{
      for (final e in categoryLimitsMinor.entries)
        if (e.value > 0) e.key: e.value,
    };
    final totalCap = cleaned.values.fold<int>(0, (s, v) => s + v);
    if (totalCap <= 0) {
      return const FailureResult(
        ValidationFailure(
          message: 'Assign a positive amount to at least one category.',
        ),
      );
    }

    await setPlannedMonthlyIncome(profile.id, incomePoolMinor);
    await setTaxReserveBps(profile.id, taxReserveBps);
    if (incomePoolMinor > 0) {
      final lifeIncomeKey =
          'life_stage.${profile.id.value}.monthly_income_minor';
      final existingLifeIncome =
          int.tryParse(await _settings.getString(lifeIncomeKey) ?? '') ?? 0;
      if (existingLifeIncome <= 0) {
        await _settings.setString(lifeIncomeKey, '$incomePoolMinor');
      }
    }

    if (existingBudgetId != null) {
      return _budgetRepo.updateBudget(
        profileId: profile.id,
        budgetId: existingBudgetId,
        name: budgetName,
        periodType: BudgetPeriodType.monthly,
        overallLimitMinor: totalCap,
        categoryLimitsMinor: cleaned,
        rolloverEnabled: rolloverEnabled,
      );
    }
    return _budgetRepo.createBudget(
      profileId: profile.id,
      name: budgetName,
      periodType: BudgetPeriodType.monthly,
      overallLimitMinor: totalCap,
      currencyCode: profile.baseCurrencyCode,
      categoryLimitsMinor: cleaned,
      rolloverEnabled: rolloverEnabled,
    );
  }

  static int _toMonthlyEquivalent(int limitMinor, BudgetPeriodType periodType) {
    return switch (periodType) {
      BudgetPeriodType.weekly => (limitMinor * 433) ~/ 100,
      BudgetPeriodType.monthly => limitMinor,
      BudgetPeriodType.quarterly => math.max(1, limitMinor ~/ 3),
      BudgetPeriodType.yearly => math.max(1, limitMinor ~/ 12),
      BudgetPeriodType.custom => limitMinor,
    };
  }
}
