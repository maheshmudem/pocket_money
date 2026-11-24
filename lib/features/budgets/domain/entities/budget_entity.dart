import 'package:equatable/equatable.dart';

import '../../../../core/financial_engine/money.dart';
import '../../../../core/utilities/id_generator.dart';

enum BudgetPeriodType {
  weekly('weekly', 'Weekly'),
  monthly('monthly', 'Monthly'),
  quarterly('quarterly', 'Quarterly'),
  yearly('yearly', 'Yearly'),
  custom('custom', 'Custom');

  const BudgetPeriodType(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static BudgetPeriodType fromWire(String raw) => switch (raw) {
    'weekly' => BudgetPeriodType.weekly,
    'quarterly' => BudgetPeriodType.quarterly,
    'yearly' => BudgetPeriodType.yearly,
    'custom' => BudgetPeriodType.custom,
    _ => BudgetPeriodType.monthly,
  };
}

final class BudgetCategoryAllocation extends Equatable {
  const BudgetCategoryAllocation({
    required this.categoryId,
    required this.categoryName,
    required this.limitMinor,
    required this.spentMinor,
    required this.currencyCode,
  });

  final String categoryId;
  final String categoryName;
  final int limitMinor;
  final int spentMinor;
  final String currencyCode;

  int get remainingMinor => limitMinor - spentMinor;
  double get utilizationRatio => limitMinor > 0 ? spentMinor / limitMinor : 0.0;
  bool get isOverspent => spentMinor > limitMinor;

  @override
  List<Object?> get props => [
    categoryId,
    categoryName,
    limitMinor,
    spentMinor,
    currencyCode,
  ];
}

final class BudgetEntity extends Equatable {
  const BudgetEntity({
    required this.id,
    required this.profileId,
    required this.name,
    required this.periodType,
    required this.startDateUtc,
    required this.overallLimit,
    required this.totalSpent,
    required this.rolloverEnabled,
    required this.isActive,
    required this.allocations,
    this.endDateUtc,
  });

  final String id;
  final ProfileId profileId;
  final String name;
  final BudgetPeriodType periodType;
  final String startDateUtc;
  final String? endDateUtc;
  final Money overallLimit;
  final Money totalSpent;
  final bool rolloverEnabled;
  final bool isActive;
  final List<BudgetCategoryAllocation> allocations;

  Money get remaining => Money(
    amountMinor: overallLimit.amountMinor - totalSpent.amountMinor,
    currencyCode: overallLimit.currencyCode,
  );

  double get utilizationRatio => overallLimit.amountMinor > 0
      ? totalSpent.amountMinor / overallLimit.amountMinor
      : 0.0;

  bool get isOverspent => totalSpent.amountMinor > overallLimit.amountMinor;

  /// Inclusive remaining days in this budget's active window from [nowUtc].
  int remainingDaysAt(DateTime nowUtc) {
    final end = endDateUtc != null
        ? DateTime.tryParse(endDateUtc!)?.toUtc()
        : null;
    if (end == null) {
      final fallbackEnd = DateTime.utc(nowUtc.year, nowUtc.month + 1, 0);
      final diff = fallbackEnd.day - nowUtc.day + 1;
      return diff < 1 ? 1 : diff;
    }
    final today = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
    final endDay = DateTime.utc(end.year, end.month, end.day);
    final diff = endDay.difference(today).inDays + 1;
    return diff < 1 ? 1 : diff;
  }

  /// Safe daily spending allowance within this budget's remaining window.
  int safePerDayMinorAt(DateTime nowUtc) {
    final rem = remaining.amountMinor;
    if (rem <= 0) return 0;
    return rem ~/ remainingDaysAt(nowUtc);
  }

