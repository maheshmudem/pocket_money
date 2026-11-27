import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import 'currency.dart';
import 'money.dart';

/// Lightweight spend entry fed into [MonthlyTrackerEngine.buildSnapshot].
final class MonthSpendEntry extends Equatable {
  const MonthSpendEntry({
    required this.dateUtc,
    required this.amountMinor,
    required this.categoryName,
    required this.isEssential,
  });

  final String dateUtc;
  final int amountMinor;
  final String categoryName;
  final bool isEssential;

  @override
  List<Object?> get props => [dateUtc, amountMinor, categoryName, isEssential];
}

/// Upcoming recurring bill or loan EMI due within the selected month window.
final class UpcomingCommitment extends Equatable {
  const UpcomingCommitment({
    required this.label,
    required this.dueDateUtc,
    required this.amountMinor,
    required this.kind,
  });

  final String label;
  final String dueDateUtc;
  final int amountMinor;

  /// `'bill'` | `'emi'`
  final String kind;

  @override
  List<Object?> get props => [label, dueDateUtc, amountMinor, kind];
}

/// Pure-Dart input representing a planned bucket list item for cash-flow planning.
final class BucketPlanInput extends Equatable {
  const BucketPlanInput({
    required this.id,
    required this.name,
    required this.priority,
    required this.estimatedMinor,
    required this.savedMinor,
    required this.targetYearMonth,
    required this.createdAtUtc,
    this.dueDateUtc,
    this.reminderAtUtc,
  });

  final String id;
  final String name;

  /// `'urgent'` | `'essential'` | `'nice'` | `'dream'`
  final String priority;
  final int estimatedMinor;
  final int savedMinor;
  final String targetYearMonth;
  final String? dueDateUtc;
  final String? reminderAtUtc;
  final String createdAtUtc;

  @override
  List<Object?> get props => [
    id,
    name,
    priority,
    estimatedMinor,
    savedMinor,
    targetYearMonth,
    dueDateUtc,
    reminderAtUtc,
    createdAtUtc,
  ];
}

/// Complete input bundle for [MonthlyTrackerEngine.buildSnapshot].
final class MonthlyTrackerInput extends Equatable {
  const MonthlyTrackerInput({
    required this.currencyCode,
    required this.year,
    required this.month,
    required this.nowUtc,
    required this.incomeMinor,
    required this.expenses,
    this.refundsMinor = 0,
    this.previousIncomeMinor = 0,
    this.previousSpendMinor = 0,
    this.previousSpendByCategory = const {},
    this.expectedIncomeMinor = 0,
    this.upcoming = const [],
    this.savingsTargetPct = 20,
    this.wantsCapPct = 30,
    this.budgetLimitMinor,
    this.budgetSpentMinor,
    this.bucketItems = const [],
  });

  final String currencyCode;
  final int year;
  final int month;
  final DateTime nowUtc;
  final int incomeMinor;
  final List<MonthSpendEntry> expenses;
  final int refundsMinor;
  final int previousIncomeMinor;
  final int previousSpendMinor;
  final Map<String, int> previousSpendByCategory;
  final int expectedIncomeMinor;
  final List<UpcomingCommitment> upcoming;
  final int savingsTargetPct;
  final int wantsCapPct;
  final int? budgetLimitMinor;
  final int? budgetSpentMinor;
  final List<BucketPlanInput> bucketItems;

  @override
  List<Object?> get props => [
    currencyCode,
    year,
    month,
    nowUtc,
    incomeMinor,
    expenses,
    refundsMinor,
    previousIncomeMinor,
    previousSpendMinor,
    previousSpendByCategory,
    expectedIncomeMinor,
    upcoming,
    savingsTargetPct,
    wantsCapPct,
    budgetLimitMinor,
    budgetSpentMinor,
    bucketItems,
  ];
}

/// Per-category spend breakdown + month-over-month delta.
final class MonthCategoryStat extends Equatable {
  const MonthCategoryStat({
    required this.name,
    required this.amountMinor,
    required this.sharePct,
    required this.previousMinor,
    required this.isEssential,
    this.deltaPct,
  });

  final String name;
  final int amountMinor;
  final double sharePct;
  final int previousMinor;
  final double? deltaPct;
  final bool isEssential;

  @override
  List<Object?> get props => [
    name,
    amountMinor,
    sharePct,
    previousMinor,
    deltaPct,
    isEssential,
  ];
}

/// Actionable month insight banner.
final class MonthInsight extends Equatable {
  const MonthInsight({
    required this.title,
    required this.detail,
    required this.severity,
    required this.iconKey,
  });

  final String title;
  final String detail;

  /// `'positive'` | `'info'` | `'warning'` | `'danger'`
  final String severity;
  final String iconKey;

  @override
  List<Object?> get props => [title, detail, severity, iconKey];
}

/// Verdict produced per Bucket List item when evaluated against real monthly cash flow.
enum BucketVerdict {
  buyNow('buy_now', 'Buy now'),
  partial('partial', 'Fund partial'),
  defer('defer', 'Defer'),
  saveUp('save_up', 'Save monthly'),
  urgentShortfall('urgent_shortfall', 'Shortfall'),
  funded('funded', 'Ready to buy'),
  scheduled('scheduled', 'Upcoming');

  const BucketVerdict(this.wireValue, this.label);
  final String wireValue;
  final String label;
}

/// Action plan for a single Bucket List item.
final class BucketItemPlan extends Equatable {
  const BucketItemPlan({
    required this.itemId,
    required this.verdict,
    required this.allocatedThisMonthMinor,
    required this.remainingAfterMinor,
    required this.usesSavingsMinor,
    required this.suggestedMonthlySavingMinor,
    required this.monthsToSave,
    required this.isOverdue,
    required this.isDueSoon,
    required this.coolingOffSuggested,
    required this.headline,
    required this.detail,
  });

  final String itemId;
  final BucketVerdict verdict;
  final int allocatedThisMonthMinor;
  final int remainingAfterMinor;
  final int usesSavingsMinor;
  final int suggestedMonthlySavingMinor;
  final int monthsToSave;
  final bool isOverdue;
  final bool isDueSoon;
  final bool coolingOffSuggested;
  final String headline;
  final String detail;

  @override
  List<Object?> get props => [
    itemId,
    verdict,
    allocatedThisMonthMinor,
    remainingAfterMinor,
    usesSavingsMinor,
    suggestedMonthlySavingMinor,
    monthsToSave,
    isOverdue,
    isDueSoon,
    coolingOffSuggested,
    headline,
    detail,
  ];
}

