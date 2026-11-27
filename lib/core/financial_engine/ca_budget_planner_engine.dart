import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import 'currency.dart';
import 'money.dart';

/// Chartered Accountant (CA) cost-behavior classification for budgeting & BvA reporting.
enum CaCostClass {
  fixedNeed('Fixed Need', 'Essential fixed or recurring operating cost'),
  variableWant('Variable Want', 'Flexible discretionary spending'),
  taxStatutory('Tax & Statutory', 'Income tax, GST, TDS, audit & compliance'),
  savingsCapex('Savings & CapEx', 'Wealth building, SIPs, reserves & capex');

  const CaCostClass(this.label, this.description);
  final String label;
  final String description;
}

/// Reporting period window for CA Budget vs. Actual (BvA) Variance Statements.
enum CaFiscalPeriodPreset {
  currentMonth('This Month'),
  previousMonth('Last Month'),
  currentQuarter('FY Quarter'),
  yearToDate('FY YTD');

  const CaFiscalPeriodPreset(this.label);
  final String label;
}

/// One-tap Chartered Accountant & CFO Zero-Based Budgeting (ZBB) blueprints.
enum CaBudgetBlueprint {
  balanced503020(
    '50/30/20',
    '50 / 30 / 20 Balanced',
    '50% Needs • 30% Wants • 20% Savings',
    needsPct: 50,
    wantsPct: 30,
    taxPct: 0,
    savingsPct: 20,
  ),
  profitFirst(
    'Profit First',
    'Profit First (Business/CA)',
    '50% OpEx • 30% Owner Pay • 15% Tax • 5% Profit',
    needsPct: 50,
    wantsPct: 30,
    taxPct: 15,
    savingsPct: 5,
  ),
  leanSaver702010(
    '70/20/10',
    '70 / 20 / 10 Lean Saver',
    '70% Essentials • 20% Savings • 10% Discretionary',
    needsPct: 70,
    wantsPct: 10,
    taxPct: 0,
    savingsPct: 20,
  ),
  taxReadyFreelancer(
    'Tax-Ready',
    'Tax-Ready Freelancer',
    '45% Living/OpEx • 25% Tax Shield • 20% Savings • 10% Wants',
    needsPct: 45,
    wantsPct: 10,
    taxPct: 25,
    savingsPct: 20,
  ),
  copyLastMonth(
    'Last Mo -5%',
    'Last Month Actuals (-5%)',
    'Builds category caps from prior month spend with 5% savings trim',
    needsPct: 50,
    wantsPct: 30,
    taxPct: 0,
    savingsPct: 20,
  );

  const CaBudgetBlueprint(
    this.shortLabel,
    this.fullLabel,
    this.summary, {
    required this.needsPct,
    required this.wantsPct,
    required this.taxPct,
    required this.savingsPct,
  });

  final String shortLabel;
  final String fullLabel;
  final String summary;
  final int needsPct;
  final int wantsPct;
  final int taxPct;
  final int savingsPct;
}

final class CaFiscalWindow extends Equatable {
  const CaFiscalWindow({
    required this.preset,
    required this.label,
    required this.fiscalCycleLabel,
    required this.fromUtc,
    required this.toUtc,
    required this.elapsedDays,
    required this.totalDays,
    required this.remainingDays,
    required this.monthlyBudgetMultiplier,
    required this.isCurrentOpenPeriod,
  });

  final CaFiscalPeriodPreset preset;
  final String label;
  final String fiscalCycleLabel;
  final DateTime fromUtc;
  final DateTime toUtc;
  final int elapsedDays;
  final int totalDays;
  final int remainingDays;

  /// Number of monthly budget cycles spanned by this window (e.g. 1, 3, or YTD months).
  final int monthlyBudgetMultiplier;
  final bool isCurrentOpenPeriod;

  double get elapsedRatio =>
      totalDays > 0 ? (elapsedDays / totalDays).clamp(0.0, 1.0) : 1.0;

  @override
  List<Object?> get props => [
    preset,
    label,
    fiscalCycleLabel,
    fromUtc,
    toUtc,
    elapsedDays,
    totalDays,
    remainingDays,
    monthlyBudgetMultiplier,
    isCurrentOpenPeriod,
  ];
}

final class SafeToSpendSnapshot extends Equatable {
  const SafeToSpendSnapshot({
    required this.currencyCode,
    required this.liquidCashMinor,
    required this.upcomingBillsMinor,
    required this.upcomingEmisMinor,
    required this.taxProvisionMinor,
    required this.sinkingFundAccrualsMinor,
    required this.committedObligationsMinor,
    required this.rawNetLiquidityMinor,
    required this.safeToSpendMinor,
    required this.dailySafeToSpendMinor,
    required this.remainingDaysInMonth,
    required this.liquidityStatus,
    required this.statusNote,
  });

  final String currencyCode;
  final int liquidCashMinor;
  final int upcomingBillsMinor;
  final int upcomingEmisMinor;
  final int taxProvisionMinor;
  final int sinkingFundAccrualsMinor;
  final int committedObligationsMinor;
  final int rawNetLiquidityMinor;
  final int safeToSpendMinor;
  final int dailySafeToSpendMinor;
  final int remainingDaysInMonth;

  /// `'comfortable'` | `'tight'` | `'crunch'`
  final String liquidityStatus;
  final String statusNote;

  bool get isCashCrunch => rawNetLiquidityMinor < 0;
  int get shortfallMinor =>
      rawNetLiquidityMinor < 0 ? -rawNetLiquidityMinor : 0;

