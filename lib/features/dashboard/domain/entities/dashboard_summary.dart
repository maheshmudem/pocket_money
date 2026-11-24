import 'package:equatable/equatable.dart';

import '../../../../core/financial_engine/money.dart';
import '../../../../core/utilities/id_generator.dart';
import '../../../accounts/domain/entities/financial_account_entity.dart';
import '../../../transactions/domain/entities/transaction_entity.dart';

enum DashboardPeriodPreset {
  thisMonth('This month'),
  lastMonth('Last month'),
  last3Months('Last 3 months'),
  yearToDate('Year to date'),
  allTime('All time');

  const DashboardPeriodPreset(this.label);
  final String label;

  ({DateTime? fromUtc, DateTime? toUtc}) resolveBoundsUtc(DateTime nowUtc) {
    final y = nowUtc.year;
    final m = nowUtc.month;
    return switch (this) {
      DashboardPeriodPreset.thisMonth => (
        fromUtc: DateTime.utc(y, m, 1),
        toUtc: DateTime.utc(y, m + 1, 0, 23, 59, 59),
      ),
      DashboardPeriodPreset.lastMonth => (
        fromUtc: DateTime.utc(y, m - 1, 1),
        toUtc: DateTime.utc(y, m, 0, 23, 59, 59),
      ),
      DashboardPeriodPreset.last3Months => (
        fromUtc: DateTime.utc(y, m - 2, 1),
        toUtc: DateTime.utc(y, m + 1, 0, 23, 59, 59),
      ),
      DashboardPeriodPreset.yearToDate => (
        fromUtc: DateTime.utc(y, 1, 1),
        toUtc: DateTime.utc(y, 12, 31, 23, 59, 59),
      ),
      DashboardPeriodPreset.allTime => (fromUtc: null, toUtc: null),
    };
  }
}

final class CategorySpendItem extends Equatable {
  const CategorySpendItem({
    required this.categoryId,
    required this.categoryName,
    required this.grossSpendMinor,
    required this.refundsMinor,
    required this.netSpendMinor,
    required this.currencyCode,
    required this.sharePercent,
  });

  final String categoryId;
  final String categoryName;
  final int grossSpendMinor;
  final int refundsMinor;
  final int netSpendMinor;
  final String currencyCode;
  final double sharePercent;

  @override
  List<Object?> get props => [
    categoryId,
    categoryName,
    grossSpendMinor,
    refundsMinor,
    netSpendMinor,
    currencyCode,
    sharePercent,
  ];
}

final class MonthlyCashFlowPoint extends Equatable {
  const MonthlyCashFlowPoint({
    required this.yearMonth,
    required this.incomeMinor,
    required this.expenseMinor,
    required this.currencyCode,
  });

  final String yearMonth; // YYYY-MM
  final int incomeMinor;
  final int expenseMinor;
  final String currencyCode;

  int get netCashFlowMinor => incomeMinor - expenseMinor;

  @override
  List<Object?> get props => [
    yearMonth,
    incomeMinor,
    expenseMinor,
    currencyCode,
  ];
}

final class DashboardSummary extends Equatable {
  const DashboardSummary({
    required this.profileId,
    required this.baseCurrencyCode,
    required this.periodPreset,
    required this.valuationTimestampUtc,
    required this.totalAssets,
    required this.totalLiabilities,
    required this.netWorth,
    required this.periodIncome,
    required this.periodGrossExpense,
    required this.periodNetExpense,
    required this.periodNetCashFlow,
    required this.accounts,
    required this.recentTransactions,
    required this.categoryBreakdown,
    required this.monthlyCashFlow,
    required this.pendingSyncCount,
  });

  final ProfileId profileId;
  final String baseCurrencyCode;
  final DashboardPeriodPreset periodPreset;
  final String valuationTimestampUtc;
  final Money totalAssets;
  final Money totalLiabilities;
  final Money netWorth;
  final Money periodIncome;
  final Money periodGrossExpense;
  final Money periodNetExpense;
  final Money periodNetCashFlow;
  final List<FinancialAccountEntity> accounts;
  final List<TransactionEntity> recentTransactions;
  final List<CategorySpendItem> categoryBreakdown;
  final List<MonthlyCashFlowPoint> monthlyCashFlow;
  final int pendingSyncCount;

  @override
  List<Object?> get props => [
    profileId,
    baseCurrencyCode,
    periodPreset,
    valuationTimestampUtc,
    totalAssets,
    totalLiabilities,
    netWorth,
    periodIncome,
    periodGrossExpense,
    periodNetExpense,
    periodNetCashFlow,
    accounts,
    recentTransactions,
    categoryBreakdown,
    monthlyCashFlow,
    pendingSyncCount,
  ];
}
