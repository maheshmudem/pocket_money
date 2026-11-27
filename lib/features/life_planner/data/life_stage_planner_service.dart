import 'dart:convert';
import 'dart:math' as math;

import '../../../core/errors/failures.dart';
import '../../../core/financial_engine/life_stage_planner_engine.dart';
import '../../../core/utilities/clock.dart';
import '../../../core/utilities/id_generator.dart';
import '../../accounts/domain/entities/financial_account_entity.dart';
import '../../accounts/domain/repositories/account_repository.dart';
import '../../budgets/data/ca_budget_planner_service.dart';
import '../../budgets/domain/entities/budget_entity.dart';
import '../../categories/domain/entities/category_entity.dart';
import '../../categories/domain/repositories/category_repository.dart';
import '../../loans/data/repositories/drift_loan_repository.dart';
import '../../profiles/domain/entities/profile_entity.dart';
import '../../recurring/data/repositories/drift_recurring_repository.dart';
import '../../recurring/domain/entities/recurring_rule_entity.dart';
import '../../savings_goals/domain/entities/savings_goal_entity.dart';
import '../../savings_goals/domain/repositories/savings_goal_repository.dart';
import '../../settings/data/settings_repository.dart';
import '../../transactions/domain/entities/transaction_entity.dart';
import '../../transactions/domain/repositories/transaction_repository.dart';

/// Outcome of crediting monthly salary into a real bank or cash account.
final class CreditSalaryResult {
  const CreditSalaryResult({
    required this.transactionId,
    required this.accountId,
    required this.accountName,
    required this.amountMinor,
    required this.monthKey,
    required this.recurringRuleCreated,
  });

  final String transactionId;
  final String accountId;
  final String accountName;
  final int amountMinor;
  final String monthKey;
  final bool recurringRuleCreated;
}

/// Complete profile-isolated workspace snapshot for the 3-tab Life-Stage & EMI Planner.
final class LifeStageWorkspaceSnapshot {
  const LifeStageWorkspaceSnapshot({
    required this.profileId,
    required this.currencyCode,
    required this.targets,
    required this.incomePoolMinor,
    required this.actualMonthlyIncomeMinor,
    required this.expenseProfile,
    required this.cashFlowPlan,
    required this.blueprint,
    required this.emiHealth,
    required this.shield,
    required this.protectionChecklist,
    required this.playbook,
    required this.hasEmergencyGoalAlready,
    this.salaryAccountId,
    this.liquidAccounts = const <FinancialAccountEntity>[],
    this.currentMonthActualIncomeMinor = 0,
    this.salaryCreditedThisMonth = false,
  });

  final ProfileId profileId;
  final String currencyCode;
  final EffectiveLifeStageTargets targets;
  final int incomePoolMinor;
  final int actualMonthlyIncomeMinor;
  final MonthlyExpenseProfile expenseProfile;
  final BottomUpCashFlowPlan cashFlowPlan;
  final LifeStageBudgetBlueprint blueprint;
  final EmiHealthSummary emiHealth;
  final EmergencyShieldSnapshot shield;
  final List<ProtectionCheckItem> protectionChecklist;
  final List<LifeStageActionTip> playbook;
  final bool hasEmergencyGoalAlready;
  final String? salaryAccountId;
  final List<FinancialAccountEntity> liquidAccounts;
  final int currentMonthActualIncomeMinor;
  final bool salaryCreditedThisMonth;
}

/// Profile-scoped service assembling real ledger cash, categories, recurring bills,
/// active loans, and persisted Bottom-Up CFP preferences for [LifeStagePlannerEngine].
final class LifeStagePlannerService {
  LifeStagePlannerService({
    required AccountRepository accountRepository,
    required CategoryRepository categoryRepository,
    required TransactionRepository transactionRepository,
    required DriftRecurringRepository recurringRepository,
    required DriftLoanRepository loanRepository,
    required SavingsGoalRepository savingsGoalRepository,
    required CaBudgetPlannerService caBudgetPlannerService,
    required SettingsRepository settingsRepository,
    required UtcClock clock,
  }) : _accountRepo = accountRepository,
       _categoryRepo = categoryRepository,
       _txRepo = transactionRepository,
       _recurringRepo = recurringRepository,
       _loanRepo = loanRepository,
       _goalRepo = savingsGoalRepository,
       _caBudgetService = caBudgetPlannerService,
       _settings = settingsRepository,
       _clock = clock;