  @override
  List<Object?> get props => [
    currencyCode,
    liquidCashMinor,
    upcomingBillsMinor,
    upcomingEmisMinor,
    taxProvisionMinor,
    sinkingFundAccrualsMinor,
    committedObligationsMinor,
    rawNetLiquidityMinor,
    safeToSpendMinor,
    dailySafeToSpendMinor,
    remainingDaysInMonth,
    liquidityStatus,
    statusNote,
  ];
}

final class SinkingFundAccrual extends Equatable {
  const SinkingFundAccrual({
    required this.goalId,
    required this.name,
    required this.targetMinor,
    required this.contributedMinor,
    required this.remainingMinor,
    required this.monthsRemaining,
    required this.monthlyAccrualMinor,
    required this.targetDateIso,
  });

  final String goalId;
  final String name;
  final int targetMinor;
  final int contributedMinor;
  final int remainingMinor;
  final int monthsRemaining;
  final int monthlyAccrualMinor;
  final String targetDateIso;

  double get progressRatio =>
      targetMinor > 0 ? (contributedMinor / targetMinor).clamp(0.0, 1.0) : 0.0;

  @override
  List<Object?> get props => [
    goalId,
    name,
    targetMinor,
    contributedMinor,
    remainingMinor,
    monthsRemaining,
    monthlyAccrualMinor,
    targetDateIso,
  ];
}

final class ZbbCategorySeed extends Equatable {
  const ZbbCategorySeed({
    required this.categoryId,
    required this.categoryName,
    required this.trailingSpendMinor,
    required this.previousMonthSpendMinor,
  });

  final String categoryId;
  final String categoryName;
  final int trailingSpendMinor;
  final int previousMonthSpendMinor;

  @override
  List<Object?> get props => [
    categoryId,
    categoryName,
    trailingSpendMinor,
    previousMonthSpendMinor,
  ];
}

final class ZbbGeneratedPlan extends Equatable {
  const ZbbGeneratedPlan({
    required this.blueprint,
    required this.incomePoolMinor,
    required this.taxReserveBps,
    required this.taxReserveMinor,
    required this.savingsReserveMinor,
    required this.categoryAllocationsMinor,
  });

  final CaBudgetBlueprint blueprint;
  final int incomePoolMinor;
  final int taxReserveBps;
  final int taxReserveMinor;
  final int savingsReserveMinor;
  final Map<String, int> categoryAllocationsMinor;

  int get totalCategoryAllocatedMinor =>
      categoryAllocationsMinor.values.fold(0, (s, v) => s + v);

  int get totalAssignedMinor =>
      totalCategoryAllocatedMinor + taxReserveMinor + savingsReserveMinor;

  int get unallocatedMinor => incomePoolMinor - totalAssignedMinor;

  @override
  List<Object?> get props => [
    blueprint,
    incomePoolMinor,
    taxReserveBps,
    taxReserveMinor,
    savingsReserveMinor,
    categoryAllocationsMinor,
  ];
}

final class ZbbBalanceSummary extends Equatable {
  const ZbbBalanceSummary({
    required this.incomePoolMinor,
    required this.categoryAssignedMinor,
    required this.taxReserveMinor,
    required this.savingsReserveMinor,
    required this.totalAssignedMinor,
    required this.unallocatedMinor,
  });

  final int incomePoolMinor;
  final int categoryAssignedMinor;
  final int taxReserveMinor;
  final int savingsReserveMinor;
  final int totalAssignedMinor;
  final int unallocatedMinor;

  bool get isBalanced => incomePoolMinor > 0 && unallocatedMinor == 0;
  bool get isOverAllocated => unallocatedMinor < 0;
  double get assignedRatio => incomePoolMinor > 0
      ? (totalAssignedMinor / incomePoolMinor).clamp(0.0, 1.0)
      : 0.0;

  @override
  List<Object?> get props => [
    incomePoolMinor,
    categoryAssignedMinor,
    taxReserveMinor,
    savingsReserveMinor,
    totalAssignedMinor,
    unallocatedMinor,
  ];
}

final class CaBudgetLineInput extends Equatable {
  const CaBudgetLineInput({
    required this.budgetId,
    required this.budgetName,
    required this.categoryId,
    required this.categoryName,
    required this.monthlyEquivalentLimitMinor,
  });

  final String budgetId;
  final String budgetName;
  final String categoryId;
  final String categoryName;
  final int monthlyEquivalentLimitMinor;

  @override
  List<Object?> get props => [
    budgetId,
    budgetName,
    categoryId,
    categoryName,
    monthlyEquivalentLimitMinor,
  ];
}

final class CaActualSpendInput extends Equatable {
  const CaActualSpendInput({
    required this.categoryId,
    required this.categoryName,
    required this.actualMinor,
  });

  final String categoryId;
  final String categoryName;
  final int actualMinor;

  @override
  List<Object?> get props => [categoryId, categoryName, actualMinor];
}

final class CaVarianceLineItem extends Equatable {
  const CaVarianceLineItem({
    required this.categoryId,
    required this.categoryName,
    required this.costClass,
    required this.budgetedMinor,
    required this.actualMinor,
    required this.varianceMinor,
    required this.variancePercent,
    required this.utilizationPercent,
    required this.expectedToDateMinor,
    required this.paceStatus,
    required this.projectedEndMinor,
    required this.projectedEndVarianceMinor,
    this.budgetId,
    this.budgetName,
  });

  final String categoryId;
  final String categoryName;
  final CaCostClass costClass;
  final String? budgetId;
  final String? budgetName;
  final int budgetedMinor;
  final int actualMinor;

