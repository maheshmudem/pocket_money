import 'dart:io';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/financial_engine/money.dart';
import '../../../../core/utilities/clock.dart';
import '../../../../shared/widgets/editorial_bento_kit.dart';
import '../../../../shared/widgets/enterprise_layout.dart';
import '../../../../shared/widgets/fintech_widgets.dart';
import '../../../../shared/widgets/flagship_visuals.dart';
import '../../../accounts/domain/entities/financial_account_entity.dart';
import '../../../budgets/domain/entities/budget_entity.dart';
import '../../../budgets/presentation/pages/budgets_page.dart';
import '../../../dashboard/domain/entities/dashboard_summary.dart';
import '../../../dashboard/presentation/bloc/dashboard_bloc.dart';
import '../../../profiles/domain/entities/profile_entity.dart';
import '../../../profiles/presentation/bloc/active_profile_cubit.dart';
import '../../../reports/data/report_exporter.dart';
import '../../../settings/presentation/bloc/settings_cubit.dart';
import '../../../transactions/domain/entities/transaction_entity.dart';
import '../../../transactions/domain/repositories/transaction_repository.dart';
import '../../../transactions/presentation/pages/transactions_page.dart';

/// Covers `SCR-ANA-001` (Spending Analysis & CFO Health Score),
/// `SCR-ANA-002` (Cash Flow Bar Chart & Monthly Ledger),
/// and `SCR-REP-001` (Report Builder & PDF/CSV Export Studio).
class AnalyticsReportsPage extends StatefulWidget {
  const AnalyticsReportsPage({super.key});

  @override
  State<AnalyticsReportsPage> createState() => _AnalyticsReportsPageState();
}

class _AnalyticsReportsPageState extends State<AnalyticsReportsPage> {
  static const _chartPalette = [
    Color(0xFF1D4ED8),
    Color(0xFF059669),
    Color(0xFF0284C7),
    Color(0xFF475569),
    Color(0xFFD97706),
    Color(0xFFDC2626),
    Color(0xFF0D9488),
  ];

  int _touchedSlice = -1;
  bool _exportingPdf = false;
  bool _exportingCsv = false;

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ActiveProfileCubit>().state.activeProfile;
    final hideBalances = context.watch<SettingsCubit>().state.hideBalances;
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;

    if (profile == null) {
      return const EmptyStateView(
        icon: Icons.insights_outlined,
        title: 'No active profile',
        description: 'Select a profile to view analytics and export reports.',
      );
    }

