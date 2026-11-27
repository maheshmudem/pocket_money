import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import 'currency.dart';
import 'life_stage_planner_engine.dart';
import 'money.dart';

/// 50/30/20 personal/business spending classification bucket.
enum SpendBucket {
  needs('Needs', 'Essential bills, housing, groceries & health (Target 50%)'),
  wants('Wants', 'Dining, shopping, entertainment & lifestyle (Target 30%)'),
  savingsDebt(
    'Savings & Debt',
    'Investments, goals, reserves & debt payoff (Target 20%)',
  );

  const SpendBucket(this.label, this.description);
  final String label;
  final String description;
}

final class AdvisorExpenseEntry extends Equatable {
  const AdvisorExpenseEntry({
    required this.dateUtc,
    required this.amountMinor,
    required this.categoryName,
    required this.merchantLabel,
    this.categoryId,
  });

  final DateTime dateUtc;
  final int amountMinor;
  final String? categoryId;
  final String categoryName;
  final String merchantLabel;

  @override
  List<Object?> get props => [
    dateUtc,
    amountMinor,
    categoryId,
    categoryName,
    merchantLabel,
  ];
}

final class AdvisorIncomeEntry extends Equatable {
  const AdvisorIncomeEntry({
    required this.dateUtc,
    required this.amountMinor,
    required this.categoryName,
  });

  final DateTime dateUtc;
  final int amountMinor;
  final String categoryName;

  @override
  List<Object?> get props => [dateUtc, amountMinor, categoryName];
}

final class AdvisorActiveBudget extends Equatable {
  const AdvisorActiveBudget({
    required this.id,
    required this.name,
    required this.overallLimitMinor,
    required this.spentMinor,
    required this.categoryIds,
  });

  final String id;
  final String name;
  final int overallLimitMinor;
  final int spentMinor;
  final List<String> categoryIds;

  bool get isOverall => categoryIds.isEmpty;

  @override
  List<Object?> get props => [
    id,
    name,
    overallLimitMinor,
    spentMinor,
    categoryIds,
  ];
}

final class CfoAdvisorInput extends Equatable {
  const CfoAdvisorInput({
    required this.currencyCode,
    required this.nowUtc,
    required this.expenses,
    required this.incomes,
    required this.activeBudgets,
    this.selectedYearMonth,
    this.totalLiquidAssetsMinor = 0,
  });

  final String currencyCode;
  final DateTime nowUtc;
  final String? selectedYearMonth; // YYYY-MM; defaults to current month
  final List<AdvisorExpenseEntry> expenses;
  final List<AdvisorIncomeEntry> incomes;
  final List<AdvisorActiveBudget> activeBudgets;
  final int totalLiquidAssetsMinor;

  @override
  List<Object?> get props => [
    currencyCode,
    nowUtc,
    selectedYearMonth,
    expenses,
    incomes,
    activeBudgets,
    totalLiquidAssetsMinor,
  ];
}

final class AdvisorMonthOption extends Equatable {
  const AdvisorMonthOption({
    required this.yearMonth,
    required this.shortLabel,
    required this.fullLabel,
    required this.totalSpendMinor,
    required this.totalIncomeMinor,
  });

  final String yearMonth;
  final String shortLabel;
  final String fullLabel;
  final int totalSpendMinor;
  final int totalIncomeMinor;

  @override
  List<Object?> get props => [
    yearMonth,
    shortLabel,
    fullLabel,
    totalSpendMinor,
    totalIncomeMinor,
  ];
}

final class CategoryAuditItem extends Equatable {
  const CategoryAuditItem({
    required this.categoryName,
    required this.bucket,
    required this.spendMinor,
    required this.sharePercent,
    required this.trailingAvgMinor,
    required this.txCount,
    required this.isSpike,
    this.categoryId,
    this.deltaVsAvgPercent,
  });

  final String? categoryId;
  final String categoryName;
  final SpendBucket bucket;
  final int spendMinor;
  final double sharePercent;
  final int trailingAvgMinor;
  final double? deltaVsAvgPercent;
  final int txCount;
  final bool isSpike;

  @override
  List<Object?> get props => [
    categoryId,
    categoryName,
    bucket,
    spendMinor,
    sharePercent,
    trailingAvgMinor,
    deltaVsAvgPercent,
    txCount,
    isSpike,
  ];
}

final class TopMerchantItem extends Equatable {
  const TopMerchantItem({
    required this.label,
    required this.totalMinor,
    required this.txCount,
    required this.averageMinor,
    required this.sharePercent,
    required this.primaryCategory,
  });

  final String label;
  final int totalMinor;
  final int txCount;
  final int averageMinor;
  final double sharePercent;
  final String primaryCategory;

  @override
  List<Object?> get props => [
    label,
    totalMinor,
    txCount,
    averageMinor,
    sharePercent,
    primaryCategory,
  ];
}

final class MoneyLeakItem extends Equatable {
  const MoneyLeakItem({
    required this.label,
    required this.categoryName,
    required this.txCount,
    required this.totalMinor,
    required this.averageMinor,
    required this.annualizedMinor,
    required this.potentialAnnualSavingMinor,
  });

  final String label;
  final String categoryName;
  final int txCount;
  final int totalMinor;
  final int averageMinor;
  final int annualizedMinor;
  final int potentialAnnualSavingMinor;

  @override
  List<Object?> get props => [
    label,
    categoryName,
    txCount,
    totalMinor,
    averageMinor,
    annualizedMinor,
    potentialAnnualSavingMinor,
  ];
}

final class WeekendBurnInsight extends Equatable {
  const WeekendBurnInsight({
    required this.weekdayDailyAvgMinor,
    required this.weekendDailyAvgMinor,
    required this.weekendSharePercent,
    required this.weekendMultiplier,
    required this.suggestedWeekendDailyCapMinor,
  });

  final int weekdayDailyAvgMinor;
  final int weekendDailyAvgMinor;
  final double weekendSharePercent;
  final double weekendMultiplier;
  final int suggestedWeekendDailyCapMinor;

  bool get isWeekendHeavy =>
      weekendDailyAvgMinor > 0 && weekendMultiplier >= 1.35;

  @override
  List<Object?> get props => [
    weekdayDailyAvgMinor,
    weekendDailyAvgMinor,
    weekendSharePercent,
    weekendMultiplier,
    suggestedWeekendDailyCapMinor,
  ];
}

final class Rule503020Snapshot extends Equatable {
  const Rule503020Snapshot({
    required this.needsMinor,
    required this.wantsMinor,
    required this.savingsMinor,
    required this.needsPct,
    required this.wantsPct,
    required this.savingsPct,
    required this.hasIncomeBasis,
  });

  final int needsMinor;
  final int wantsMinor;
  final int savingsMinor;
  final double needsPct;
  final double wantsPct;
  final double savingsPct;
  final bool hasIncomeBasis;

  @override
  List<Object?> get props => [
    needsMinor,
    wantsMinor,
    savingsMinor,
    needsPct,
    wantsPct,
    savingsPct,
    hasIncomeBasis,
  ];
}

final class SuggestedCategoryBudget extends Equatable {
  const SuggestedCategoryBudget({
    required this.categoryName,
    required this.bucket,
    required this.currentSpendMinor,
    required this.trailingAvgMinor,
    required this.suggestedLimitMinor,
    required this.potentialMonthlySavingMinor,
    required this.rationale,
    required this.alreadyBudgeted,
    this.categoryId,
  });

  final String? categoryId;
  final String categoryName;
  final SpendBucket bucket;
  final int currentSpendMinor;
  final int trailingAvgMinor;
  final int suggestedLimitMinor;
  final int potentialMonthlySavingMinor;
  final String rationale;
  final bool alreadyBudgeted;

  @override
  List<Object?> get props => [
    categoryId,
    categoryName,
    bucket,
    currentSpendMinor,
    trailingAvgMinor,
    suggestedLimitMinor,
    potentialMonthlySavingMinor,
    rationale,
    alreadyBudgeted,
  ];
}

final class BudgetRecommendationPlan extends Equatable {
  const BudgetRecommendationPlan({
    required this.methodologyLabel,
    required this.methodologyNote,
    required this.recommendedOverallLimitMinor,
    required this.estimatedMonthlySavingsMinor,
    required this.dailySafeTargetMinor,
    required this.weeklyEnvelopeMinor,
    required this.hasOverallBudgetAlready,
    required this.categorySuggestions,
  });

  final String methodologyLabel;
  final String methodologyNote;
  final int recommendedOverallLimitMinor;
  final int estimatedMonthlySavingsMinor;
  final int dailySafeTargetMinor;
  final int weeklyEnvelopeMinor;
  final bool hasOverallBudgetAlready;
  final List<SuggestedCategoryBudget> categorySuggestions;