  /// `budgetedMinor - actualMinor`. Positive/zero = Favorable `(F)`, negative = Unfavorable `(U)`.
  final int varianceMinor;
  final double variancePercent;
  final double utilizationPercent;
  final int expectedToDateMinor;

  /// `'ahead_favorable'` | `'on_pace'` | `'burning_fast'` | `'overspent'` | `'unbudgeted'`
  final String paceStatus;
  final int projectedEndMinor;
  final int projectedEndVarianceMinor;

  bool get isUnbudgeted => budgetedMinor <= 0 && actualMinor > 0;
  bool get isFavorable => !isUnbudgeted && varianceMinor >= 0;
  String get caCode => isFavorable ? 'F' : 'U';

  @override
  List<Object?> get props => [
    categoryId,
    categoryName,
    costClass,
    budgetId,
    budgetName,
    budgetedMinor,
    actualMinor,
    varianceMinor,
    variancePercent,
    utilizationPercent,
    expectedToDateMinor,
    paceStatus,
    projectedEndMinor,
    projectedEndVarianceMinor,
  ];
}

final class RebalanceSuggestion extends Equatable {
  const RebalanceSuggestion({
    required this.fromBudgetId,
    required this.fromCategoryId,
    required this.fromCategoryName,
    required this.toBudgetId,
    required this.toCategoryId,
    required this.toCategoryName,
    required this.suggestedTransferMinor,
    required this.donorSurplusMinor,
    required this.recipientDeficitMinor,
  });

  final String fromBudgetId;
  final String fromCategoryId;
  final String fromCategoryName;
  final String toBudgetId;
  final String toCategoryId;
  final String toCategoryName;
  final int suggestedTransferMinor;
  final int donorSurplusMinor;
  final int recipientDeficitMinor;

  @override
  List<Object?> get props => [
    fromBudgetId,
    fromCategoryId,
    fromCategoryName,
    toBudgetId,
    toCategoryId,
    toCategoryName,
    suggestedTransferMinor,
    donorSurplusMinor,
    recipientDeficitMinor,
  ];
}

final class CaVarianceStatement extends Equatable {
  const CaVarianceStatement({
    required this.currencyCode,
    required this.window,
    required this.periodIncomeMinor,
    required this.totalBudgetedMinor,
    required this.totalActualMinor,
    required this.totalVarianceMinor,
    required this.totalVariancePercent,
    required this.utilizationPercent,
    required this.expectedToDateMinor,
    required this.projectedEndMinor,
    required this.unbudgetedSpendMinor,
    required this.unbudgetedCategoryCount,
    required this.fixedNeedActualMinor,
    required this.variableWantActualMinor,
    required this.taxStatutoryActualMinor,
    required this.savingsCapexActualMinor,
    required this.lines,
    required this.rebalanceSuggestions,
  });

  final String currencyCode;
  final CaFiscalWindow window;
  final int periodIncomeMinor;
  final int totalBudgetedMinor;
  final int totalActualMinor;
  final int totalVarianceMinor;
  final double totalVariancePercent;
  final double utilizationPercent;
  final int expectedToDateMinor;
  final int projectedEndMinor;
  final int unbudgetedSpendMinor;
  final int unbudgetedCategoryCount;
  final int fixedNeedActualMinor;
  final int variableWantActualMinor;
  final int taxStatutoryActualMinor;
  final int savingsCapexActualMinor;
  final List<CaVarianceLineItem> lines;
  final List<RebalanceSuggestion> rebalanceSuggestions;

  bool get isNetFavorable => totalVarianceMinor >= 0;
  String get netCaCode => isNetFavorable ? 'F' : 'U';

  double get fixedCostSharePercent => totalActualMinor > 0
      ? (fixedNeedActualMinor * 100.0 / totalActualMinor)
      : 0.0;
  double get variableCostSharePercent => totalActualMinor > 0
      ? (variableWantActualMinor * 100.0 / totalActualMinor)
      : 0.0;

  @override
  List<Object?> get props => [
    currencyCode,
    window,
    periodIncomeMinor,
    totalBudgetedMinor,
    totalActualMinor,
    totalVarianceMinor,
    totalVariancePercent,
    utilizationPercent,
    expectedToDateMinor,
    projectedEndMinor,
    unbudgetedSpendMinor,
    unbudgetedCategoryCount,
    fixedNeedActualMinor,
    variableWantActualMinor,
    taxStatutoryActualMinor,
    savingsCapexActualMinor,
    lines,
    rebalanceSuggestions,
  ];
}

/// 100% Pure-Dart Chartered Accountant & CFO Budgeting Engine (`ADR-003`).
///
/// Uses integer minor-unit arithmetic exclusively so Variance Analysis (BvA),
/// Zero-Based Budgeting (ZBB), Safe-to-Spend liquidity waterfalls, and Sinking
/// Fund accruals remain exact, offline, and deterministic.
abstract final class CaBudgetPlannerEngine {
  static const _monthsShort = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static const _taxKeywords = [
    'tax',
    'gst',
    'vat',
    'tds',
    'cess',
    'statutory',
    'compliance',
    'audit',
    'ca fee',
    'accounting',
    'filing',
    'duty',
    'levy',
  ];

  static const _savingsCapexKeywords = [
    'saving',
    'invest',
    'sip',
    'mutual',
    'equity',
    'stock',
    'gold',
    'ppf',
    'nps',
    'fd',
    'rd',
    'deposit',
    'retirement',
    'emergency',
    'capex',
    'equipment',
    'reserve',
    'wealth',
    'profit',
  ];