/// Aggregated Bucket List allocation plan for a target month.
final class BucketPlan extends Equatable {
  const BucketPlan({
    required this.items,
    required this.byItemId,
    required this.totalPlannedThisMonthMinor,
    required this.totalAllocatedMinor,
    required this.totalUsesSavingsMinor,
    required this.affordableCount,
    required this.deferredCount,
    required this.urgentShortfallMinor,
    required this.essentialUnfundedMinor,
    required this.poolLeftAfterMinor,
  });

  final List<BucketItemPlan> items;
  final Map<String, BucketItemPlan> byItemId;
  final int totalPlannedThisMonthMinor;
  final int totalAllocatedMinor;
  final int totalUsesSavingsMinor;
  final int affordableCount;
  final int deferredCount;
  final int urgentShortfallMinor;
  final int essentialUnfundedMinor;
  final int poolLeftAfterMinor;

  int get poolAllocatedMinor =>
      math.max<int>(0, totalAllocatedMinor - totalUsesSavingsMinor);

  @override
  List<Object?> get props => [
    items,
    byItemId,
    totalPlannedThisMonthMinor,
    totalAllocatedMinor,
    totalUsesSavingsMinor,
    affordableCount,
    deferredCount,
    urgentShortfallMinor,
    essentialUnfundedMinor,
    poolLeftAfterMinor,
  ];
}

/// Full monthly cash-flow, daily spend heatmap, pacing, insights & bucket-list snapshot.
final class MonthlyTrackerSnapshot extends Equatable {
  const MonthlyTrackerSnapshot({
    required this.currencyCode,
    required this.year,
    required this.month,
    required this.monthKey,
    required this.isCurrentMonth,
    required this.isPastMonth,
    required this.isFutureMonth,
    required this.daysInMonth,
    required this.daysElapsed,
    required this.daysLeft,
    required this.incomeMinor,
    required this.expectedIncomeMinor,
    required this.effectiveIncomeMinor,
    required this.grossSpendMinor,
    required this.refundsMinor,
    required this.spentMinor,
    required this.needsSpentMinor,
    required this.wantsSpentMinor,
    required this.savedMinor,
    required this.savingsRatePct,
    required this.committedRemainingMinor,
    required this.savingsTargetMinor,
    required this.bucketReserveMinor,
    required this.freeToSpendMinor,
    required this.safeDailySpendMinor,
    required this.projectedMonthEndSpendMinor,
    required this.dailySpendMinor,
    required this.noSpendDays,
    required this.noSpendStreak,
    required this.biggestDayNumber,
    required this.biggestDayMinor,
    required this.topCategories,
    required this.previousIncomeMinor,
    required this.previousSpendMinor,
    required this.spendDeltaVsLastMonthPct,
    required this.budgetLimitMinor,
    required this.budgetSpentMinor,
    required this.budgetUsedPct,
    required this.healthScore,
    required this.healthLabel,
    required this.insights,
    required this.bucketPlan,
  });

  final String currencyCode;
  final int year;
  final int month;
  final String monthKey;
  final bool isCurrentMonth;
  final bool isPastMonth;
  final bool isFutureMonth;
  final int daysInMonth;
  final int daysElapsed;
  final int daysLeft;
  final int incomeMinor;
  final int expectedIncomeMinor;
  final int effectiveIncomeMinor;
  final int grossSpendMinor;
  final int refundsMinor;
  final int spentMinor;
  final int needsSpentMinor;
  final int wantsSpentMinor;
  final int savedMinor;
  final double savingsRatePct;
  final int committedRemainingMinor;
  final int savingsTargetMinor;
  final int bucketReserveMinor;
  final int freeToSpendMinor;
  final int safeDailySpendMinor;
  final int projectedMonthEndSpendMinor;
  final List<int> dailySpendMinor;
  final int noSpendDays;
  final int noSpendStreak;
  final int biggestDayNumber;
  final int biggestDayMinor;
  final List<MonthCategoryStat> topCategories;
  final int previousIncomeMinor;
  final int previousSpendMinor;
  final double? spendDeltaVsLastMonthPct;
  final int? budgetLimitMinor;
  final int? budgetSpentMinor;
  final double? budgetUsedPct;
  final int healthScore;

  /// `'On Track'` | `'Watch'` | `'Over Plan'`
  final String healthLabel;
  final List<MonthInsight> insights;
  final BucketPlan bucketPlan;

  @override
  List<Object?> get props => [
    currencyCode,
    year,
    month,
    monthKey,
    isCurrentMonth,
    isPastMonth,
    isFutureMonth,
    daysInMonth,
    daysElapsed,
    daysLeft,
    incomeMinor,
    expectedIncomeMinor,
    effectiveIncomeMinor,
    grossSpendMinor,
    refundsMinor,
    spentMinor,
    needsSpentMinor,
    wantsSpentMinor,
    savedMinor,
    savingsRatePct,
    committedRemainingMinor,
    savingsTargetMinor,
    bucketReserveMinor,
    freeToSpendMinor,
    safeDailySpendMinor,
    projectedMonthEndSpendMinor,
    dailySpendMinor,
    noSpendDays,
    noSpendStreak,
    biggestDayNumber,
    biggestDayMinor,
    topCategories,
    previousIncomeMinor,
    previousSpendMinor,
    spendDeltaVsLastMonthPct,
    budgetLimitMinor,
    budgetSpentMinor,
    budgetUsedPct,
    healthScore,
    healthLabel,
    insights,
    bucketPlan,
  ];
}

/// 3-way split recommendation for extra / windfall income arriving mid-month.
final class WindfallSplit extends Equatable {
  const WindfallSplit({
    required this.toSavingsMinor,
    required this.toBucketMinor,
    required this.toSpendMinor,
    required this.rationale,
  });

  final int toSavingsMinor;
  final int toBucketMinor;
  final int toSpendMinor;
  final String rationale;

  int get totalMinor => toSavingsMinor + toBucketMinor + toSpendMinor;

  @override
  List<Object?> get props => [
    toSavingsMinor,
    toBucketMinor,
    toSpendMinor,
    rationale,
  ];
}

/// Comprehensive Monthly CFO Scorecard ("Month Wrapped") derived cleanly
/// from savings velocity, spending pace, zero-spend discipline & bucket health.
final class MonthScorecard extends Equatable {
  const MonthScorecard({
    required this.score,
    required this.grade,
    required this.headline,
    required this.savingsPoints,
    required this.pacePoints,
    required this.disciplinePoints,
    required this.bucketPoints,
    required this.shareSummary,
  });

  final int score;
  final String grade;
  final String headline;
  final int savingsPoints;
  final int pacePoints;
  final int disciplinePoints;
  final int bucketPoints;
  final String shareSummary;

  @override
  List<Object?> get props => [
    score,
    grade,
    headline,
    savingsPoints,
    pacePoints,
    disciplinePoints,
    bucketPoints,
    shareSummary,
  ];
}