  @override
  List<Object?> get props => [
    methodologyLabel,
    methodologyNote,
    recommendedOverallLimitMinor,
    estimatedMonthlySavingsMinor,
    dailySafeTargetMinor,
    weeklyEnvelopeMinor,
    hasOverallBudgetAlready,
    categorySuggestions,
  ];
}

final class MaintenanceTip extends Equatable {
  const MaintenanceTip({
    required this.title,
    required this.detail,
    required this.priority,
    this.impactLabel,
  });

  final String title;
  final String detail;
  final String? impactLabel;
  final int priority;

  @override
  List<Object?> get props => [title, detail, impactLabel, priority];
}

final class CfoAdvisorReport extends Equatable {
  const CfoAdvisorReport({
    required this.currencyCode,
    required this.selectedYearMonth,
    required this.selectedMonthLabel,
    required this.isCurrentMonth,
    required this.availableMonths,
    required this.monthSpendMinor,
    required this.monthIncomeMinor,
    required this.previousMonthSpendMinor,
    required this.trailingThreeMonthAvgSpendMinor,
    required this.projectedMonthEndSpendMinor,
    required this.elapsedDaysInMonth,
    required this.totalDaysInMonth,
    required this.remainingDaysInMonth,
    required this.dailyAverageSpendMinor,
    required this.activeOverallBudgetLimitMinor,
    required this.paceStatus,
    required this.categories,
    required this.topMerchants,
    required this.moneyLeaks,
    required this.weekendBurn,
    required this.rule503020,
    required this.budgetPlan,
    required this.maintenanceTips,
    this.momSpendDeltaPercent,
  });

  final String currencyCode;
  final String selectedYearMonth;
  final String selectedMonthLabel;
  final bool isCurrentMonth;
  final List<AdvisorMonthOption> availableMonths;
  final int monthSpendMinor;
  final int monthIncomeMinor;
  final int previousMonthSpendMinor;
  final int trailingThreeMonthAvgSpendMinor;
  final int projectedMonthEndSpendMinor;
  final int elapsedDaysInMonth;
  final int totalDaysInMonth;
  final int remainingDaysInMonth;
  final int dailyAverageSpendMinor;
  final int? activeOverallBudgetLimitMinor;
  final String paceStatus; // 'no_data' | 'on_track' | 'watch' | 'overspending'
  final double? momSpendDeltaPercent;
  final List<CategoryAuditItem> categories;
  final List<TopMerchantItem> topMerchants;
  final List<MoneyLeakItem> moneyLeaks;
  final WeekendBurnInsight weekendBurn;
  final Rule503020Snapshot rule503020;
  final BudgetRecommendationPlan budgetPlan;
  final List<MaintenanceTip> maintenanceTips;

  int get netSavedMinor => monthIncomeMinor - monthSpendMinor;
  double get savingsRatePercent => monthIncomeMinor > 0
      ? ((monthIncomeMinor - monthSpendMinor) * 100.0 / monthIncomeMinor)
      : 0.0;
  bool get hasActivity => monthSpendMinor > 0 || monthIncomeMinor > 0;

  @override
  List<Object?> get props => [
    currencyCode,
    selectedYearMonth,
    selectedMonthLabel,
    isCurrentMonth,
    availableMonths,
    monthSpendMinor,
    monthIncomeMinor,
    previousMonthSpendMinor,
    trailingThreeMonthAvgSpendMinor,
    projectedMonthEndSpendMinor,
    elapsedDaysInMonth,
    totalDaysInMonth,
    remainingDaysInMonth,
    dailyAverageSpendMinor,
    activeOverallBudgetLimitMinor,
    paceStatus,
    momSpendDeltaPercent,
    categories,
    topMerchants,
    moneyLeaks,
    weekendBurn,
    rule503020,
    budgetPlan,
    maintenanceTips,
  ];
}

final class CoachBudgetAction extends Equatable {
  const CoachBudgetAction({
    required this.name,
    required this.limitMinor,
    this.categoryId,
    this.categoryName,
  });

  final String name;
  final int limitMinor;
  final String? categoryId;
  final String? categoryName;

  @override
  List<Object?> get props => [name, limitMinor, categoryId, categoryName];
}

final class CoachMetricChip extends Equatable {
  const CoachMetricChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  List<Object?> get props => [label, value];
}

final class CoachReply extends Equatable {
  const CoachReply({
    required this.headline,
    required this.summary,
    this.metrics = const [],
    this.actionSteps = const [],
    this.budgetAction,
  });

  final String headline;
  final String summary;
  final List<CoachMetricChip> metrics;
  final List<String> actionSteps;
  final CoachBudgetAction? budgetAction;

  @override
  List<Object?> get props => [
    headline,
    summary,
    metrics,
    actionSteps,
    budgetAction,
  ];
}