  final AccountRepository _accountRepo;
  final CategoryRepository _categoryRepo;
  final TransactionRepository _txRepo;
  final DriftRecurringRepository _recurringRepo;
  final DriftLoanRepository _loanRepo;
  final SavingsGoalRepository _goalRepo;
  final CaBudgetPlannerService _caBudgetService;
  final SettingsRepository _settings;
  final UtcClock _clock;

  static String _statusKey(ProfileId id) => 'life_stage.${id.value}.status';
  static String _depsKey(ProfileId id) => 'life_stage.${id.value}.dependents';
  static String _housingKey(ProfileId id) =>
      'life_stage.${id.value}.housing_mode';
  static String _incomeKey(ProfileId id) =>
      'life_stage.${id.value}.monthly_income_minor';
  static String _salaryAccountKey(ProfileId id) =>
      'life_stage.${id.value}.salary_account_id';
  static String _cashflowJsonKey(ProfileId id) =>
      'life_stage.${id.value}.cashflow_profile_json';

  Future<String?> getSalaryAccountId(ProfileId profileId) =>
      _settings.getString(_salaryAccountKey(profileId));

  Future<void> saveSalaryAccountId(
    ProfileId profileId,
    String? accountId,
  ) async {
    final trimmed = accountId?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    await _settings.setString(_salaryAccountKey(profileId), trimmed);
  }

  static LifeStageStatus defaultStatusForProfile(FinancialProfile profile) =>
      switch (profile.profileType) {
        ProfileType.family => LifeStageStatus.familyWithKids,
        ProfileType.business => LifeStageStatus.freelancerBusiness,
        ProfileType.personal => LifeStageStatus.bachelor,
      };

  Future<LifeStageStatus> readSavedStatus(FinancialProfile profile) async {
    final raw = await _settings.getString(_statusKey(profile.id));
    if (raw == null) return defaultStatusForProfile(profile);
    return LifeStageStatus.fromWire(raw);
  }

  /// Lightweight read of saved life-stage targets & planned monthly income
  /// without executing any ledger queries.
  Future<({EffectiveLifeStageTargets targets, int plannedIncomeMinor})>
  readPlanningBasics(FinancialProfile profile) async {
    final statusRaw = await _settings.getString(_statusKey(profile.id));
    final status = statusRaw != null
        ? LifeStageStatus.fromWire(statusRaw)
        : defaultStatusForProfile(profile);

    final depsRaw = await _settings.getString(_depsKey(profile.id));
    final defaultDeps = status == LifeStageStatus.familyWithKids
        ? 2
        : (status == LifeStageStatus.sandwichFamily ? 3 : 0);
    final dependents = depsRaw != null
        ? (int.tryParse(depsRaw) ?? defaultDeps).clamp(0, 6)
        : defaultDeps;

    final housingRaw = await _settings.getString(_housingKey(profile.id));
    final housingMode = HousingMode.fromWire(housingRaw);

    final savedExp = await _readSavedExpenseProfile(profile.id);
    final savedIncomeRaw = await _settings.getString(_incomeKey(profile.id));
    final savedIncomeMinor = int.tryParse(savedIncomeRaw ?? '') ?? 0;
    final plannedIncome = (savedExp != null && savedExp.totalIncomeMinor > 0)
        ? savedExp.totalIncomeMinor
        : savedIncomeMinor;

    final targets = LifeStagePlannerEngine.resolveEffectiveTargets(
      status: status,
      dependentsCount: dependents,
      housingMode: housingMode,
    );
    return (targets: targets, plannedIncomeMinor: plannedIncome);
  }

  Future<void> savePreferences({
    required ProfileId profileId,
    required LifeStageStatus status,
    required int dependentsCount,
    required HousingMode housingMode,
    int? plannedMonthlyIncomeMinor,
  }) async {
    await _settings.setString(_statusKey(profileId), status.wireValue);
    await _settings.setString(
      _depsKey(profileId),
      '${dependentsCount.clamp(0, 6)}',
    );
    await _settings.setString(_housingKey(profileId), housingMode.wireValue);
    if (plannedMonthlyIncomeMinor != null && plannedMonthlyIncomeMinor >= 0) {
      await _settings.setString(
        _incomeKey(profileId),
        '$plannedMonthlyIncomeMinor',
      );
      if (plannedMonthlyIncomeMinor > 0) {
        await _caBudgetService.setPlannedMonthlyIncome(
          profileId,
          plannedMonthlyIncomeMinor,
        );
      }
      final existing = await _readSavedExpenseProfile(profileId);
      if (existing != null) {
        await saveExpenseProfile(
          profileId: profileId,
          expenseProfile: existing.copyWith(
            primaryIncomeMinor: plannedMonthlyIncomeMinor,
          ),
        );
      }
    }
  }

