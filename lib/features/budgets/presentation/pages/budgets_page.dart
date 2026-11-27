import 'dart:io';
import 'dart:math' as math;

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
import '../../../../core/financial_engine/ca_budget_planner_engine.dart';
import '../../../../core/financial_engine/currency.dart';
import '../../../../core/financial_engine/money.dart';
import '../../../../core/utilities/clock.dart';
import '../../../../shared/widgets/classic_motion.dart';
import '../../../../shared/widgets/enterprise_layout.dart';
import '../../../../shared/widgets/fintech_widgets.dart';
import '../../../../shared/widgets/flagship_visuals.dart';
import '../../../../shared/widgets/modern_dialogs.dart';
import '../../../../shared/widgets/modern_dropdown.dart';
import '../../../../shared/widgets/modern_inputs.dart';
import '../../../categories/domain/entities/category_entity.dart';
import '../../../categories/domain/repositories/category_repository.dart';
import '../../../dashboard/presentation/bloc/dashboard_bloc.dart';
import '../../../profiles/domain/entities/profile_entity.dart';
import '../../../profiles/presentation/bloc/active_profile_cubit.dart';
import '../../../reports/data/report_exporter.dart';
import '../../../settings/presentation/bloc/settings_cubit.dart';
import '../../../transactions/domain/entities/transaction_entity.dart';
import '../../../transactions/presentation/pages/transactions_page.dart';
import '../../data/ca_budget_planner_service.dart';
import '../../domain/entities/budget_entity.dart';
import '../../domain/repositories/budget_repository.dart';
import '../widgets/ca_variance_statement_tab.dart';
import '../widgets/ca_zero_based_planner_tab.dart';

/// Reusable `SCR-BUD-002` modal for creating or editing a spending budget
/// (overall, single-category, or multi-category envelope).
Future<void> openCreateBudgetModal(
  BuildContext context,
  FinancialProfile profile, {
  String suggestedName = '',
  String suggestedLimit = '',
  BudgetPeriodType initialPeriod = BudgetPeriodType.monthly,
  String? initialCategoryId,
  BudgetEntity? existing,
  Future<void> Function()? onSaved,
}) async {
  final dashBloc = context.read<DashboardBloc?>();
  final catsRes = await GetIt.I<CategoryRepository>().listCategories(
    profile.id,
    type: CategoryType.expense,
  );
  if (!context.mounted) return;
  final cats = catsRes.valueOrNull ?? const <CategoryEntity>[];

  await showEnterpriseModal<void>(
    context: context,
    maxWidth: 520,
    builder: (_) => _CreateOrEditBudgetSheetBody(
      profile: profile,
      cats: cats,
      suggestedName: suggestedName,
      suggestedLimit: suggestedLimit,
      initialPeriod: existing?.periodType ?? initialPeriod,
      initialCategoryId: initialCategoryId,
      existing: existing,
      onSaved: () async {
        dashBloc?.add(const DashboardRefreshRequested());
        if (onSaved != null) {
          await onSaved();
        }
      },
    ),
  );
}

/// Modal for atomic Envelope Rebalancing ("Move Funds" to cover overspending
/// from an under-spent category cap in 1 transaction).
Future<void> openRebalanceBudgetModal(
  BuildContext context,
  FinancialProfile profile,
  List<BudgetEntity> budgets, {
  RebalanceSuggestion? initialSuggestion,
  Future<void> Function()? onSaved,
}) async {
  final dashBloc = context.read<DashboardBloc?>();
  final envelopes = <_EnvelopeOption>[];
  for (final b in budgets) {
    for (final a in b.allocations) {
      envelopes.add(
        _EnvelopeOption(budgetId: b.id, budgetName: b.name, allocation: a),
      );
    }
  }
  if (envelopes.length < 2) {
    showFintechToast(
      context,
      'Create at least 2 category envelopes (or a Zero-Based Plan) to rebalance funds.',
      tone: FintechToastTone.info,
    );
    return;
  }

  await showEnterpriseModal<void>(
    context: context,
    maxWidth: 500,
    builder: (_) => _RebalanceEnvelopesSheet(
      profile: profile,
      envelopes: envelopes,
      initialSuggestion: initialSuggestion,
      onSaved: () async {
        dashBloc?.add(const DashboardRefreshRequested());
        if (onSaved != null) {
          await onSaved();
        }
      },
    ),
  );
}

/// Covers `SCR-BUD-001` (Minimal 3-Tab Chartered Accountant Budget Studio:
/// `Overview` & Safe-to-Spend, `Zero-Based` Planner, and `CA Variance` BvA)
/// plus `SCR-BUD-002` (Create/Edit/Rebalance Budget Envelopes).
class BudgetsPage extends StatefulWidget {
  const BudgetsPage({super.key, this.initialTab = 0});

  /// `0` = Overview, `1` = Zero-Based Planner, `2` = CA Variance (BvA).
  final int initialTab;

  @override
  State<BudgetsPage> createState() => _BudgetsPageState();
}