/// 100% Pure-Dart, Zero-Cost, On-Device Financial Intelligence & Budget Coach.
///
/// Combines proven deterministic financial & statistical algorithms:
/// - **50 / 30 / 20 Adaptive Rule** (Needs / Wants / Savings classification)
/// - **Weighted Moving Average (WMA)** baseline & **End-of-Month Pace Forecast**
/// - **Statistical Spike Detection** (current spend vs trailing 3-month baseline)
/// - **Pareto 80/20 Concentration & Merchant Ranking** ("what you spend most on")
/// - **High-Frequency Money Leak Detector** (small recurring drains annualized)
/// - **Weekday vs Weekend Burn Analysis**
/// - **Offline Natural-Language Financial Q&A Engine** (zero API cost, zero cloud leak)
abstract final class CfoAdvisorEngine {
  static const _shortMonths = [
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

  static const _fullMonths = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// Classifies a category name into Needs (50%), Wants (30%), or Savings/Debt (20%).
  static SpendBucket classifyCategory(String categoryName) {
    final lower = categoryName.toLowerCase();
    if (_matchesAny(lower, const [
      'saving',
      'invest',
      'sip',
      'mutual',
      'stock',
      'fd',
      'rd',
      'debt',
      'loan',
      'emi',
      'repay',
      'reserve',
      'emergency',
      'gold',
      'retire',
      'ppf',
      'nps',
    ])) {
      return SpendBucket.savingsDebt;
    }
    if (_matchesAny(lower, const [
      'rent',
      'housing',
      'mortgage',
      'grocer',
      'supermarket',
      'utilit',
      'electric',
      'water',
      'gas',
      'internet',
      'broadband',
      'mobile',
      'phone',
      'bill',
      'health',
      'medical',
      'pharma',
      'doctor',
      'hospital',
      'insur',
      'educat',
      'school',
      'tuition',
      'child',
      'tax',
      'fuel',
      'commut',
      'transport',
      'payroll',
      'office',
      'supplier',
      'software',
    ])) {
      return SpendBucket.needs;
    }
    return SpendBucket.wants;
  }

  /// Rounds a raw minor-unit target to a clean, human-friendly budget step
  /// (e.g., nearest 100 or 500 major units) while staying >= 1 major unit.
  static int roundFriendlyBudget(int rawMinor, String currencyCode) {
    if (rawMinor <= 0) return 0;
    final factor = CurrencyCatalog.byCode(currencyCode)?.minorFactor ?? 100;
    final major = rawMinor / factor;
    final double step;
    if (major >= 50000) {
      step = 1000;
    } else if (major >= 10000) {
      step = 500;
    } else if (major >= 2000) {
      step = 250;
    } else if (major >= 500) {
      step = 100;
    } else if (major >= 100) {
      step = 50;
    } else {
      step = 10;
    }
    final roundedMajor = math.max(step, (major / step).round() * step);
    return (roundedMajor * factor).round();
  }

  /// Computes a full monthly spend audit, smart budget plan, and maintenance playbook.
  static CfoAdvisorReport analyze(CfoAdvisorInput input) {
    final now = input.nowUtc.toUtc();
    final currentYm = _ymKey(now.year, now.month);

    // 1. Build trailing 6-month timeline options (newest -> oldest).
    final spendByYm = <String, int>{};
    final incomeByYm = <String, int>{};
    for (final e in input.expenses) {
      if (e.amountMinor <= 0) continue;
      final ym = _ymKey(e.dateUtc.toUtc().year, e.dateUtc.toUtc().month);
      spendByYm[ym] = (spendByYm[ym] ?? 0) + e.amountMinor;
    }
    for (final i in input.incomes) {
      if (i.amountMinor <= 0) continue;
      final ym = _ymKey(i.dateUtc.toUtc().year, i.dateUtc.toUtc().month);
      incomeByYm[ym] = (incomeByYm[ym] ?? 0) + i.amountMinor;
    }

    final availableMonths = <AdvisorMonthOption>[];
    for (var offset = 0; offset < 6; offset++) {
      final dt = DateTime.utc(now.year, now.month - offset, 1);
      final ym = _ymKey(dt.year, dt.month);
      availableMonths.add(
        AdvisorMonthOption(
          yearMonth: ym,
          shortLabel: '${_shortMonths[dt.month - 1]} ${dt.year % 100}',
          fullLabel: '${_fullMonths[dt.month - 1]} ${dt.year}',
          totalSpendMinor: spendByYm[ym] ?? 0,
          totalIncomeMinor: incomeByYm[ym] ?? 0,
        ),
      );
    }

    final selectedYm =
        (input.selectedYearMonth != null &&
            availableMonths.any((m) => m.yearMonth == input.selectedYearMonth))
        ? input.selectedYearMonth!
        : currentYm;
    final selectedOption = availableMonths.firstWhere(
      (m) => m.yearMonth == selectedYm,
    );
    final selectedParts = selectedYm.split('-');
    final selYear = int.parse(selectedParts[0]);
    final selMonth = int.parse(selectedParts[1]);
    final isCurrentMonth = selectedYm == currentYm;

    final totalDaysInMonth = DateTime.utc(selYear, selMonth + 1, 0).day;
    final elapsedDays = isCurrentMonth
        ? now.day.clamp(1, totalDaysInMonth)
        : totalDaysInMonth;
    final remainingDays = isCurrentMonth
        ? (totalDaysInMonth - now.day + 1).clamp(1, totalDaysInMonth)
        : 0;

    // Prior 3 months relative to selected month for weighted moving average & spikes.
    final prevMonthKeys = <String>[
      for (var k = 1; k <= 3; k++)
        _ymKey(
          DateTime.utc(selYear, selMonth - k, 1).year,
          DateTime.utc(selYear, selMonth - k, 1).month,
        ),
    ];
    final prevYm = prevMonthKeys.first;

    // 2. Filter selected month entries & build trailing category histories.
    final selExpenses = <AdvisorExpenseEntry>[];
    final selIncomes = <AdvisorIncomeEntry>[];
    final catHistoryByYm = <String, Map<String, int>>{}; // catName -> ym -> amt
    final catIdByName = <String, String?>{};

    for (final e in input.expenses) {
      if (e.amountMinor <= 0) continue;
      final dt = e.dateUtc.toUtc();
      final ym = _ymKey(dt.year, dt.month);
      catIdByName[e.categoryName] ??= e.categoryId;
      if (ym == selectedYm) {
        selExpenses.add(e);
      } else if (prevMonthKeys.contains(ym)) {
        final byYm = catHistoryByYm.putIfAbsent(e.categoryName, () => {});
        byYm[ym] = (byYm[ym] ?? 0) + e.amountMinor;
      }
    }
    for (final i in input.incomes) {
      if (i.amountMinor <= 0) continue;
      final dt = i.dateUtc.toUtc();
      if (_ymKey(dt.year, dt.month) == selectedYm) {
        selIncomes.add(i);
      }
    }

    final monthSpend = selExpenses.fold<int>(0, (s, e) => s + e.amountMinor);
    final monthIncome = selIncomes.fold<int>(0, (s, i) => s + i.amountMinor);
    final prevMonthSpend = spendByYm[prevYm] ?? 0;

    // Weighted moving average across non-zero trailing months (weights 0.5 / 0.3 / 0.2).
    final trailingSpendWma = _weightedHistoryAverage(prevMonthKeys, spendByYm);
    final trailingIncomeWma = _weightedHistoryAverage(
      prevMonthKeys,
      incomeByYm,
    );

    final double? momDeltaPct = prevMonthSpend > 0
        ? ((monthSpend - prevMonthSpend) * 100.0 / prevMonthSpend)
        : null;

    final dailyAvg = elapsedDays > 0 ? (monthSpend ~/ elapsedDays) : 0;
    final int projectedEndOfMonth;
    if (!isCurrentMonth) {
      projectedEndOfMonth = monthSpend;
    } else if (monthSpend == 0) {
      projectedEndOfMonth = 0;
    } else {
      final linearProj = (monthSpend * totalDaysInMonth) ~/ elapsedDays;
      // Early in the month (days 1-5), blend linear run-rate with trailing baseline
      // so a single rent payment on day 1 doesn't forecast 30x rent!
      if (elapsedDays <= 5 && trailingSpendWma > 0) {
        final weightLinear = elapsedDays / 10.0;
        projectedEndOfMonth =
            (linearProj * weightLinear +
                    trailingSpendWma * (1.0 - weightLinear))
                .round();
      } else {
        projectedEndOfMonth = linearProj;
      }
    }

    // 3. Category Pareto Audit + Spike Detection.
    final selCatTotals = <String, int>{};
    final selCatCounts = <String, int>{};
    for (final e in selExpenses) {
      selCatTotals[e.categoryName] =
          (selCatTotals[e.categoryName] ?? 0) + e.amountMinor;
      selCatCounts[e.categoryName] = (selCatCounts[e.categoryName] ?? 0) + 1;
    }

    final categories = <CategoryAuditItem>[];
    for (final entry in selCatTotals.entries) {
      final name = entry.key;
      final amt = entry.value;
      final hist = catHistoryByYm[name] ?? const {};
      final avg = _weightedHistoryAverage(prevMonthKeys, hist);
      final double? deltaPct = avg > 0 ? ((amt - avg) * 100.0 / avg) : null;
      final isSpike = deltaPct != null && deltaPct >= 25.0 && amt > 0;
      categories.add(
        CategoryAuditItem(
          categoryId: catIdByName[name],
          categoryName: name,
          bucket: classifyCategory(name),
          spendMinor: amt,
          sharePercent: monthSpend > 0 ? (amt * 100.0 / monthSpend) : 0.0,
          trailingAvgMinor: avg,
          deltaVsAvgPercent: deltaPct,
          txCount: selCatCounts[name] ?? 0,
          isSpike: isSpike,
        ),
      );
    }
    categories.sort((a, b) => b.spendMinor.compareTo(a.spendMinor));

    // 4. Top Things / Merchants You Spend Most On.
    final merchTotals = <String, int>{};
    final merchCounts = <String, int>{};
    final merchCatCounts = <String, Map<String, int>>{};
    final merchDisplay = <String, String>{};

    for (final e in selExpenses) {
      final clean = e.merchantLabel.trim().isEmpty
          ? e.categoryName
          : e.merchantLabel.trim();
      final key = clean.toLowerCase();
      merchDisplay[key] ??= clean;
      merchTotals[key] = (merchTotals[key] ?? 0) + e.amountMinor;
      merchCounts[key] = (merchCounts[key] ?? 0) + 1;
      final catMap = merchCatCounts.putIfAbsent(key, () => {});
      catMap[e.categoryName] = (catMap[e.categoryName] ?? 0) + e.amountMinor;
    }

    final topMerchants = <TopMerchantItem>[];
    for (final entry in merchTotals.entries) {
      final key = entry.key;
      final total = entry.value;
      final count = merchCounts[key] ?? 1;
      final topCat =
          (merchCatCounts[key]?.entries.toList()
                ?..sort((a, b) => b.value.compareTo(a.value)))
              ?.firstOrNull
              ?.key ??
          'General';
      topMerchants.add(
        TopMerchantItem(
          label: merchDisplay[key]!,
          totalMinor: total,
          txCount: count,
          averageMinor: total ~/ count,
          sharePercent: monthSpend > 0 ? (total * 100.0 / monthSpend) : 0.0,
          primaryCategory: topCat,
        ),
      );
    }
    topMerchants.sort((a, b) => b.totalMinor.compareTo(a.totalMinor));

    // 5. Hidden Money Leaks (frequent discretionary small drains >= 3x/month).
    final moneyLeaks = <MoneyLeakItem>[];
    for (final m in topMerchants) {
      final bucket = classifyCategory(m.primaryCategory);
      final isSmallTicket =
          monthSpend > 0 && (m.averageMinor <= (monthSpend * 0.20));
      if (m.txCount >= 3 && bucket == SpendBucket.wants && isSmallTicket) {
        final annualized = m.totalMinor * 12;
        moneyLeaks.add(
          MoneyLeakItem(
            label: m.label,
            categoryName: m.primaryCategory,
            txCount: m.txCount,
            totalMinor: m.totalMinor,
            averageMinor: m.averageMinor,
            annualizedMinor: annualized,
            potentialAnnualSavingMinor: (annualized * 0.30).round(),
          ),
        );
      }
    }
    moneyLeaks.sort((a, b) => b.totalMinor.compareTo(a.totalMinor));

    // 6. Weekday vs Weekend Burn Pattern.
    var weekdayTotal = 0;
    var weekendTotal = 0;
    final weekdayDates = <int>{};
    final weekendDates = <int>{};
    for (final e in selExpenses) {
      final localLike = e.dateUtc.toUtc();
      final wd = localLike.weekday;
      if (wd == DateTime.friday ||
          wd == DateTime.saturday ||
          wd == DateTime.sunday) {
        weekendTotal += e.amountMinor;
        weekendDates.add(localLike.day);
      } else {
        weekdayTotal += e.amountMinor;
        weekdayDates.add(localLike.day);
      }
    }
    // Count actual weekdays & weekend days elapsed in this month for fair daily averages.
    var elapsedWeekdays = 0;
    var elapsedWeekendDays = 0;
    for (var day = 1; day <= elapsedDays; day++) {
      final wd = DateTime.utc(selYear, selMonth, day).weekday;
      if (wd == DateTime.friday ||
          wd == DateTime.saturday ||
          wd == DateTime.sunday) {
        elapsedWeekendDays++;
      } else {
        elapsedWeekdays++;
      }
    }
    final wdAvg = elapsedWeekdays > 0 ? weekdayTotal ~/ elapsedWeekdays : 0;
    final weAvg = elapsedWeekendDays > 0
        ? weekendTotal ~/ elapsedWeekendDays
        : 0;
    final weShare = monthSpend > 0 ? (weekendTotal * 100.0 / monthSpend) : 0.0;
    final weMultiplier = wdAvg > 0 ? (weAvg / wdAvg) : (weAvg > 0 ? 2.0 : 1.0);
    final suggestedWeCap = weAvg > 0
        ? roundFriendlyBudget((weAvg * 0.80).round(), input.currencyCode)
        : 0;
    final weekendBurn = WeekendBurnInsight(
      weekdayDailyAvgMinor: wdAvg,
      weekendDailyAvgMinor: weAvg,
      weekendSharePercent: weShare,
      weekendMultiplier: weMultiplier,
      suggestedWeekendDailyCapMinor: suggestedWeCap,
    );

    // 7. 50 / 30 / 20 Actual Breakdown.
    var needsMinor = 0;
    var wantsMinor = 0;
    var explicitSavingsDebtMinor = 0;
    for (final c in categories) {
      switch (c.bucket) {
        case SpendBucket.needs:
          needsMinor += c.spendMinor;
        case SpendBucket.wants:
          wantsMinor += c.spendMinor;
        case SpendBucket.savingsDebt:
          explicitSavingsDebtMinor += c.spendMinor;
      }
    }
    final incomeBasis = monthIncome > 0 ? monthIncome : trailingIncomeWma;
    final hasIncomeBasis = incomeBasis > 0;
    final netSurplus = math.max(0, monthIncome - monthSpend);
    final effectiveSavings = explicitSavingsDebtMinor + netSurplus;
    final denom = hasIncomeBasis
        ? math.max(monthIncome, monthSpend)
        : math.max(1, monthSpend);
    final rule503020 = Rule503020Snapshot(
      needsMinor: needsMinor,
      wantsMinor: wantsMinor,
      savingsMinor: effectiveSavings,
      needsPct: denom > 0 ? (needsMinor * 100.0 / denom) : 0.0,
      wantsPct: denom > 0 ? (wantsMinor * 100.0 / denom) : 0.0,
      savingsPct: hasIncomeBasis && denom > 0
          ? (effectiveSavings * 100.0 / denom)
          : 0.0,
      hasIncomeBasis: hasIncomeBasis,
    );

    // 8. Active Overall Budget & Pace Status.
    final overallBudgets = input.activeBudgets
        .where((b) => b.isOverall)
        .toList();
    final int? activeOverallLimit = overallBudgets.isNotEmpty
        ? overallBudgets.fold<int>(0, (s, b) => s + b.overallLimitMinor)
        : null;
    final budgetedCatIds = <String>{
      for (final b in input.activeBudgets) ...b.categoryIds,
    };

    final String paceStatus;
    if (monthSpend == 0 && monthIncome == 0) {
      paceStatus = 'no_data';
    } else if (activeOverallLimit != null && activeOverallLimit > 0) {
      final projRatio = projectedEndOfMonth / activeOverallLimit;
      paceStatus = projRatio > 1.05
          ? 'overspending'
          : projRatio >= 0.85
          ? 'watch'
          : 'on_track';
    } else if (monthIncome > 0) {
      final projRatio = projectedEndOfMonth / monthIncome;
      paceStatus = projRatio > 0.90
          ? 'overspending'
          : projRatio >= 0.78
          ? 'watch'
          : 'on_track';
    } else if (trailingSpendWma > 0) {
      final projRatio = projectedEndOfMonth / trailingSpendWma;
      paceStatus = projRatio > 1.15
          ? 'overspending'
          : projRatio >= 0.95
          ? 'watch'
          : 'on_track';
    } else {
      paceStatus = 'on_track';
    }

    // 9. Smart Adaptive Budget Recommendation Engine.
    final budgetPlan = _buildBudgetPlan(
      currencyCode: input.currencyCode,
      monthSpend: monthSpend,
      projectedMonthEnd: projectedEndOfMonth,
      monthIncome: monthIncome,
      trailingSpendWma: trailingSpendWma,
      trailingIncomeWma: trailingIncomeWma,
      totalDaysInMonth: totalDaysInMonth,
      categories: categories,
      catHistoryByYm: catHistoryByYm,
      catIdByName: catIdByName,
      prevMonthKeys: prevMonthKeys,
      hasOverallBudgetAlready: activeOverallLimit != null,
      budgetedCatIds: budgetedCatIds,
    );

    // 10. Personalized "How to Maintain Your Budget" Coaching Playbook.
    final tips = _buildMaintenanceTips(
      currencyCode: input.currencyCode,
      monthSpend: monthSpend,
      monthIncome: monthIncome,
      projectedEndOfMonth: projectedEndOfMonth,
      remainingDays: remainingDays,
      activeOverallLimit: activeOverallLimit,
      categories: categories,
      moneyLeaks: moneyLeaks,
      weekendBurn: weekendBurn,
      rule503020: rule503020,
      budgetPlan: budgetPlan,
    );

    return CfoAdvisorReport(
      currencyCode: input.currencyCode,
      selectedYearMonth: selectedYm,
      selectedMonthLabel: selectedOption.fullLabel,
      isCurrentMonth: isCurrentMonth,
      availableMonths: availableMonths,
      monthSpendMinor: monthSpend,
      monthIncomeMinor: monthIncome,
      previousMonthSpendMinor: prevMonthSpend,
      trailingThreeMonthAvgSpendMinor: trailingSpendWma,
      projectedMonthEndSpendMinor: projectedEndOfMonth,
      elapsedDaysInMonth: elapsedDays,
      totalDaysInMonth: totalDaysInMonth,
      remainingDaysInMonth: remainingDays,
      dailyAverageSpendMinor: dailyAvg,
      activeOverallBudgetLimitMinor: activeOverallLimit,
      paceStatus: paceStatus,
      momSpendDeltaPercent: momDeltaPct,
      categories: categories,
      topMerchants: topMerchants.take(8).toList(),
      moneyLeaks: moneyLeaks.take(5).toList(),
      weekendBurn: weekendBurn,
      rule503020: rule503020,
      budgetPlan: budgetPlan,
      maintenanceTips: tips,
    );
  }

  /// Offline, zero-latency natural-language Financial Q&A engine.
  /// Respects [maskBalances] so amounts are never leaked when privacy masking is on.
  static CoachReply answerQuestion(
    CfoAdvisorReport report,
    String rawQuestion, {
    bool maskBalances = false,
    LifeStageStatus? lifeStage,
    int? monthlyEmiMinor,
  }) {
    final q = rawQuestion.trim().toLowerCase();
    final ccy = report.currencyCode;
    String fmt(int minor) =>
        Money(amountMinor: minor, currencyCode: ccy).format(mask: maskBalances);

    if (q.isEmpty) {
      return CoachReply(
        headline: 'Ask Pocket CFO anything',
        summary:
            'Try asking where your money went this month, how to save a target amount, or how to manage your EMIs safely.',
        actionSteps: const [
          'Ask: "Where is most of my money going?"',
          'Ask: "How should I manage my EMIs?"',
          'Ask: "How can I save 5000 per month?"',
        ],
      );
    }

    // 0. Life-Stage & EMI Guard intent.
    if (_matchesAny(q, const [
      'emi',
      'loan',
      'debt',
      'bachelor',
      'family',
      'married',
      'freelancer',
      'emergency fund',
      'status',
    ])) {
      final detected = q.contains('family')
          ? LifeStageStatus.familyWithKids
          : q.contains('married')
          ? LifeStageStatus.marriedCouple
          : q.contains('freelanc')
          ? LifeStageStatus.freelancerBusiness
          : q.contains('student')
          ? LifeStageStatus.studentStarter
          : q.contains('bachelor')
          ? LifeStageStatus.bachelor
          : (lifeStage ?? LifeStageStatus.bachelor);
      final targets = LifeStagePlannerEngine.resolveEffectiveTargets(
        status: detected,
      );
      final incomeBasis = report.monthIncomeMinor > 0
          ? report.monthIncomeMinor
          : report.budgetPlan.recommendedOverallLimitMinor;
      final safeEmiCap = incomeBasis > 0
          ? (incomeBasis * targets.maxSafeDtiPct) ~/ 100
          : 0;
      final emiVal = monthlyEmiMinor ?? 0;
      final dtiStr = incomeBasis > 0 && emiVal > 0
          ? '${(emiVal * 100.0 / incomeBasis).round()}%'
          : '0%';
      return CoachReply(
        headline: '${detected.title} — Budget & EMI Guard',
        summary:
            'Recommended split for ${detected.title}: ${targets.needsPct}% Essentials, ${targets.wantsPct}% Wants${targets.taxPct > 0 ? ', ${targets.taxPct}% Tax Shield' : ''}, and ${targets.savingsPct}% Savings — with total EMIs capped under ${targets.maxSafeDtiPct}% of income.',
        metrics: [
          CoachMetricChip(
            label: 'Max Safe EMI',
            value: safeEmiCap > 0
                ? fmt(safeEmiCap)
                : '${targets.maxSafeDtiPct}% cap',
          ),
          CoachMetricChip(
            label: 'Emergency Shield',
            value: '${targets.emergencyMonths} months',
          ),
          if (emiVal > 0)
            CoachMetricChip(
              label: 'Current DTI',
              value: maskBalances ? '••%' : dtiStr,
            ),
        ],
        actionSteps: [
          'Open Life & EMI Plan from Home to simulate Debt Avalanche vs. Snowball payoff speed and test new EMIs before signing.',
          'Build ${targets.emergencyMonths} months of essential outgo (Rent + Groceries + Bills + EMIs) in liquid cash before high-risk investments.',
          'Never finance lifestyle wants on high-interest (>= 12% APR) EMIs — prepay highest-rate loans first.',
        ],
      );
    }

    // 1. Check if the user asked about a specific category or merchant in their ledger.
    for (final cat in report.categories) {
      final catLower = cat.categoryName.toLowerCase();
      final tokens = catLower
          .split(RegExp(r'[\s&/,-]+'))
          .where((t) => t.length >= 3);
      if (q.contains(catLower) || tokens.any((t) => q.contains(t))) {
        final suggested = report.budgetPlan.categorySuggestions
            .where((s) => s.categoryName == cat.categoryName)
            .firstOrNull;
        final deltaStr = cat.deltaVsAvgPercent != null
            ? '${cat.deltaVsAvgPercent! >= 0 ? '+' : ''}${cat.deltaVsAvgPercent!.round()}% vs 3-mo avg'
            : 'No 3-mo history yet';
        return CoachReply(
          headline: '${cat.categoryName} in ${report.selectedMonthLabel}',
          summary:
              'You spent ${fmt(cat.spendMinor)} across ${cat.txCount} transaction(s) (${maskBalances ? '••%' : '${cat.sharePercent.round()}%'} of monthly outflows). Bucket: ${cat.bucket.label}.',
          metrics: [
            CoachMetricChip(label: 'Spent', value: fmt(cat.spendMinor)),
            CoachMetricChip(
              label: 'Share',
              value: maskBalances ? '••%' : '${cat.sharePercent.round()}%',
            ),
            CoachMetricChip(label: 'Trend', value: deltaStr),
          ],
          actionSteps: [
            if (suggested != null)
              'Recommended monthly cap: ${fmt(suggested.suggestedLimitMinor)} (${suggested.rationale}).',
            if (cat.bucket == SpendBucket.wants)
              'Split this into 4 weekly envelopes of ${fmt((suggested?.suggestedLimitMinor ?? cat.spendMinor) ~/ 4)} so you never exhaust it mid-month.',
            if (cat.bucket == SpendBucket.needs)
              'As an essential Need, audit recurring subscriptions/plans once per quarter rather than skipping necessities.',
          ],
          budgetAction: suggested != null
              ? CoachBudgetAction(
                  name: '${cat.categoryName} Cap',
                  limitMinor: suggested.suggestedLimitMinor,
                  categoryId: cat.categoryId,
                  categoryName: cat.categoryName,
                )
              : null,
        );
      }
    }

    for (final merch in report.topMerchants) {
      final mLower = merch.label.toLowerCase();
      if (mLower.length >= 3 && q.contains(mLower)) {
        return CoachReply(
          headline: '${merch.label} Spending Breakdown',
          summary:
              'You spent ${fmt(merch.totalMinor)} at ${merch.label} across ${merch.txCount} visit(s) in ${report.selectedMonthLabel}, averaging ${fmt(merch.averageMinor)} per entry.',
          metrics: [
            CoachMetricChip(label: 'Total', value: fmt(merch.totalMinor)),
            CoachMetricChip(label: 'Count', value: '${merch.txCount}x'),
            CoachMetricChip(label: 'Avg', value: fmt(merch.averageMinor)),
          ],
          actionSteps: [
            'Annualized pace at this rate: ${fmt(merch.totalMinor * 12)} / year.',
            'Trimming 1 in 4 entries saves ~${fmt((merch.totalMinor * 0.25).round())} per month.',
          ],
        );
      }
    }

    // 2. Savings Goal / "How can I save X?" intent.
    if (_matchesAny(q, const [
      'save',
      'saving',
      'cut',
      'reduce',
      'trim',
      'spend less',
    ])) {
      final targetMinor = _extractAmountMinor(q, ccy);
      final wantsCats = report.categories
          .where((c) => c.bucket == SpendBucket.wants)
          .toList();
      final totalWants = wantsCats.fold<int>(0, (s, c) => s + c.spendMinor);
      final effectiveTarget = targetMinor != null && targetMinor > 0
          ? targetMinor
          : (report.budgetPlan.estimatedMonthlySavingsMinor > 0
                ? report.budgetPlan.estimatedMonthlySavingsMinor
                : roundFriendlyBudget(
                    (report.monthSpendMinor * 0.15).round(),
                    ccy,
                  ));

      if (report.monthSpendMinor == 0) {
        return CoachReply(
          headline: 'Log expenses to build your savings cut plan',
          summary:
              'Once you record your regular expenses for ${report.selectedMonthLabel}, I will pinpoint the exact discretionary categories to trim first.',
          actionSteps: const [
            'Log this week\'s spending using Quick Log Presets on Home.',
            'Set a 20% Payday Savings Goal right after salary arrives.',
          ],
        );
      }

      final steps = <String>[];
      var remainingToCut = effectiveTarget;
      final candidates = wantsCats.isNotEmpty ? wantsCats : report.categories;
      for (final c in candidates.take(4)) {
        if (remainingToCut <= 0) break;
        final maxRealisticCut =
            (c.spendMinor * (c.bucket == SpendBucket.wants ? 0.30 : 0.10))
                .round();
        final cut = math.min(remainingToCut, maxRealisticCut);
        if (cut > 0) {
          final pct = c.spendMinor > 0
              ? ((cut * 100) / c.spendMinor).round()
              : 0;
          steps.add(
            'Trim ${c.categoryName} by $pct% (${fmt(cut)}/mo -> new cap ${fmt(c.spendMinor - cut)}).',
          );
          remainingToCut -= cut;
        }
      }
      if (remainingToCut > 0) {
        steps.add(
          'Remaining gap of ${fmt(remainingToCut)}/mo: review recurring bills/subscriptions or boost income to avoid squeezing essential Needs.',
        );
      }
      if (report.weekendBurn.isWeekendHeavy) {
        steps.add(
          'Cap Fri–Sun spend at ${fmt(report.weekendBurn.suggestedWeekendDailyCapMinor)}/day to curb weekend spikes.',
        );
      }

      final suggestedOverall = math.max(
        roundFriendlyBudget((report.monthSpendMinor * 0.5).round(), ccy),
        roundFriendlyBudget(report.monthSpendMinor - effectiveTarget, ccy),
      );
      return CoachReply(
        headline: 'Savings Roadmap: Target ${fmt(effectiveTarget)} / month',
        summary: totalWants > 0
            ? 'Your discretionary Wants total ${fmt(totalWants)} in ${report.selectedMonthLabel}. Here is the cleanest way to free up ${fmt(effectiveTarget)}/month without cutting core essentials:'
            : 'Based on ${fmt(report.monthSpendMinor)} spent in ${report.selectedMonthLabel}, here is your highest-impact reduction plan:',
        metrics: [
          CoachMetricChip(label: 'Target Save', value: fmt(effectiveTarget)),
          CoachMetricChip(label: 'Wants Pool', value: fmt(totalWants)),
          CoachMetricChip(label: 'New Cap', value: fmt(suggestedOverall)),
        ],
        actionSteps: steps,
        budgetAction: suggestedOverall > 0
            ? CoachBudgetAction(
                name: 'Savings-First Monthly Cap',
                limitMinor: suggestedOverall,
              )
            : null,
      );
    }

    // 3. Budget Suggestion intent.
    if (_matchesAny(q, const [
      'suggest',
      'recommend',
      'budget plan',
      'create budget',
      'what budget',
      'ideal budget',
      'budget for me',
    ])) {
      final plan = report.budgetPlan;
      if (plan.recommendedOverallLimitMinor <= 0) {
        return const CoachReply(
          headline: 'Add income or expenses for tailored limits',
          summary:
              'Record your monthly income or a few expenses and I will automatically build a 50/30/20 or Weighted Moving Average monthly budget with 1-tap apply.',
          actionSteps: [
            'Tap "+ Salary" on Home to record your monthly income.',
            'I will automatically split 50% Needs, 30% Wants, and 20% Savings.',
          ],
        );
      }
      return CoachReply(
        headline:
            'Recommended Monthly Budget: ${fmt(plan.recommendedOverallLimitMinor)}',
        summary: '${plan.methodologyLabel}: ${plan.methodologyNote}',
        metrics: [
          CoachMetricChip(
            label: 'Monthly Cap',
            value: fmt(plan.recommendedOverallLimitMinor),
          ),
          CoachMetricChip(
            label: 'Daily Safe',
            value: fmt(plan.dailySafeTargetMinor),
          ),
          CoachMetricChip(
            label: 'Weekly Env',
            value: fmt(plan.weeklyEnvelopeMinor),
          ),
        ],
        actionSteps: [
          for (final s in plan.categorySuggestions.take(3))
            '${s.categoryName}: cap at ${fmt(s.suggestedLimitMinor)} (${s.rationale}).',
          'Tap the button below to apply this monthly cap directly to your Budgets & Limits guard.',
        ],
        budgetAction: CoachBudgetAction(
          name: 'Smart Monthly Budget',
          limitMinor: plan.recommendedOverallLimitMinor,
        ),
      );
    }

    // 4. How to Maintain / Manage Budget intent.
    if (_matchesAny(q, const [
      'maintain',
      'stick',
      'manage',
      'control',
      'follow',
      'discipline',
      'habit',
      'rule',
      '50/30/20',
      'weekly',
      'daily',
    ])) {
      final plan = report.budgetPlan;
      final effectiveDaily =
          report.activeOverallBudgetLimitMinor != null &&
              report.remainingDaysInMonth > 0
          ? math.max(
              0,
              (report.activeOverallBudgetLimitMinor! -
                      report.monthSpendMinor) ~/
                  report.remainingDaysInMonth,
            )
          : plan.dailySafeTargetMinor;
      return CoachReply(
        headline: 'How to Maintain Your Budget Every Month',
        summary:
            'Budgeting succeeds when you manage weekly & daily pace instead of waiting for month-end surprises. Here is your live operating rhythm:',
        metrics: [
          CoachMetricChip(label: 'Safe / Day', value: fmt(effectiveDaily)),
          CoachMetricChip(
            label: 'Weekly Cap',
            value: fmt(plan.weeklyEnvelopeMinor),
          ),
          CoachMetricChip(
            label: 'Wants Share',
            value: maskBalances
                ? '••%'
                : '${report.rule503020.wantsPct.round()}% (30% ideal)',
          ),
        ],
        actionSteps: [
          for (final tip in report.maintenanceTips.take(4))
            '${tip.title}: ${tip.detail}',
        ],
        budgetAction:
            !plan.hasOverallBudgetAlready &&
                plan.recommendedOverallLimitMinor > 0
            ? CoachBudgetAction(
                name: 'Smart Monthly Budget',
                limitMinor: plan.recommendedOverallLimitMinor,
              )
            : null,
      );
    }

    // 5. Hidden Money Leaks & Spikes intent.
    if (_matchesAny(q, const [
      'leak',
      'small',
      'frequent',
      'spike',
      'unusual',
      'waste',
      'wasting',
      'drain',
    ])) {
      final spikes = report.categories.where((c) => c.isSpike).toList();
      if (report.moneyLeaks.isEmpty && spikes.isEmpty) {
        return CoachReply(
          headline: 'No major leaks or spikes detected!',
          summary:
              'Your spending in ${report.selectedMonthLabel} looks disciplined with no frequent small discretionary drains (>= 3x/mo) or +25% category spikes.',
          actionSteps: const [
            'Keep logging everyday small coffee/snack/ride transactions so I can catch recurring creep early.',
            'Review the Monthly Audit tab each Sunday for a 60-second check-in.',
          ],
        );
      }
      final leakSteps = <String>[
        for (final l in report.moneyLeaks.take(3))
          '${l.label} (${l.txCount}x = ${fmt(l.totalMinor)}/mo -> ${fmt(l.annualizedMinor)}/yr). Cutting 30% saves ${fmt(l.potentialAnnualSavingMinor)}/yr.',
        for (final s in spikes.take(2))
          'Spike in ${s.categoryName}: ${fmt(s.spendMinor)} (+${s.deltaVsAvgPercent!.round()}% above your 3-month average of ${fmt(s.trailingAvgMinor)}).',
      ];
      return CoachReply(
        headline: 'Hidden Money Leaks & Spending Spikes',
        summary:
            'Detected ${report.moneyLeaks.length} frequent leak(s) and ${spikes.length} category spike(s) in ${report.selectedMonthLabel}:',
        metrics: [
          if (report.moneyLeaks.isNotEmpty)
            CoachMetricChip(
              label: 'Top Leak',
              value:
                  '${report.moneyLeaks.first.label} (${fmt(report.moneyLeaks.first.totalMinor)})',
            ),
          if (spikes.isNotEmpty)
            CoachMetricChip(
              label: 'Top Spike',
              value:
                  '${spikes.first.categoryName} +${spikes.first.deltaVsAvgPercent!.round()}%',
            ),
        ],
        actionSteps: leakSteps,
      );
    }

    // 6. Month-over-Month Comparison intent.
    if (_matchesAny(q, const [
      'compare',
      'last month',
      'previous',
      'trend',
      'vs',
      'difference',
      'higher',
      'lower',
    ])) {
      final deltaText = report.momSpendDeltaPercent == null
          ? 'No prior month data yet to compare.'
          : '${report.momSpendDeltaPercent! >= 0 ? 'Up +' : 'Down '}${report.momSpendDeltaPercent!.abs().round()}% vs last month (${fmt(report.previousMonthSpendMinor)}).';
      final rising = report.categories
          .where((c) => (c.deltaVsAvgPercent ?? 0) > 10)
          .take(2)
          .toList();
      final falling = report.categories
          .where((c) => (c.deltaVsAvgPercent ?? 0) < -10)
          .take(2)
          .toList();
      return CoachReply(
        headline: 'Month-over-Month Trend (${report.selectedMonthLabel})',
        summary:
            'Total spent: ${fmt(report.monthSpendMinor)}. $deltaText 3-month weighted average: ${fmt(report.trailingThreeMonthAvgSpendMinor)}.',
        metrics: [
          CoachMetricChip(
            label: 'This Month',
            value: fmt(report.monthSpendMinor),
          ),
          CoachMetricChip(
            label: 'Last Month',
            value: fmt(report.previousMonthSpendMinor),
          ),
          CoachMetricChip(
            label: '3-Mo Avg',
            value: fmt(report.trailingThreeMonthAvgSpendMinor),
          ),
        ],
        actionSteps: [
          for (final r in rising)
            'Rising: ${r.categoryName} is +${r.deltaVsAvgPercent!.round()}% above baseline (${fmt(r.spendMinor)}).',
          for (final f in falling)
            'Improved: ${f.categoryName} is down ${f.deltaVsAvgPercent!.abs().round()}% (${fmt(f.spendMinor)}).',
          if (rising.isEmpty && falling.isEmpty)
            'Spending is closely aligned with your trailing multi-month history.',
        ],
      );
    }

    // 7. Pace / Overspend Forecast intent.
    if (_matchesAny(q, const [
      'overspend',
      'forecast',
      'predict',
      'track',
      'pace',
      'end of month',
      'project',
    ])) {
      final refCap =
          report.activeOverallBudgetLimitMinor ??
          report.budgetPlan.recommendedOverallLimitMinor;
      final overBy = refCap > 0
          ? report.projectedMonthEndSpendMinor - refCap
          : 0;
      return CoachReply(
        headline: report.paceStatus == 'overspending'
            ? 'Pace Alert: Trending Over Limit'
            : 'Monthly Pace Forecast (${report.selectedMonthLabel})',
        summary: report.isCurrentMonth
            ? 'At ${fmt(report.dailyAverageSpendMinor)}/day across ${report.elapsedDaysInMonth} day(s), you are projected to finish the month at ${fmt(report.projectedMonthEndSpendMinor)}.'
            : '${report.selectedMonthLabel} closed at ${fmt(report.monthSpendMinor)} total spending.',
        metrics: [
          CoachMetricChip(
            label: 'Spent So Far',
            value: fmt(report.monthSpendMinor),
          ),
          CoachMetricChip(
            label: 'Projected End',
            value: fmt(report.projectedMonthEndSpendMinor),
          ),
          if (refCap > 0)
            CoachMetricChip(label: 'Target Cap', value: fmt(refCap)),
        ],
        actionSteps: [
          if (overBy > 0 && report.remainingDaysInMonth > 0)
            'You are trending ${fmt(overBy)} over target. Lower daily discretionary spend to ${fmt(math.max(0, (refCap - report.monthSpendMinor) ~/ report.remainingDaysInMonth))}/day for the next ${report.remainingDaysInMonth} day(s).'
          else
            'You are pacing within target — stay under ${fmt(report.budgetPlan.dailySafeTargetMinor)}/day to protect your monthly savings.',
        ],
      );
    }

    // 8. Default / "Where is my money going?" / "How much did I spend?" summary.
    if (!report.hasActivity) {
      return CoachReply(
        headline: 'No activity recorded in ${report.selectedMonthLabel}',
        summary:
            'There are no posted expenses or income entries in ${report.selectedMonthLabel} yet. Select another month above or record a transaction to unlock live coaching.',
        actionSteps: const [
          'Use Quick Log Presets on Home to track expenses in 2 taps.',
          'Import a bank statement via CSV Import for instant multi-month analysis.',
        ],
      );
    }

    final topCats = report.categories.take(3).toList();
    final topItems = report.topMerchants.take(3).toList();
    return CoachReply(
      headline: '${report.selectedMonthLabel} Spending Breakdown',
      summary:
          'You spent ${fmt(report.monthSpendMinor)} and earned ${fmt(report.monthIncomeMinor)} (${report.netSavedMinor >= 0 ? 'saved' : 'deficit of'} ${fmt(report.netSavedMinor.abs())}). Your top ${topCats.length} categories drive ${maskBalances ? '••%' : '${topCats.fold<double>(0, (s, c) => s + c.sharePercent).round()}%'} of all outflows.',
      metrics: [
        CoachMetricChip(
          label: 'Total Spent',
          value: fmt(report.monthSpendMinor),
        ),
        CoachMetricChip(label: 'Income', value: fmt(report.monthIncomeMinor)),
        if (topCats.isNotEmpty)
          CoachMetricChip(
            label: '#1 Drain',
            value:
                '${topCats.first.categoryName} (${maskBalances ? '••%' : '${topCats.first.sharePercent.round()}%'})',
          ),
      ],
      actionSteps: [
        for (final c in topCats)
          'Category • ${c.categoryName}: ${fmt(c.spendMinor)} (${maskBalances ? '••%' : '${c.sharePercent.round()}%'} • ${c.txCount} tx).',
        if (topItems.isNotEmpty)
          'Biggest item: ${topItems.first.label} (${fmt(topItems.first.totalMinor)} across ${topItems.first.txCount}x).',
      ],
      budgetAction:
          !report.budgetPlan.hasOverallBudgetAlready &&
              report.budgetPlan.recommendedOverallLimitMinor > 0
          ? CoachBudgetAction(
              name: 'Smart Monthly Budget',
              limitMinor: report.budgetPlan.recommendedOverallLimitMinor,
            )
          : null,
    );
  }

  static BudgetRecommendationPlan _buildBudgetPlan({
    required String currencyCode,
    required int monthSpend,
    required int projectedMonthEnd,
    required int monthIncome,
    required int trailingSpendWma,
    required int trailingIncomeWma,
    required int totalDaysInMonth,
    required List<CategoryAuditItem> categories,
    required Map<String, Map<String, int>> catHistoryByYm,
    required Map<String, String?> catIdByName,
    required List<String> prevMonthKeys,
    required bool hasOverallBudgetAlready,
    required Set<String> budgetedCatIds,
  }) {
    final effectiveIncome = monthIncome > 0 ? monthIncome : trailingIncomeWma;
    final baselineSpend = trailingSpendWma > 0
        ? trailingSpendWma
        : math.max(monthSpend, projectedMonthEnd);

    String methodologyLabel;
    String methodologyNote;
    int recommendedOverall;
    int estimatedSavings;

    if (effectiveIncome > 0) {
      // 50% Needs + 30% Wants = 80% max spending cap, saving >= 20% of income!
      final rule80Cap = (effectiveIncome * 0.80).round();
      if (baselineSpend > 0 &&
          baselineSpend < rule80Cap &&
          monthSpend < rule80Cap) {
        // User already lives below 80% of income -> lock in a realistic 5% stretch cushion
        // around their actual baseline so we never tell a frugal saver to spend MORE!
        recommendedOverall = roundFriendlyBudget(
          (baselineSpend * 1.05).round(),
          currencyCode,
        );
        methodologyLabel = 'Surplus-First Adaptive Cap';
        methodologyNote =
            'You already live comfortably below 80% of income. This cap protects your strong savings rate while leaving a 5% buffer.';
      } else {
        recommendedOverall = roundFriendlyBudget(rule80Cap, currencyCode);
        methodologyLabel = '50 / 30 / 20 Income Rule';
        methodologyNote =
            'Allocates 50% to Needs, 30% to Wants, and automatically locks in 20% monthly savings from your income.';
      }
      estimatedSavings = math.max(0, effectiveIncome - recommendedOverall);
    } else if (baselineSpend > 0) {
      // Expense-only history: trim 12% off discretionary spend using Weighted Moving Average.
      recommendedOverall = roundFriendlyBudget(
        (baselineSpend * 0.88).round(),
        currencyCode,
      );
      estimatedSavings = math.max(0, baselineSpend - recommendedOverall);
      methodologyLabel = '3-Month Smart Trim (-12%)';
      methodologyNote =
          'Built from your weighted spending baseline with a realistic 12% discretionary trim. Log income anytime to unlock 50/30/20 targeting.';
    } else {
      recommendedOverall = 0;
      estimatedSavings = 0;
      methodologyLabel = 'Awaiting Ledger Data';
      methodologyNote =
          'Record your monthly income or first week of expenses to generate tailored category and monthly caps.';
    }

    // Build per-category suggestions across active + historical categories.
    final allCatNames = <String>{
      for (final c in categories) c.categoryName,
      ...catHistoryByYm.keys,
    };
    final catMap = {for (final c in categories) c.categoryName: c};

    final suggestions = <SuggestedCategoryBudget>[];
    for (final name in allCatNames) {
      final curr = catMap[name];
      final currentSpend = curr?.spendMinor ?? 0;
      final trailingAvg = _weightedHistoryAverage(
        prevMonthKeys,
        catHistoryByYm[name] ?? const {},
      );
      final base = trailingAvg > 0
          ? math.max(currentSpend, trailingAvg)
          : currentSpend;
      if (base <= 0) continue;

      final bucket = curr?.bucket ?? classifyCategory(name);
      final double multiplier;
      final String rationale;
      if (bucket == SpendBucket.wants) {
        if (curr?.isSpike == true && trailingAvg > 0) {
          // Bring spiking category back down to its 3-month average.
          multiplier = trailingAvg / base;
          rationale = 'Normalize spike back to your 3-month average';
        } else {
          multiplier = 0.85;
          rationale = '15% discretionary Want trim for effortless savings';
        }
      } else if (bucket == SpendBucket.needs) {
        multiplier = 1.0;
        rationale = 'Essential Need — keep steady with zero surprise overshoot';
      } else {
        multiplier = 1.0;
        rationale = 'Dedicated Savings & Debt allocation';
      }

      final suggestedLimit = roundFriendlyBudget(
        (base * multiplier).round(),
        currencyCode,
      );
      final saving = math.max(0, base - suggestedLimit);
      final catId = curr?.categoryId ?? catIdByName[name];
      suggestions.add(
        SuggestedCategoryBudget(
          categoryId: catId,
          categoryName: name,
          bucket: bucket,
          currentSpendMinor: currentSpend,
          trailingAvgMinor: trailingAvg,
          suggestedLimitMinor: suggestedLimit,
          potentialMonthlySavingMinor: saving,
          rationale: rationale,
          alreadyBudgeted: catId != null && budgetedCatIds.contains(catId),
        ),
      );
    }

    // Prioritize highest savings opportunity first, then largest spend.
    suggestions.sort((a, b) {
      final cmpSave = b.potentialMonthlySavingMinor.compareTo(
        a.potentialMonthlySavingMinor,
      );
      if (cmpSave != 0) return cmpSave;
      return b.currentSpendMinor.compareTo(a.currentSpendMinor);
    });

    final dailySafe = totalDaysInMonth > 0
        ? (recommendedOverall ~/ totalDaysInMonth)
        : 0;
    final weeklyEnv = (recommendedOverall * 7) ~/ math.max(1, totalDaysInMonth);

    return BudgetRecommendationPlan(
      methodologyLabel: methodologyLabel,
      methodologyNote: methodologyNote,
      recommendedOverallLimitMinor: recommendedOverall,
      estimatedMonthlySavingsMinor: estimatedSavings,
      dailySafeTargetMinor: dailySafe,
      weeklyEnvelopeMinor: weeklyEnv,
      hasOverallBudgetAlready: hasOverallBudgetAlready,
      categorySuggestions: suggestions.take(6).toList(),
    );
  }

  static List<MaintenanceTip> _buildMaintenanceTips({
    required String currencyCode,
    required int monthSpend,
    required int monthIncome,
    required int projectedEndOfMonth,
    required int remainingDays,
    required int? activeOverallLimit,
    required List<CategoryAuditItem> categories,
    required List<MoneyLeakItem> moneyLeaks,
    required WeekendBurnInsight weekendBurn,
    required Rule503020Snapshot rule503020,
    required BudgetRecommendationPlan budgetPlan,
  }) {
    String fmt(int m) =>
        Money(amountMinor: m, currencyCode: currencyCode).format();
    final tips = <MaintenanceTip>[];

    // 1. Pace / Weekly Envelope Tip.
    if (budgetPlan.weeklyEnvelopeMinor > 0) {
      tips.add(
        MaintenanceTip(
          priority: 1,
          title: 'Use a Weekly Spending Envelope',
          detail:
              'Divide your month into 4 weekly caps of ${fmt(budgetPlan.weeklyEnvelopeMinor)} (${fmt(budgetPlan.dailySafeTargetMinor)}/day). Weekly check-ins catch drift 3× faster than monthly reviews.',
          impactLabel: 'Core Habit',
        ),
      );
    }

    // 2. Top Spike or Discretionary Drain Tip.
    final topSpike = categories.where((c) => c.isSpike).firstOrNull;
    final topWant = categories
        .where((c) => c.bucket == SpendBucket.wants)
        .firstOrNull;
    if (topSpike != null) {
      tips.add(
        MaintenanceTip(
          priority: 2,
          title: 'Cool Down ${topSpike.categoryName} Surge',
          detail:
              '${topSpike.categoryName} jumped +${topSpike.deltaVsAvgPercent!.round()}% above your 3-month baseline (${fmt(topSpike.trailingAvgMinor)}). Set a dedicated category cap to trigger 80% early warnings.',
          impactLabel: '+${topSpike.deltaVsAvgPercent!.round()}% Spike',
        ),
      );
    } else if (topWant != null && topWant.sharePercent >= 22) {
      final trim = roundFriendlyBudget(
        (topWant.spendMinor * 0.15).round(),
        currencyCode,
      );
      tips.add(
        MaintenanceTip(
          priority: 2,
          title: 'Trim Top Discretionary Category (${topWant.categoryName})',
          detail:
              '${topWant.categoryName} absorbs ${topWant.sharePercent.round()}% of your monthly spend. A gentle 15% trim saves ~${fmt(trim)} every month (${fmt(trim * 12)}/year).',
          impactLabel: 'Save ${fmt(trim)}/mo',
        ),
      );
    }

    // 3. Weekend Guardrail Tip.
    if (weekendBurn.isWeekendHeavy) {
      tips.add(
        MaintenanceTip(
          priority: 3,
          title: 'Set a Fri–Sun Weekend Guardrail',
          detail:
              'Your weekend daily spend (${fmt(weekendBurn.weekendDailyAvgMinor)}/day) is ${weekendBurn.weekendMultiplier.toStringAsFixed(1)}× higher than weekdays. Keep weekends under ${fmt(weekendBurn.suggestedWeekendDailyCapMinor)}/day.',
          impactLabel:
              '${weekendBurn.weekendMultiplier.toStringAsFixed(1)}× Weekend',
        ),
      );
    }

    // 4. Hidden Money Leaks Tip.
    if (moneyLeaks.isNotEmpty) {
      final leak = moneyLeaks.first;
      tips.add(
        MaintenanceTip(
          priority: 4,
          title: 'Plug "${leak.label}" Repeat Micro-Spends',
          detail:
              '${leak.txCount} small visits added up to ${fmt(leak.totalMinor)} this month (${fmt(leak.annualizedMinor)}/yr). Batching or skipping 1 in 3 visits keeps your budget green painlessly.',
          impactLabel: '${fmt(leak.potentialAnnualSavingMinor)}/yr',
        ),
      );
    }

    // 5. Pay-Yourself-First Rule (50/30/20).
    if (monthIncome > 0 && rule503020.savingsPct < 20) {
      final targetSave = roundFriendlyBudget(
        (monthIncome * 0.20).round(),
        currencyCode,
      );
      tips.add(
        MaintenanceTip(
          priority: 5,
          title: 'Automate "Pay Yourself First" on Salary Day',
          detail:
              'Move ${fmt(targetSave)} (20% of income) to a Savings Goal or separate account on day 1 via Recurring Rules so you only spend what remains.',
          impactLabel: '20% Rule',
        ),
      );
    } else if (activeOverallLimit != null &&
        projectedEndOfMonth > activeOverallLimit &&
        remainingDays > 0) {
      final safeLeft = math.max(
        0,
        (activeOverallLimit - monthSpend) ~/ remainingDays,
      );
      tips.add(
        MaintenanceTip(
          priority: 5,
          title: '48-Hour Pause Rule for Remaining $remainingDays Day(s)',
          detail:
              'Wait 48 hours before any non-essential purchase and stay under ${fmt(safeLeft)}/day to finish this month inside your budget.',
          impactLabel: 'Finish Green',
        ),
      );
    } else {
      tips.add(
        MaintenanceTip(
          priority: 6,
          title: 'Apply the 48-Hour Rule on Wants',
          detail:
              'Pause 48 hours before unplanned shopping or dining splurges, and keep Budget 80% alerts enabled in Settings for effortless course-correction.',
          impactLabel: 'Zero Stress',
        ),
      );
    }

    return tips.take(5).toList();
  }

  static int _weightedHistoryAverage(
    List<String> prevMonthKeys,
    Map<String, int> totalsByYm,
  ) {
    const weights = [0.5, 0.3, 0.2];
    var weightedSum = 0.0;
    var activeWeight = 0.0;
    for (var i = 0; i < prevMonthKeys.length && i < weights.length; i++) {
      final v = totalsByYm[prevMonthKeys[i]] ?? 0;
      if (v > 0) {
        weightedSum += v * weights[i];
        activeWeight += weights[i];
      }
    }
    if (activeWeight <= 0) return 0;
    return (weightedSum / activeWeight).round();
  }

  static int? _extractAmountMinor(String q, String currencyCode) {
    final match = RegExp(r'\b(\d[\d,]*(?:\.\d{1,3})?)\b').firstMatch(q);
    if (match == null) return null;
    final raw = match.group(1)!.replaceAll(',', '');
    final curr =
        CurrencyCatalog.byCode(currencyCode) ??
        CurrencySpec(
          code: currencyCode,
          name: currencyCode,
          minorUnit: 2,
          symbol: currencyCode,
        );
    return Money.parseDecimal(raw, currency: curr).valueOrNull?.amountMinor;
  }

  static bool _matchesAny(String text, List<String> keywords) {
    for (final k in keywords) {
      if (text.contains(k)) return true;
    }
    return false;
  }

  static String _ymKey(int year, int month) =>
      '$year-${month.toString().padLeft(2, '0')}';
}