  static const _fixedNeedKeywords = [
    'rent',
    'housing',
    'home',
    'mortgage',
    'emi',
    'loan',
    'debt',
    'grocer',
    'supermarket',
    'utility',
    'utilities',
    'bill',
    'electric',
    'water',
    'gas',
    'internet',
    'broadband',
    'wifi',
    'mobile',
    'phone',
    'health',
    'medical',
    'doctor',
    'pharmacy',
    'hospital',
    'insurance',
    'school',
    'tuition',
    'education',
    'transport',
    'commute',
    'fuel',
    'petrol',
    'diesel',
    'payroll',
    'salary',
    'office',
    'hosting',
    'cloud',
    'inventory',
    'supplier',
    'vendor',
    'logistics',
    'maintenance',
    'childcare',
  ];

  /// Classifies a category name into CA cost-behavior groups.
  static CaCostClass classifyCostClass(String categoryName) {
    final lower = categoryName.toLowerCase();
    for (final k in _taxKeywords) {
      if (lower.contains(k)) return CaCostClass.taxStatutory;
    }
    for (final k in _savingsCapexKeywords) {
      if (lower.contains(k)) return CaCostClass.savingsCapex;
    }
    for (final k in _fixedNeedKeywords) {
      if (lower.contains(k)) return CaCostClass.fixedNeed;
    }
    return CaCostClass.variableWant;
  }

  /// Resolves an Indian Financial Year (`fyStartMonth = 4`, Apr–Mar) or
  /// Calendar Year (`fyStartMonth = 1`, Jan–Dec) reporting window cleanly.
  static CaFiscalWindow resolveFiscalWindow({
    required DateTime nowUtc,
    required CaFiscalPeriodPreset preset,
    int fyStartMonth = 4,
  }) {
    final normalizedStart = fyStartMonth == 4 ? 4 : 1;
    final cycleLabel = normalizedStart == 4
        ? 'Indian FY (Apr–Mar)'
        : 'Calendar Year (Jan–Dec)';
    final todayEnd = DateTime.utc(
      nowUtc.year,
      nowUtc.month,
      nowUtc.day,
      23,
      59,
      59,
    );

    switch (preset) {
      case CaFiscalPeriodPreset.currentMonth:
        final from = DateTime.utc(nowUtc.year, nowUtc.month, 1);
        final to = DateTime.utc(nowUtc.year, nowUtc.month + 1, 0, 23, 59, 59);
        final totalDays = to.day;
        final elapsed = nowUtc.day.clamp(1, totalDays);
        final remaining = math.max(1, totalDays - elapsed + 1);
        return CaFiscalWindow(
          preset: preset,
          label: '${_monthsShort[nowUtc.month - 1]} ${nowUtc.year}',
          fiscalCycleLabel: cycleLabel,
          fromUtc: from,
          toUtc: to,
          elapsedDays: elapsed,
          totalDays: totalDays,
          remainingDays: remaining,
          monthlyBudgetMultiplier: 1,
          isCurrentOpenPeriod: true,
        );

      case CaFiscalPeriodPreset.previousMonth:
        final prevAnchor = DateTime.utc(nowUtc.year, nowUtc.month - 1, 1);
        final from = DateTime.utc(prevAnchor.year, prevAnchor.month, 1);
        final to = DateTime.utc(
          prevAnchor.year,
          prevAnchor.month + 1,
          0,
          23,
          59,
          59,
        );
        final totalDays = to.day;
        return CaFiscalWindow(
          preset: preset,
          label: '${_monthsShort[prevAnchor.month - 1]} ${prevAnchor.year}',
          fiscalCycleLabel: cycleLabel,
          fromUtc: from,
          toUtc: to,
          elapsedDays: totalDays,
          totalDays: totalDays,
          remainingDays: 0,
          monthlyBudgetMultiplier: 1,
          isCurrentOpenPeriod: false,
        );

      case CaFiscalPeriodPreset.currentQuarter:
        final offsetFromFyStart = (nowUtc.month - normalizedStart + 12) % 12;
        final quarterIndex = offsetFromFyStart ~/ 3; // 0..3 => Q1..Q4
        final fyStartYear = nowUtc.month >= normalizedStart
            ? nowUtc.year
            : nowUtc.year - 1;
        final qStartDate = DateTime.utc(
          fyStartYear,
          normalizedStart + (quarterIndex * 3),
          1,
        );
        final qEndDate = DateTime.utc(
          qStartDate.year,
          qStartDate.month + 3,
          0,
          23,
          59,
          59,
        );
        final totalDays = qEndDate.difference(qStartDate).inDays + 1;
        final elapsed = (todayEnd.difference(qStartDate).inDays + 1).clamp(
          1,
          totalDays,
        );
        final remaining = math.max(1, totalDays - elapsed + 1);
        final fyTag = normalizedStart == 4
            ? 'FY${((fyStartYear + 1) % 100).toString().padLeft(2, '0')}'
            : '${qStartDate.year}';
        final rangeTag =
            '${_monthsShort[qStartDate.month - 1]}–${_monthsShort[qEndDate.month - 1]}';
        return CaFiscalWindow(
          preset: preset,
          label: 'Q${quarterIndex + 1} $fyTag ($rangeTag)',
          fiscalCycleLabel: cycleLabel,
          fromUtc: qStartDate,
          toUtc: qEndDate,
          elapsedDays: elapsed,
          totalDays: totalDays,
          remainingDays: remaining,
          monthlyBudgetMultiplier: 3,
          isCurrentOpenPeriod: true,
        );

      case CaFiscalPeriodPreset.yearToDate:
        final fyStartYear = nowUtc.month >= normalizedStart
            ? nowUtc.year
            : nowUtc.year - 1;
        final from = DateTime.utc(fyStartYear, normalizedStart, 1);
        final to = DateTime.utc(nowUtc.year, nowUtc.month + 1, 0, 23, 59, 59);
        final totalDays = to.difference(from).inDays + 1;
        final elapsed = (todayEnd.difference(from).inDays + 1).clamp(
          1,
          totalDays,
        );
        final remaining = math.max(1, totalDays - elapsed + 1);
        final monthsElapsed =
            ((nowUtc.year - from.year) * 12) + (nowUtc.month - from.month) + 1;
        final fyTag = normalizedStart == 4
            ? 'FY${((fyStartYear + 1) % 100).toString().padLeft(2, '0')} YTD'
            : '${from.year} YTD';
        return CaFiscalWindow(
          preset: preset,
          label: '$fyTag ($monthsElapsed mo)',
          fiscalCycleLabel: cycleLabel,
          fromUtc: from,
          toUtc: to,
          elapsedDays: elapsed,
          totalDays: totalDays,
          remainingDays: remaining,
          monthlyBudgetMultiplier: math.max(1, monthsElapsed),
          isCurrentOpenPeriod: true,
        );
    }
  }