/// Real-time pre-purchase affordability preview ("Can I Afford It?")
/// evaluated against remaining monthly headroom, days left, and impulse caps.
final class PurchaseAffordabilityPreview extends Equatable {
  const PurchaseAffordabilityPreview({
    required this.tone,
    required this.verdictLabel,
    required this.guidance,
    required this.remainingFreeAfterMinor,
    required this.dailySafeAfterMinor,
    required this.coolingOffWarning,
  });

  /// `'safe'` | `'caution'` | `'tight'` | `'goal'`
  final String tone;
  final String verdictLabel;
  final String guidance;
  final int remainingFreeAfterMinor;
  final int dailySafeAfterMinor;
  final bool coolingOffWarning;

  @override
  List<Object?> get props => [
    tone,
    verdictLabel,
    guidance,
    remainingFreeAfterMinor,
    dailySafeAfterMinor,
    coolingOffWarning,
  ];
}

/// 100% Pure-Dart Monthly Tracker, Smart Bucket List & Extra-Income Engine (`ADR-003`).
abstract final class MonthlyTrackerEngine {
  static String monthKey(int year, int month) {
    final dt = DateTime.utc(year, month, 1);
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}';
  }

  static int daysInMonth(int year, int month) =>
      DateTime.utc(year, month + 1, 0).day;

  static (int year, int month) parseMonthKey(String key) {
    final parts = key.split('-');
    if (parts.length != 2) return (2026, 1);
    final y = int.tryParse(parts[0]) ?? 2026;
    final m = (int.tryParse(parts[1]) ?? 1).clamp(1, 12);
    return (y, m);
  }

  static String shiftMonth(String key, int delta) {
    final (y, m) = parseMonthKey(key);
    final dt = DateTime.utc(y, m + delta, 1);
    return monthKey(dt.year, dt.month);
  }

  static int monthsBetween(String fromKey, String toKey) {
    final (fy, fm) = parseMonthKey(fromKey);
    final (ty, tm) = parseMonthKey(toKey);
    return (ty - fy) * 12 + (tm - fm);
  }

  static int _priorityRank(String wire) => switch (wire) {
    'urgent' => 0,
    'essential' => 1,
    'nice' => 2,
    'dream' => 3,
    _ => 1,
  };

  static String _fmt(int minor, String currencyCode) => Money(
    amountMinor: minor,
    currencyCode: currencyCode,
  ).format(spec: CurrencyCatalog.byCode(currencyCode));

  /// Computes a complete monthly overview snapshot + smart bucket list plan.
  static MonthlyTrackerSnapshot buildSnapshot(MonthlyTrackerInput input) {
    final mk = monthKey(input.year, input.month);
    final nowMk = monthKey(input.nowUtc.year, input.nowUtc.month);
    final cmp = mk.compareTo(nowMk);
    final isCurrentMonth = cmp == 0;
    final isPastMonth = cmp < 0;
    final isFutureMonth = cmp > 0;

    final totalDays = daysInMonth(input.year, input.month);
    final daysElapsed = isCurrentMonth
        ? input.nowUtc.day.clamp(1, totalDays)
        : (isPastMonth ? totalDays : 0);
    final daysLeft = isCurrentMonth
        ? math.max<int>(1, totalDays - input.nowUtc.day + 1)
        : (isFutureMonth ? totalDays : 0);

    var grossSpend = 0;
    var needsSpent = 0;
    final dailySpend = List<int>.filled(totalDays, 0);
    final spendByCat = <String, int>{};
    final catIsEssential = <String, bool>{};

    for (final e in input.expenses) {
      if (e.amountMinor <= 0) continue;
      grossSpend += e.amountMinor;
      if (e.isEssential) {
        needsSpent += e.amountMinor;
      }
      spendByCat[e.categoryName] =
          (spendByCat[e.categoryName] ?? 0) + e.amountMinor;
      if (e.isEssential) {
        catIsEssential[e.categoryName] = true;
      } else {
        catIsEssential.putIfAbsent(e.categoryName, () => false);
      }

      final dt = DateTime.tryParse(e.dateUtc)?.toUtc();
      if (dt != null && dt.year == input.year && dt.month == input.month) {
        final idx = (dt.day - 1).clamp(0, totalDays - 1);
        dailySpend[idx] += e.amountMinor;
      }
    }

    final refunds = math.max<int>(0, input.refundsMinor);
    final spentMinor = math.max<int>(0, grossSpend - refunds);
    final wantsSpent = math.max<int>(0, spentMinor - needsSpent);

    final safeIncome = math.max<int>(0, input.incomeMinor);
    final safeExpected = math.max<int>(0, input.expectedIncomeMinor);
    final effectiveIncome = isPastMonth
        ? safeIncome
        : math.max<int>(safeIncome, safeExpected);

    final savedMinor = safeIncome - spentMinor;
    final savingsRatePct = safeIncome > 0
        ? (savedMinor * 100.0 / safeIncome)
        : 0.0;

    final committedRemaining = input.upcoming.fold<int>(
      0,
      (s, u) => s + math.max<int>(0, u.amountMinor),
    );
    final savingsTarget = (effectiveIncome * input.savingsTargetPct) ~/ 100;
    final availablePool = math.max<int>(
      0,
      effectiveIncome - spentMinor - committedRemaining - savingsTarget,
    );
    final wantsCapMinor = (effectiveIncome * input.wantsCapPct) ~/ 100;
    final wantsHeadroom = math.max<int>(0, wantsCapMinor - wantsSpent);

    final bucketPlan = planBucketList(
      items: input.bucketItems,
      monthKey: mk,
      nowUtc: input.nowUtc,
      availablePoolMinor: availablePool,
      savingsFloorMinor: savingsTarget,
      wantsHeadroomMinor: wantsHeadroom,
      effectiveIncomeMinor: effectiveIncome,
      currencyCode: input.currencyCode,
    );

    final bucketReserve = bucketPlan.poolAllocatedMinor;
    final freeToSpend =
        effectiveIncome -
        spentMinor -
        committedRemaining -
        savingsTarget -
        bucketReserve;
    final safeDaily = daysLeft > 0
        ? math.max<int>(0, freeToSpend) ~/ daysLeft
        : 0;

    final projectedMonthEnd = isCurrentMonth
        ? math.max<int>(
            spentMinor + committedRemaining,
            (spentMinor * totalDays) ~/ math.max<int>(1, daysElapsed),
          )
        : (isPastMonth ? spentMinor : committedRemaining);

    var noSpendDays = 0;
    for (var i = 0; i < daysElapsed; i++) {
      if (dailySpend[i] == 0) noSpendDays++;
    }
    var noSpendStreak = 0;
    for (var i = daysElapsed - 1; i >= 0; i--) {
      if (dailySpend[i] == 0) {
        noSpendStreak++;
      } else {
        break;
      }
    }
    var biggestDayNumber = 0;
    var biggestDayMinor = 0;
    for (var i = 0; i < totalDays; i++) {
      if (dailySpend[i] > biggestDayMinor) {
        biggestDayMinor = dailySpend[i];
        biggestDayNumber = i + 1;
      }
    }

    final catEntries = spendByCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topCategories = <MonthCategoryStat>[
      for (final entry in catEntries.take(6))
        () {
          final prev = input.previousSpendByCategory[entry.key] ?? 0;
          final deltaPct = prev > 0
              ? ((entry.value - prev) * 100.0 / prev)
              : null;
          return MonthCategoryStat(
            name: entry.key,
            amountMinor: entry.value,
            sharePct: grossSpend > 0 ? (entry.value * 100.0 / grossSpend) : 0.0,
            previousMinor: prev,
            deltaPct: deltaPct,
            isEssential: catIsEssential[entry.key] ?? false,
          );
        }(),
    ];

    final prevSpend = math.max<int>(0, input.previousSpendMinor);
    final spendDeltaPct = prevSpend > 0
        ? ((spentMinor - prevSpend) * 100.0 / prevSpend)
        : null;

    final budgetLimit = input.budgetLimitMinor;
    final budgetSpent = input.budgetSpentMinor;
    final budgetUsedPct = budgetLimit != null && budgetLimit > 0
        ? ((budgetSpent ?? spentMinor) * 100.0 / budgetLimit)
        : null;

    var score = 70;
    if (safeIncome > 0 && savingsRatePct >= input.savingsTargetPct) {
      score += 15;
    }
    if (effectiveIncome > 0 && projectedMonthEnd > effectiveIncome) {
      score -= 20;
    }
    if (effectiveIncome > 0 &&
        (wantsSpent * 100.0 / effectiveIncome) > input.wantsCapPct) {
      score -= 10;
    }
    if (bucketPlan.urgentShortfallMinor > 0) {
      score -= 15;
    }
    if (noSpendStreak >= 3) {
      score += 5;
    }
    final healthScore = score.clamp(10, 100);
    final healthLabel = healthScore < 45
        ? 'Over Plan'
        : (healthScore < 70 ? 'Watch' : 'On Track');

    // Deterministic Month Insights
    final insights = <MonthInsight>[];
    if (isCurrentMonth && safeIncome == 0 && safeExpected > 0) {
      insights.add(
        MonthInsight(
          title: 'Salary not logged yet',
          detail:
              'Using your ${_fmt(safeExpected, input.currencyCode)} planned income to project monthly headroom until salary hits.',
          severity: 'info',
          iconKey: 'schedule',
        ),
      );
    }
    if (safeIncome > 0 && savingsRatePct >= input.savingsTargetPct) {
      insights.add(
        MonthInsight(
          title: 'Savings rate ahead of target (${savingsRatePct.round()}%)',
          detail:
              'You kept ${_fmt(savedMinor, input.currencyCode)} unspent vs your ${input.savingsTargetPct}% goal.',
          severity: 'positive',
          iconKey: 'savings',
        ),
      );
    }
    if (effectiveIncome > 0 && projectedMonthEnd > effectiveIncome) {
      insights.add(
        MonthInsight(
          title: 'Month-end pace exceeds income',
          detail:
              'At current burn rate + upcoming bills, spend projects to ${_fmt(projectedMonthEnd, input.currencyCode)} vs ${_fmt(effectiveIncome, input.currencyCode)} income.',
          severity: 'danger',
          iconKey: 'warning',
        ),
      );
    }
    if (effectiveIncome > 0 &&
        (wantsSpent * 100.0 / effectiveIncome) > input.wantsCapPct) {
      final wantsPct = (wantsSpent * 100.0 / effectiveIncome).round();
      insights.add(
        MonthInsight(
          title: 'Wants share above ${input.wantsCapPct}% cap ($wantsPct%)',
          detail:
              'Discretionary spend is ${_fmt(wantsSpent, input.currencyCode)}. Trim dining/shopping or pause optional bucket items.',
          severity: 'warning',
          iconKey: 'tune',
        ),
      );
    }
    if (spendDeltaPct != null && spendDeltaPct >= 10.0) {
      insights.add(
        MonthInsight(
          title: 'Spending +${spendDeltaPct.round()}% vs last month',
          detail:
              'Spent ${_fmt(spentMinor, input.currencyCode)} vs ${_fmt(prevSpend, input.currencyCode)} last month.',
          severity: 'warning',
          iconKey: 'trending_up',
        ),
      );
    } else if (spendDeltaPct != null &&
        spendDeltaPct <= -10.0 &&
        spentMinor > 0) {
      insights.add(
        MonthInsight(
          title: 'Spending ${spendDeltaPct.abs().round()}% lower vs last month',
          detail:
              'Saved ${_fmt(prevSpend - spentMinor, input.currencyCode)} compared to last month.',
          severity: 'positive',
          iconKey: 'trending_down',
        ),
      );
    }
    if (noSpendStreak >= 3) {
      insights.add(
        MonthInsight(
          title: '$noSpendStreak-day no-spend streak active',
          detail:
              '$noSpendDays zero-spend days so far this month — strong daily discipline.',
          severity: 'positive',
          iconKey: 'streak',
        ),
      );
    }
    if (committedRemaining >
        math.max<int>(0, freeToSpend + committedRemaining)) {
      insights.add(
        MonthInsight(
          title: 'Upcoming bills exceed remaining room',
          detail:
              '${_fmt(committedRemaining, input.currencyCode)} in bills/EMIs are due later this month.',
          severity: 'warning',
          iconKey: 'receipt',
        ),
      );
    }
    if (bucketPlan.urgentShortfallMinor > 0) {
      insights.add(
        MonthInsight(
          title:
              'Urgent bucket shortfall (${_fmt(bucketPlan.urgentShortfallMinor, input.currencyCode)})',
          detail:
              'One or more urgent bucket purchases exceed both cash-flow headroom and savings buffer.',
          severity: 'danger',
          iconKey: 'bolt',
        ),
      );
    }

    return MonthlyTrackerSnapshot(
      currencyCode: input.currencyCode,
      year: input.year,
      month: input.month,
      monthKey: mk,
      isCurrentMonth: isCurrentMonth,
      isPastMonth: isPastMonth,
      isFutureMonth: isFutureMonth,
      daysInMonth: totalDays,
      daysElapsed: daysElapsed,
      daysLeft: daysLeft,
      incomeMinor: safeIncome,
      expectedIncomeMinor: safeExpected,
      effectiveIncomeMinor: effectiveIncome,
      grossSpendMinor: grossSpend,
      refundsMinor: refunds,
      spentMinor: spentMinor,
      needsSpentMinor: needsSpent,
      wantsSpentMinor: wantsSpent,
      savedMinor: savedMinor,
      savingsRatePct: savingsRatePct,
      committedRemainingMinor: committedRemaining,
      savingsTargetMinor: savingsTarget,
      bucketReserveMinor: bucketReserve,
      freeToSpendMinor: freeToSpend,
      safeDailySpendMinor: safeDaily,
      projectedMonthEndSpendMinor: projectedMonthEnd,
      dailySpendMinor: dailySpend,
      noSpendDays: noSpendDays,
      noSpendStreak: noSpendStreak,
      biggestDayNumber: biggestDayNumber,
      biggestDayMinor: biggestDayMinor,
      topCategories: topCategories,
      previousIncomeMinor: math.max<int>(0, input.previousIncomeMinor),
      previousSpendMinor: prevSpend,
      spendDeltaVsLastMonthPct: spendDeltaPct,
      budgetLimitMinor: budgetLimit,
      budgetSpentMinor: budgetSpent,
      budgetUsedPct: budgetUsedPct,
      healthScore: healthScore,
      healthLabel: healthLabel,
      insights: insights,
      bucketPlan: bucketPlan,
    );
  }

  /// Priority-aware Bucket List planner allocating free headroom cleanly:
  /// `urgent` -> `essential` -> `nice` (inside wants headroom) -> `dream` (goal).
  static BucketPlan planBucketList({
    required List<BucketPlanInput> items,
    required String monthKey,
    required DateTime nowUtc,
    required int availablePoolMinor,
    required int savingsFloorMinor,
    required int wantsHeadroomMinor,
    required int effectiveIncomeMinor,
    String currencyCode = 'INR',
  }) {
    final todayDay = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
    bool isOverdueItem(BucketPlanInput x) {
      if (x.targetYearMonth.compareTo(monthKey) < 0) return true;
      final raw = x.dueDateUtc;
      final d = raw != null ? DateTime.tryParse(raw)?.toUtc() : null;
      if (d == null) return false;
      return DateTime.utc(d.year, d.month, d.day).isBefore(todayDay);
    }

    final sorted = [...items]
      ..sort((a, b) {
        final pa = _priorityRank(a.priority);
        final pb = _priorityRank(b.priority);
        if (pa != pb) return pa.compareTo(pb);
        final oa = isOverdueItem(a) ? 0 : 1;
        final ob = isOverdueItem(b) ? 0 : 1;
        if (oa != ob) return oa.compareTo(ob);
        final da = a.dueDateUtc ?? '9999-12-31';
        final db = b.dueDateUtc ?? '9999-12-31';
        final dc = da.compareTo(db);
        if (dc != 0) return dc;
        return a.createdAtUtc.compareTo(b.createdAtUtc);
      });

    var pool = math.max<int>(0, availablePoolMinor);
    var savingsFloorLeft = math.max<int>(0, savingsFloorMinor);
    var headroom = math.max<int>(0, wantsHeadroomMinor);

    var totalPlannedThisMonth = 0;
    var totalAllocated = 0;
    var totalUsesSavings = 0;
    var affordableCount = 0;
    var deferredCount = 0;
    var urgentShortfallTotal = 0;
    var essentialUnfundedTotal = 0;

    final plans = <BucketItemPlan>[];
    final byId = <String, BucketItemPlan>{};

    for (final item in sorted) {
      final remaining = math.max<int>(
        0,
        item.estimatedMinor - math.max<int>(0, item.savedMinor),
      );
      final dueDt = item.dueDateUtc != null
          ? DateTime.tryParse(item.dueDateUtc!)?.toUtc()
          : null;
      final dueDay = dueDt != null
          ? DateTime.utc(dueDt.year, dueDt.month, dueDt.day)
          : null;
      final isMonthPast = item.targetYearMonth.compareTo(monthKey) < 0;
      final isDuePast = dueDay != null && dueDay.isBefore(todayDay);
      final isOverdue = isMonthPast || isDuePast;
      final daysToDue = dueDay != null
          ? dueDay.difference(todayDay).inDays
          : 99;
      final isDueSoon = !isOverdue && daysToDue >= 0 && daysToDue <= 7;

      // Cooling-off flag for impulse 'nice' purchases created within 7 days > 5% income
      final createdDt = DateTime.tryParse(item.createdAtUtc)?.toUtc();
      final ageDays = createdDt != null
          ? nowUtc.difference(createdDt).inDays
          : 99;
      final coolingOff =
          item.priority == 'nice' &&
          ageDays <= 7 &&
          effectiveIncomeMinor > 0 &&
          (item.estimatedMinor * 20) > effectiveIncomeMinor;

      // Future target months: verdict = scheduled
      if (item.targetYearMonth.compareTo(monthKey) > 0) {
        final monthsUntil = math.max<int>(
          0,
          monthsBetween(monthKey, item.targetYearMonth),
        );
        final denom = math.max<int>(1, monthsUntil + 1);
        final perMonth = remaining > 0 ? (remaining + denom - 1) ~/ denom : 0;
        final p = BucketItemPlan(
          itemId: item.id,
          verdict: BucketVerdict.scheduled,
          allocatedThisMonthMinor: 0,
          remainingAfterMinor: remaining,
          usesSavingsMinor: 0,
          suggestedMonthlySavingMinor: perMonth,
          monthsToSave: denom,
          isOverdue: false,
          isDueSoon: isDueSoon,
          coolingOffSuggested: coolingOff,
          headline: 'Scheduled for ${item.targetYearMonth}',
          detail: remaining == 0
              ? 'Already fully funded ahead of ${item.targetYearMonth}.'
              : 'Set aside ${_fmt(perMonth, currencyCode)}/mo for $denom months.',
        );
        plans.add(p);
        byId[item.id] = p;
        continue;
      }

      // Target month <= active month
      totalPlannedThisMonth += remaining;

      if (remaining == 0) {
        affordableCount++;
        final p = BucketItemPlan(
          itemId: item.id,
          verdict: BucketVerdict.funded,
          allocatedThisMonthMinor: 0,
          remainingAfterMinor: 0,
          usesSavingsMinor: 0,
          suggestedMonthlySavingMinor: 0,
          monthsToSave: 0,
          isOverdue: isOverdue,
          isDueSoon: isDueSoon,
          coolingOffSuggested: false,
          headline: 'Fully funded — buy anytime',
          detail: 'Full estimate saved. Mark as bought when purchased.',
        );
        plans.add(p);
        byId[item.id] = p;
        continue;
      }

      if (item.priority == 'urgent') {
        final fromPool = math.min<int>(remaining, pool);
        pool -= fromPool;
        final stillNeed = remaining - fromPool;
        final fromSavings = stillNeed > 0
            ? math.min<int>(stillNeed, savingsFloorLeft)
            : 0;
        savingsFloorLeft -= fromSavings;
        final alloc = fromPool + fromSavings;
        final shortfall = remaining - alloc;

        totalAllocated += alloc;
        totalUsesSavings += fromSavings;

        if (shortfall > 0) {
          deferredCount++;
          urgentShortfallTotal += shortfall;
          final p = BucketItemPlan(
            itemId: item.id,
            verdict: BucketVerdict.urgentShortfall,
            allocatedThisMonthMinor: alloc,
            remainingAfterMinor: shortfall,
            usesSavingsMinor: fromSavings,
            suggestedMonthlySavingMinor: shortfall,
            monthsToSave: 1,
            isOverdue: isOverdue,
            isDueSoon: isDueSoon,
            coolingOffSuggested: false,
            headline: 'Short ${_fmt(shortfall, currencyCode)} this month',
            detail: alloc > 0
                ? 'Allocated ${_fmt(alloc, currencyCode)} (incl. ${_fmt(fromSavings, currencyCode)} savings buffer); add extra income or trim wants for ${_fmt(shortfall, currencyCode)}.'
                : 'Exceeds available cash flow and savings target by ${_fmt(shortfall, currencyCode)}.',
          );
          plans.add(p);
          byId[item.id] = p;
        } else {
          affordableCount++;
          final p = BucketItemPlan(
            itemId: item.id,
            verdict: BucketVerdict.buyNow,
            allocatedThisMonthMinor: alloc,
            remainingAfterMinor: 0,
            usesSavingsMinor: fromSavings,
            suggestedMonthlySavingMinor: 0,
            monthsToSave: 0,
            isOverdue: isOverdue,
            isDueSoon: isDueSoon,
            coolingOffSuggested: false,
            headline: fromSavings > 0
                ? 'Buy now (uses ${_fmt(fromSavings, currencyCode)} savings)'
                : 'Buy now — covered cleanly',
            detail: fromSavings > 0
                ? 'Covered by ${_fmt(fromPool, currencyCode)} surplus + ${_fmt(fromSavings, currencyCode)} from monthly savings floor.'
                : 'Fully covered within this month’s free cash flow without touching savings.',
          );
          plans.add(p);
          byId[item.id] = p;
        }
        continue;
      }

      if (item.priority == 'essential') {
        final alloc = math.min<int>(remaining, pool);
        pool -= alloc;
        final remAfter = remaining - alloc;
        totalAllocated += alloc;

        if (remAfter == 0) {
          affordableCount++;
          final p = BucketItemPlan(
            itemId: item.id,
            verdict: BucketVerdict.buyNow,
            allocatedThisMonthMinor: alloc,
            remainingAfterMinor: 0,
            usesSavingsMinor: 0,
            suggestedMonthlySavingMinor: 0,
            monthsToSave: 0,
            isOverdue: isOverdue,
            isDueSoon: isDueSoon,
            coolingOffSuggested: false,
            headline: 'Buy now — fits your Need budget',
            detail:
                'Reserved ${_fmt(alloc, currencyCode)} without cutting savings.',
          );
          plans.add(p);
          byId[item.id] = p;
        } else if (alloc > 0) {
          deferredCount++;
          essentialUnfundedTotal += remAfter;
          final p = BucketItemPlan(
            itemId: item.id,
            verdict: BucketVerdict.partial,
            allocatedThisMonthMinor: alloc,
            remainingAfterMinor: remAfter,
            usesSavingsMinor: 0,
            suggestedMonthlySavingMinor: remAfter,
            monthsToSave: 2,
            isOverdue: isOverdue,
            isDueSoon: isDueSoon,
            coolingOffSuggested: false,
            headline:
                'Fund ${_fmt(alloc, currencyCode)} now · ${_fmt(remAfter, currencyCode)} next mo',
            detail:
                'Reserve ${_fmt(alloc, currencyCode)} this month and finish the remaining ${_fmt(remAfter, currencyCode)} next month.',
          );
          plans.add(p);
          byId[item.id] = p;
        } else {
          deferredCount++;
          essentialUnfundedTotal += remaining;
          final p = BucketItemPlan(
            itemId: item.id,
            verdict: BucketVerdict.defer,
            allocatedThisMonthMinor: 0,
            remainingAfterMinor: remaining,
            usesSavingsMinor: 0,
            suggestedMonthlySavingMinor: remaining,
            monthsToSave: 2,
            isOverdue: isOverdue,
            isDueSoon: isDueSoon,
            coolingOffSuggested: false,
            headline: 'Defer to ${shiftMonth(monthKey, 1)}',
            detail:
                'Free cash flow is committed; save ${_fmt(remaining, currencyCode)} for next month.',
          );
          plans.add(p);
          byId[item.id] = p;
        }
        continue;
      }

      if (item.priority == 'nice') {
        final alloc = math.min<int>(remaining, math.min<int>(pool, headroom));
        pool -= alloc;
        headroom -= alloc;
        final remAfter = remaining - alloc;
        totalAllocated += alloc;

        if (remAfter == 0) {
          affordableCount++;
          final p = BucketItemPlan(
            itemId: item.id,
            verdict: BucketVerdict.buyNow,
            allocatedThisMonthMinor: alloc,
            remainingAfterMinor: 0,
            usesSavingsMinor: 0,
            suggestedMonthlySavingMinor: 0,
            monthsToSave: 0,
            isOverdue: isOverdue,
            isDueSoon: isDueSoon,
            coolingOffSuggested: coolingOff,
            headline: coolingOff
                ? 'Affordable — wait 7 days first'
                : 'Buy now — inside wants cap',
            detail: coolingOff
                ? '7-day impulse rule: wait until week’s end before spending >5% of income.'
                : 'Fits cleanly inside your monthly wants & free-cash cap.',
          );
          plans.add(p);
          byId[item.id] = p;
        } else if (alloc > 0) {
          deferredCount++;
          final p = BucketItemPlan(
            itemId: item.id,
            verdict: BucketVerdict.partial,
            allocatedThisMonthMinor: alloc,
            remainingAfterMinor: remAfter,
            usesSavingsMinor: 0,
            suggestedMonthlySavingMinor: remAfter,
            monthsToSave: 2,
            isOverdue: isOverdue,
            isDueSoon: isDueSoon,
            coolingOffSuggested: coolingOff,
            headline: 'Fund ${_fmt(alloc, currencyCode)} now · finish next mo',
            detail:
                'Wants cap limits this month to ${_fmt(alloc, currencyCode)}. Finish ${_fmt(remAfter, currencyCode)} next month.',
          );
          plans.add(p);
          byId[item.id] = p;
        } else {
          deferredCount++;
          final p = BucketItemPlan(
            itemId: item.id,
            verdict: BucketVerdict.defer,
            allocatedThisMonthMinor: 0,
            remainingAfterMinor: remaining,
            usesSavingsMinor: 0,
            suggestedMonthlySavingMinor: (remaining + 1) ~/ 2,
            monthsToSave: 2,
            isOverdue: isOverdue,
            isDueSoon: isDueSoon,
            coolingOffSuggested: coolingOff,
            headline: 'Wait — wants cap reached',
            detail:
                'Save ${_fmt((remaining + 1) ~/ 2, currencyCode)}/mo across 2 months without breaking savings.',
          );
          plans.add(p);
          byId[item.id] = p;
        }
        continue;
      }

      // Priority == 'dream': never allocated directly out of monthly cash flow; save up via Goal.
      deferredCount++;
      final dreamMonths = dueDt != null
          ? math.max<int>(
              1,
              monthsBetween(
                monthKey,
                MonthlyTrackerEngine.monthKey(dueDt.year, dueDt.month),
              ),
            )
          : 6;
      final monthlySave = (remaining + dreamMonths - 1) ~/ dreamMonths;
      final p = BucketItemPlan(
        itemId: item.id,
        verdict: BucketVerdict.saveUp,
        allocatedThisMonthMinor: 0,
        remainingAfterMinor: remaining,
        usesSavingsMinor: 0,
        suggestedMonthlySavingMinor: monthlySave,
        monthsToSave: dreamMonths,
        isOverdue: isOverdue,
        isDueSoon: isDueSoon,
        coolingOffSuggested: false,
        headline:
            'Save ${_fmt(monthlySave, currencyCode)}/mo ($dreamMonths mo)',
        detail:
            'Convert to Savings Goal so this dream builds steadily without squeezing monthly essentials.',
      );
      plans.add(p);
      byId[item.id] = p;
    }

    return BucketPlan(
      items: plans,
      byItemId: byId,
      totalPlannedThisMonthMinor: totalPlannedThisMonth,
      totalAllocatedMinor: totalAllocated,
      totalUsesSavingsMinor: totalUsesSavings,
      affordableCount: affordableCount,
      deferredCount: deferredCount,
      urgentShortfallMinor: urgentShortfallTotal,
      essentialUnfundedMinor: essentialUnfundedTotal,
      poolLeftAfterMinor: pool,
    );
  }

  /// Smart 3-way windfall split: patches any month gap first, funds urgent/essential
  /// bucket items next, lets you enjoy a small slice, and compounds the rest to Savings.
  static WindfallSplit suggestWindfallSplit({
    required int amountMinor,
    required int monthGapMinor,
    required int urgentShortfallMinor,
    required int essentialUnfundedMinor,
    String currencyCode = 'INR',
  }) {
    final safeAmount = math.max<int>(0, amountMinor);
    if (safeAmount == 0) {
      return const WindfallSplit(
        toSavingsMinor: 0,
        toBucketMinor: 0,
        toSpendMinor: 0,
        rationale: 'Enter an extra income amount to calculate a split.',
      );
    }

    final safeGap = math.max<int>(0, monthGapMinor);
    final safeUrgent = math.max<int>(0, urgentShortfallMinor);
    final safeEssential = math.max<int>(0, essentialUnfundedMinor);

    var toSpend = math.min<int>(safeAmount, safeGap);
    var r = safeAmount - toSpend;

    final bucketNeed = safeUrgent + safeEssential;
    final toBucket = math.min<int>(
      bucketNeed,
      (r * (safeUrgent > 0 ? 0.6 : 0.3)).round(),
    );
    r -= toBucket;

    final extraSpend = math.min<int>(
      r,
      (r * (safeGap > 0 ? 0.1 : 0.2)).round(),
    );
    toSpend += extraSpend;

    final toSavings = safeAmount - toBucket - toSpend;

    final reasons = <String>[];
    if (safeGap > 0) {
      reasons.add(
        'closes ${_fmt(math.min<int>(safeAmount, safeGap), currencyCode)} monthly gap',
      );
    }
    if (toBucket > 0) {
      reasons.add(
        'funds ${_fmt(toBucket, currencyCode)} of priority bucket items',
      );
    }
    if (toSavings > 0) {
      reasons.add('locks ${_fmt(toSavings, currencyCode)} into future savings');
    }

    return WindfallSplit(
      toSavingsMinor: toSavings,
      toBucketMinor: toBucket,
      toSpendMinor: toSpend,
      rationale: reasons.isEmpty
          ? 'Balanced split across savings, bucket list, and spending.'
          : 'Smart CFP split: ${reasons.join(', ')}.',
    );
  }

  /// Fixed-percentage split preset guaranteeing exact zero-remainder sum.
  static WindfallSplit presetSplit(
    int amountMinor,
    int savePct,
    int bucketPct,
  ) {
    final safeAmount = math.max<int>(0, amountMinor);
    final toSavings = (safeAmount * savePct.clamp(0, 100)) ~/ 100;
    final maxRest = safeAmount - toSavings;
    final toBucket = math.min<int>(
      maxRest,
      (safeAmount * bucketPct.clamp(0, 100)) ~/ 100,
    );
    final toSpend = safeAmount - toSavings - toBucket;
    return WindfallSplit(
      toSavingsMinor: toSavings,
      toBucketMinor: toBucket,
      toSpendMinor: toSpend,
      rationale:
          '$savePct% savings · $bucketPct% bucket · ${100 - savePct - bucketPct}% this month.',
    );
  }

  /// Generates a 100-point CFO Monthly Scorecard & shareable plain-text recap.
  static MonthScorecard buildScorecard(
    MonthlyTrackerSnapshot snap, {
    int boughtBucketCount = 0,
  }) {
    final int savingsPts;
    if (snap.incomeMinor <= 0) {
      savingsPts = snap.spentMinor == 0 ? 20 : 10;
    } else {
      final derivedTargetPct = snap.effectiveIncomeMinor > 0
          ? (snap.savingsTargetMinor * 100.0) / snap.effectiveIncomeMinor
          : 20.0;
      final target = math.max<double>(1.0, derivedTargetPct);
      savingsPts = ((snap.savingsRatePct / target) * 40.0).round().clamp(0, 40);
    }

    final safeCeiling = math.max<int>(
      1,
      snap.effectiveIncomeMinor - snap.savingsTargetMinor,
    );
    final paceRatio = snap.projectedMonthEndSpendMinor / safeCeiling;
    final int pacePts;
    if (paceRatio <= 1.0) {
      pacePts = 30;
    } else if (paceRatio <= 1.15) {
      pacePts = 20;
    } else if (paceRatio <= 1.30) {
      pacePts = 10;
    } else {
      pacePts = 4;
    }

    final elapsed = math.max<int>(1, snap.daysElapsed);
    final disciplinePts = ((snap.noSpendDays / elapsed) * 15.0).round().clamp(
      0,
      15,
    );

    final int bucketPts;
    if (snap.bucketPlan.urgentShortfallMinor == 0 &&
        snap.bucketPlan.deferredCount == 0) {
      bucketPts = 15;
    } else if (snap.bucketPlan.urgentShortfallMinor == 0) {
      bucketPts = 10;
    } else {
      bucketPts = 4;
    }

    final score = (savingsPts + pacePts + disciplinePts + bucketPts).clamp(
      0,
      100,
    );
    final grade = switch (score) {
      >= 90 => 'A+',
      >= 78 => 'A',
      >= 64 => 'B',
      >= 48 => 'C',
      _ => 'D',
    };

    final streakNote = snap.noSpendStreak >= 3
        ? ' ${snap.noSpendStreak}-day zero-spend streak active.'
        : (boughtBucketCount > 0
              ? ' $boughtBucketCount planned buy${boughtBucketCount == 1 ? '' : 's'} fulfilled without stress.'
              : '');

    final headline = switch (grade) {
      'A+' =>
        'Elite monthly rhythm — savings & pace are ahead of plan.$streakNote',
      'A' => 'Strong cash-flow control with healthy headroom.$streakNote',
      'B' =>
        'Steady month — small tweaks to discretionary pace unlock more room.$streakNote',
      'C' =>
        'Tight month ahead — protect your savings floor & delay non-urgent wants.$streakNote',
      _ =>
        'Deficit alert — pause impulse buys and route extra income to essentials.',
    };

    final monthTag = monthKey(snap.year, snap.month);
    final rateLabel = snap.incomeMinor > 0
        ? '${snap.savingsRatePct.toStringAsFixed(0)}%'
        : 'Planned';
    final shareSummary =
        'Pocket CFO Recap ($monthTag): Grade $grade ($score/100) · '
        'Savings rate $rateLabel · ${snap.noSpendDays} zero-spend days · '
        'Safe daily pace ${_fmt(snap.safeDailySpendMinor, snap.currencyCode)}/day.';

    return MonthScorecard(
      score: score,
      grade: grade,
      headline: headline.trim(),
      savingsPoints: savingsPts,
      pacePoints: pacePts,
      disciplinePoints: disciplinePts,
      bucketPoints: bucketPts,
      shareSummary: shareSummary,
    );
  }

  /// Evaluates in real time whether a planned bucket item fits this month's
  /// remaining safe-to-spend pool before the user saves or buys it.
  static PurchaseAffordabilityPreview previewPurchaseAffordability({
    required MonthlyTrackerSnapshot snapshot,
    required int amountMinor,
    required String priority,
  }) {
    final safeAmt = math.max<int>(0, amountMinor);
    final ccy = snapshot.currencyCode;
    final remainingAfter = snapshot.freeToSpendMinor - safeAmt;
    final dailyAfter = snapshot.daysLeft > 0
        ? math.max<int>(0, remainingAfter) ~/ snapshot.daysLeft
        : 0;
    final coolingOff =
        priority == 'nice' &&
        snapshot.effectiveIncomeMinor > 0 &&
        safeAmt * 100 > snapshot.effectiveIncomeMinor * 5;

    if (priority == 'dream') {
      final per3 = (safeAmt / 3.0).ceil();
      return PurchaseAffordabilityPreview(
        tone: 'goal',
        verdictLabel: 'Plan as Savings Goal',
        guidance:
            'Big wish — save ~${_fmt(per3, ccy)}/mo over 3 months without touching monthly bills.',
        remainingFreeAfterMinor: remainingAfter,
        dailySafeAfterMinor: dailyAfter,
        coolingOffWarning: false,
      );
    }

    if (safeAmt <= 0) {
      return PurchaseAffordabilityPreview(
        tone: 'safe',
        verdictLabel: 'Enter cost to test headroom',
        guidance:
            'Current free-to-spend pool: ${_fmt(snapshot.freeToSpendMinor, ccy)}.',
        remainingFreeAfterMinor: snapshot.freeToSpendMinor,
        dailySafeAfterMinor: snapshot.safeDailySpendMinor,
        coolingOffWarning: false,
      );
    }

    if (remainingAfter >= 0) {
      final isClose =
          snapshot.freeToSpendMinor > 0 &&
          remainingAfter < (snapshot.freeToSpendMinor * 0.2).round();
      if (coolingOff) {
        return PurchaseAffordabilityPreview(
          tone: 'caution',
          verdictLabel: 'Fits headroom · Wait 7 days',
          guidance:
              'Above 5% of monthly income — let the 7-day rule test it. Leaves ${_fmt(dailyAfter, ccy)}/day.',
          remainingFreeAfterMinor: remainingAfter,
          dailySafeAfterMinor: dailyAfter,
          coolingOffWarning: true,
        );
      }
      return PurchaseAffordabilityPreview(
        tone: isClose ? 'caution' : 'safe',
        verdictLabel: isClose
            ? 'Fits, but leaves a thin buffer'
            : 'Comfortably affordable',
        guidance:
            'Leaves ${_fmt(remainingAfter, ccy)} free (${_fmt(dailyAfter, ccy)}/day for ${snapshot.daysLeft}d).',
        remainingFreeAfterMinor: remainingAfter,
        dailySafeAfterMinor: dailyAfter,
        coolingOffWarning: false,
      );
    }

    final shortfall = -remainingAfter;
    if (priority == 'urgent') {
      return PurchaseAffordabilityPreview(
        tone: 'tight',
        verdictLabel: 'Draws ${_fmt(shortfall, ccy)} from savings',
        guidance:
            'Urgent need exceeds free headroom — cover the gap from your savings buffer or Extra Income.',
        remainingFreeAfterMinor: remainingAfter,
        dailySafeAfterMinor: 0,
        coolingOffWarning: false,
      );
    }

    return PurchaseAffordabilityPreview(
      tone: 'tight',
      verdictLabel: 'Short by ${_fmt(shortfall, ccy)} this month',
      guidance: coolingOff
          ? 'Exceeds this month\'s headroom & 5% wants threshold — schedule for next month.'
          : 'Try splitting into 2 months or funding with a mid-month windfall.',
      remainingFreeAfterMinor: remainingAfter,
      dailySafeAfterMinor: 0,
      coolingOffWarning: coolingOff,
    );
  }
}