class _BudgetsPageState extends State<BudgetsPage> {
  late int _activeTab;
  CaFiscalPeriodPreset _bvaPeriod = CaFiscalPeriodPreset.currentMonth;
  CaBudgetWorkspaceSnapshot? _snapshot;
  bool _loading = true;
  bool _exportingPdf = false;
  bool _exportingCsv = false;
  bool _waterfallExpanded = false;
  String? _loadedProfileId;

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab.clamp(0, 2);
  }

  Future<void> _reload(
    FinancialProfile profile, {
    CaFiscalPeriodPreset? period,
  }) async {
    _loadedProfileId = profile.id.value;
    final targetPeriod = period ?? _bvaPeriod;
    setState(() {
      _bvaPeriod = targetPeriod;
      _loading = true;
    });
    final res = await GetIt.I<CaBudgetPlannerService>().loadWorkspace(
      profile: profile,
      periodPreset: targetPeriod,
    );
    if (!mounted) return;
    setState(() {
      _snapshot = res.valueOrNull;
      _loading = false;
    });
  }

  String _safeSlug(String raw) => raw
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  Future<void> _exportBvaPdf(
    FinancialProfile profile,
    CaBudgetWorkspaceSnapshot snap,
  ) async {
    if (_exportingPdf) return;
    setState(() => _exportingPdf = true);
    try {
      final bytes = await ReportExporter.generateBudgetVariancePdf(
        profile: profile,
        statement: snap.varianceStatement,
        safeToSpend: snap.safeToSpend,
        sinkingFunds: snap.sinkingFunds,
        generatedAtUtc: GetIt.I<UtcClock>().nowIsoUtc(),
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            'pocket_cfo_${_safeSlug(profile.name)}_ca_bva_${_safeSlug(snap.varianceStatement.window.label)}.pdf',
      );
    } catch (_) {
      if (mounted) {
        showFintechToast(
          context,
          'Could not export CA Variance PDF right now.',
          tone: FintechToastTone.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  Future<void> _exportBvaCsv(
    FinancialProfile profile,
    CaBudgetWorkspaceSnapshot snap,
  ) async {
    if (_exportingCsv) return;
    setState(() => _exportingCsv = true);
    try {
      final csvText = ReportExporter.generateBudgetVarianceCsv(
        profile: profile,
        statement: snap.varianceStatement,
      );
      final dir = await getTemporaryDirectory();
      final file = File(
        p.join(
          dir.path,
          'pocket_cfo_${_safeSlug(profile.name)}_ca_bva_${_safeSlug(snap.varianceStatement.window.label)}.csv',
        ),
      );
      await file.writeAsString(csvText);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject:
              'Pocket CFO CA Budget vs. Actual (${profile.name} - ${snap.varianceStatement.window.label})',
        ),
      );
    } catch (_) {
      if (mounted) {
        showFintechToast(
          context,
          'Could not export CA Variance CSV right now.',
          tone: FintechToastTone.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _exportingCsv = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ActiveProfileCubit>().state.activeProfile;
    final hideBalances = context.watch<SettingsCubit>().state.hideBalances;

    if (profile == null) {
      return const Scaffold(
        body: EmptyStateView(
          icon: Icons.pie_chart_outline,
          title: 'No active profile',
          description: 'Select a profile to plan and monitor budgets.',
        ),
      );
    }
    if (_loadedProfileId != profile.id.value) {
      _loadedProfileId = profile.id.value;
      Future.microtask(() => _reload(profile));
    }

    final snap = _snapshot;
    final budgets = snap?.budgets ?? const <BudgetEntity>[];
    final hasBudgets = budgets.isNotEmpty;
    final canPost = profile.permissions.canPostTransaction;
    final canManageBudget = profile.permissions.canManageCategoriesAndBudgets;

    return Scaffold(
      appBar: EnterpriseAppBar(
        title: const Text('Budgets & Limits'),
        actions: [
          IconButton(
            key: const Key('budgets_open_monthly_btn'),
            tooltip: 'Monthly Tracker',
            onPressed: () => context.push('/monthly'),
            icon: const Icon(Icons.calendar_month_rounded, size: 20),
          ),
          TextButton.icon(
            key: const Key('budgets_smart_suggest_btn'),
            onPressed: () async {
              await context.push('/coach?tab=1');
              if (mounted) await _reload(profile);
            },
            icon: const Icon(Icons.auto_awesome_rounded, size: 17),
            label: const Text('AI Plan'),
          ),
          if (canPost && hasBudgets && _activeTab == 0)
            IconButton(
              tooltip: 'Track Expense',
              onPressed: () async {
                await openAddTransactionSheet(
                  context,
                  profile,
                  initialType: TransactionType.expense,
                );
                if (mounted) await _reload(profile);
              },
              icon: const Icon(Icons.north_east_rounded, size: 20),
            ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      floatingActionButton: ClassicAnimatedFab(
        child: _activeTab == 0 && hasBudgets && canManageBudget
            ? FloatingActionButton.extended(
                key: const ValueKey<String>('budgets_fab'),
                onPressed: () => openCreateBudgetModal(
                  context,
                  profile,
                  onSaved: () => _reload(profile),
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New Budget'),
              )
            : null,
      ),
      body: ClassicContentSwitcher(
        stateKey: _loading && snap == null
            ? 'loading'
            : snap == null
            ? 'empty'
            : 'loaded',
        child: _loading && snap == null
            ? const DashboardSkeletonView()
            : snap == null
            ? EmptyStateView(
                icon: Icons.pie_chart_outline_rounded,
                title: 'Unable to load budget planner',
                description:
                    'Pull down or tap retry to sync your local ledger.',
                actionLabel: 'Retry',
                onAction: () => _reload(profile),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Minimal 3-Tab Segmented Bar
                  Container(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.xs,
                      AppSpacing.md,
                      AppSpacing.xs,
                    ),
                    child: EnterprisePageContainer(
                      maxWidth: AppBreakpoints.maxContentWidth,
                      child: FintechSegmentedControl<int>(
                        key: const Key('budgets_mode_tabs'),
                        selected: _activeTab,
                        options: const [
                          FintechSegmentOption(
                            value: 0,
                            label: 'Overview',
                            icon: Icons.shield_outlined,
                          ),
                          FintechSegmentOption(
                            value: 1,
                            label: 'Zero-Based',
                            icon: Icons.account_balance_wallet_outlined,
                          ),
                          FintechSegmentOption(
                            value: 2,
                            label: 'CA Variance',
                            icon: Icons.fact_check_outlined,
                          ),
                        ],
                        onChanged: (idx) {
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          setState(() => _activeTab = idx);
                        },
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClassicTabSwitcher(
                      activeIndex: _activeTab,
                      child: switch (_activeTab) {
                        1 => CaZeroBasedPlannerTab(
                          profile: profile,
                          snapshot: snap,
                          masked: hideBalances,
                          canManageBudget: canManageBudget,
                          onRefresh: () => _reload(profile),
                          onSaveZeroBased:
                              ({
                                required categoryLimitsMinor,
                                required incomePoolMinor,
                                required taxReserveBps,
                                required rolloverEnabled,
                                existingBudgetId,
                              }) async {
                                final dashBloc = context.read<DashboardBloc?>();
                                final res =
                                    await GetIt.I<CaBudgetPlannerService>()
                                        .saveZeroBasedBudget(
                                          profile: profile,
                                          categoryLimitsMinor:
                                              categoryLimitsMinor,
                                          incomePoolMinor: incomePoolMinor,
                                          taxReserveBps: taxReserveBps,
                                          rolloverEnabled: rolloverEnabled,
                                          existingBudgetId: existingBudgetId,
                                        );
                                if (!context.mounted) return;
                                if (res.isSuccess) {
                                  dashBloc?.add(
                                    const DashboardRefreshRequested(),
                                  );
                                  showFintechToast(
                                    context,
                                    existingBudgetId != null
                                        ? 'Master Zero-Based Budget updated.'
                                        : 'Master Zero-Based Budget saved.',
                                    tone: FintechToastTone.success,
                                  );
                                  await _reload(profile);
                                  if (mounted) setState(() => _activeTab = 0);
                                } else {
                                  showFintechToast(
                                    context,
                                    res.failureOrNull?.message ??
                                        'Could not save Zero-Based Budget.',
                                    tone: FintechToastTone.danger,
                                  );
                                }
                              },
                        ),
                        2 => CaVarianceStatementTab(
                          snapshot: snap,
                          selectedPeriod: _bvaPeriod,
                          masked: hideBalances,
                          canManageBudget: canManageBudget,
                          exportingPdf: _exportingPdf,
                          exportingCsv: _exportingCsv,
                          onRefresh: () => _reload(profile),
                          onSelectPeriod: (p) => _reload(profile, period: p),
                          onToggleFyCycle: () async {
                            final nextStart = snap.fyStartMonth == 4 ? 1 : 4;
                            await GetIt.I<CaBudgetPlannerService>()
                                .setFyStartMonth(profile.id, nextStart);
                            if (mounted) await _reload(profile);
                          },
                          onQuickRebalance: (suggestion) =>
                              openRebalanceBudgetModal(
                                context,
                                profile,
                                snap.budgets,
                                initialSuggestion: suggestion,
                                onSaved: () => _reload(profile),
                              ),
                          onCapUnbudgeted: (line) {
                            final spec = CurrencyCatalog.requireByCode(
                              profile.baseCurrencyCode,
                            );
                            final factor = math.pow(10, spec.minorUnit).toInt();
                            final suggestedMajor = math.max(
                              1,
                              (line.actualMinor / factor).ceil(),
                            );
                            openCreateBudgetModal(
                              context,
                              profile,
                              suggestedName: '${line.categoryName} Budget',
                              suggestedLimit: '$suggestedMajor',
                              initialCategoryId: line.categoryId,
                              onSaved: () => _reload(profile),
                            );
                          },
                          onExportPdf: () => _exportBvaPdf(profile, snap),
                          onExportCsv: () => _exportBvaCsv(profile, snap),
                        ),
                        _ => _buildOverviewTab(
                          context,
                          profile: profile,
                          snap: snap,
                          hideBalances: hideBalances,
                          canManageBudget: canManageBudget,
                        ),
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildOverviewTab(
    BuildContext context, {
    required FinancialProfile profile,
    required CaBudgetWorkspaceSnapshot snap,
    required bool hideBalances,
    required bool canManageBudget,
  }) {
    final budgets = snap.budgets;
    final hasBudgets = budgets.isNotEmpty;
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final nowUtc = snap.nowUtc;

    if (!hasBudgets) {
      return RefreshIndicator(
        onRefresh: () => _reload(profile),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EnterprisePageContainer.responsivePadding(
            context,
            bottom: 40,
          ),
          child: EnterprisePageContainer(
            maxWidth: AppBreakpoints.maxContentWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (snap.safeToSpend.liquidCashMinor > 0 ||
                    snap.safeToSpend.committedObligationsMinor > 0) ...[
                  _SafeToSpendWaterfallCard(
                    safe: snap.safeToSpend,
                    masked: hideBalances,
                    expanded: _waterfallExpanded,
                    onToggleExpand: () => setState(
                      () => _waterfallExpanded = !_waterfallExpanded,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                EmptyStateView(
                  icon: Icons.pie_chart_outline_rounded,
                  title: 'No budgets configured',
                  description:
                      'Set monthly, weekly, or quarterly spending limits—or launch the CA Zero-Based Planner to assign every rupee/dollar cleanly.',
                  actionLabel: canManageBudget ? 'Create Budget' : null,
                  onAction: canManageBudget
                      ? () => openCreateBudgetModal(
                          context,
                          profile,
                          suggestedName: 'Monthly Living',
                          onSaved: () => _reload(profile),
                        )
                      : null,
                ),
                if (canManageBudget) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Center(
                    child: TextButton.icon(
                      key: const Key('budgets_launch_zbb_empty_btn'),
                      onPressed: () => setState(() => _activeTab = 1),
                      icon: const Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 18,
                      ),
                      label: const Text('Launch CA Zero-Based Planner'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final aggregate = BudgetHealthAggregate.compute(budgets, nowUtc);
    final totalLimitMinor = aggregate.totalLimitMinor;
    final totalSpentMinor = aggregate.totalSpentMinor;
    final remainingMinor = aggregate.remainingMinor;
    final safePerDayMinor = aggregate.safePerDayMinor;

    final overallRatio = totalLimitMinor > 0
        ? (totalSpentMinor / totalLimitMinor).clamp(0.0, 1.0)
        : 0.0;
    final statusColor = remainingMinor < 0
        ? cfo.expense
        : (overallRatio >= 0.8 ? cfo.warning : cfo.income);

    final envelopeCount = budgets.fold<int>(
      0,
      (s, b) => s + b.allocations.length,
    );

    return RefreshIndicator(
      onRefresh: () => _reload(profile),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EnterprisePageContainer.responsivePadding(context, bottom: 96),
        child: EnterprisePageContainer(
          maxWidth: AppBreakpoints.maxContentWidth,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final twoCols = constraints.maxWidth >= 680;
              final cardWidth = twoCols
                  ? (constraints.maxWidth - AppSpacing.sm) / 2
                  : constraints.maxWidth;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Accountant True Safe-to-Spend (Open-to-Buy) Liquidity Card
                  StaggeredFadeSlide(
                    index: 0,
                    child: _SafeToSpendWaterfallCard(
                      safe: snap.safeToSpend,
                      masked: hideBalances,
                      expanded: _waterfallExpanded,
                      onToggleExpand: () => setState(
                        () => _waterfallExpanded = !_waterfallExpanded,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  // 2. Budget Health + Pro-Rata Pace Bar
                  StaggeredFadeSlide(
                    index: 1,
                    child: PressScaleCard(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              MiniRingGauge(
                                progress: overallRatio,
                                color: statusColor,
                                size: 42,
                                strokeWidth: 4.5,
                                centerLabel: '${(overallRatio * 100).round()}%',
                                masked: hideBalances,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Budget Health (${budgets.length})',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    Text(
                                      aggregate.daysLeftHeadline,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(color: cfo.subtleText),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              FintechStatusPill(
                                label: hideBalances
                                    ? '••%'
                                    : '${(overallRatio * 100).round()}% Used',
                                foreground: statusColor,
                                background: statusColor.withValues(alpha: 0.14),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          // Progress bar with elapsed month pace tick!
                          SizedBox(
                            height: 12,
                            child: LayoutBuilder(
                              builder: (context, barBox) {
                                final elapsedRatio =
                                    snap.varianceStatement.window.elapsedRatio;
                                final tickX = (barBox.maxWidth * elapsedRatio)
                                    .clamp(2.0, barBox.maxWidth - 2.0);
                                return Stack(
                                  alignment: Alignment.centerLeft,
                                  children: [
                                    AnimatedProgressBar(
                                      value: hideBalances ? 0.0 : overallRatio,
                                      color: statusColor,
                                      height: 8,
                                    ),
                                    if (!hideBalances)
                                      Positioned(
                                        left: tickX - 1,
                                        top: 0,
                                        bottom: 0,
                                        child: Container(
                                          width: 2,
                                          decoration: BoxDecoration(
                                            color: scheme.onSurface.withValues(
                                              alpha: 0.65,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              2,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Row(
                            children: [
                              Expanded(
                                child: _BudgetMetricBox(
                                  label: 'Total Spent',
                                  money: Money(
                                    amountMinor: totalSpentMinor,
                                    currencyCode: profile.baseCurrencyCode,
                                  ),
                                  masked: hideBalances,
                                  color: cfo.expense,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Expanded(
                                child: _BudgetMetricBox(
                                  label: 'Remaining',
                                  money: Money(
                                    amountMinor: remainingMinor,
                                    currencyCode: profile.baseCurrencyCode,
                                  ),
                                  masked: hideBalances,
                                  color: remainingMinor < 0
                                      ? cfo.expense
                                      : cfo.income,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Expanded(
                                child: _BudgetMetricBox(
                                  label: 'Safe / Day',
                                  money: Money(
                                    amountMinor: safePerDayMinor,
                                    currencyCode: profile.baseCurrencyCode,
                                  ),
                                  masked: hideBalances,
                                  color: scheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // 3. Active Budgets Header + Rebalance Shortcut
                  Row(
                    children: [
                      const Expanded(
                        child: SectionHeader(
                          title: 'Active Envelopes',
                          subtitle: 'Edit limits or shift surplus anytime',
                        ),
                      ),
                      if (canManageBudget && envelopeCount >= 2)
                        TextButton.icon(
                          key: const Key('budgets_rebalance_btn'),
                          onPressed: () => openRebalanceBudgetModal(
                            context,
                            profile,
                            budgets,
                            onSaved: () => _reload(profile),
                          ),
                          icon: const Icon(Icons.swap_horiz_rounded, size: 17),
                          label: const Text('Rebalance'),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),

                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (var idx = 0; idx < budgets.length; idx++)
                        SizedBox(
                          width: cardWidth,
                          child: _BudgetCard(
                            index: idx + 2,
                            budget: budgets[idx],
                            nowUtc: nowUtc,
                            masked: hideBalances,
                            onEdit: canManageBudget
                                ? () => openCreateBudgetModal(
                                    context,
                                    profile,
                                    existing: budgets[idx],
                                    onSaved: () => _reload(profile),
                                  )
                                : null,
                            onDelete: canManageBudget
                                ? () async {
                                    final target = budgets[idx];
                                    final confirmed = await showModernConfirmDialog(
                                      context: context,
                                      title: 'Delete Budget?',
                                      message:
                                          'Remove "${target.name}" spending guard? Existing ledger transactions will remain untouched.',
                                      icon: Icons.delete_outline_rounded,
                                      accent: ModernDialogAccent.danger,
                                      confirmLabel: 'Delete',
                                    );
                                    if (confirmed != true || !context.mounted) {
                                      return;
                                    }
                                    final dashBloc = context
                                        .read<DashboardBloc?>();
                                    await GetIt.I<BudgetRepository>()
                                        .deleteBudget(profile.id, target.id);
                                    dashBloc?.add(
                                      const DashboardRefreshRequested(),
                                    );
                                    if (context.mounted) {
                                      showFintechToast(
                                        context,
                                        'Budget "${target.name}" removed.',
                                        tone: FintechToastTone.info,
                                      );
                                    }
                                    await _reload(profile);
                                  }
                                : null,
                          ),
                        ),
                    ],
                  ),

                  // 4. Monthly Sinking Fund Provisions (when dated Savings Goals exist)
                  if (snap.sinkingFunds.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        const Expanded(
                          child: SectionHeader(
                            title: 'Sinking Fund Provisions',
                            subtitle: 'Monthly accruals for upcoming targets',
                          ),
                        ),
                        TextButton(
                          onPressed: () => context.push('/goals'),
                          child: const Text('Goals'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    PressScaleCard(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        children: [
                          for (
                            var i = 0;
                            i < snap.sinkingFunds.length;
                            i++
                          ) ...[
                            if (i > 0) Divider(height: 18, color: cfo.divider),
                            _SinkingFundRow(
                              fund: snap.sinkingFunds[i],
                              currencyCode: profile.baseCurrencyCode,
                              masked: hideBalances,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SafeToSpendWaterfallCard extends StatelessWidget {
  const _SafeToSpendWaterfallCard({
    required this.safe,
    required this.masked,
    required this.expanded,
    required this.onToggleExpand,
  });

  final SafeToSpendSnapshot safe;
  final bool masked;
  final bool expanded;
  final VoidCallback onToggleExpand;

  @override
  Widget build(BuildContext context) {
    final (
      SignatureHeroTone heroTone,
      Color tone,
      String badge,
    ) = switch (safe.liquidityStatus) {
      'crunch' => (
        SignatureHeroTone.crimson,
        const Color(0xFFFDA4AF),
        'Cash Crunch',
      ),
      'tight' => (
        SignatureHeroTone.amber,
        const Color(0xFFFDE68A),
        'Tight Buffer',
      ),
      _ => (
        SignatureHeroTone.indigo,
        const Color(0xFF6EE7B7),
        'Liquid & Clear',
      ),
    };

    return FintechSignatureHero(
      key: const Key('budgets_safe_to_spend_card'),
      tone: heroTone,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'True Safe-to-Spend (Open-to-Buy)',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.74),
                  fontWeight: FontWeight.w700,
                ),
              ),
              HeroGlassPill(label: badge, dotColor: tone, foreground: tone),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 230),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: MoneyText(
                      money: Money(
                        amountMinor: safe.safeToSpendMinor,
                        currencyCode: safe.currencyCode,
                      ),
                      masked: masked,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.7,
                          ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              HeroGlassWell(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Daily Free Cap',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.68),
                        fontSize: 10,
                      ),
                    ),
                    MoneyText(
                      money: Money(
                        amountMinor: safe.dailySafeToSpendMinor,
                        currencyCode: safe.currencyCode,
                      ),
                      masked: masked,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: const Color(0xFF7DD3FC),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            onTap: onToggleExpand,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      safe.committedObligationsMinor > 0
                          ? 'After ${Money(amountMinor: safe.committedObligationsMinor, currencyCode: safe.currencyCode).format(mask: masked)} reserved for bills, EMIs & provisions'
                          : safe.statusNote,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0.0,
                    duration: AppMotion.resolve(context, AppMotion.fast),
                    curve: AppMotion.curveStandard,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.74),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ClassicExpandCollapse(
            expanded: expanded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Divider(
                  height: 16,
                  color: Colors.white.withValues(alpha: 0.14),
                ),
                _WaterfallRow(
                  label: 'Liquid Cash (Bank + Cash + Wallet)',
                  amountMinor: safe.liquidCashMinor,
                  currencyCode: safe.currencyCode,
                  masked: masked,
                  color: const Color(0xFF6EE7B7),
                  prefix: '',
                  onDark: true,
                ),
                const SizedBox(height: 4),
                _WaterfallRow(
                  label: 'Upcoming Recurring Bills (this month)',
                  amountMinor: safe.upcomingBillsMinor,
                  currencyCode: safe.currencyCode,
                  masked: masked,
                  color: const Color(0xFFFDA4AF),
                  prefix: '− ',
                  onDark: true,
                ),
                const SizedBox(height: 4),
                _WaterfallRow(
                  label: 'Upcoming Loan EMIs (this month)',
                  amountMinor: safe.upcomingEmisMinor,
                  currencyCode: safe.currencyCode,
                  masked: masked,
                  color: const Color(0xFFFDA4AF),
                  prefix: '− ',
                  onDark: true,
                ),
                const SizedBox(height: 4),
                _WaterfallRow(
                  label: 'Tax & Statutory Reserve',
                  amountMinor: safe.taxProvisionMinor,
                  currencyCode: safe.currencyCode,
                  masked: masked,
                  color: const Color(0xFFFDE68A),
                  prefix: '− ',
                  onDark: true,
                ),
                const SizedBox(height: 4),
                _WaterfallRow(
                  label: 'Sinking Fund Monthly Accruals',
                  amountMinor: safe.sinkingFundAccrualsMinor,
                  currencyCode: safe.currencyCode,
                  masked: masked,
                  color: const Color(0xFFC7D2FE),
                  prefix: '− ',
                  onDark: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WaterfallRow extends StatelessWidget {
  const _WaterfallRow({
    required this.label,
    required this.amountMinor,
    required this.currencyCode,
    required this.masked,
    required this.color,
    required this.prefix,
    this.onDark = false,
  });

  final String label;
  final int amountMinor;
  final String currencyCode;
  final bool masked;
  final Color color;
  final String prefix;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final subtle = onDark
        ? Colors.white.withValues(alpha: 0.70)
        : cfo.subtleText;
    final formatted = Money(
      amountMinor: amountMinor,
      currencyCode: currencyCode,
    ).format(mask: masked);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: subtle),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$prefix$formatted',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: amountMinor > 0 ? color : subtle,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _SinkingFundRow extends StatelessWidget {
  const _SinkingFundRow({
    required this.fund,
    required this.currencyCode,
    required this.masked,
  });

  final SinkingFundAccrual fund;
  final String currencyCode;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                fund.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  '${Money(amountMinor: fund.monthlyAccrualMinor, currencyCode: currencyCode).format(mask: masked)}/mo',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: AnimatedProgressBar(
                value: masked ? 0.0 : fund.progressRatio,
                color: cfo.income,
                height: 5,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${fund.monthsRemaining} mo left',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: cfo.subtleText),
            ),
          ],
        ),
      ],
    );
  }
}

class _BudgetMetricBox extends StatelessWidget {
  const _BudgetMetricBox({
    required this.label,
    required this.money,
    required this.masked,
    required this.color,
  });

  final String label;
  final Money money;
  final bool masked;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: cfo.surfaceTonal,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: cfo.subtleText),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MoneyText(
              money: money,
              masked: masked,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateOrEditBudgetSheetBody extends StatefulWidget {
  const _CreateOrEditBudgetSheetBody({
    required this.profile,
    required this.cats,
    required this.suggestedName,
    required this.suggestedLimit,
    required this.initialPeriod,
    required this.onSaved,
    this.initialCategoryId,
    this.existing,
  });

  final FinancialProfile profile;
  final List<CategoryEntity> cats;
  final String suggestedName;
  final String suggestedLimit;
  final BudgetPeriodType initialPeriod;
  final String? initialCategoryId;
  final BudgetEntity? existing;
  final Future<void> Function() onSaved;

  @override
  State<_CreateOrEditBudgetSheetBody> createState() =>
      _CreateOrEditBudgetSheetBodyState();
}

class _CreateOrEditBudgetSheetBodyState
    extends State<_CreateOrEditBudgetSheetBody> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _limitCtrl;
  late BudgetPeriodType _period;
  String? _selectedCatId;
  bool _rollover = false;
  String? _errorMsg;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _nameCtrl = TextEditingController(text: existing.name);
      final spec = CurrencyCatalog.requireByCode(
        widget.profile.baseCurrencyCode,
      );
      final factor = math.pow(10, spec.minorUnit).toInt();
      final minor = existing.overallLimit.amountMinor;
      final limitStr = spec.minorUnit == 0
          ? '$minor'
          : (minor % factor == 0
                ? '${minor ~/ factor}'
                : (minor / factor).toStringAsFixed(spec.minorUnit));
      _limitCtrl = TextEditingController(text: limitStr);
      _period = existing.periodType;
      _rollover = existing.rolloverEnabled;
      _selectedCatId = existing.allocations.length == 1
          ? existing.allocations.first.categoryId
          : null;
    } else {
      _nameCtrl = TextEditingController(
        text: widget.suggestedName.isEmpty
            ? 'Monthly Spending'
            : widget.suggestedName,
      );
      _limitCtrl = TextEditingController(text: widget.suggestedLimit);
      _period = widget.initialPeriod;
      _selectedCatId = widget.initialCategoryId;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _limitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final ccy = profile.baseCurrencyCode;
    final isEditing = widget.existing != null;
    final isMultiCategoryEdit =
        isEditing && widget.existing!.allocations.length > 1;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EnterpriseModalHeader(
                title: isEditing ? 'Edit Budget' : 'Create Budget',
                subtitle: isMultiCategoryEdit
                    ? 'Adjust name, period, or rollover. Use Zero-Based tab to tweak per-category caps.'
                    : 'Set a period spending guard with optional rollover.',
                icon: isEditing ? Icons.edit_outlined : Icons.pie_chart_rounded,
              ),
              if (_errorMsg != null) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: context.cfoColors.expenseContainer,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Text(
                    _errorMsg!,
                    style: TextStyle(
                      color: context.cfoColors.expense,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              FintechTextField(
                label: 'Budget Name (e.g., Monthly Living)',
                controller: _nameCtrl,
                leadingIcon: Icons.pie_chart_outline_rounded,
                textCapitalization: TextCapitalization.words,
                showClearButton: true,
              ),
              const SizedBox(height: AppSpacing.sm),
              FintechDropdownField<BudgetPeriodType>(
                key: const Key('budget_period_dropdown'),
                label: 'Period',
                value: _period,
                leadingIcon: Icons.calendar_month_rounded,
                options:
                    const [
                          BudgetPeriodType.weekly,
                          BudgetPeriodType.monthly,
                          BudgetPeriodType.quarterly,
                          BudgetPeriodType.yearly,
                        ]
                        .map(
                          (p) => FintechDropdownOption<BudgetPeriodType>(
                            value: p,
                            label: p.label,
                            icon: Icons.date_range_rounded,
                          ),
                        )
                        .toList(),
                onChanged: (v) => setState(() => _period = v),
              ),
              if (!isMultiCategoryEdit) ...[
                const SizedBox(height: AppSpacing.sm),
                FintechTextField(
                  label: 'Limit ($ccy)',
                  controller: _limitCtrl,
                  autofocus: !isEditing && widget.suggestedLimit.isEmpty,
                  leadingIcon: Icons.payments_outlined,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final preset in const [
                      '5000',
                      '15000',
                      '30000',
                      '50000',
                    ])
                      ActionChip(
                        visualDensity: VisualDensity.compact,
                        label: Text('$ccy $preset'),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          setState(() => _limitCtrl.text = preset);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                FintechDropdownField<String?>(
                  key: const Key('budget_category_scope_dropdown'),
                  label: 'Category Scope (optional)',
                  value: _selectedCatId,
                  leadingIcon: Icons.pie_chart_outline_rounded,
                  searchable: widget.cats.length >= 6,
                  searchHint: 'Search categories...',
                  options: [
                    const FintechDropdownOption<String?>(
                      value: null,
                      label: 'All Expense Categories',
                      subtitle: 'Track total spending across every category',
                      icon: Icons.all_inclusive_rounded,
                    ),
                    ...widget.cats.map(
                      (c) => FintechDropdownOption<String?>(
                        value: c.id,
                        label: c.name,
                        icon: Icons.local_offer_outlined,
                      ),
                    ),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _selectedCatId = v;
                      if (v != null && !isEditing) {
                        final cat = widget.cats
                            .where((c) => c.id == v)
                            .firstOrNull;
                        if (cat != null &&
                            _nameCtrl.text.trim() == 'Monthly Spending') {
                          _nameCtrl.text = '${cat.name} Budget';
                        }
                      }
                    });
                  },
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              FintechSwitchCard(
                icon: Icons.autorenew_rounded,
                title: 'Enable rollover',
                subtitle: 'Carry unspent allowance into next period',
                value: _rollover,
                onChanged: (v) => setState(() => _rollover = v),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: _saving
                    ? null
                    : () async {
                        if (_nameCtrl.text.trim().isEmpty) {
                          setState(
                            () => _errorMsg = 'Please enter a budget name.',
                          );
                          return;
                        }
                        final curr = CurrencyCatalog.requireByCode(ccy);
                        final int limitMinor;
                        final Map<String, int> catLimits;

                        if (isMultiCategoryEdit) {
                          catLimits = {
                            for (final a in widget.existing!.allocations)
                              a.categoryId: a.limitMinor,
                          };
                          limitMinor = catLimits.values.fold<int>(
                            0,
                            (s, v) => s + v,
                          );
                        } else {
                          final parsed = Money.parseDecimal(
                            _limitCtrl.text,
                            currency: curr,
                          );
                          if (parsed.isFailure) {
                            setState(
                              () => _errorMsg =
                                  'Enter a valid positive budget limit.',
                            );
                            return;
                          }
                          limitMinor = parsed.valueOrNull!.amountMinor;
                          catLimits = _selectedCatId != null
                              ? {_selectedCatId!: limitMinor}
                              : const {};
                        }

                        setState(() {
                          _saving = true;
                          _errorMsg = null;
                        });
                        final nav = Navigator.of(context);
                        final repo = GetIt.I<BudgetRepository>();
                        final res = isEditing
                            ? await repo.updateBudget(
                                profileId: profile.id,
                                budgetId: widget.existing!.id,
                                name: _nameCtrl.text.trim(),
                                periodType: _period,
                                overallLimitMinor: limitMinor,
                                categoryLimitsMinor: catLimits,
                                rolloverEnabled: _rollover,
                              )
                            : await repo.createBudget(
                                profileId: profile.id,
                                name: _nameCtrl.text.trim(),
                                periodType: _period,
                                overallLimitMinor: limitMinor,
                                currencyCode: ccy,
                                categoryLimitsMinor: catLimits,
                                rolloverEnabled: _rollover,
                              );
                        if (!mounted) return;
                        if (res.isFailure) {
                          setState(() {
                            _saving = false;
                            _errorMsg =
                                res.failureOrNull?.message ??
                                'Could not save budget.';
                          });
                          return;
                        }
                        if (nav.canPop()) nav.pop();
                        await widget.onSaved();
                      },
                child: Text(isEditing ? 'Update Budget' : 'Save Budget'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EnvelopeOption {
  const _EnvelopeOption({
    required this.budgetId,
    required this.budgetName,
    required this.allocation,
  });

  final String budgetId;
  final String budgetName;
  final BudgetCategoryAllocation allocation;

  String get key => '$budgetId|${allocation.categoryId}';
}

class _RebalanceEnvelopesSheet extends StatefulWidget {
  const _RebalanceEnvelopesSheet({
    required this.profile,
    required this.envelopes,
    required this.onSaved,
    this.initialSuggestion,
  });

  final FinancialProfile profile;
  final List<_EnvelopeOption> envelopes;
  final RebalanceSuggestion? initialSuggestion;
  final Future<void> Function() onSaved;

  @override
  State<_RebalanceEnvelopesSheet> createState() =>
      _RebalanceEnvelopesSheetState();
}

class _RebalanceEnvelopesSheetState extends State<_RebalanceEnvelopesSheet> {
  late String _fromKey;
  late String _toKey;
  late final TextEditingController _amountCtrl;
  String? _errorMsg;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final sug = widget.initialSuggestion;
    if (sug != null) {
      final matchFrom = widget.envelopes
          .where(
            (e) =>
                e.budgetId == sug.fromBudgetId &&
                e.allocation.categoryId == sug.fromCategoryId,
          )
          .firstOrNull;
      final matchTo = widget.envelopes
          .where(
            (e) =>
                e.budgetId == sug.toBudgetId &&
                e.allocation.categoryId == sug.toCategoryId,
          )
          .firstOrNull;
      _fromKey = matchFrom?.key ?? widget.envelopes.first.key;
      _toKey = matchTo?.key ?? widget.envelopes.last.key;
      _amountCtrl = TextEditingController(
        text: _minorToPlain(sug.suggestedTransferMinor),
      );
    } else {
      final sortedBySurplus = [...widget.envelopes]
        ..sort(
          (a, b) => b.allocation.remainingMinor.compareTo(
            a.allocation.remainingMinor,
          ),
        );
      _fromKey = sortedBySurplus.first.key;
      _toKey = sortedBySurplus.last.key;
      final deficit = sortedBySurplus.last.allocation.remainingMinor < 0
          ? -sortedBySurplus.last.allocation.remainingMinor
          : 0;
      _amountCtrl = TextEditingController(
        text: deficit > 0 ? _minorToPlain(deficit) : '',
      );
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  String _minorToPlain(int minor) {
    final spec = CurrencyCatalog.requireByCode(widget.profile.baseCurrencyCode);
    final factor = math.pow(10, spec.minorUnit).toInt();
    if (spec.minorUnit == 0) return '$minor';
    if (minor % factor == 0) return '${minor ~/ factor}';
    return (minor / factor).toStringAsFixed(spec.minorUnit);
  }

  @override
  Widget build(BuildContext context) {
    final ccy = widget.profile.baseCurrencyCode;
    final fromEnv = widget.envelopes.firstWhere((e) => e.key == _fromKey);
    final toEnv = widget.envelopes.firstWhere((e) => e.key == _toKey);
    final deficit = toEnv.allocation.remainingMinor < 0
        ? -toEnv.allocation.remainingMinor
        : 0;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const EnterpriseModalHeader(
                title: 'Rebalance Envelopes',
                subtitle:
                    'Move unused limit from a surplus category to cover overspending.',
                icon: Icons.swap_horiz_rounded,
              ),
              if (_errorMsg != null) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: context.cfoColors.expenseContainer,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Text(
                    _errorMsg!,
                    style: TextStyle(
                      color: context.cfoColors.expense,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              FintechDropdownField<String>(
                key: const Key('rebalance_from_dropdown'),
                label: 'Move From (Donor Envelope)',
                value: _fromKey,
                leadingIcon: Icons.north_east_rounded,
                options: widget.envelopes
                    .map(
                      (e) => FintechDropdownOption<String>(
                        value: e.key,
                        label: e.allocation.categoryName,
                        subtitle:
                            '${e.budgetName} • Left: ${Money(amountMinor: e.allocation.remainingMinor, currencyCode: ccy).format()}',
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _fromKey = v),
              ),
              const SizedBox(height: AppSpacing.sm),
              FintechDropdownField<String>(
                key: const Key('rebalance_to_dropdown'),
                label: 'Move To (Target Envelope)',
                value: _toKey,
                leadingIcon: Icons.south_west_rounded,
                options: widget.envelopes
                    .map(
                      (e) => FintechDropdownOption<String>(
                        value: e.key,
                        label: e.allocation.categoryName,
                        subtitle:
                            '${e.budgetName} • ${e.allocation.isOverspent ? 'Over by ${Money(amountMinor: -e.allocation.remainingMinor, currencyCode: ccy).format()}' : 'Cap: ${Money(amountMinor: e.allocation.limitMinor, currencyCode: ccy).format()}'}',
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _toKey = v),
              ),
              const SizedBox(height: AppSpacing.sm),
              FintechTextField(
                key: const Key('rebalance_amount_field'),
                label: 'Amount to Shift ($ccy)',
                controller: _amountCtrl,
                leadingIcon: Icons.payments_outlined,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              if (deficit > 0) ...[
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: 6,
                  children: [
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        'Cover Exact Deficit (${Money(amountMinor: deficit, currencyCode: ccy).format()})',
                      ),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        setState(
                          () => _amountCtrl.text = _minorToPlain(deficit),
                        );
                      },
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                key: const Key('rebalance_confirm_btn'),
                onPressed: _saving
                    ? null
                    : () async {
                        if (_fromKey == _toKey) {
                          setState(
                            () => _errorMsg =
                                'Select two different category envelopes.',
                          );
                          return;
                        }
                        final spec = CurrencyCatalog.requireByCode(ccy);
                        final parsed = Money.parseDecimal(
                          _amountCtrl.text,
                          currency: spec,
                        );
                        if (parsed.isFailure ||
                            parsed.valueOrNull!.amountMinor <= 0) {
                          setState(
                            () => _errorMsg =
                                'Enter a valid positive amount to transfer.',
                          );
                          return;
                        }
                        setState(() {
                          _saving = true;
                          _errorMsg = null;
                        });
                        final nav = Navigator.of(context);
                        final res = await GetIt.I<BudgetRepository>()
                            .reallocateCategoryLimit(
                              profileId: widget.profile.id,
                              fromBudgetId: fromEnv.budgetId,
                              fromCategoryId: fromEnv.allocation.categoryId,
                              toBudgetId: toEnv.budgetId,
                              toCategoryId: toEnv.allocation.categoryId,
                              amountMinor: parsed.valueOrNull!.amountMinor,
                            );
                        if (!context.mounted) return;
                        if (res.isFailure) {
                          setState(() {
                            _saving = false;
                            _errorMsg =
                                res.failureOrNull?.message ??
                                'Rebalance failed.';
                          });
                          return;
                        }
                        showFintechToast(
                          context,
                          'Moved ${parsed.valueOrNull!.format()} from ${fromEnv.allocation.categoryName} → ${toEnv.allocation.categoryName}.',
                          tone: FintechToastTone.success,
                        );
                        if (nav.canPop()) nav.pop();
                        await widget.onSaved();
                      },
                icon: const Icon(Icons.swap_horiz_rounded),
                label: const Text('Confirm Rebalance'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({
    required this.index,
    required this.budget,
    required this.nowUtc,
    required this.masked,
    this.onEdit,
    this.onDelete,
  });

  final int index;
  final BudgetEntity budget;
  final DateTime nowUtc;
  final bool masked;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final ratio = budget.utilizationRatio.clamp(0.0, 1.0);
    final isWarning = !budget.isOverspent && budget.utilizationRatio >= 0.8;
    final daysLeft = budget.remainingDaysAt(nowUtc);

    final (
      Color barColor,
      Color badgeBg,
      String badgeLabel,
    ) = budget.isOverspent
        ? (cfo.expense, cfo.expenseContainer, 'Overspent')
        : isWarning
        ? (cfo.warning, cfo.warningContainer, '80%+ Used')
        : (cfo.income, cfo.incomeContainer, 'On Track');

    return StaggeredFadeSlide(
      index: index,
      child: PressScaleCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        budget.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${budget.periodType.label} • $daysLeft d left${budget.rolloverEnabled ? ' • Rollover' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.labelSmall?.copyWith(color: cfo.subtleText),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                FintechStatusPill(
                  label: badgeLabel,
                  showDot: true,
                  foreground: barColor,
                  background: badgeBg,
                ),
                if (onEdit != null)
                  IconButton(
                    tooltip: 'Edit budget',
                    visualDensity: VisualDensity.compact,
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 19),
                  ),
                if (onDelete != null)
                  IconButton(
                    tooltip: 'Delete budget',
                    visualDensity: VisualDensity.compact,
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded, size: 19),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            AnimatedProgressBar(value: masked ? 0.0 : ratio, color: barColor),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Text(
                  masked
                      ? 'Spent: ••••'
                      : 'Spent: ${budget.totalSpent.format()}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  masked
                      ? 'Limit: ••••'
                      : 'Limit: ${budget.overallLimit.format()}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cfo.subtleText,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            if (budget.allocations.isNotEmpty) ...[
              const Divider(height: 18),
              for (final alloc in budget.allocations)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              alloc.categoryName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 150),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                masked
                                    ? '•••• / ••••'
                                    : '${Money(amountMinor: alloc.spentMinor, currencyCode: alloc.currencyCode).format()} / ${Money(amountMinor: alloc.limitMinor, currencyCode: alloc.currencyCode).format()}',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: alloc.isOverspent
                                          ? cfo.expense
                                          : cfo.subtleText,
                                      fontWeight: FontWeight.w700,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      AnimatedProgressBar(
                        value: masked
                            ? 0.0
                            : alloc.utilizationRatio.clamp(0.0, 1.0),
                        color: alloc.isOverspent ? cfo.expense : barColor,
                        height: 4,
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