  /// Computes Accountant-grade True "Safe-to-Spend" (Open-to-Buy) liquidity
  /// after ring-fencing upcoming bills, due loan EMIs, tax provisions, and sinking funds.
  static SafeToSpendSnapshot computeSafeToSpend({
    required String currencyCode,
    required int liquidCashMinor,
    required int upcomingBillsMinor,
    required int upcomingEmisMinor,
    required int taxProvisionMinor,
    required int sinkingFundAccrualsMinor,
    required int remainingDaysInMonth,
  }) {
    final safeDays = math.max(1, remainingDaysInMonth);
    final bills = math.max(0, upcomingBillsMinor);
    final emis = math.max(0, upcomingEmisMinor);
    final tax = math.max(0, taxProvisionMinor);
    final sinking = math.max(0, sinkingFundAccrualsMinor);
    final committed = bills + emis + tax + sinking;
    final rawNet = liquidCashMinor - committed;
    final safeToSpend = math.max(0, rawNet);
    final dailySafe = safeToSpend ~/ safeDays;

    final String status;
    final String note;
    if (rawNet < 0) {
      status = 'crunch';
      final shortFmt = Money(
        amountMinor: -rawNet,
        currencyCode: currencyCode,
      ).format();
      note =
          'Committed bills, EMIs & provisions exceed liquid cash by $shortFmt — hold discretionary spend.';
    } else if (committed > 0 && safeToSpend < (committed * 0.25).round()) {
      status = 'tight';
      note =
          'Liquidity buffer is lean after upcoming obligations — stay strictly within your daily safe cap.';
    } else {
      status = 'comfortable';
      note = committed > 0
          ? 'All upcoming bills, EMIs & reserves are covered — remaining balance is genuinely free to spend.'
          : 'No pending bills or reserves deducting from cash — add recurring bills or goals for sharper liquidity tracking.';
    }

    return SafeToSpendSnapshot(
      currencyCode: currencyCode,
      liquidCashMinor: liquidCashMinor,
      upcomingBillsMinor: bills,
      upcomingEmisMinor: emis,
      taxProvisionMinor: tax,
      sinkingFundAccrualsMinor: sinking,
      committedObligationsMinor: committed,
      rawNetLiquidityMinor: rawNet,
      safeToSpendMinor: safeToSpend,
      dailySafeToSpendMinor: dailySafe,
      remainingDaysInMonth: safeDays,
      liquidityStatus: status,
      statusNote: note,
    );
  }

  /// Calculates required monthly sinking-fund accrual for a target goal date.
  static SinkingFundAccrual? computeSinkingFundAccrual({
    required String goalId,
    required String name,
    required int targetMinor,
    required int contributedMinor,
    required String? targetDateUtc,
    required DateTime nowUtc,
  }) {
    final remaining = targetMinor - contributedMinor;
    if (remaining <= 0 || targetDateUtc == null) return null;
    final due = DateTime.tryParse(targetDateUtc)?.toUtc();
    if (due == null) return null;
    final monthsDiff =
        ((due.year - nowUtc.year) * 12) +
        (due.month - nowUtc.month) +
        (due.day > nowUtc.day ? 1 : 0);
    final monthsRemaining = math.max(1, monthsDiff);
    final monthlyAccrual = (remaining + monthsRemaining - 1) ~/ monthsRemaining;
    return SinkingFundAccrual(
      goalId: goalId,
      name: name,
      targetMinor: targetMinor,
      contributedMinor: contributedMinor,
      remainingMinor: remaining,
      monthsRemaining: monthsRemaining,
      monthlyAccrualMinor: monthlyAccrual,
      targetDateIso: due.toIso8601String(),
    );
  }