    return BlocBuilder<DashboardBloc, DashboardState>(
      builder: (context, state) {
        final summary = state.summary;
        if (summary == null) {
          return const EmptyStateView(
            icon: Icons.insights_outlined,
            title: 'No financial activity yet',
            description:
                'Add accounts and record transactions to generate spending analysis, cash-flow trends, and PDF/CSV statements.',
          );
        }

        final budgets = state.budgets;
        final ccy = profile.baseCurrencyCode;
        final incomeMinor = summary.periodIncome.amountMinor;
        final netSpendMinor = summary.periodNetExpense.amountMinor;
        final netCashFlowMinor = incomeMinor - netSpendMinor;
        final assetsMinor = summary.totalAssets.amountMinor;
        final liabilitiesMinor = summary.totalLiabilities.amountMinor;
        final liquidAssetsMinor = summary.accounts.isEmpty
            ? assetsMinor
            : summary.accounts
                  .where(
                    (a) =>
                        !a.isLiability &&
                        (a.accountType == FinancialAccountType.bank ||
                            a.accountType == FinancialAccountType.cash ||
                            a.accountType == FinancialAccountType.wallet),
                  )
                  .fold<int>(0, (s, a) => s + a.baseBalance.amountMinor);
        final liquidAssetsMoney = Money(
          amountMinor: liquidAssetsMinor,
          currencyCode: ccy,
        );
        final savingsRatePct = incomeMinor > 0
            ? (((incomeMinor - netSpendMinor) / incomeMinor) * 100).round()
            : (netSpendMinor > 0 ? -100 : 0);

        final elapsedDays = _elapsedDaysInPeriod(
          state.period,
          GetIt.I<UtcClock>().nowUtc(),
          summary.monthlyCashFlow,
        );
        final avgDailySpendMinor = elapsedDays > 0
            ? (netSpendMinor ~/ elapsedDays)
            : 0;
        final monthlyBurnMinor = avgDailySpendMinor * 30;
        final runwayBaseMinor = liquidAssetsMinor > 0
            ? liquidAssetsMinor
            : assetsMinor;
        final runwayMonths = monthlyBurnMinor > 0 && runwayBaseMinor > 0
            ? (runwayBaseMinor / monthlyBurnMinor)
            : null;

        final health = _computeHealthScore(
          incomeMinor: incomeMinor,
          netSpendMinor: netSpendMinor,
          assetsMinor: assetsMinor,
          liabilitiesMinor: liabilitiesMinor,
          budgets: budgets,
        );

        final netFlowMoney = Money(
          amountMinor: netCashFlowMinor,
          currencyCode: ccy,
        );
        final avgDailyMoney = Money(
          amountMinor: avgDailySpendMinor,
          currencyCode: ccy,
        );

        final safeTouched =
            (_touchedSlice >= 0 &&
                _touchedSlice < summary.categoryBreakdown.length)
            ? _touchedSlice
            : -1;
        final touchedItem = safeTouched >= 0
            ? summary.categoryBreakdown[safeTouched]
            : null;

        return RefreshIndicator(
          onRefresh: () async => context.read<DashboardBloc>().add(
            DashboardRefreshRequested(period: state.period),
          ),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EnterprisePageContainer.responsivePadding(
              context,
              top: 10,
              bottom: 44,
            ),
            child: EnterprisePageContainer(
              maxWidth: AppBreakpoints.maxDashboardWidth,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= AppBreakpoints.medium;

                  final healthHero = StaggeredFadeSlide(
                    index: 0,
                    child: _FinancialHealthHeroCard(
                      health: health,
                      assetsMinor: assetsMinor,
                      liabilitiesMinor: liabilitiesMinor,
                      runwayMonths: runwayMonths,
                      budgetsCount: budgets.length,
                      masked: hideBalances,
                    ),
                  );

                  final kpiGrid = StaggeredFadeSlide(
                    index: 1,
                    child: _InsightsKpiGrid(
                      isWide: isWide,
                      savingsRatePct: savingsRatePct,
                      incomeMinor: incomeMinor,
                      spendMinor: netSpendMinor,
                      netFlowMoney: netFlowMoney,
                      netCashFlowMinor: netCashFlowMinor,
                      avgDailyMoney: avgDailyMoney,
                      totalAssets: liquidAssetsMoney,
                      runwayMonths: runwayMonths,
                      spendSparkline: summary.monthlyCashFlow
                          .map((pt) => pt.expenseMinor.toDouble())
                          .toList(),
                      masked: hideBalances,
                    ),
                  );

                  final smartInsights = StaggeredFadeSlide(
                    index: 2,
                    child: _SmartCfoInsightsCard(
                      profile: profile,
                      summary: summary,
                      budgets: budgets,
                      savingsRatePct: savingsRatePct,
                      runwayMonths: runwayMonths,
                      masked: hideBalances,
                    ),
                  );

                  final cashFlowChart = StaggeredFadeSlide(
                    index: 3,
                    child: _CashFlowBarChartCard(
                      points: summary.monthlyCashFlow,
                      currencyCode: ccy,
                      masked: hideBalances,
                    ),
                  );

                  final spendingStudio = StaggeredFadeSlide(
                    index: 4,
                    child: PressScaleCard(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SectionHeader(
                            title: 'Spending Breakdown',
                            subtitle:
                                '${summary.periodPreset.label} • Gross: ${summary.periodGrossExpense.format(mask: hideBalances)} • Net: ${summary.periodNetExpense.format(mask: hideBalances)}',
                            trailingLabel:
                                summary.categoryBreakdown.isNotEmpty &&
                                    profile
                                        .permissions
                                        .canManageCategoriesAndBudgets
                                ? 'Budgets'
                                : null,
                            onTrailingPressed: () => context.push('/budgets'),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          if (summary.categoryBreakdown.isEmpty)
                            _EmptyBreakdownBanner(
                              canPost: profile.permissions.canPostTransaction,
                              onTrackExpense: () => openAddTransactionSheet(
                                context,
                                profile,
                                initialType: TransactionType.expense,
                              ),
                            )
                          else
                            _SpendingBreakdownBody(
                              isWide: isWide,
                              summary: summary,
                              palette: _chartPalette,
                              touchedIndex: safeTouched,
                              touchedItem: touchedItem,
                              masked: hideBalances,
                              canSetBudget: profile
                                  .permissions
                                  .canManageCategoriesAndBudgets,
                              onSelectSlice: (idx) {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  _touchedSlice = _touchedSlice == idx
                                      ? -1
                                      : idx;
                                });
                              },
                              onSetCategoryBudget: (item) =>
                                  openCreateBudgetModal(
                                    context,
                                    profile,
                                    suggestedName: '${item.categoryName} Cap',
                                  ),
                            ),
                        ],
                      ),
                    ),
                  );

                  final cashFlowLedger = StaggeredFadeSlide(
                    index: 5,
                    child: _MonthlyCashFlowLedgerCard(
                      points: summary.monthlyCashFlow,
                      masked: hideBalances,
                    ),
                  );

                  final exportStudio = StaggeredFadeSlide(
                    index: 6,
                    child: PressScaleCard(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              IconSquircle(
                                icon: Icons.description_outlined,
                                iconColor: scheme.primary,
                                backgroundColor: scheme.primaryContainer,
                                size: 38,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Export Statements',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    Text(
                                      '${profile.name} ($ccy) • Formula-injection sanitized',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(color: cfo.subtleText),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Wrap(
                            spacing: AppSpacing.xs,
                            runSpacing: AppSpacing.xs,
                            children: [
                              FilledButton.icon(
                                onPressed: _exportingPdf
                                    ? null
                                    : () =>
                                          _exportPdf(context, profile, summary),
                                icon: _exportingPdf
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.picture_as_pdf_rounded,
                                        size: 18,
                                      ),
                                label: const Text('Export PDF Statement'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _exportingCsv
                                    ? null
                                    : () =>
                                          _exportCsv(context, profile, summary),
                                icon: _exportingCsv
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.table_view_rounded,
                                        size: 18,
                                      ),
                                label: const Text('Export Sanitized CSV'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _InsightsPeriodHeader(
                        selected: state.period,
                        onSelect: (preset) {
                          HapticFeedback.selectionClick();
                          setState(() => _touchedSlice = -1);
                          context.read<DashboardBloc>().add(
                            DashboardRefreshRequested(period: preset),
                          );
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                      healthHero,
                      const SizedBox(height: AppSpacing.md),
                      kpiGrid,
                      const SizedBox(height: AppSpacing.md),
                      if (isWide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 6, child: cashFlowChart),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(flex: 5, child: smartInsights),
                          ],
                        )
                      else ...[
                        smartInsights,
                        const SizedBox(height: AppSpacing.md),
                        cashFlowChart,
                      ],
                      const SizedBox(height: AppSpacing.md),
                      spendingStudio,
                      const SizedBox(height: AppSpacing.md),
                      if (isWide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 5, child: cashFlowLedger),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(flex: 4, child: exportStudio),
                          ],
                        )
                      else ...[
                        cashFlowLedger,
                        const SizedBox(height: AppSpacing.md),
                        exportStudio,
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  int _elapsedDaysInPeriod(
    DashboardPeriodPreset preset,
    DateTime nowUtc,
    List<MonthlyCashFlowPoint> history,
  ) {
    return switch (preset) {
      DashboardPeriodPreset.thisMonth => nowUtc.day.clamp(1, 31),
      DashboardPeriodPreset.lastMonth => DateTime.utc(
        nowUtc.year,
        nowUtc.month,
        0,
      ).day,
      DashboardPeriodPreset.last3Months => 90,
      DashboardPeriodPreset.yearToDate =>
        nowUtc.difference(DateTime.utc(nowUtc.year, 1, 1)).inDays + 1,
      DashboardPeriodPreset.allTime => _allTimeElapsedDays(nowUtc, history),
    };
  }

  int _allTimeElapsedDays(DateTime nowUtc, List<MonthlyCashFlowPoint> history) {
    DateTime? earliest;
    for (final pt in history) {
      if (pt.incomeMinor == 0 && pt.expenseMinor == 0) continue;
      final parts = pt.yearMonth.split('-');
      if (parts.length != 2) continue;
      final yr = int.tryParse(parts[0]);
      final mo = int.tryParse(parts[1]);
      if (yr == null || mo == null || mo < 1 || mo > 12) continue;
      final start = DateTime.utc(yr, mo, 1);
      if (earliest == null || start.isBefore(earliest)) {
        earliest = start;
      }
    }
    if (earliest == null) return nowUtc.day.clamp(1, 31);
    final diff = nowUtc.difference(earliest).inDays + 1;
    return diff < 1 ? 1 : diff;
  }

  String _safeFileSlug(String raw) {
    final cleaned = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return cleaned.isEmpty ? 'profile' : cleaned;
  }

  _HealthAssessment _computeHealthScore({
    required int incomeMinor,
    required int netSpendMinor,
    required int assetsMinor,
    required int liabilitiesMinor,
    required List<BudgetEntity> budgets,
  }) {
    // 1. Savings velocity (0–40)
    int savingsPts;
    if (incomeMinor > 0) {
      final rate = ((incomeMinor - netSpendMinor) / incomeMinor * 100).clamp(
        0.0,
        50.0,
      );
      savingsPts = ((rate / 50.0) * 40).round();
    } else if (netSpendMinor == 0 && assetsMinor > 0) {
      savingsPts = 26;
    } else if (assetsMinor > netSpendMinor * 3 && netSpendMinor > 0) {
      savingsPts = 18;
    } else {
      savingsPts = 8;
    }

    // 2. Balance-sheet solvency (0–30)
    int solvencyPts;
    if (liabilitiesMinor <= 0 && assetsMinor > 0) {
      solvencyPts = 30;
    } else if (assetsMinor > 0) {
      final ratio = (liabilitiesMinor / assetsMinor).clamp(0.0, 1.0);
      solvencyPts = ((1.0 - ratio) * 30).round();
    } else {
      solvencyPts = 12;
    }

    // 3. Budget discipline (0–20)
    int budgetPts;
    if (budgets.isEmpty) {
      budgetPts = 10;
    } else {
      final totalLimit = budgets.fold<int>(
        0,
        (s, b) => s + b.overallLimit.amountMinor,
      );
      final totalSpent = budgets.fold<int>(
        0,
        (s, b) => s + b.totalSpent.amountMinor,
      );
      final util = totalLimit > 0 ? totalSpent / totalLimit : 0.0;
      budgetPts = util <= 0.80
          ? 20
          : util <= 1.0
          ? 14
          : 5;
    }

    // 4. Liquid asset reserve (0–10)
    final liquidityPts = assetsMinor > 0 ? 10 : 2;

    final total = (savingsPts + solvencyPts + budgetPts + liquidityPts).clamp(
      0,
      100,
    );
    final (String grade, String headline) = total >= 82
        ? ('Elite', 'Exceptional savings discipline & balance sheet')
        : total >= 65
        ? ('Strong', 'Healthy capital buffer with balanced cash flow')
        : total >= 45
        ? ('Steady', 'Solid foundation — add budgets & boost surplus')
        : ('Watch', 'Tighten outflows or log inflows to raise score');

    return _HealthAssessment(
      score: total,
      grade: grade,
      headline: headline,
      savingsPts: savingsPts,
      solvencyPts: solvencyPts,
      budgetPts: budgetPts,
    );
  }

  Future<void> _exportPdf(
    BuildContext context,
    FinancialProfile profile,
    DashboardSummary summary,
  ) async {
    setState(() => _exportingPdf = true);
    try {
      final bounds = summary.periodPreset.resolveBoundsUtc(
        GetIt.I<UtcClock>().nowUtc(),
      );
      final txPage = await GetIt.I<TransactionRepository>().queryTransactions(
        profile.id,
        filter: TransactionFilter(
          fromUtc: bounds.fromUtc?.toIso8601String(),
          toUtc: bounds.toUtc?.toIso8601String(),
        ),
        limit: 500,
      );
      final bytes = await ReportExporter.generateSummaryPdf(
        profile: profile,
        summary: summary,
        transactions: txPage.valueOrNull?.items ?? const [],
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'pocket_cfo_${_safeFileSlug(profile.name)}_statement.pdf',
      );
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  Future<void> _exportCsv(
    BuildContext context,
    FinancialProfile profile,
    DashboardSummary summary,
  ) async {
    setState(() => _exportingCsv = true);
    try {
      final bounds = summary.periodPreset.resolveBoundsUtc(
        GetIt.I<UtcClock>().nowUtc(),
      );
      final txPage = await GetIt.I<TransactionRepository>().queryTransactions(
        profile.id,
        filter: TransactionFilter(
          fromUtc: bounds.fromUtc?.toIso8601String(),
          toUtc: bounds.toUtc?.toIso8601String(),
        ),
        limit: 2000,
      );
      final csvData = ReportExporter.generateTransactionsCsv(
        profile: profile,
        transactions: txPage.valueOrNull?.items ?? const [],
      );
      final dir = await getTemporaryDirectory();
      final file = File(
        p.join(
          dir.path,
          'pocket_cfo_${_safeFileSlug(profile.name)}_export.csv',
        ),
      );
      await file.writeAsString(csvData);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Pocket CFO Statement CSV (${profile.name})',
        ),
      );
    } finally {
      if (mounted) setState(() => _exportingCsv = false);
    }
  }
}

class _HealthAssessment {
  const _HealthAssessment({
    required this.score,
    required this.grade,
    required this.headline,
    required this.savingsPts,
    required this.solvencyPts,
    required this.budgetPts,
  });

  final int score;
  final String grade;
  final String headline;
  final int savingsPts;
  final int solvencyPts;
  final int budgetPts;
}

class _InsightsPeriodHeader extends StatelessWidget {
  const _InsightsPeriodHeader({required this.selected, required this.onSelect});

  final DashboardPeriodPreset selected;
  final ValueChanged<DashboardPeriodPreset> onSelect;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Financial Intelligence',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                'Live CFO telemetry & ledger analytics',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: cfo.subtleText),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        PopupMenuButton<DashboardPeriodPreset>(
          tooltip: 'Change analytics period',
          onSelected: onSelect,
          itemBuilder: (_) => [
            for (final preset in DashboardPeriodPreset.values)
              PopupMenuItem(
                value: preset,
                child: Row(
                  children: [
                    Icon(
                      preset == selected
                          ? Icons.check_circle_rounded
                          : Icons.calendar_today_outlined,
                      size: 16,
                      color: preset == selected
                          ? scheme.primary
                          : cfo.subtleText,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        preset.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: preset == selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: cfo.surfaceElevated,
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              border: Border.all(color: cfo.divider),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.calendar_today_rounded,
                  size: 14,
                  color: scheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  selected.label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: cfo.subtleText,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FinancialHealthHeroCard extends StatelessWidget {
  const _FinancialHealthHeroCard({
    required this.health,
    required this.assetsMinor,
    required this.liabilitiesMinor,
    required this.runwayMonths,
    required this.budgetsCount,
    required this.masked,
  });

  final _HealthAssessment health;
  final int assetsMinor;
  final int liabilitiesMinor;
  final double? runwayMonths;
  final int budgetsCount;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final gaugePrimary = health.score >= 70
        ? const Color(0xFF2DD4A8)
        : health.score >= 45
        ? const Color(0xFFE8C468)
        : const Color(0xFFFB7185);
    final gaugeSecondary = health.score >= 70
        ? const Color(0xFFE8C468)
        : health.score >= 45
        ? const Color(0xFFCFA03B)
        : const Color(0xFFEF4444);
    final heroTone = health.score >= 70
        ? SignatureHeroTone.indigo
        : health.score >= 45
        ? SignatureHeroTone.amber
        : SignatureHeroTone.crimson;

    final solvencyText = liabilitiesMinor <= 0
        ? 'Debt-Free'
        : assetsMinor > 0
        ? '${((liabilitiesMinor / assetsMinor) * 100).round()}% Debt'
        : 'Leveraged';

    final runwayText = masked
        ? 'Runway ••'
        : runwayMonths != null
        ? '${runwayMonths!.clamp(0.1, 99.0).toStringAsFixed(1)} mo runway'
        : 'Strong buffer';

    return FullBleedTheaterStage(
      tone: heroTone,
      isWideCard: true,
      padding: const EdgeInsets.fromLTRB(18, 17, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              RadialScoreGauge(
                key: const Key('insights_health_gauge'),
                score: health.score,
                label: health.grade,
                activeColor: gaugePrimary,
                secondaryColor: gaugeSecondary,
                trackColor: Colors.white.withValues(alpha: 0.14),
                textColor: Colors.white,
                subtitleColor: Colors.white.withValues(alpha: 0.72),
                size: 102,
                strokeWidth: 8.5,
                masked: masked,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HeroGlassPill(
                      label: 'CFO HEALTH SCORE',
                      dotColor: gaugePrimary,
                      foreground: gaugePrimary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      health.headline,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          // 3 Live Pillar Sub-Score Micro Bars
          HeroGlassWell(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Expanded(
                  child: _HealthPillarMeter(
                    label: 'Savings',
                    score: health.savingsPts,
                    maxScore: 40,
                    color: const Color(0xFF34D399),
                    masked: masked,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _HealthPillarMeter(
                    label: 'Solvency',
                    score: health.solvencyPts,
                    maxScore: 30,
                    color: const Color(0xFF38BDF8),
                    masked: masked,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _HealthPillarMeter(
                    label: 'Budgets',
                    score: health.budgetPts,
                    maxScore: 20,
                    color: const Color(0xFFFBBF24),
                    masked: masked,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 11),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _GlassPill(
                icon: Icons.verified_user_outlined,
                label: solvencyText,
              ),
              _GlassPill(icon: Icons.timelapse_rounded, label: runwayText),
              _GlassPill(
                icon: Icons.pie_chart_outline_rounded,
                label: budgetsCount > 0
                    ? '$budgetsCount Budget(s)'
                    : 'No Budget Cap',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HealthPillarMeter extends StatelessWidget {
  const _HealthPillarMeter({
    required this.label,
    required this.score,
    required this.maxScore,
    required this.color,
    required this.masked,
  });

  final String label;
  final int score;
  final int maxScore;
  final Color color;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final ratio = maxScore > 0 ? (score / maxScore).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              masked ? '••' : '$score/$maxScore',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          child: Container(
            height: 4,
            color: Colors.white.withValues(alpha: 0.14),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: masked ? 0.0 : ratio,
              child: Container(color: color),
            ),
          ),
        ),
      ],
    );
  }
}

class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return HeroGlassPill(
      icon: icon,
      label: label,
      foreground: Colors.white.withValues(alpha: 0.90),
    );
  }
}

class _InsightsKpiGrid extends StatelessWidget {
  const _InsightsKpiGrid({
    required this.isWide,
    required this.savingsRatePct,
    required this.incomeMinor,
    required this.spendMinor,
    required this.netFlowMoney,
    required this.netCashFlowMinor,
    required this.avgDailyMoney,
    required this.totalAssets,
    required this.runwayMonths,
    required this.spendSparkline,
    required this.masked,
  });

  final bool isWide;
  final int savingsRatePct;
  final int incomeMinor;
  final int spendMinor;
  final Money netFlowMoney;
  final int netCashFlowMinor;
  final Money avgDailyMoney;
  final Money totalAssets;
  final double? runwayMonths;
  final List<double> spendSparkline;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final savingsColor = savingsRatePct >= 0 ? cfo.income : cfo.expense;
    final runwayRatio = runwayMonths != null
        ? (runwayMonths! / 12.0).clamp(0.08, 1.0)
        : (totalAssets.amountMinor > 0 ? 0.85 : 0.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = isWide ? 4 : 2;
        const gap = AppSpacing.sm;
        final w = (constraints.maxWidth - (gap * (cols - 1))) / cols;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            // Tile 1: Savings Rate + Animated Mini Ring Meter
            SizedBox(
              width: w,
              child: WatermarkBentoCard(
                accent: savingsColor,
                watermarkIcon: Icons.savings_rounded,
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Savings Rate',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: cfo.subtleText,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 6),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              masked ? '••••' : '$savingsRatePct%',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    fontFamily: 'PlusJakartaSans',
                                    color: savingsColor,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 23,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            savingsRatePct >= 20
                                ? 'Above target'
                                : 'Target 20%',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: cfo.subtleText, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    MiniRingGauge(
                      progress: (savingsRatePct / 100.0).clamp(0.0, 1.0),
                      color: savingsColor,
                      size: 46,
                      strokeWidth: 4.8,
                      masked: masked,
                    ),
                  ],
                ),
              ),
            ),

            // Tile 2: Net Period Flow + Visual In/Out Ratio Bar
            SizedBox(
              width: w,
              child: WatermarkBentoCard(
                accent: scheme.primary,
                watermarkIcon: Icons.trending_up_rounded,
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Net Period Flow',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: cfo.subtleText,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        Icon(
                          netCashFlowMinor >= 0
                              ? Icons.trending_up_rounded
                              : Icons.trending_down_rounded,
                          size: 16,
                          color: netCashFlowMinor >= 0
                              ? cfo.income
                              : cfo.expense,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: MoneyText(
                        money: netFlowMoney,
                        showPlusSign: true,
                        masked: masked,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: netCashFlowMinor >= 0
                              ? cfo.income
                              : cfo.expense,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    VisualFlowRatioBar(
                      primaryMinor: incomeMinor,
                      secondaryMinor: spendMinor,
                      primaryColor: cfo.income,
                      secondaryColor: cfo.expense,
                      height: 5.0,
                      masked: masked,
                    ),
                  ],
                ),
              ),
            ),

            // Tile 3: Avg Spend / Day + Live Velocity Sparkline
            SizedBox(
              width: w,
              child: WatermarkBentoCard(
                accent: cfo.warning,
                watermarkIcon: Icons.local_fire_department_rounded,
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Avg Spend / Day',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: cfo.subtleText,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        Icon(
                          Icons.local_fire_department_rounded,
                          size: 15,
                          color: cfo.warning,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: MoneyText(
                              money: avgDailyMoney,
                              masked: masked,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        MiniSparklineChart(
                          values: spendSparkline,
                          color: cfo.warning,
                          width: 44,
                          height: 22,
                          strokeWidth: 2.0,
                          masked: masked,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Tile 4: Liquid Assets + Reserve Runway Bar
            SizedBox(
              width: w,
              child: WatermarkBentoCard(
                accent: scheme.secondary,
                watermarkIcon: Icons.account_balance_rounded,
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Liquid Assets',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: cfo.subtleText,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        Icon(
                          Icons.account_balance_rounded,
                          size: 15,
                          color: scheme.secondary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: MoneyText(
                        money: totalAssets,
                        masked: masked,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    AnimatedProgressBar(
                      value: masked ? 0.0 : runwayRatio,
                      color: scheme.secondary,
                      height: 5.0,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SmartCfoInsightsCard extends StatelessWidget {
  const _SmartCfoInsightsCard({
    required this.profile,
    required this.summary,
    required this.budgets,
    required this.savingsRatePct,
    required this.runwayMonths,
    required this.masked,
  });

  final FinancialProfile profile;
  final DashboardSummary summary;
  final List<BudgetEntity> budgets;
  final int savingsRatePct;
  final double? runwayMonths;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final canManageBudget = profile.permissions.canManageCategoriesAndBudgets;
    final canPost = profile.permissions.canPostTransaction;

    final signals =
        <
          ({
            IconData icon,
            Color fg,
            Color bg,
            String title,
            String detail,
            String? actionLabel,
            VoidCallback? onAction,
          })
        >[];

    // Signal 1: Top spending category driver
    if (summary.categoryBreakdown.isNotEmpty) {
      final top = summary.categoryBreakdown.first;
      final amtText = Money(
        amountMinor: top.netSpendMinor,
        currencyCode: top.currencyCode,
      ).format(mask: masked);
      signals.add((
        icon: Icons.trending_up_rounded,
        fg: cfo.expense,
        bg: cfo.expenseContainer,
        title: 'Top Spend: ${top.categoryName}',
        detail:
            'Drives ${top.sharePercent.toStringAsFixed(0)}% ($amtText) of period net outflows.',
        actionLabel: canManageBudget ? 'Set Cap' : null,
        onAction: canManageBudget
            ? () => openCreateBudgetModal(
                context,
                profile,
                suggestedName: '${top.categoryName} Cap',
              )
            : null,
      ));
    }

    // Signal 2: Budget discipline or prompt
    if (budgets.isEmpty) {
      signals.add((
        icon: Icons.pie_chart_rounded,
        fg: scheme.primary,
        bg: scheme.primaryContainer,
        title: 'Activate Budget Guard',
        detail:
            'Add a monthly cap to unlock real-time pace alerts & Safe / Day allowance.',
        actionLabel: canManageBudget ? 'Set Budget' : null,
        onAction: canManageBudget
            ? () => openCreateBudgetModal(
                context,
                profile,
                suggestedName: 'Monthly Spending',
              )
            : null,
      ));
    } else {
      final totalLimit = budgets.fold<int>(
        0,
        (s, b) => s + b.overallLimit.amountMinor,
      );
      final totalSpent = budgets.fold<int>(
        0,
        (s, b) => s + b.totalSpent.amountMinor,
      );
      final pct = totalLimit > 0
          ? ((totalSpent / totalLimit) * 100).round()
          : 0;
      final over = totalSpent > totalLimit;
      signals.add((
        icon: over ? Icons.warning_amber_rounded : Icons.verified_rounded,
        fg: over ? cfo.expense : cfo.income,
        bg: over ? cfo.expenseContainer : cfo.incomeContainer,
        title: over
            ? 'Budget Cap Exceeded ($pct%)'
            : 'Budget Guard Active ($pct% used)',
        detail: over
            ? 'Period expenses passed your configured limit across ${budgets.length} budget(s).'
            : 'Spending stays inside guardrails across ${budgets.length} active budget(s).',
        actionLabel: 'Inspect',
        onAction: () => context.push('/budgets'),
      ));
    }

    // Signal 3: Cash-flow / liquidity velocity
    if (summary.periodIncome.amountMinor == 0 &&
        summary.periodNetExpense.amountMinor > 0) {
      signals.add((
        icon: Icons.south_west_rounded,
        fg: cfo.transfer,
        bg: cfo.transferContainer,
        title: 'No Income Logged Yet',
        detail:
            'Log salary or inflows to compute true savings rate & surplus trend.',
        actionLabel: canPost ? 'Add Income' : null,
        onAction: canPost
            ? () => openAddTransactionSheet(
                context,
                profile,
                initialType: TransactionType.income,
              )
            : null,
      ));
    } else {
      signals.add((
        icon: Icons.auto_awesome_rounded,
        fg: savingsRatePct >= 20 ? cfo.income : cfo.warning,
        bg: savingsRatePct >= 20 ? cfo.incomeContainer : cfo.warningContainer,
        title: savingsRatePct >= 20
            ? 'Healthy Surplus Velocity'
            : 'Balance Sheet Snapshot',
        detail: summary.totalLiabilities.amountMinor <= 0
            ? 'Zero recorded liabilities${runwayMonths != null && !masked ? ' • ~${runwayMonths!.clamp(0.1, 99.0).toStringAsFixed(1)} mo asset runway' : ''}.'
            : 'Liabilities stand at ${summary.totalLiabilities.format(mask: masked)} vs ${summary.totalAssets.format(mask: masked)} assets.',
        actionLabel: null,
        onAction: null,
      ));
    }

    return PressScaleCard(
      key: const Key('insights_smart_signals'),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Smart CFO Signals',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                ),
                child: Text(
                  'LIVE LEDGER',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 9.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < signals.length; i++) ...[
            if (i > 0) Divider(height: 16, color: cfo.divider),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconSquircle(
                  icon: signals[i].icon,
                  iconColor: signals[i].fg,
                  backgroundColor: signals[i].bg,
                  size: 38,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        signals[i].title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        signals[i].detail,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: cfo.subtleText),
                      ),
                    ],
                  ),
                ),
                if (signals[i].actionLabel != null &&
                    signals[i].onAction != null) ...[
                  const SizedBox(width: 6),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: signals[i].onAction,
                    child: Text(signals[i].actionLabel!),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 12),
          Divider(height: 1, color: cfo.divider),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  key: const Key('insights_open_coach_btn'),
                  onPressed: () => context.push('/coach'),
                  icon: const Icon(Icons.auto_awesome_rounded, size: 17),
                  label: const Text('Open Smart CFO Coach & Budget Plan'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CashFlowBarChartCard extends StatelessWidget {
  const _CashFlowBarChartCard({
    required this.points,
    required this.currencyCode,
    required this.masked,
  });

  final List<MonthlyCashFlowPoint> points;
  final String currencyCode;
  final bool masked;

  static const _monthNames = [
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

  String _shortMonth(String yearMonth) {
    final parts = yearMonth.split('-');
    if (parts.length == 2) {
      final m = int.tryParse(parts[1]);
      if (m != null && m >= 1 && m <= 12) return _monthNames[m - 1];
    }
    return yearMonth;
  }

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final visible = points.length > 6
        ? points.sublist(points.length - 6)
        : points;

    final maxMinor = visible.fold<int>(
      0,
      (m, p) => math.max(m, math.max(p.incomeMinor, p.expenseMinor)),
    );
    final maxY = maxMinor > 0 ? (maxMinor * 1.18) : 10000.0;

    return PressScaleCard(
      key: const Key('insights_cashflow_barchart'),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cash-Flow Momentum',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Monthly inflow vs outflow trend',
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: cfo.subtleText),
                    ),
                  ],
                ),
              ),
              _LegendDot(color: cfo.income, label: 'In'),
              const SizedBox(width: 10),
              _LegendDot(color: cfo.expense, label: 'Out'),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (visible.isEmpty || maxMinor == 0)
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: cfo.surfaceTonal,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Text(
                'Post income or expense entries to render your interactive monthly cash-flow chart.',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cfo.subtleText),
              ),
            )
          else
            RepaintBoundary(
              child: SizedBox(
                height: 186,
                child: Semantics(
                  label:
                      'Monthly income versus expense bar chart across ${visible.length} months',
                  child: BarChart(
                    BarChartData(
                      maxY: maxY,
                      minY: 0,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: maxY / 3,
                        getDrawingHorizontalLine: (_) => FlLine(
                          color: cfo.divider,
                          strokeWidth: 1,
                          dashArray: const [4, 4],
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      barTouchData: BarTouchData(
                        enabled: !masked,
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (_) => cfo.surfaceElevated,
                          tooltipBorder: BorderSide(color: cfo.divider),
                          getTooltipItem: (group, _, rod, rodIndex) {
                            final pt = visible[group.x];
                            final isIncome = rodIndex == 0;
                            final val = Money(
                              amountMinor: isIncome
                                  ? pt.incomeMinor
                                  : pt.expenseMinor,
                              currencyCode: pt.currencyCode,
                            ).format();
                            return BarTooltipItem(
                              '${_shortMonth(pt.yearMonth)} • ${isIncome ? 'In' : 'Out'}\n$val',
                              TextStyle(
                                color: isIncome ? cfo.income : cfo.expense,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            );
                          },
                        ),
                      ),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            getTitlesWidget: (val, _) {
                              final idx = val.toInt();
                              if (idx < 0 || idx >= visible.length) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  _shortMonth(visible[idx].yearMonth),
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: cfo.subtleText,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: [
                        for (var i = 0; i < visible.length; i++)
                          BarChartGroupData(
                            x: i,
                            barsSpace: 5,
                            barRods: [
                              BarChartRodData(
                                toY: masked
                                    ? maxY * 0.35
                                    : visible[i].incomeMinor.toDouble(),
                                color: cfo.income,
                                width: 13,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(6),
                                ),
                              ),
                              BarChartRodData(
                                toY: masked
                                    ? maxY * 0.25
                                    : visible[i].expenseMinor.toDouble(),
                                color: cfo.expense,
                                width: 13,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(6),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: context.cfoColors.subtleText,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _EmptyBreakdownBanner extends StatelessWidget {
  const _EmptyBreakdownBanner({
    required this.canPost,
    required this.onTrackExpense,
  });

  final bool canPost;
  final VoidCallback onTrackExpense;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cfo.surfaceTonal,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'No posted expenses in this period yet.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cfo.subtleText),
            ),
          ),
          if (canPost) ...[
            const SizedBox(width: AppSpacing.sm),
            FilledButton.tonalIcon(
              onPressed: onTrackExpense,
              icon: const Icon(Icons.north_east_rounded, size: 16),
              label: const Text('Track Expense'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SpendingBreakdownBody extends StatelessWidget {
  const _SpendingBreakdownBody({
    required this.isWide,
    required this.summary,
    required this.palette,
    required this.touchedIndex,
    required this.touchedItem,
    required this.masked,
    required this.canSetBudget,
    required this.onSelectSlice,
    required this.onSetCategoryBudget,
  });

  final bool isWide;
  final DashboardSummary summary;
  final List<Color> palette;
  final int touchedIndex;
  final CategorySpendItem? touchedItem;
  final bool masked;
  final bool canSetBudget;
  final ValueChanged<int> onSelectSlice;
  final ValueChanged<CategorySpendItem> onSetCategoryBudget;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;

    final donutWidget = RepaintBoundary(
      child: SizedBox(
        height: 224,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Semantics(
              label:
                  'Spending breakdown donut chart across ${summary.categoryBreakdown.length} categories',
              child: PieChart(
                PieChartData(
                  centerSpaceRadius: 56,
                  sectionsSpace: 3,
                  pieTouchData: PieTouchData(
                    touchCallback: (event, response) {
                      if (!event.isInterestedForInteractions ||
                          event is! FlTapUpEvent ||
                          response?.touchedSection == null) {
                        return;
                      }
                      final idx = response!.touchedSection!.touchedSectionIndex;
                      if (idx >= 0 && idx < summary.categoryBreakdown.length) {
                        onSelectSlice(idx);
                      }
                    },
                  ),
                  sections: masked
                      ? [
                          PieChartSectionData(
                            value: 1,
                            color: cfo.divider,
                            title: '',
                            radius: 52,
                            showTitle: false,
                          ),
                        ]
                      : [
                          for (
                            var i = 0;
                            i < summary.categoryBreakdown.length;
                            i++
                          )
                            PieChartSectionData(
                              value: summary.categoryBreakdown[i].netSpendMinor
                                  .toDouble(),
                              color: palette[i % palette.length],
                              title:
                                  '${summary.categoryBreakdown[i].sharePercent.round()}%',
                              radius: i == touchedIndex ? 62 : 52,
                              titleStyle: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                        ],
                ),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 102),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    touchedItem?.categoryName ?? 'Net Spend',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: cfo.subtleText),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      touchedItem != null
                          ? Money(
                              amountMinor: touchedItem!.netSpendMinor,
                              currencyCode: touchedItem!.currencyCode,
                            ).format(mask: masked)
                          : summary.periodNetExpense.format(mask: masked),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  if (touchedItem != null)
                    Text(
                      masked
                          ? '••% share'
                          : '${touchedItem!.sharePercent.toStringAsFixed(0)}% share',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: palette[touchedIndex % palette.length],
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final rows = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < summary.categoryBreakdown.length; i++) ...[
          _CategoryBreakdownRow(
            item: summary.categoryBreakdown[i],
            color: palette[i % palette.length],
            masked: masked,
            highlighted: i == touchedIndex,
            canSetBudget: canSetBudget,
            onTap: () => onSelectSlice(i),
            onSetBudget: () =>
                onSetCategoryBudget(summary.categoryBreakdown[i]),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ],
    );

    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(flex: 5, child: donutWidget),
          const SizedBox(width: AppSpacing.lg),
          Expanded(flex: 6, child: rows),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        donutWidget,
        const SizedBox(height: AppSpacing.md),
        rows,
      ],
    );
  }
}

class _CategoryBreakdownRow extends StatelessWidget {
  const _CategoryBreakdownRow({
    required this.item,
    required this.color,
    required this.masked,
    required this.highlighted,
    required this.canSetBudget,
    required this.onTap,
    required this.onSetBudget,
  });

  final CategorySpendItem item;
  final Color color;
  final bool masked;
  final bool highlighted;
  final bool canSetBudget;
  final VoidCallback onTap;
  final VoidCallback onSetBudget;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    return Material(
      color: highlighted ? cfo.surfaceTonal : Colors.transparent,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(
              color: highlighted ? color.withValues(alpha: 0.45) : cfo.divider,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      item.categoryName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    masked
                        ? '•••• (••%)'
                        : '${Money(amountMinor: item.netSpendMinor, currencyCode: item.currencyCode).format()} (${item.sharePercent.toStringAsFixed(1)}%)',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              AnimatedProgressBar(
                value: masked
                    ? 0.0
                    : (item.sharePercent / 100.0).clamp(0.0, 1.0),
                color: color,
                height: 6,
              ),
              if (item.refundsMinor > 0) ...[
                const SizedBox(height: 4),
                Text(
                  'Gross ${Money(amountMinor: item.grossSpendMinor, currencyCode: item.currencyCode).format(mask: masked)} • Refunds ${Money(amountMinor: item.refundsMinor, currencyCode: item.currencyCode).format(mask: masked)}',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: cfo.subtleText),
                ),
              ],
              if (highlighted && canSetBudget) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: ActionChip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(
                      Icons.pie_chart_rounded,
                      size: 15,
                      color: color,
                    ),
                    label: Text('Cap ${item.categoryName}'),
                    onPressed: onSetBudget,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthlyCashFlowLedgerCard extends StatelessWidget {
  const _MonthlyCashFlowLedgerCard({
    required this.points,
    required this.masked,
  });

  final List<MonthlyCashFlowPoint> points;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final peakMinor = points.fold<int>(
      1,
      (m, pt) => math.max(m, math.max(pt.incomeMinor, pt.expenseMinor)),
    );

    return PressScaleCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            title: 'Monthly Cash-Flow Ledger',
            subtitle: 'Period inflow vs outflow comparison',
          ),
          const SizedBox(height: AppSpacing.xs),
          if (points.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                'No monthly history recorded yet.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cfo.subtleText),
              ),
            )
          else
            for (final pt in points.reversed) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: cfo.surfaceTonal,
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusSm,
                            ),
                          ),
                          child: Text(
                            pt.yearMonth,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                          ),
                        ),
                        const Spacer(),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: MoneyText(
                              money: Money(
                                amountMinor: pt.netCashFlowMinor,
                                currencyCode: pt.currencyCode,
                              ),
                              showPlusSign: true,
                              masked: masked,
                              semanticKind: pt.netCashFlowMinor >= 0
                                  ? 'income'
                                  : 'expense',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'In ${Money(amountMinor: pt.incomeMinor, currencyCode: pt.currencyCode).format(mask: masked)} • Out ${Money(amountMinor: pt.expenseMinor, currencyCode: pt.currencyCode).format(mask: masked)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: cfo.subtleText),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: AnimatedProgressBar(
                            value: masked
                                ? 0.0
                                : (pt.incomeMinor / peakMinor).clamp(0.0, 1.0),
                            color: cfo.income,
                            height: 5,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: AnimatedProgressBar(
                            value: masked
                                ? 0.0
                                : (pt.expenseMinor / peakMinor).clamp(0.0, 1.0),
                            color: cfo.expense,
                            height: 5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (pt != points.first) Divider(height: 1, color: cfo.divider),
            ],
        ],
      ),
    );
  }
}