  Future<void> saveExpenseProfile({
    required ProfileId profileId,
    required MonthlyExpenseProfile expenseProfile,
  }) async {
    await _settings.setString(
      _cashflowJsonKey(profileId),
      jsonEncode(expenseProfile.toJsonMap()),
    );
    await _settings.setString(
      _incomeKey(profileId),
      '${expenseProfile.totalIncomeMinor}',
    );
    if (expenseProfile.totalIncomeMinor > 0) {
      await _caBudgetService.setPlannedMonthlyIncome(
        profileId,
        expenseProfile.totalIncomeMinor,
      );
    }
  }

  Future<MonthlyExpenseProfile?> _readSavedExpenseProfile(
    ProfileId profileId,
  ) async {
    final raw = await _settings.getString(_cashflowJsonKey(profileId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return MonthlyExpenseProfile.fromJsonMap(decoded);
      }
    } catch (_) {
      // Corrupt preference falls back cleanly to empty profile.
    }
    return null;
  }

  /// Auto-fills a [MonthlyExpenseProfile] from the profile's real trailing ledger
  /// expenses and active recurring bills (Rent, Groceries, Fees, Utilities, Insurance, Subscriptions, etc.).
  Future<Result<MonthlyExpenseProfile>> autoFillExpensesFromLedger({
    required FinancialProfile profile,
  }) async {
    try {
      final nowUtc = _clock.nowUtc();
      final lookbackFrom = DateTime.utc(nowUtc.year, nowUtc.month - 3, 1);
      final txRes = await _txRepo.queryTransactions(
        profile.id,
        filter: TransactionFilter(
          status: TransactionStatus.posted,
          fromUtc: lookbackFrom.toIso8601String(),
        ),
        limit: 3000,
      );
      final txs = txRes.valueOrNull?.items ?? const <TransactionEntity>[];
      final rulesRes = await _recurringRepo.listRules(profile.id);
      final rules = rulesRes.valueOrNull ?? const <RecurringRuleEntity>[];
      final catsRes = await _categoryRepo.listCategories(
        profile.id,
        type: CategoryType.expense,
      );
      final catNameById = {
        for (final c in (catsRes.valueOrNull ?? const <CategoryEntity>[]))
          c.id: c.name,
      };

      final incomeByYm = <String, int>{};
      final bucketByYm = <String, Map<String, int>>{};

      void addLedgerBucket(String ym, String label, int minor) {
        if (minor <= 0) return;
        final key = _classifyExpenseSlot(label);
        if (key == null) return;
        final m = bucketByYm.putIfAbsent(key, () => {});
        m[ym] = (m[ym] ?? 0) + minor;
      }

      for (final tx in txs) {
        if (tx.isReversed || tx.status != TransactionStatus.posted) continue;
        final dt = DateTime.tryParse(tx.transactionDateUtc)?.toUtc();
        if (dt == null) continue;
        final ym = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';

        if (tx.type == TransactionType.income) {
          incomeByYm[ym] = (incomeByYm[ym] ?? 0) + tx.baseAmount.amountMinor;
          continue;
        }
        if (tx.type != TransactionType.expense) continue;
        if (tx.splits.isNotEmpty) {
          for (final sp in tx.splits) {
            addLedgerBucket(ym, sp.categoryName, sp.baseAmountMinor);
          }
        } else {
          final label = '${tx.categoryName ?? ''} ${tx.description ?? ''}'
              .trim();
          addLedgerBucket(ym, label, tx.baseAmount.amountMinor);
        }
      }

      int avgSlot(String slot) {
        final byYm = bucketByYm[slot];
        if (byYm == null || byYm.isEmpty) return 0;
        return byYm.values.fold<int>(0, (s, v) => s + v) ~/ byYm.length;
      }

      // Layer active recurring bills (take max of recurring monthly equivalent vs ledger avg).
      final recSlotTotals = <String, int>{};
      for (final r in rules) {
        if (r.status != 'active' ||
            r.transactionType != TransactionType.expense) {
          continue;
        }
        final catLabel =
            '${r.categoryId != null ? (catNameById[r.categoryId!] ?? '') : ''} ${r.name}'
                .trim();
        final slot = _classifyExpenseSlot(catLabel);
        if (slot == null) continue;
        final monthlyEquiv = switch (r.cadence) {
          RecurringCadence.daily => r.amount.amountMinor * 30,
          RecurringCadence.weekly => (r.amount.amountMinor * 433) ~/ 100,
          RecurringCadence.monthly => r.amount.amountMinor,
          RecurringCadence.yearly => r.amount.amountMinor ~/ 12,
        };
        recSlotTotals[slot] = (recSlotTotals[slot] ?? 0) + monthlyEquiv;
      }

      int slotVal(String slot) =>
          math.max(avgSlot(slot), recSlotTotals[slot] ?? 0);

      final existing = await _readSavedExpenseProfile(profile.id);
      final ledgerIncomeAvg = incomeByYm.isNotEmpty
          ? incomeByYm.values.fold<int>(0, (s, v) => s + v) ~/ incomeByYm.length
          : 0;
      final primaryIncome = ledgerIncomeAvg > 0
          ? ledgerIncomeAvg
          : (existing?.primaryIncomeMinor ?? 0);

      final filled = MonthlyExpenseProfile(
        primaryIncomeMinor: primaryIncome,
        secondaryIncomeMinor: existing?.secondaryIncomeMinor ?? 0,
        rentOrHousingMinor: slotVal('rent'),
        groceriesMinor: slotVal('groceries'),
        utilitiesMinor: slotVal('utilities'),
        schoolFeesMinor: slotVal('school_fees'),
        insuranceMinor: slotVal('insurance'),
        transportFuelMinor: slotVal('transport'),
        medicalMinor: slotVal('medical'),
        parentsSupportMinor: slotVal('parents'),
        subscriptionsMinor: slotVal('subscriptions'),
        manualEmiMinor: existing?.manualEmiMinor ?? 0,
        otherFixedMinor: slotVal('other_fixed'),
      );
      return Success(filled);
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  Future<Result<LifeStageWorkspaceSnapshot>> loadWorkspace({
    required FinancialProfile profile,
  }) async {
    try {
      final nowUtc = _clock.nowUtc();
      final ccy = profile.baseCurrencyCode;

      final statusRaw = await _settings.getString(_statusKey(profile.id));
      final status = statusRaw != null
          ? LifeStageStatus.fromWire(statusRaw)
          : defaultStatusForProfile(profile);

      final depsRaw = await _settings.getString(_depsKey(profile.id));
      final defaultDeps = status == LifeStageStatus.familyWithKids
          ? 2
          : (status == LifeStageStatus.sandwichFamily ? 3 : 0);
      final dependents = depsRaw != null
          ? (int.tryParse(depsRaw) ?? defaultDeps).clamp(0, 6)
          : defaultDeps;

      final housingRaw = await _settings.getString(_housingKey(profile.id));
      final housingMode = HousingMode.fromWire(housingRaw);

      final savedIncomeRaw = await _settings.getString(_incomeKey(profile.id));
      final savedIncomeMinor = int.tryParse(savedIncomeRaw ?? '') ?? 0;

      final targets = LifeStagePlannerEngine.resolveEffectiveTargets(
        status: status,
        dependentsCount: dependents,
        housingMode: housingMode,
      );

      // Load live profile-isolated financial data.
      final accountsRes = await _accountRepo.listAccounts(profile.id);
      final accounts =
          accountsRes.valueOrNull ?? const <FinancialAccountEntity>[];

      final catsRes = await _categoryRepo.listCategories(
        profile.id,
        type: CategoryType.expense,
      );
      final expenseCats = catsRes.valueOrNull ?? const <CategoryEntity>[];

      final monthStart = DateTime.utc(nowUtc.year, nowUtc.month, 1);
      final lookbackStart = DateTime.utc(nowUtc.year, nowUtc.month - 3, 1);
      final txRes = await _txRepo.queryTransactions(
        profile.id,
        filter: TransactionFilter(
          status: TransactionStatus.posted,
          fromUtc: lookbackStart.toIso8601String(),
        ),
        limit: 3000,
      );
      final txs = txRes.valueOrNull?.items ?? const <TransactionEntity>[];

      final loansRes = await _loanRepo.listLoans(profile.id);
      final loansRaw = loansRes.valueOrNull ?? const [];

      final goalsRes = await _goalRepo.listGoals(profile.id);
      final goals = goalsRes.valueOrNull ?? const <SavingsGoalEntity>[];

      final liquidAccounts = accounts
          .where((a) => !a.isLiability)
          .toList(growable: false);
      final savedSalaryAccId = await getSalaryAccountId(profile.id);
      final salaryAccountId =
          savedSalaryAccId != null &&
              liquidAccounts.any((a) => a.id == savedSalaryAccId)
          ? savedSalaryAccId
          : liquidAccounts.firstOrNull?.id;

      final liquidCashMinor = liquidAccounts
          .where(
            (a) =>
                a.accountType == FinancialAccountType.bank ||
                a.accountType == FinancialAccountType.cash ||
                a.accountType == FinancialAccountType.wallet,
          )
          .fold<int>(0, (s, a) => s + a.baseBalance.amountMinor);

      final currentMonthKey =
          '${nowUtc.year}-${nowUtc.month.toString().padLeft(2, '0')}';
      final expectedSalaryRef = 'salary:${profile.id.value}:$currentMonthKey';
      var currMonthIncome = 0;
      var salaryCreditedThisMonth = false;
      final trailingIncomeByYm = <String, int>{};
      final currMonthExpByCat = <String, int>{};
      final currMonthRefundByCat = <String, int>{};

      for (final tx in txs) {
        if (tx.isReversed || tx.status != TransactionStatus.posted) continue;
        final dt = DateTime.tryParse(tx.transactionDateUtc)?.toUtc();
        if (dt == null) continue;
        final inCurrMonth = !dt.isBefore(monthStart);
        final ym = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';

        if (tx.type == TransactionType.income) {
          final amt = tx.baseAmount.amountMinor;
          if (inCurrMonth) {
            currMonthIncome += amt;
            if (tx.externalRef == expectedSalaryRef ||
                (tx.description ?? '').startsWith('Monthly Salary (')) {
              salaryCreditedThisMonth = true;
            }
          } else {
            trailingIncomeByYm[ym] = (trailingIncomeByYm[ym] ?? 0) + amt;
          }
          continue;
        }
        if (!inCurrMonth) continue;

        if (tx.type == TransactionType.refund && tx.categoryId != null) {
          currMonthRefundByCat[tx.categoryId!] =
              (currMonthRefundByCat[tx.categoryId!] ?? 0) +
              tx.baseAmount.amountMinor;
          continue;
        }
        if (tx.type != TransactionType.expense) continue;
        if (tx.splits.isNotEmpty) {
          for (final sp in tx.splits) {
            currMonthExpByCat[sp.categoryId] =
                (currMonthExpByCat[sp.categoryId] ?? 0) + sp.baseAmountMinor;
          }
        } else if (tx.categoryId != null) {
          currMonthExpByCat[tx.categoryId!] =
              (currMonthExpByCat[tx.categoryId!] ?? 0) +
              tx.baseAmount.amountMinor;
        }
      }

      final trailingIncomeAvg = trailingIncomeByYm.isNotEmpty
          ? trailingIncomeByYm.values.fold<int>(0, (s, v) => s + v) ~/
                trailingIncomeByYm.length
          : 0;
      final fallbackIncome = savedIncomeMinor > 0
          ? savedIncomeMinor
          : (currMonthIncome > 0 ? currMonthIncome : trailingIncomeAvg);

      // Load or seed profile-scoped bottom-up MonthlyExpenseProfile.
      final savedExp = await _readSavedExpenseProfile(profile.id);
      final expenseProfile = savedExp != null
          ? (savedExp.totalIncomeMinor > 0
                ? savedExp
                : savedExp.copyWith(primaryIncomeMinor: fallbackIncome))
          : MonthlyExpenseProfile(primaryIncomeMinor: fallbackIncome);

      final effectiveIncome = expenseProfile.totalIncomeMinor > 0
          ? expenseProfile.totalIncomeMinor
          : fallbackIncome;

      final catInputs = <LifeStageCategoryInput>[
        for (final cat in expenseCats)
          LifeStageCategoryInput(
            categoryId: cat.id,
            categoryName: cat.name,
            currentMonthSpendMinor: math.max(
              0,
              (currMonthExpByCat[cat.id] ?? 0) -
                  (currMonthRefundByCat[cat.id] ?? 0),
            ),
          ),
      ];

      final blueprint = LifeStagePlannerEngine.buildCategoryBlueprint(
        currencyCode: ccy,
        incomePoolMinor: effectiveIncome,
        targets: targets,
        categories: catInputs,
      );

      // Assemble active loan snapshots for live DTI & Avalanche/Snowball simulator.
      final activeLoans = <ActiveLoanSnapshot>[];
      for (final loan in loansRaw) {
        if (loan.status != 'active' || loan.remainingPrincipalMinor <= 0) {
          continue;
        }
        final unpaid = loan.installments
            .where((i) => i.status != 'paid')
            .toList();
        if (unpaid.isEmpty) continue;
        final monthlyEmi = unpaid.first.totalDueMinor;
        activeLoans.add(
          ActiveLoanSnapshot(
            loanId: loan.id,
            name: loan.name,
            remainingPrincipalMinor: loan.remainingPrincipalMinor,
            monthlyEmiMinor: monthlyEmi,
            annualInterestRateBps: loan.annualInterestRateBps,
            remainingMonths: unpaid.length,
          ),
        );
      }

      final trackedLoanEmiMinor = activeLoans.fold<int>(
        0,
        (s, l) => s + l.monthlyEmiMinor,
      );

      final emiHealth = LifeStagePlannerEngine.analyzeEmiHealth(
        currencyCode: ccy,
        monthlyIncomeMinor: effectiveIncome,
        targets: targets,
        loans: activeLoans,
        manualMonthlyEmiMinor: expenseProfile.manualEmiMinor,
      );

      final cashFlowPlan = LifeStagePlannerEngine.buildBottomUpCashFlowPlan(
        currencyCode: ccy,
        targets: targets,
        expenses: expenseProfile,
        trackedLoanEmiMinor: trackedLoanEmiMinor,
        liquidCashMinor: liquidCashMinor,
        hasHighInterestDebt: emiHealth.hasHighInterestDebt,
      );

      final protectionPack = LifeStagePlannerEngine.buildProtectionAndPlaybook(
        currencyCode: ccy,
        targets: targets,
        blueprint: blueprint,
        emiHealth: emiHealth,
        liquidCashMinor: liquidCashMinor,
        realEssentialOutgoMinor: expenseProfile.hasAnyEnteredExpenses
            ? cashFlowPlan.essentialOutgoForShieldMinor
            : null,
      );

      final hasEmergencyGoal = goals.any(
        (g) =>
            g.status == 'active' && g.name.toLowerCase().contains('emergency'),
      );

      return Success(
        LifeStageWorkspaceSnapshot(
          profileId: profile.id,
          currencyCode: ccy,
          targets: targets,
          incomePoolMinor: effectiveIncome,
          actualMonthlyIncomeMinor: currMonthIncome,
          expenseProfile: expenseProfile,
          cashFlowPlan: cashFlowPlan,
          blueprint: blueprint,
          emiHealth: emiHealth,
          shield: protectionPack.shield,
          protectionChecklist: protectionPack.protection,
          playbook: protectionPack.playbook,
          hasEmergencyGoalAlready: hasEmergencyGoal,
          salaryAccountId: salaryAccountId,
          liquidAccounts: liquidAccounts,
          currentMonthActualIncomeMinor: currMonthIncome,
          salaryCreditedThisMonth: salaryCreditedThisMonth,
        ),
      );
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  /// Credits real monthly salary into a chosen Bank/Cash account as a posted
  /// double-entry [TransactionType.income] and optionally creates a monthly
  /// recurring income reminder rule so future months stay in sync.
  Future<Result<CreditSalaryResult>> creditMonthlySalaryToAccount({
    required FinancialProfile profile,
    required String accountId,
    required int amountMinor,
    required int year,
    required int month,
    bool createRecurringRule = false,
    bool forceDuplicate = false,
  }) async {
    if (amountMinor <= 0) {
      return const FailureResult(
        ValidationFailure(message: 'Salary amount must be greater than zero.'),
      );
    }

    final accRes = await _accountRepo.getAccount(profile.id, accountId);
    if (accRes.isFailure) return FailureResult(accRes.failureOrNull!);
    final acc = accRes.valueOrNull!;
    if (acc.isLiability) {
      return const FailureResult(
        ValidationFailure(
          message:
              'Salary must be credited to a bank, cash, or wallet asset account.',
        ),
      );
    }

    final monthKey = '$year-${month.toString().padLeft(2, '0')}';
    final salaryRef = 'salary:${profile.id.value}:$monthKey';
    final monthStart = DateTime.utc(year, month, 1);
    final monthEnd = DateTime.utc(year, month + 1, 0, 23, 59, 59);

    if (!forceDuplicate) {
      final existingRes = await _txRepo.queryTransactions(
        profile.id,
        filter: TransactionFilter(
          status: TransactionStatus.posted,
          type: TransactionType.income,
          fromUtc: monthStart.toIso8601String(),
          toUtc: monthEnd.toIso8601String(),
        ),
        limit: 500,
      );
      final alreadyCredited =
          (existingRes.valueOrNull?.items ?? const <TransactionEntity>[]).any(
            (tx) => !tx.isReversed && tx.externalRef == salaryRef,
          );
      if (alreadyCredited) {
        return FailureResult(
          ValidationFailure(
            message:
                'Monthly salary for $monthKey is already credited to your account.',
          ),
        );
      }
    }

    final incCatsRes = await _categoryRepo.listCategories(
      profile.id,
      type: CategoryType.income,
    );
    final incCats = incCatsRes.valueOrNull ?? const <CategoryEntity>[];
    String? salaryCatId;
    for (final c in incCats) {
      if (c.isActive && c.name.trim().toLowerCase() == 'salary') {
        salaryCatId = c.id;
        break;
      }
    }
    salaryCatId ??= incCats.where((c) => c.isActive).firstOrNull?.id;
    if (salaryCatId == null) {
      final createdCat = await _categoryRepo.createCategory(
        profileId: profile.id,
        name: 'Salary',
        categoryType: CategoryType.income,
        iconKey: 'payments',
      );
      if (createdCat.isFailure) {
        return FailureResult(createdCat.failureOrNull!);
      }
      salaryCatId = createdCat.valueOrNull!.id;
    }

    final nowUtc = _clock.nowUtc();
    final txDateUtc = (nowUtc.year == year && nowUtc.month == month)
        ? nowUtc
        : DateTime.utc(year, month, 1, 9);

    final txRes = await _txRepo.createTransaction(
      profile.id,
      CreateTransactionCommand(
        type: TransactionType.income,
        amountMinor: amountMinor,
        currencyCode: acc.currencyCode,
        transactionDateUtc: txDateUtc.toIso8601String(),
        destinationAccountId: accountId,
        categoryId: salaryCatId,
        description: 'Monthly Salary ($monthKey)',
        externalRef: forceDuplicate ? null : salaryRef,
      ),
    );
    if (txRes.isFailure) return FailureResult(txRes.failureOrNull!);
    final tx = txRes.valueOrNull!;

    await saveSalaryAccountId(profile.id, accountId);

    var recurringCreated = false;
    if (createRecurringRule) {
      final rulesRes = await _recurringRepo.listRules(profile.id);
      final rules = rulesRes.valueOrNull ?? const <RecurringRuleEntity>[];
      final hasSalaryRule = rules.any(
        (r) =>
            r.status == 'active' &&
            r.transactionType == TransactionType.income &&
            r.name.toLowerCase().contains('salary'),
      );
      if (!hasSalaryRule) {
        final nextDue = DateTime.utc(year, month + 1, 1, 9);
        final ruleRes = await _recurringRepo.createRule(
          profileId: profile.id,
          name: 'Monthly Salary',
          transactionType: TransactionType.income,
          amountMinor: amountMinor,
          currencyCode: acc.currencyCode,
          cadence: RecurringCadence.monthly,
          nextDueAtUtc: nextDue.toIso8601String(),
          destinationAccountId: accountId,
          categoryId: salaryCatId,
          autoCreateDraft: true,
        );
        recurringCreated = ruleRes.isSuccess;
      }
    }

    return Success(
      CreditSalaryResult(
        transactionId: tx.id,
        accountId: accountId,
        accountName: acc.name,
        amountMinor: amountMinor,
        monthKey: monthKey,
        recurringRuleCreated: recurringCreated,
      ),
    );
  }

  /// 1-Tap Apply: commits the custom Bottom-Up Income & Expense envelopes
  /// (auto-creating missing categories like Insurance, Subscriptions, Parents & Care)
  /// or falls back to the status blueprint if no expenses were entered yet.
  Future<Result<BudgetEntity>> applyLifeStageBudget({
    required FinancialProfile profile,
    required LifeStageWorkspaceSnapshot snapshot,
  }) async {
    final caRes = await _caBudgetService.loadWorkspace(profile: profile);
    final existingMasterId = caRes.valueOrNull?.masterZbbBudget?.id;

    Map<String, int> categoryLimits;
    if (snapshot.expenseProfile.hasAnyEnteredExpenses &&
        snapshot.cashFlowPlan.budgetEnvelopes.isNotEmpty) {
      final catsRes = await _categoryRepo.listCategories(
        profile.id,
        type: CategoryType.expense,
      );
      final existingCats = [
        ...(catsRes.valueOrNull ?? const <CategoryEntity>[]),
      ];
      categoryLimits = <String, int>{};

      for (final env in snapshot.cashFlowPlan.budgetEnvelopes) {
        if (env.amountMinor <= 0) continue;
        CategoryEntity? matched;
        final targetLower = env.categoryName.toLowerCase();

        // 1. Exact name match first.
        for (final c in existingCats) {
          if (c.name.toLowerCase() == targetLower) {
            matched = c;
            break;
          }
        }
        // 2. Keyword match next (avoid colliding two different envelopes if possible).
        if (matched == null) {
          for (final c in existingCats) {
            final cl = c.name.toLowerCase();
            if (env.matchKeywords.any((kw) => cl.contains(kw)) &&
                !categoryLimits.containsKey(c.id)) {
              matched = c;
              break;
            }
          }
        }
        // 3. Auto-create missing category cleanly (e.g., Insurance, Subscriptions, Parents & Care).
        if (matched == null) {
          final created = await _categoryRepo.createCategory(
            profileId: profile.id,
            name: env.categoryName,
            categoryType: CategoryType.expense,
            iconKey: env.iconKey,
          );
          if (created.isSuccess) {
            matched = created.valueOrNull;
            if (matched != null) existingCats.add(matched);
          }
        }
        if (matched != null) {
          categoryLimits[matched.id] =
              (categoryLimits[matched.id] ?? 0) + env.amountMinor;
        }
      }
    } else {
      categoryLimits = snapshot.blueprint.categoryLimitsMap;
    }

    return _caBudgetService.saveZeroBasedBudget(
      profile: profile,
      categoryLimitsMinor: categoryLimits,
      incomePoolMinor: snapshot.incomePoolMinor,
      taxReserveBps: snapshot.targets.taxPct * 100,
      budgetName: '${snapshot.targets.status.shortLabel} Master Budget',
      rolloverEnabled: false,
      existingBudgetId: existingMasterId,
    );
  }

  /// 1-Tap Create Emergency Shield Goal using essential-outgo × target months.
  Future<Result<SavingsGoalEntity>> createEmergencyShieldGoal({
    required FinancialProfile profile,
    required EmergencyShieldSnapshot shield,
  }) async {
    final targetMinor = shield.targetCorpusMinor > 0
        ? shield.targetCorpusMinor
        : 10000000;
    final targetDate = _clock.nowUtc().add(const Duration(days: 365));
    return _goalRepo.createGoal(
      profileId: profile.id,
      name: 'Emergency Shield (${shield.targetMonths} Months)',
      targetAmountMinor: targetMinor,
      currencyCode: profile.baseCurrencyCode,
      fundingMode: GoalFundingMode.allocated,
      targetDateUtc: targetDate.toIso8601String(),
    );
  }

  static String? _classifyExpenseSlot(String rawLabel) {
    final l = rawLabel.toLowerCase();
    if (l.isEmpty) return null;
    if (l.contains('rent') ||
        l.contains('housing') ||
        l.contains('lease') ||
        l.contains('hostel') ||
        l.contains('mortgage') ||
        l.contains('pg')) {
      return 'rent';
    }
    if (l.contains('maintenance') ||
        l.contains('society') ||
        l.contains('hoa') ||
        l.contains('repair') ||
        l.contains('plumb') ||
        l.contains('housekeeping') ||
        l.contains('maid') ||
        l.contains('cook') ||
        l.contains('domestic') ||
        l.contains('service charge')) {
      return 'other_fixed';
    }
    if (l.contains('grocer') || l.contains('supermarket')) return 'groceries';
    if (l.contains('education') ||
        l.contains('school') ||
        l.contains('tuition') ||
        l.contains('fee')) {
      return 'school_fees';
    }
    if (l.contains('insurance') || l.contains('term') || l.contains('policy')) {
      return 'insurance';
    }
    if (l.contains('subscription') ||
        l.contains('netflix') ||
        l.contains('spotify') ||
        l.contains('ott') ||
        l.contains('gym') ||
        l.contains('software') ||
        l.contains('cloud')) {
      return 'subscriptions';
    }
    if (l.contains('parent') || l.contains('dependent')) return 'parents';
    if (l.contains('health') ||
        l.contains('medical') ||
        l.contains('pharmacy') ||
        l.contains('doctor') ||
        l.contains('hospital')) {
      return 'medical';
    }
    if (l.contains('util') ||
        l.contains('bill') ||
        l.contains('electric') ||
        l.contains('wifi') ||
        l.contains('internet') ||
        l.contains('broadband') ||
        l.contains('mobile') ||
        l.contains('water') ||
        l.contains('lpg') ||
        l.contains('cylinder') ||
        l.contains('cable') ||
        l.contains('dth') ||
        l.contains('fiber') ||
        l.contains('gas')) {
      return 'utilities';
    }
    if (l.contains('transport') ||
        l.contains('fuel') ||
        l.contains('petrol') ||
        l.contains('commute') ||
        l.contains('uber') ||
        l.contains('metro')) {
      return 'transport';
    }
    return null;
  }
}