  /// Generates a Zero-Based Budgeting (ZBB) allocation matrix across real profile
  /// categories such that `sum(categories) + taxReserve + savingsReserve == incomePool`.
  static ZbbGeneratedPlan generateZeroBasedPlan({
    required CaBudgetBlueprint blueprint,
    required int incomePoolMinor,
    required List<ZbbCategorySeed> categories,
    required String currencyCode,
    int? taxReserveBpsOverride,
  }) {
    final safeIncome = math.max(0, incomePoolMinor);
    final effectiveTaxBps = taxReserveBpsOverride ?? (blueprint.taxPct * 100);
    if (safeIncome == 0 || categories.isEmpty) {
      return ZbbGeneratedPlan(
        blueprint: blueprint,
        incomePoolMinor: safeIncome,
        taxReserveBps: effectiveTaxBps,
        taxReserveMinor: 0,
        savingsReserveMinor: 0,
        categoryAllocationsMinor: {for (final c in categories) c.categoryId: 0},
      );
    }

    final step = _friendlyRoundingStep(safeIncome, currencyCode);

    // Special mode: Copy Last Month Actuals (-5% discretionary trim).
    if (blueprint == CaBudgetBlueprint.copyLastMonth) {
      final hasPrev = categories.any((c) => c.previousMonthSpendMinor > 0);
      final rawMap = <String, int>{};
      var sumRaw = 0;
      for (final c in categories) {
        final base = hasPrev ? c.previousMonthSpendMinor : c.trailingSpendMinor;
        final costClass = classifyCostClass(c.categoryName);
        final factor = costClass == CaCostClass.variableWant ? 0.90 : 0.98;
        final v = base > 0 ? _roundToStep((base * factor).round(), step) : 0;
        rawMap[c.categoryId] = v;
        sumRaw += v;
      }

      final taxReserve = effectiveTaxBps > 0
          ? _roundToStep((safeIncome * effectiveTaxBps) ~/ 10000, step)
          : 0;
      final maxSpendable = math.max(0, safeIncome - taxReserve);

      if (sumRaw > 0) {
        final alloc = <String, int>{};
        var allocated = 0;
        final scale = sumRaw > maxSpendable ? (maxSpendable / sumRaw) : 1.0;
        for (final c in categories) {
          final scaled = ((rawMap[c.categoryId] ?? 0) * scale).round();
          alloc[c.categoryId] = scaled;
          allocated += scaled;
        }
        final savings = math.max(0, safeIncome - taxReserve - allocated);
        // Ensure zero remainder if rounding overshot by a few minor units.
        final diff = safeIncome - (allocated + taxReserve + savings);
        if (diff != 0) {
          final anchor = categories.first.categoryId;
          alloc[anchor] = math.max(0, (alloc[anchor] ?? 0) + diff);
        }
        return ZbbGeneratedPlan(
          blueprint: blueprint,
          incomePoolMinor: safeIncome,
          taxReserveBps: effectiveTaxBps,
          taxReserveMinor: taxReserve,
          savingsReserveMinor: savings,
          categoryAllocationsMinor: alloc,
        );
      }
      // Fallback to 50/30/20 when no prior-month history exists yet.
    }

    // Reserve Tax & Savings pools first (Pay Yourself & Taxman First!).
    final taxReserve = effectiveTaxBps > 0
        ? _roundToStep((safeIncome * effectiveTaxBps) ~/ 10000, step)
        : 0;
    final savingsTargetPct = blueprint.savingsPct;
    final rawSavings = (safeIncome * savingsTargetPct) ~/ 100;
    var savingsReserve = _roundToStep(rawSavings, step);
    if (taxReserve + savingsReserve > safeIncome) {
      savingsReserve = math.max(0, safeIncome - taxReserve);
    }

    final spendablePool = math.max(0, safeIncome - taxReserve - savingsReserve);

    // Partition categories into Needs-side vs Wants-side buckets.
    final needsCats = <ZbbCategorySeed>[];
    final wantsCats = <ZbbCategorySeed>[];
    for (final c in categories) {
      final cls = classifyCostClass(c.categoryName);
      if (cls == CaCostClass.fixedNeed || cls == CaCostClass.taxStatutory) {
        needsCats.add(c);
      } else {
        wantsCats.add(c);
      }
    }

    final totalBucketWeight = math.max(
      1,
      blueprint.needsPct + blueprint.wantsPct,
    );
    final int needsPool;
    final int wantsPool;
    if (needsCats.isEmpty) {
      needsPool = 0;
      wantsPool = spendablePool;
    } else if (wantsCats.isEmpty) {
      needsPool = spendablePool;
      wantsPool = 0;
    } else {
      needsPool = (spendablePool * blueprint.needsPct) ~/ totalBucketWeight;
      wantsPool = spendablePool - needsPool;
    }

    final alloc = <String, int>{for (final c in categories) c.categoryId: 0};

    _distributePoolAcrossCategories(
      poolMinor: needsPool,
      bucketCats: needsCats,
      step: step,
      out: alloc,
    );
    _distributePoolAcrossCategories(
      poolMinor: wantsPool,
      bucketCats: wantsCats,
      step: step,
      out: alloc,
    );

    // Guarantee exact Zero-Based Balance: assign any tiny rounding remainder
    // to savings (or primary category) so Unallocated == 0 strictly!
    final totalCats = alloc.values.fold<int>(0, (s, v) => s + v);
    final remainder = safeIncome - (totalCats + taxReserve + savingsReserve);
    if (remainder != 0) {
      if (savingsReserve + remainder >= 0) {
        savingsReserve += remainder;
      } else {
        final anchorId =
            (needsCats.isNotEmpty ? needsCats : categories).first.categoryId;
        alloc[anchorId] = math.max(0, (alloc[anchorId] ?? 0) + remainder);
      }
    }

    return ZbbGeneratedPlan(
      blueprint: blueprint,
      incomePoolMinor: safeIncome,
      taxReserveBps: effectiveTaxBps,
      taxReserveMinor: taxReserve,
      savingsReserveMinor: savingsReserve,
      categoryAllocationsMinor: alloc,
    );
  }