  @override
  List<Object?> get props => [
    id,
    profileId,
    name,
    periodType,
    startDateUtc,
    endDateUtc,
    overallLimit,
    totalSpent,
    rolloverEnabled,
    isActive,
    allocations,
  ];
}

/// Pure aggregate across active budgets that prevents double-counting category
/// sub-caps against profile-wide overall budgets and respects each budget's
/// actual period window when computing Safe / Day allowance.
final class BudgetHealthAggregate extends Equatable {
  const BudgetHealthAggregate({
    required this.totalLimitMinor,
    required this.totalSpentMinor,
    required this.remainingMinor,
    required this.safePerDayMinor,
    required this.minDaysLeft,
    required this.maxDaysLeft,
    required this.primaryPeriodLabel,
    required this.budgetCount,
  });

  final int totalLimitMinor;
  final int totalSpentMinor;
  final int remainingMinor;
  final int safePerDayMinor;
  final int minDaysLeft;
  final int maxDaysLeft;
  final String primaryPeriodLabel;
  final int budgetCount;

  double get utilizationRatio => totalLimitMinor > 0
      ? (totalSpentMinor / totalLimitMinor).clamp(0.0, 1.0)
      : 0.0;

  String get daysLeftHeadline {
    if (minDaysLeft == maxDaysLeft) {
      return '$minDaysLeft day${minDaysLeft == 1 ? '' : 's'} left in $primaryPeriodLabel';
    }
    return '$minDaysLeft–$maxDaysLeft days left across $budgetCount budgets';
  }

  String get compactDaysLeftLabel => minDaysLeft == maxDaysLeft
      ? '$minDaysLeft day${minDaysLeft == 1 ? '' : 's'} left • $budgetCount active'
      : '$minDaysLeft–$maxDaysLeft days left • $budgetCount active';

  static BudgetHealthAggregate compute(
    List<BudgetEntity> budgets,
    DateTime nowUtc,
  ) {
    if (budgets.isEmpty) {
      final endOfMonth = DateTime.utc(nowUtc.year, nowUtc.month + 1, 0);
      final days = (endOfMonth.day - nowUtc.day + 1).clamp(1, 31);
      return BudgetHealthAggregate(
        totalLimitMinor: 0,
        totalSpentMinor: 0,
        remainingMinor: 0,
        safePerDayMinor: 0,
        minDaysLeft: days,
        maxDaysLeft: days,
        primaryPeriodLabel: 'current month',
        budgetCount: 0,
      );
    }

    // Prefer overall profile budgets over category sub-caps so category limits
    // never double-count against a master spending envelope.
    final overallBudgets = budgets.where((b) => b.allocations.isEmpty).toList();
    final primary = overallBudgets.isNotEmpty ? overallBudgets : budgets;

    final totalLimit = primary.fold<int>(
      0,
      (s, b) => s + b.overallLimit.amountMinor,
    );
    final totalSpent = primary.fold<int>(
      0,
      (s, b) => s + b.totalSpent.amountMinor,
    );
    final remaining = totalLimit - totalSpent;

    var minDays = primary.first.remainingDaysAt(nowUtc);
    var maxDays = minDays;
    var sumSafePerDay = 0;
    for (final b in primary) {
      final d = b.remainingDaysAt(nowUtc);
      if (d < minDays) minDays = d;
      if (d > maxDays) maxDays = d;
      sumSafePerDay += b.safePerDayMinorAt(nowUtc);
    }

    final safePerDay = remaining <= 0
        ? 0
        : (minDays == maxDays ? (remaining ~/ minDays) : sumSafePerDay);

    final samePeriod = primary.every(
      (b) => b.periodType == primary.first.periodType,
    );
    final periodLabel = samePeriod
        ? '${primary.first.periodType.label.toLowerCase()} window'
        : 'active windows';

    return BudgetHealthAggregate(
      totalLimitMinor: totalLimit,
      totalSpentMinor: totalSpent,
      remainingMinor: remaining,
      safePerDayMinor: safePerDay,
      minDaysLeft: minDays,
      maxDaysLeft: maxDays,
      primaryPeriodLabel: periodLabel,
      budgetCount: budgets.length,
    );
  }

  @override
  List<Object?> get props => [
    totalLimitMinor,
    totalSpentMinor,
    remainingMinor,
    safePerDayMinor,
    minDaysLeft,
    maxDaysLeft,
    primaryPeriodLabel,
    budgetCount,
  ];
}