  /// Summarizes live Zero-Based Budget balance (`Unallocated = Income - Assigned`).
  static ZbbBalanceSummary summarizeZbbBalance({
    required int incomePoolMinor,
    required Map<String, int> categoryAllocationsMinor,
    required int taxReserveMinor,
    required int savingsReserveMinor,
  }) {
    final safeIncome = math.max(0, incomePoolMinor);
    final catAssigned = categoryAllocationsMinor.values.fold<int>(
      0,
      (s, v) => s + math.max(0, v),
    );
    final tax = math.max(0, taxReserveMinor);
    final sav = math.max(0, savingsReserveMinor);
    final totalAssigned = catAssigned + tax + sav;
    return ZbbBalanceSummary(
      incomePoolMinor: safeIncome,
      categoryAssignedMinor: catAssigned,
      taxReserveMinor: tax,
      savingsReserveMinor: sav,
      totalAssignedMinor: totalAssigned,
      unallocatedMinor: safeIncome - totalAssigned,
    );
  }

  /// Builds an institutional Chartered Accountant Budget vs. Actual (BvA) Variance Statement.
  static CaVarianceStatement buildVarianceStatement({
    required String currencyCode,
    required CaFiscalWindow window,
    required int periodIncomeMinor,
    required List<CaBudgetLineInput> budgetLines,
    required List<CaActualSpendInput> actualSpends,
    int? overallProfileMonthlyLimitMinor,
  }) {
    final mult = math.max(1, window.monthlyBudgetMultiplier);
    final elapsedRatio = window.elapsedRatio;

    // Aggregate budgets per categoryId.
    final budgetByCat =
        <
          String,
          ({int limit, String budgetId, String budgetName, String name})
        >{};
    for (final line in budgetLines) {
      final scaledLimit = line.monthlyEquivalentLimitMinor * mult;
      final existing = budgetByCat[line.categoryId];
      if (existing == null) {
        budgetByCat[line.categoryId] = (
          limit: scaledLimit,
          budgetId: line.budgetId,
          budgetName: line.budgetName,
          name: line.categoryName,
        );
      } else {
        budgetByCat[line.categoryId] = (
          limit: existing.limit + scaledLimit,
          budgetId: existing.budgetId,
          budgetName: existing.budgetName,
          name: existing.name,
        );
      }
    }

    final actualByCat = <String, ({int actual, String name})>{};
    for (final act in actualSpends) {
      if (act.actualMinor <= 0) continue;
      final existing = actualByCat[act.categoryId];
      actualByCat[act.categoryId] = (
        actual: (existing?.actual ?? 0) + act.actualMinor,
        name: act.categoryName,
      );
    }

    final allCatIds = <String>{...budgetByCat.keys, ...actualByCat.keys};
    final lines = <CaVarianceLineItem>[];

    var sumBudgetedLines = 0;
    var sumActual = 0;
    var unbudgetedSpend = 0;
    var unbudgetedCount = 0;
    var fixedActual = 0;
    var variableActual = 0;
    var taxActual = 0;
    var savingsActual = 0;

    for (final catId in allCatIds) {
      final b = budgetByCat[catId];
      final a = actualByCat[catId];
      final name = b?.name ?? a?.name ?? 'Uncategorized';
      final budgeted = b?.limit ?? 0;
      final actual = a?.actual ?? 0;
      if (budgeted <= 0 && actual <= 0) continue;

      final costClass = classifyCostClass(name);
      sumBudgetedLines += budgeted;
      sumActual += actual;

      switch (costClass) {
        case CaCostClass.fixedNeed:
          fixedActual += actual;
        case CaCostClass.variableWant:
          variableActual += actual;
        case CaCostClass.taxStatutory:
          taxActual += actual;
        case CaCostClass.savingsCapex:
          savingsActual += actual;
      }

      if (budgeted <= 0 && actual > 0) {
        unbudgetedSpend += actual;
        unbudgetedCount++;
      }

      final variance = budgeted - actual;
      final variancePct = budgeted > 0
          ? (variance * 100.0 / budgeted)
          : (actual > 0 ? -100.0 : 0.0);
      final utilPct = budgeted > 0 ? (actual * 100.0 / budgeted) : 100.0;
      final expectedToDate = (budgeted * elapsedRatio).round();
      final projectedEnd = window.isCurrentOpenPeriod && window.elapsedDays > 0
          ? ((actual * window.totalDays) / window.elapsedDays).round()
          : actual;
      final projectedVar = budgeted - projectedEnd;

      final String paceStatus;
      if (budgeted <= 0) {
        paceStatus = 'unbudgeted';
      } else if (actual > budgeted) {
        paceStatus = 'overspent';
      } else if (window.isCurrentOpenPeriod &&
          expectedToDate > 0 &&
          actual > (expectedToDate * 1.15).round()) {
        paceStatus = 'burning_fast';
      } else if (window.isCurrentOpenPeriod &&
          expectedToDate > 0 &&
          actual < (expectedToDate * 0.85).round()) {
        paceStatus = 'ahead_favorable';
      } else {
        paceStatus = 'on_pace';
      }

      lines.add(
        CaVarianceLineItem(
          categoryId: catId,
          categoryName: name,
          costClass: costClass,
          budgetId: b?.budgetId,
          budgetName: b?.budgetName,
          budgetedMinor: budgeted,
          actualMinor: actual,
          varianceMinor: variance,
          variancePercent: variancePct,
          utilizationPercent: utilPct,
          expectedToDateMinor: expectedToDate,
          paceStatus: paceStatus,
          projectedEndMinor: projectedEnd,
          projectedEndVarianceMinor: projectedVar,
        ),
      );
    }

    // Sort CA BvA rows: Unfavorable / Overspent first (most urgent), then Unbudgeted, then highest spend.
    lines.sort((a, b) {
      final aUrg = a.isFavorable ? 1 : 0;
      final bUrg = b.isFavorable ? 1 : 0;
      if (aUrg != bUrg) return aUrg.compareTo(bUrg);
      if (!a.isFavorable && !b.isFavorable) {
        return a.varianceMinor.compareTo(
          b.varianceMinor,
        ); // most negative first
      }
      return b.actualMinor.compareTo(a.actualMinor);
    });

    final totalBudgeted = sumBudgetedLines > 0
        ? sumBudgetedLines
        : ((overallProfileMonthlyLimitMinor ?? 0) * mult);
    final totalVariance = totalBudgeted - sumActual;
    final totalVarPct = totalBudgeted > 0
        ? (totalVariance * 100.0 / totalBudgeted)
        : 0.0;
    final totalUtilPct = totalBudgeted > 0
        ? (sumActual * 100.0 / totalBudgeted)
        : 0.0;
    final expectedTotal = (totalBudgeted * elapsedRatio).round();
    final projectedTotal = window.isCurrentOpenPeriod && window.elapsedDays > 0
        ? ((sumActual * window.totalDays) / window.elapsedDays).round()
        : sumActual;

    // Build smart Envelope Rebalance suggestions pairing overspent lines with surplus donor lines.
    final overspent = lines
        .where(
          (l) => !l.isUnbudgeted && l.varianceMinor < 0 && l.budgetId != null,
        )
        .toList();
    final donors =
        lines
            .where(
              (l) =>
                  !l.isUnbudgeted && l.varianceMinor > 0 && l.budgetId != null,
            )
            .toList()
          ..sort((a, b) => b.varianceMinor.compareTo(a.varianceMinor));

    final rebalance = <RebalanceSuggestion>[];
    if (overspent.isNotEmpty && donors.isNotEmpty) {
      for (final need in overspent.take(3)) {
        final donor = donors.firstWhere(
          (d) => d.categoryId != need.categoryId,
          orElse: () => donors.first,
        );
        if (donor.categoryId == need.categoryId) continue;
        final deficit = -need.varianceMinor;
        // Leave at least 1 minor unit in donor cap.
        final maxTransfer = math.max(0, donor.varianceMinor - 1);
        final transfer = math.min(deficit, maxTransfer);
        if (transfer > 0) {
          rebalance.add(
            RebalanceSuggestion(
              fromBudgetId: donor.budgetId!,
              fromCategoryId: donor.categoryId,
              fromCategoryName: donor.categoryName,
              toBudgetId: need.budgetId!,
              toCategoryId: need.categoryId,
              toCategoryName: need.categoryName,
              suggestedTransferMinor: transfer,
              donorSurplusMinor: donor.varianceMinor,
              recipientDeficitMinor: deficit,
            ),
          );
        }
      }
    }

    return CaVarianceStatement(
      currencyCode: currencyCode,
      window: window,
      periodIncomeMinor: periodIncomeMinor,
      totalBudgetedMinor: totalBudgeted,
      totalActualMinor: sumActual,
      totalVarianceMinor: totalVariance,
      totalVariancePercent: totalVarPct,
      utilizationPercent: totalUtilPct,
      expectedToDateMinor: expectedTotal,
      projectedEndMinor: projectedTotal,
      unbudgetedSpendMinor: unbudgetedSpend,
      unbudgetedCategoryCount: unbudgetedCount,
      fixedNeedActualMinor: fixedActual,
      variableWantActualMinor: variableActual,
      taxStatutoryActualMinor: taxActual,
      savingsCapexActualMinor: savingsActual,
      lines: lines,
      rebalanceSuggestions: rebalance,
    );
  }

  static void _distributePoolAcrossCategories({
    required int poolMinor,
    required List<ZbbCategorySeed> bucketCats,
    required int step,
    required Map<String, int> out,
  }) {
    if (poolMinor <= 0 || bucketCats.isEmpty) return;
    final totalWeight = bucketCats.fold<int>(
      0,
      (s, c) => s + math.max(0, c.trailingSpendMinor),
    );
    var distributed = 0;
    for (var i = 0; i < bucketCats.length; i++) {
      final c = bucketCats[i];
      if (i == bucketCats.length - 1) {
        out[c.categoryId] = math.max(0, poolMinor - distributed);
      } else {
        final rawShare = totalWeight > 0
            ? (poolMinor * math.max(0, c.trailingSpendMinor)) ~/ totalWeight
            : poolMinor ~/ bucketCats.length;
        final rounded = math.min(
          math.max(0, poolMinor - distributed),
          _roundToStep(rawShare, step),
        );
        out[c.categoryId] = rounded;
        distributed += rounded;
      }
    }
  }

  static int _friendlyRoundingStep(int referenceMinor, String currencyCode) {
    final spec = CurrencyCatalog.byCode(currencyCode);
    final unit = spec != null ? math.pow(10, spec.minorUnit).toInt() : 100;
    final major = referenceMinor ~/ math.max(1, unit);
    if (major >= 50000) return 500 * unit;
    if (major >= 10000) return 100 * unit;
    if (major >= 2000) return 50 * unit;
    if (major >= 200) return 10 * unit;
    return unit;
  }

  static int _roundToStep(int value, int step) {
    if (value <= 0) return 0;
    if (step <= 1) return value;
    return ((value + (step ~/ 2)) ~/ step) * step;
  }
}
