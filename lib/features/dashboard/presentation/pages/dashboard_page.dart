import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/financial_engine/money.dart';
import '../../../../core/utilities/clock.dart';
import '../../../../shared/widgets/enterprise_layout.dart';
import '../../../../shared/widgets/fintech_widgets.dart';
import '../../../../shared/widgets/modern_dialogs.dart';
import '../../../accounts/domain/entities/financial_account_entity.dart';
import '../../../accounts/presentation/pages/accounts_page.dart';
import '../../../budgets/domain/entities/budget_entity.dart';
import '../../../budgets/presentation/pages/budgets_page.dart';
import '../../../profiles/domain/entities/profile_entity.dart';
import '../../../profiles/presentation/bloc/active_profile_cubit.dart';
import '../../../settings/presentation/bloc/settings_cubit.dart';
import '../../../transactions/domain/entities/transaction_entity.dart';
import '../../../transactions/presentation/pages/transactions_page.dart';
import '../../domain/entities/dashboard_summary.dart';
import '../bloc/dashboard_bloc.dart';

(Color fg, Color bg) _dashAccountAccent(
  FinancialAccountType type,
  PocketCfoColors cfo,
  ColorScheme scheme,
) => switch (type) {
  FinancialAccountType.bank => (scheme.primary, scheme.primaryContainer),
  FinancialAccountType.cash => (cfo.income, cfo.incomeContainer),
  FinancialAccountType.wallet => (cfo.transfer, cfo.transferContainer),
  FinancialAccountType.investment ||
  FinancialAccountType.other => (scheme.tertiary, scheme.tertiaryContainer),
  FinancialAccountType.creditCard ||
  FinancialAccountType.loan => (cfo.expense, cfo.expenseContainer),
};

/// `SCR-DASH-001` — Compact, Theme-Native Executive Home Dashboard with
/// unified Net Worth card, 3-column Cash-Flow Pulse, Expense & Budget Guard,
/// 1-Tap Quick Log Presets, sorted Account Vaults, Cash-Flow & Category charts,
/// zero-duplication Recent Activity, and Finance Hub Bento Grid.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final hideBalances = context.watch<SettingsCubit>().state.hideBalances;
    final activeProfile = context
        .watch<ActiveProfileCubit>()
        .state
        .activeProfile;

    if (activeProfile == null) {
      return EmptyStateView(
        icon: Icons.layers_outlined,
        title: 'Select or create a financial profile',
        description:
            'Every account, transaction, and summary belongs strictly to one isolated profile.',
        actionLabel: 'Manage Profiles',
        onAction: () => context.push('/profiles'),
      );
    }

    return AnimatedSwitcher(
      duration: AppMotion.resolve(context, AppMotion.fast),
      child: KeyedSubtree(
        key: ValueKey<String>(activeProfile.id.value),
        child: BlocBuilder<DashboardBloc, DashboardState>(
          builder: (context, state) {
            if (state.status == DashboardStatus.loading &&
                state.summary == null) {
              return const DashboardSkeletonView();
            }
            if (state.status == DashboardStatus.failure &&
                state.summary == null) {
              return ErrorStateView(
                message: state.failure?.message ?? 'Unable to load dashboard.',
                code: state.failure?.code,
                onRetry: () => context.read<DashboardBloc>().add(
                  const DashboardRefreshRequested(),
                ),
              );
            }

            final summary = state.summary;
            if (summary == null || state.status == DashboardStatus.empty) {
              return _EmptyDashboardLaunchpad(
                activeProfile: activeProfile,
                selectedPeriod: state.period,
              );
            }

            final canPost = activeProfile.permissions.canPostTransaction;

            return RefreshIndicator(
              onRefresh: () async => context.read<DashboardBloc>().add(
                const DashboardRefreshRequested(),
              ),
              child: CustomScrollView(
                scrollCacheExtent: const ScrollCacheExtent.pixels(640),
                slivers: [
                  SliverPadding(
                    padding: EnterprisePageContainer.responsivePadding(
                      context,
                      top: 10,
                      bottom: 84,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: EnterprisePageContainer(
                        maxWidth: AppBreakpoints.maxDashboardWidth,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final isWide =
                                constraints.maxWidth >= AppBreakpoints.medium;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _PeriodBar(selected: state.period),
                                const SizedBox(height: 10),
                                if (summary.pendingSyncCount > 0) ...[
                                  _PendingSyncBanner(
                                    pendingCount: summary.pendingSyncCount,
                                  ),
                                  const SizedBox(height: 10),
                                ],

                                // 1. Compact Net Worth Card + Unified Cash-Flow Pulse
                                if (isWide)
                                  StaggeredFadeSlide(
                                    index: 0,
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          flex: 7,
                                          child: _NetWorthHeroCard(
                                            summary: summary,
                                            activeProfile: activeProfile,
                                            hideBalances: hideBalances,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          flex: 5,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              _CashFlowPulseCard(
                                                summary: summary,
                                                activeProfile: activeProfile,
                                                masked: hideBalances,
                                                canPost: canPost,
                                              ),
                                              const SizedBox(height: 12),
                                              _ExpenseAndBudgetCommandCard(
                                                profile: activeProfile,
                                                budgets: state.budgets,
                                                periodSpend:
                                                    summary.periodNetExpense,
                                                masked: hideBalances,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else ...[
                                  StaggeredFadeSlide(
                                    index: 0,
                                    child: _NetWorthHeroCard(
                                      summary: summary,
                                      activeProfile: activeProfile,
                                      hideBalances: hideBalances,
                                    ),
                                  ),
                                  const SizedBox(height: 11),
                                  StaggeredFadeSlide(
                                    index: 1,
                                    child: _CashFlowPulseCard(
                                      summary: summary,
                                      activeProfile: activeProfile,
                                      masked: hideBalances,
                                      canPost: canPost,
                                    ),
                                  ),
                                  const SizedBox(height: 11),
                                  StaggeredFadeSlide(
                                    index: 2,
                                    child: _ExpenseAndBudgetCommandCard(
                                      profile: activeProfile,
                                      budgets: state.budgets,
                                      periodSpend: summary.periodNetExpense,
                                      masked: hideBalances,
                                    ),
                                  ),
                                ],

                                // 2. Compact 1-Tap Quick Log Presets
                                if (canPost) ...[
                                  const SizedBox(height: 11),
                                  StaggeredFadeSlide(
                                    index: 3,
                                    child: _QuickEntryPresetsStrip(
                                      profile: activeProfile,
                                    ),
                                  ),
                                ],

                                // 3. Sorted Account Vaults Overview
                                const SizedBox(height: 12),
                                StaggeredFadeSlide(
                                  index: 4,
                                  child: _AccountVaultsCarousel(
                                    accounts: summary.accounts,
                                    profile: activeProfile,
                                    masked: hideBalances,
                                  ),
                                ),

                                // 4. Cash Flow Bar Chart + Top Spending Categories
                                const SizedBox(height: 12),
                                StaggeredFadeSlide(
                                  index: 5,
                                  child: isWide
                                      ? Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              flex: 6,
                                              child: _CashFlowChartCard(
                                                points: summary.monthlyCashFlow,
                                                baseCurrency:
                                                    summary.baseCurrencyCode,
                                                masked: hideBalances,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              flex: 5,
                                              child: _TopSpendingRadarCard(
                                                items:
                                                    summary.categoryBreakdown,
                                                baseCurrency:
                                                    summary.baseCurrencyCode,
                                                masked: hideBalances,
                                                onAddExpense: canPost
                                                    ? () =>
                                                          openAddTransactionSheet(
                                                            context,
                                                            activeProfile,
                                                            initialType:
                                                                TransactionType
                                                                    .expense,
                                                          )
                                                    : null,
                                              ),
                                            ),
                                          ],
                                        )
                                      : Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            _CashFlowChartCard(
                                              points: summary.monthlyCashFlow,
                                              baseCurrency:
                                                  summary.baseCurrencyCode,
                                              masked: hideBalances,
                                            ),
                                            const SizedBox(height: 12),
                                            _TopSpendingRadarCard(
                                              items: summary.categoryBreakdown,
                                              baseCurrency:
                                                  summary.baseCurrencyCode,
                                              masked: hideBalances,
                                              onAddExpense: canPost
                                                  ? () =>
                                                        openAddTransactionSheet(
                                                          context,
                                                          activeProfile,
                                                          initialType:
                                                              TransactionType
                                                                  .expense,
                                                        )
                                                  : null,
                                            ),
                                          ],
                                        ),
                                ),

                                // 5. Recent Activity Feed
                                const SizedBox(height: 12),
                                StaggeredFadeSlide(
                                  index: 6,
                                  child: _RecentTransactionsCard(
                                    transactions: summary.recentTransactions,
                                    masked: hideBalances,
                                    onQuickRecord: canPost
                                        ? () => openAddTransactionSheet(
                                            context,
                                            activeProfile,
                                          )
                                        : null,
                                  ),
                                ),

                                // 6. Finance Hub Bento Grid
                                const SizedBox(height: 14),
                                const SectionHeader(
                                  title: 'Finance Hub',
                                  subtitle:
                                      'Planning, automation, imports & backups',
                                ),
                                const SizedBox(height: 8),
                                const StaggeredFadeSlide(
                                  index: 7,
                                  child: _QuickModulesBento(),
                                ),
                                const SizedBox(height: 8),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// First-run launchpad harmonized with the app's theme-native [FintechAccentCard].
class _EmptyDashboardLaunchpad extends StatelessWidget {
  const _EmptyDashboardLaunchpad({
    required this.activeProfile,
    required this.selectedPeriod,
  });

  final FinancialProfile activeProfile;
  final DashboardPeriodPreset selectedPeriod;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final canPost = activeProfile.permissions.canPostTransaction;

    final accountPresets = [
      (
        icon: Icons.account_balance_rounded,
        title: 'Bank Account',
        sub: 'Salary & savings',
        type: FinancialAccountType.bank,
        suggested: 'Primary Bank',
        fg: scheme.primary,
        bg: scheme.primaryContainer,
      ),
      (
        icon: Icons.payments_rounded,
        title: 'Cash Wallet',
        sub: 'Notes & petty cash',
        type: FinancialAccountType.cash,
        suggested: 'Cash in Hand',
        fg: cfo.income,
        bg: cfo.incomeContainer,
      ),
      (
        icon: Icons.credit_card_rounded,
        title: 'Credit Card',
        sub: 'Billing & limits',
        type: FinancialAccountType.creditCard,
        suggested: 'Rewards Card',
        fg: cfo.expense,
        bg: cfo.expenseContainer,
      ),
      (
        icon: Icons.account_balance_wallet_rounded,
        title: 'Digital Wallet',
        sub: 'UPI & instant pay',
        type: FinancialAccountType.wallet,
        suggested: 'Digital Wallet',
        fg: cfo.transfer,
        bg: cfo.transferContainer,
      ),
    ];

    return RefreshIndicator(
      onRefresh: () async =>
          context.read<DashboardBloc>().add(const DashboardRefreshRequested()),
      child: CustomScrollView(
        scrollCacheExtent: const ScrollCacheExtent.pixels(640),
        slivers: [
          SliverPadding(
            padding: EnterprisePageContainer.responsivePadding(
              context,
              top: 10,
              bottom: 84,
            ),
            sliver: SliverToBoxAdapter(
              child: EnterprisePageContainer(
                maxWidth: AppBreakpoints.maxDashboardWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PeriodBar(selected: selectedPeriod),
                    const SizedBox(height: 10),

                    // Theme-Native Launchpad Hero Card
                    StaggeredFadeSlide(
                      index: 0,
                      child: FintechAccentCard(
                        padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
                        bottomBar: canPost
                            ? FintechFlatActionBar(
                                items: [
                                  FintechFlatActionItem(
                                    key: const Key('dashboard_quick_setup_btn'),
                                    icon: Icons.bolt_rounded,
                                    label: 'Instant Setup',
                                    color: scheme.primary,
                                    onTap: () => openAddAccountModal(
                                      context,
                                      activeProfile,
                                    ),
                                  ),
                                  FintechFlatActionItem(
                                    icon: Icons.pie_chart_rounded,
                                    label: 'Set Budget',
                                    color: cfo.income,
                                    onTap: () => openCreateBudgetModal(
                                      context,
                                      activeProfile,
                                      suggestedName: 'Monthly Spending',
                                    ),
                                  ),
                                ],
                              )
                            : null,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                FintechStatusPill(
                                  label:
                                      '${activeProfile.profileType.label.toUpperCase()} • ${activeProfile.baseCurrencyCode}',
                                  foreground: scheme.primary,
                                  background: scheme.primaryContainer,
                                ),
                                FintechStatusPill(
                                  label: 'Vault Active',
                                  showDot: true,
                                  foreground: cfo.success,
                                  background: cfo.successContainer,
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Welcome to ${activeProfile.name}',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Add your first bank, cash, wallet, or card account to unlock live net worth, cash-flow tracking, and 1-tap logging.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: cfo.subtleText,
                                    height: 1.4,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 42),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                              ),
                              onPressed: () => context.go('/accounts'),
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('Add First Account'),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 1-Tap Quick Account Templates
                    if (canPost) ...[
                      const SizedBox(height: 14),
                      const SectionHeader(
                        title: '1-Tap Account Templates',
                        subtitle: 'Start tracking in seconds',
                      ),
                      const SizedBox(height: 8),
                      StaggeredFadeSlide(
                        index: 1,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final cols =
                                constraints.maxWidth >= AppBreakpoints.medium
                                ? 4
                                : 2;
                            const gap = 9.0;
                            final w =
                                (constraints.maxWidth - (cols - 1) * gap) /
                                cols;
                            return Wrap(
                              spacing: gap,
                              runSpacing: gap,
                              children: [
                                for (final p in accountPresets)
                                  SizedBox(
                                    width: w,
                                    child: PressScaleCard(
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        openAddAccountModal(
                                          context,
                                          activeProfile,
                                          initialType: p.type,
                                          suggestedName: p.suggested,
                                        );
                                      },
                                      borderRadius: AppSpacing.radiusMd,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 10,
                                      ),
                                      child: Row(
                                        children: [
                                          IconSquircle(
                                            icon: p.icon,
                                            iconColor: p.fg,
                                            backgroundColor: p.bg,
                                            size: 36,
                                          ),
                                          const SizedBox(width: 9),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  p.title,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelLarge
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                ),
                                                Text(
                                                  p.sub,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelSmall
                                                      ?.copyWith(
                                                        color: cfo.subtleText,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],

                    // Compact Readiness Card
                    const SizedBox(height: 12),
                    StaggeredFadeSlide(
                      index: 2,
                      child: PressScaleCard(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                IconSquircle(
                                  icon: Icons.rocket_launch_rounded,
                                  iconColor: scheme.primary,
                                  backgroundColor: scheme.primaryContainer,
                                  size: 34,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Workspace Readiness',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      Text(
                                        'Step 1 of 3 complete • Encrypted SQLite active',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(color: cfo.subtleText),
                                      ),
                                    ],
                                  ),
                                ),
                                FintechStatusPill(
                                  label: '33%',
                                  foreground: scheme.primary,
                                  background: scheme.primaryContainer,
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            AnimatedProgressBar(
                              value: 0.33,
                              color: scheme.primary,
                              height: 5,
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                ActionChip(
                                  visualDensity: VisualDensity.compact,
                                  avatar: Icon(
                                    Icons.check_circle_rounded,
                                    size: 15,
                                    color: cfo.success,
                                  ),
                                  label: const Text('1. Vault Created'),
                                  onPressed: () {},
                                ),
                                if (canPost)
                                  ActionChip(
                                    visualDensity: VisualDensity.compact,
                                    avatar: Icon(
                                      Icons.add_circle_outline_rounded,
                                      size: 15,
                                      color: scheme.primary,
                                    ),
                                    label: const Text('2. Add Account'),
                                    onPressed: () => openAddAccountModal(
                                      context,
                                      activeProfile,
                                    ),
                                  ),
                                ActionChip(
                                  visualDensity: VisualDensity.compact,
                                  avatar: Icon(
                                    Icons.upload_file_rounded,
                                    size: 15,
                                    color: scheme.tertiary,
                                  ),
                                  label: const Text('3. Import CSV'),
                                  onPressed: () => context.push('/import-csv'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),
                    const SectionHeader(
                      title: 'Finance Hub',
                      subtitle: 'Plan budgets, goals, loans & imports anytime',
                    ),
                    const SizedBox(height: 8),
                    const StaggeredFadeSlide(
                      index: 3,
                      child: _QuickModulesBento(),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingSyncBanner extends StatelessWidget {
  const _PendingSyncBanner({required this.pendingCount});

  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    return PressScaleCard(
      onTap: () => context.push('/sync'),
      backgroundColor: cfo.warningContainer,
      borderColor: cfo.warning.withValues(alpha: 0.35),
      borderRadius: AppSpacing.radiusMd,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          Icon(Icons.cloud_upload_outlined, size: 18, color: cfo.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$pendingCount local change(s) pending cloud sync',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: cfo.warning,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            'Review',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cfo.warning,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 2),
          Icon(Icons.chevron_right_rounded, size: 16, color: cfo.warning),
        ],
      ),
    );
  }
}

/// Compact single-row overview title + pill period selector.
class _PeriodBar extends StatelessWidget {
  const _PeriodBar({required this.selected});
  final DashboardPeriodPreset selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cfo = context.cfoColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Financial Overview',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<DashboardPeriodPreset>(
            tooltip: 'Select reporting period',
            initialValue: selected,
            onSelected: (preset) {
              HapticFeedback.selectionClick();
              context.read<DashboardBloc>().add(
                DashboardRefreshRequested(period: preset),
              );
            },
            itemBuilder: (ctx) => [
              for (final preset in DashboardPeriodPreset.values)
                PopupMenuItem<DashboardPeriodPreset>(
                  value: preset,
                  child: Row(
                    children: [
                      Icon(
                        preset == selected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        size: 17,
                        color: preset == selected
                            ? scheme.primary
                            : cfo.subtleText,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
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
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
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
                    size: 13,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 5),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 115),
                    child: Text(
                      selected.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                        fontSize: 12,
                      ),
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
      ),
    );
  }
}

/// Compact, theme-native Net Worth card harmonized with Accounts, Ledger & Profile.
class _NetWorthHeroCard extends StatelessWidget {
  const _NetWorthHeroCard({
    required this.summary,
    required this.activeProfile,
    required this.hideBalances,
  });

  final DashboardSummary summary;
  final FinancialProfile activeProfile;
  final bool hideBalances;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final incomeMinor = summary.periodIncome.amountMinor;
    final spendMinor = summary.periodNetExpense.amountMinor;
    final int? savingsPct = incomeMinor > 0
        ? (((incomeMinor - spendMinor) / incomeMinor) * 100).round()
        : null;

    final assetsMinor = summary.totalAssets.amountMinor.abs();
    final liabMinor = summary.totalLiabilities.amountMinor.abs();
    final totalGross = assetsMinor + liabMinor;
    final assetRatio = totalGross > 0
        ? (assetsMinor / totalGross).clamp(0.06, 0.94)
        : 1.0;

    final canPost = activeProfile.permissions.canPostTransaction;

    return FintechAccentCard(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
      bottomBar: canPost
          ? FintechFlatActionBar(
              verticalPadding: 10,
              items: [
                FintechFlatActionItem(
                  icon: Icons.north_east_rounded,
                  label: 'Spend',
                  color: cfo.expense,
                  onTap: () => openAddTransactionSheet(
                    context,
                    activeProfile,
                    initialType: TransactionType.expense,
                  ),
                ),
                FintechFlatActionItem(
                  icon: Icons.south_west_rounded,
                  label: 'Receive',
                  color: cfo.income,
                  onTap: () => openAddTransactionSheet(
                    context,
                    activeProfile,
                    initialType: TransactionType.income,
                  ),
                ),
                FintechFlatActionItem(
                  icon: Icons.swap_horiz_rounded,
                  label: 'Transfer',
                  color: cfo.transfer,
                  onTap: () => openAddTransactionSheet(
                    context,
                    activeProfile,
                    initialType: TransactionType.transfer,
                  ),
                ),
                FintechFlatActionItem(
                  icon: Icons.add_card_rounded,
                  label: 'Vault',
                  color: scheme.primary,
                  onTap: () => openAddAccountModal(context, activeProfile),
                ),
              ],
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row 1: NET WORTH • INR + Savings / Live status pill
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        'NET WORTH • ${summary.baseCurrencyCode}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cfo.subtleText,
                          letterSpacing: 0.7,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (savingsPct != null && !hideBalances) ...[
                      const SizedBox(width: 7),
                      FintechStatusPill(
                        label: savingsPct >= 0
                            ? 'Saved $savingsPct%'
                            : 'Overspent',
                        foreground: savingsPct >= 0 ? cfo.income : cfo.expense,
                        background: savingsPct >= 0
                            ? cfo.incomeContainer
                            : cfo.expenseContainer,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FintechStatusPill(
                label: 'LIVE LEDGER',
                showDot: true,
                foreground: cfo.success,
                background: cfo.successContainer,
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Row 2: Crisp Hero Net Worth + Valuation timestamp pill
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: AnimatedMoneyText(
                    money: summary.netWorth,
                    masked: hideBalances,
                    semanticContextLabel: 'Net worth',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      color: summary.netWorth.amountMinor >= 0
                          ? scheme.onSurface
                          : cfo.expense,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Updated ${UiDateFormatter.shortDayMonth(summary.valuationTimestampUtc)}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: cfo.subtleText,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Row 3: Thin Asset vs Liability health ratio bar
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            child: SizedBox(
              height: 5,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: (assetRatio * 100).round(),
                    child: ColoredBox(color: cfo.income),
                  ),
                  if (liabMinor > 0) ...[
                    const SizedBox(width: 2),
                    Expanded(
                      flex: ((1.0 - assetRatio) * 100).round(),
                      child: ColoredBox(color: cfo.expense),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Row 4: Single recessed inline Assets | Liabilities split strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cfo.surfaceTonal,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: cfo.divider.withValues(alpha: 0.7)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _HeroSplitCell(
                    label: 'Assets',
                    money: summary.totalAssets,
                    masked: hideBalances,
                    dotColor: cfo.income,
                    amountColor: cfo.income,
                  ),
                ),
                Container(
                  width: 1,
                  height: 26,
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  color: cfo.divider,
                ),
                Expanded(
                  child: _HeroSplitCell(
                    label: 'Liabilities',
                    money: summary.totalLiabilities,
                    masked: hideBalances,
                    dotColor: cfo.expense,
                    amountColor: liabMinor > 0 ? cfo.expense : cfo.subtleText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroSplitCell extends StatelessWidget {
  const _HeroSplitCell({
    required this.label,
    required this.money,
    required this.masked,
    required this.dotColor,
    required this.amountColor,
  });

  final String label;
  final Money money;
  final bool masked;
  final Color dotColor;
  final Color amountColor;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: cfo.subtleText,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: AnimatedMoneyText(
            money: money,
            masked: masked,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: amountColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

/// Compact unified Cash-Flow Pulse card combining Income, Net Expense,
/// Net Cash Flow, and Burn-Rate velocity bar into one sleek high-signal module.
class _CashFlowPulseCard extends StatelessWidget {
  const _CashFlowPulseCard({
    required this.summary,
    required this.activeProfile,
    required this.masked,
    required this.canPost,
  });

  final DashboardSummary summary;
  final FinancialProfile activeProfile;
  final bool masked;
  final bool canPost;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final income = summary.periodIncome.amountMinor;
    final spend = summary.periodNetExpense.amountMinor;
    final netFlow = summary.periodNetCashFlow;

    final double burnRatio = income > 0
        ? (spend / income).clamp(0.0, 1.0)
        : (spend > 0 ? 1.0 : 0.0);

    final (String badgeText, Color badgeFg, Color badgeBg) = switch ((
      income,
      spend,
    )) {
      (0, 0) => ('No flow yet', cfo.subtleText, cfo.surfaceTonal),
      _ when spend <= income * 0.7 => (
        'Healthy Pace',
        cfo.success,
        cfo.successContainer,
      ),
      _ when spend <= income => (
        'Watch Spend',
        cfo.warning,
        cfo.warningContainer,
      ),
      _ => ('Deficit Period', cfo.expense, cfo.expenseContainer),
    };

    return PressScaleCard(
      onTap: () => context.go('/insights'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconSquircle(
                icon: Icons.speed_rounded,
                iconColor: scheme.primary,
                backgroundColor: scheme.primaryContainer,
                size: 30,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Net Cash Flow',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              FintechStatusPill(
                label: badgeText,
                showDot: true,
                foreground: badgeFg,
                background: badgeBg,
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: cfo.subtleText,
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Compact 3-Column Inline Pulse Ribbon: Income | Net Expense | Net Delta
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: cfo.surfaceTonal,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: cfo.divider.withValues(alpha: 0.7)),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: _PulseColumn(
                      label: 'Income',
                      money: summary.periodIncome,
                      masked: masked,
                      color: cfo.income,
                      showQuickAdd: canPost,
                      onTap: canPost
                          ? () => openAddTransactionSheet(
                              context,
                              activeProfile,
                              initialType: TransactionType.income,
                            )
                          : null,
                    ),
                  ),
                  VerticalDivider(
                    width: 14,
                    thickness: 1,
                    indent: 2,
                    endIndent: 2,
                    color: cfo.divider,
                  ),
                  Expanded(
                    child: _PulseColumn(
                      label: 'Net Expense',
                      money: summary.periodNetExpense,
                      masked: masked,
                      color: cfo.expense,
                      showQuickAdd: canPost,
                      onTap: canPost
                          ? () => openAddTransactionSheet(
                              context,
                              activeProfile,
                              initialType: TransactionType.expense,
                            )
                          : null,
                    ),
                  ),
                  VerticalDivider(
                    width: 14,
                    thickness: 1,
                    indent: 2,
                    endIndent: 2,
                    color: cfo.divider,
                  ),
                  Expanded(
                    child: _PulseColumn(
                      label: 'Net Delta',
                      money: netFlow,
                      masked: masked,
                      showPlusSign: true,
                      color: netFlow.amountMinor >= 0
                          ? cfo.income
                          : cfo.expense,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 9),

          AnimatedProgressBar(
            value: masked ? 0.0 : burnRatio,
            color: badgeFg == cfo.subtleText ? scheme.primary : badgeFg,
            height: 5,
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: Text(
                  masked
                      ? 'Balances hidden'
                      : (income > 0
                            ? '${((spend / income) * 100).round()}% of period income utilized'
                            : 'Log income & expenses to track savings velocity'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cfo.subtleText,
                    fontSize: 11,
                  ),
                ),
              ),
              if (!masked && income > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '${((spend / income) * 100).round()}%',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: badgeFg,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _PulseColumn extends StatelessWidget {
  const _PulseColumn({
    required this.label,
    required this.money,
    required this.masked,
    required this.color,
    this.showPlusSign = false,
    this.showQuickAdd = false,
    this.onTap,
  });

  final String label;
  final Money money;
  final bool masked;
  final Color color;
  final bool showPlusSign;
  final bool showQuickAdd;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final content = Column(
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
                  color: cfo.subtleText,
                  fontWeight: FontWeight.w600,
                  fontSize: 10.5,
                ),
              ),
            ),
            if (showQuickAdd) ...[
              const SizedBox(width: 2),
              Icon(Icons.add_circle_outline_rounded, size: 12.5, color: color),
            ],
          ],
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: AnimatedMoneyText(
            money: money,
            showPlusSign: showPlusSign,
            masked: masked,
            semanticContextLabel: label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );

    if (onTap == null) return content;
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap!();
      },
      child: content,
    );
  }
}

/// Compact 1-Tap Quick Log Presets card with sleek 3x2 / 6x1 grid.
class _QuickEntryPresetsStrip extends StatelessWidget {
  const _QuickEntryPresetsStrip({required this.profile});

  final FinancialProfile profile;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;

    final presets = [
      (
        icon: Icons.payments_outlined,
        label: '+ Salary',
        type: TransactionType.income,
        desc: 'Salary / Income',
        fg: cfo.income,
        bg: cfo.incomeContainer,
      ),
      (
        icon: Icons.restaurant_rounded,
        label: 'Food & Cafe',
        type: TransactionType.expense,
        desc: 'Food & Dining',
        fg: cfo.expense,
        bg: cfo.expenseContainer,
      ),
      (
        icon: Icons.shopping_bag_outlined,
        label: 'Groceries',
        type: TransactionType.expense,
        desc: 'Groceries',
        fg: cfo.warning,
        bg: cfo.warningContainer,
      ),
      (
        icon: Icons.bolt_rounded,
        label: 'Utilities',
        type: TransactionType.expense,
        desc: 'Utility Bill',
        fg: scheme.primary,
        bg: scheme.primaryContainer,
      ),
      (
        icon: Icons.directions_car_outlined,
        label: 'Fuel & Ride',
        type: TransactionType.expense,
        desc: 'Transport & Fuel',
        fg: scheme.tertiary,
        bg: scheme.tertiaryContainer,
      ),
      (
        icon: Icons.swap_horiz_rounded,
        label: 'Self Transfer',
        type: TransactionType.transfer,
        desc: 'Own Account Transfer',
        fg: cfo.transfer,
        bg: cfo.transferContainer,
      ),
    ];

    return PressScaleCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flash_on_rounded, size: 15, color: scheme.primary),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  'QUICK LOG PRESETS',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cfo.subtleText,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
              Text(
                '1-tap entry',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: cfo.subtleText,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = constraints.maxWidth >= 680 ? 6 : 3;
              const gap = 7.0;
              final tileWidth =
                  (constraints.maxWidth - (cols - 1) * gap) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final p in presets)
                    SizedBox(
                      width: tileWidth,
                      child: Material(
                        color: cfo.surfaceTonal,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusMd,
                          ),
                          side: BorderSide(
                            color: cfo.divider.withValues(alpha: 0.65),
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusMd,
                          ),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            openAddTransactionSheet(
                              context,
                              profile,
                              initialType: p.type,
                              initialDescription: p.desc,
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 8,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: p.bg,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(p.icon, size: 15, color: p.fg),
                                ),
                                const SizedBox(height: 5),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    p.label,
                                    maxLines: 1,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 11,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Sorted full-width Account Vaults overview with zero-truncation tabular share readouts.
class _AccountVaultsCarousel extends StatelessWidget {
  const _AccountVaultsCarousel({
    required this.accounts,
    required this.profile,
    required this.masked,
  });

  final List<FinancialAccountEntity> accounts;
  final FinancialProfile profile;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final canPost = profile.permissions.canPostTransaction;
    final sorted = [...accounts]
      ..sort(
        (a, b) =>
            b.baseBalance.amountMinor.compareTo(a.baseBalance.amountMinor),
      );
    final totalAbsMinor = sorted.fold<int>(
      0,
      (s, a) => s + a.baseBalance.amountMinor.abs(),
    );
    final preview = sorted.take(5).toList();

    return PressScaleCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Account Vaults',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6.5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: cfo.surfaceTonal,
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusFull,
                          ),
                        ),
                        child: Text(
                          '${accounts.length}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: cfo.subtleText,
                                fontWeight: FontWeight.w800,
                                fontSize: 10,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (canPost)
                  InkWell(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      openAddAccountModal(context, profile);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusFull,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add_rounded,
                            size: 13.5,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            'New',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => context.go('/accounts'),
                  child: const Text('See all'),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cfo.divider),
          for (var i = 0; i < preview.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 60, color: cfo.divider),
            Builder(
              builder: (context) {
                final acc = preview[i];
                final share = totalAbsMinor > 0
                    ? (acc.baseBalance.amountMinor.abs() / totalAbsMinor).clamp(
                        0.0,
                        1.0,
                      )
                    : 0.0;
                final sharePct = (share * 100).round();
                final (accent, bg) = _dashAccountAccent(
                  acc.accountType,
                  cfo,
                  scheme,
                );

                return InkWell(
                  onTap: () => context.go('/accounts'),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                    child: Row(
                      children: [
                        IconSquircle(
                          icon: switch (acc.accountType) {
                            FinancialAccountType.bank =>
                              Icons.account_balance_rounded,
                            FinancialAccountType.cash => Icons.payments_rounded,
                            FinancialAccountType.creditCard ||
                            FinancialAccountType.loan =>
                              Icons.credit_card_rounded,
                            FinancialAccountType.wallet =>
                              Icons.account_balance_wallet_rounded,
                            FinancialAccountType.investment =>
                              Icons.trending_up_rounded,
                            FinancialAccountType.other => Icons.layers_rounded,
                          },
                          iconColor: accent,
                          backgroundColor: bg,
                          size: 38,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      acc.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5.5,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: cfo.surfaceTonal,
                                      borderRadius: BorderRadius.circular(
                                        AppSpacing.radiusFull,
                                      ),
                                    ),
                                    child: Text(
                                      acc.currencyCode,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w800,
                                            color: cfo.subtleText,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 1),
                              Text(
                                acc.accountType.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: cfo.subtleText,
                                      fontSize: 11,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: AnimatedProgressBar(
                                      value: masked ? 0.0 : share,
                                      color: accent,
                                      height: 4,
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  Text(
                                    masked ? '••%' : '$sharePct%',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: cfo.subtleText,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 10.5,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 112),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: MoneyText(
                                money: acc.balance,
                                masked: masked,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        ),
                        if (canPost) ...[
                          const SizedBox(width: 6),
                          IconButton(
                            tooltip: 'Record entry for ${acc.name}',
                            visualDensity: VisualDensity.compact,
                            style: IconButton.styleFrom(
                              backgroundColor: scheme.primaryContainer,
                              foregroundColor: scheme.primary,
                              minimumSize: const Size(30, 30),
                              padding: EdgeInsets.zero,
                            ),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              openAddTransactionSheet(
                                context,
                                profile,
                                initialSourceAccountId: acc.id,
                              );
                            },
                            icon: const Icon(Icons.add_rounded, size: 17),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _CashFlowChartCard extends StatelessWidget {
  const _CashFlowChartCard({
    required this.points,
    required this.baseCurrency,
    required this.masked,
  });

  final List<MonthlyCashFlowPoint> points;
  final String baseCurrency;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final maxMinor = points.fold<int>(
      100,
      (m, p) =>
          [m, p.incomeMinor, p.expenseMinor].reduce((a, b) => a > b ? a : b),
    );

    return PressScaleCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
                      'Cash Flow ($baseCurrency)',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Last 6 months • Excludes transfers',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cfo.subtleText,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => context.go('/insights'),
                child: const Text('Insights'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            children: [
              _LegendDot(color: cfo.income, label: 'Income'),
              _LegendDot(color: cfo.expense, label: 'Net Expense'),
            ],
          ),
          const SizedBox(height: 10),
          RepaintBoundary(
            child: SizedBox(
              height: 148,
              child: Semantics(
                label:
                    '6-month cash flow bar chart comparing income and net expense in $baseCurrency',
                child: BarChart(
                  BarChartData(
                    maxY: (maxMinor * 1.18).toDouble(),
                    barTouchData: BarTouchData(
                      enabled: !masked,
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipColor: (_) =>
                            Theme.of(context).colorScheme.onSurface,
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          if (groupIndex < 0 || groupIndex >= points.length) {
                            return null;
                          }
                          final pt = points[groupIndex];
                          final amount = Money(
                            amountMinor: rod.toY.round(),
                            currencyCode: baseCurrency,
                          ).format();
                          final kind = rodIndex == 0 ? 'In' : 'Out';
                          return BarTooltipItem(
                            '${pt.yearMonth} • $kind\n$amount',
                            TextStyle(
                              color: Theme.of(context).colorScheme.surface,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          );
                        },
                      ),
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) => FlLine(
                        color: cfo.divider,
                        strokeWidth: 1,
                        dashArray: const [4, 4],
                      ),
                    ),
                    borderData: FlBorderData(show: false),
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
                          getTitlesWidget: (val, _) {
                            final idx = val.toInt();
                            if (idx < 0 || idx >= points.length) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: Text(
                                points[idx].yearMonth.substring(5),
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: cfo.subtleText),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    barGroups: [
                      for (var i = 0; i < points.length; i++)
                        BarChartGroupData(
                          x: i,
                          barsSpace: 4,
                          barRods: [
                            BarChartRodData(
                              toY: masked
                                  ? 0
                                  : points[i].incomeMinor.toDouble(),
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  cfo.income.withValues(alpha: 0.72),
                                  cfo.income,
                                ],
                              ),
                              width: 10,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(5),
                              ),
                            ),
                            BarChartRodData(
                              toY: masked
                                  ? 0
                                  : points[i].expenseMinor.toDouble(),
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  cfo.expense.withValues(alpha: 0.72),
                                  cfo.expense,
                                ],
                              ),
                              width: 10,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(5),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  duration: AppMotion.resolve(context, AppMotion.standard),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact Top Spending Categories card with mini Donut ring + amount & share bars.
class _TopSpendingRadarCard extends StatelessWidget {
  const _TopSpendingRadarCard({
    required this.items,
    required this.baseCurrency,
    required this.masked,
    this.onAddExpense,
  });

  final List<CategorySpendItem> items;
  final String baseCurrency;
  final bool masked;
  final VoidCallback? onAddExpense;

  static const _palette = [
    Color(0xFF4F46E5),
    Color(0xFF0EA5E9),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFF43F5E),
  ];

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final topItems = items.take(4).toList();

    return PressScaleCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
                      'Top Categories',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Net spending distribution',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cfo.subtleText,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => context.go('/insights'),
                child: const Text('Analyze'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (topItems.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'No categorized expenses in this period yet.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: cfo.subtleText),
                    ),
                  ),
                  if (onAddExpense != null) ...[
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onPressed: onAddExpense,
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Log Expense'),
                    ),
                  ],
                ],
              ),
            )
          else
            Row(
              children: [
                RepaintBoundary(
                  child: SizedBox(
                    width: 74,
                    height: 74,
                    child: PieChart(
                      PieChartData(
                        centerSpaceRadius: 21,
                        sectionsSpace: 2,
                        sections: masked
                            ? [
                                PieChartSectionData(
                                  value: 1,
                                  color: cfo.divider,
                                  radius: 13,
                                  showTitle: false,
                                ),
                              ]
                            : [
                                for (var i = 0; i < topItems.length; i++)
                                  PieChartSectionData(
                                    value: topItems[i].netSpendMinor <= 0
                                        ? 1
                                        : topItems[i].netSpendMinor.toDouble(),
                                    color: _palette[i % _palette.length],
                                    radius: 13,
                                    showTitle: false,
                                  ),
                              ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    children: [
                      for (var i = 0; i < topItems.length; i++) ...[
                        if (i > 0) const SizedBox(height: 8),
                        Builder(
                          builder: (context) {
                            final item = topItems[i];
                            final color = _palette[i % _palette.length];
                            final pct = item.sharePercent.round();
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: BoxDecoration(
                                        color: color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        item.categoryName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 88,
                                      ),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerRight,
                                        child: MoneyText(
                                          money: Money(
                                            amountMinor: item.netSpendMinor,
                                            currencyCode: baseCurrency,
                                          ),
                                          masked: masked,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      masked ? '••%' : '$pct%',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: cfo.subtleText,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 10.5,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                AnimatedProgressBar(
                                  value: masked
                                      ? 0.0
                                      : (item.sharePercent / 100).clamp(
                                          0.04,
                                          1.0,
                                        ),
                                  color: color,
                                  height: 4.5,
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ],
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
        const SizedBox(width: 5),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: context.cfoColors.subtleText,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _QuickModulesBento extends StatelessWidget {
  const _QuickModulesBento();

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final shortcuts = [
      (
        icon: Icons.pie_chart_rounded,
        label: 'Budgets',
        subtitle: 'Limits & alerts',
        route: '/budgets',
        fg: scheme.primary,
        bg: scheme.primaryContainer,
      ),
      (
        icon: Icons.savings_rounded,
        label: 'Goals',
        subtitle: 'Reserves & targets',
        route: '/goals',
        fg: cfo.income,
        bg: cfo.incomeContainer,
      ),
      (
        icon: Icons.request_quote_rounded,
        label: 'Loans',
        subtitle: 'EMI schedule',
        route: '/loans',
        fg: cfo.warning,
        bg: cfo.warningContainer,
      ),
      (
        icon: Icons.repeat_rounded,
        label: 'Recurring',
        subtitle: 'Auto schedules',
        route: '/recurring',
        fg: cfo.transfer,
        bg: cfo.transferContainer,
      ),
      (
        icon: Icons.upload_file_rounded,
        label: 'CSV Import',
        subtitle: 'Bank statements',
        route: '/import-csv',
        fg: scheme.tertiary,
        bg: scheme.tertiaryContainer,
      ),
      (
        icon: Icons.category_rounded,
        label: 'Categories',
        subtitle: 'Ledger mapping',
        route: '/categories',
        fg: cfo.expense,
        bg: cfo.expenseContainer,
      ),
      (
        icon: Icons.cloud_sync_rounded,
        label: 'Sync',
        subtitle: 'Outbox & conflicts',
        route: '/sync',
        fg: scheme.primary,
        bg: scheme.primaryContainer,
      ),
      (
        icon: Icons.shield_rounded,
        label: 'Backup',
        subtitle: 'Encrypted .pcfo',
        route: '/backup',
        fg: cfo.success,
        bg: cfo.successContainer,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 640 ? 4 : 2;
        const gap = 8.0;
        final tileWidth = (constraints.maxWidth - (cols - 1) * gap) / cols;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final s in shortcuts)
              SizedBox(
                width: tileWidth,
                child: PressScaleCard(
                  onTap: () => context.push(s.route),
                  borderRadius: AppSpacing.radiusMd,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  child: Row(
                    children: [
                      IconSquircle(
                        icon: s.icon,
                        iconColor: s.fg,
                        backgroundColor: s.bg,
                        size: 34,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              s.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              s.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: cfo.subtleText,
                                    fontSize: 10.5,
                                  ),
                            ),
                          ],
                        ),
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

class _RecentTransactionsCard extends StatelessWidget {
  const _RecentTransactionsCard({
    required this.transactions,
    required this.masked,
    this.onQuickRecord,
  });

  final List<TransactionEntity> transactions;
  final bool masked;
  final VoidCallback? onQuickRecord;

  String _smartSubtitle(TransactionEntity tx, String title) {
    final parts = <String>[
      UiDateFormatter.shortDayMonth(tx.transactionDateUtc),
    ];
    if (tx.type == TransactionType.transfer &&
        tx.sourceAccountName != null &&
        tx.destinationAccountName != null) {
      parts.add('${tx.sourceAccountName} → ${tx.destinationAccountName}');
    } else {
      final acct = tx.sourceAccountName ?? tx.destinationAccountName;
      if (acct != null && acct.isNotEmpty) {
        parts.add(acct);
      }
      final cat = tx.categoryName ?? tx.type.label;
      if (cat.toLowerCase() != title.toLowerCase()) {
        parts.add(cat);
      }
    }
    if (tx.isReversed) {
      parts.add('Reversed');
    }
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    return PressScaleCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 10, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Recent Activity',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => context.go('/transactions'),
                  child: const Text('Ledger'),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cfo.divider),
          if (transactions.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'No transactions recorded in this period yet.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: cfo.subtleText),
                    ),
                  ),
                  if (onQuickRecord != null) ...[
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onPressed: onQuickRecord,
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Record'),
                    ),
                  ],
                ],
              ),
            )
          else
            for (var i = 0; i < transactions.length; i++) ...[
              if (i > 0) Divider(height: 1, indent: 58, color: cfo.divider),
              Builder(
                builder: (context) {
                  final tx = transactions[i];
                  final title = tx.description?.isNotEmpty == true
                      ? tx.description!
                      : (tx.categoryName ?? tx.type.label);
                  return InkWell(
                    onTap: () => context.go('/transactions'),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
                      child: Row(
                        children: [
                          _TxTypeAvatar(type: tx.type),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  _smartSubtitle(tx, title),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: cfo.subtleText,
                                        fontSize: 11,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 114),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: MoneyText(
                                  money: tx.amount,
                                  masked: masked,
                                  semanticKind: switch (tx.type) {
                                    TransactionType.income ||
                                    TransactionType.refund => 'income',
                                    TransactionType.expense => 'expense',
                                    TransactionType.transfer => 'transfer',
                                    _ => null,
                                  },
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
        ],
      ),
    );
  }
}

class _TxTypeAvatar extends StatelessWidget {
  const _TxTypeAvatar({required this.type});
  final TransactionType type;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final (IconData icon, Color fg, Color bg) = switch (type) {
      TransactionType.income => (
        Icons.south_west_rounded,
        cfo.income,
        cfo.incomeContainer,
      ),
      TransactionType.refund => (
        Icons.replay_rounded,
        cfo.income,
        cfo.incomeContainer,
      ),
      TransactionType.expense => (
        Icons.north_east_rounded,
        cfo.expense,
        cfo.expenseContainer,
      ),
      TransactionType.transfer => (
        Icons.swap_horiz_rounded,
        cfo.transfer,
        cfo.transferContainer,
      ),
      TransactionType.openingBalance || TransactionType.adjustment => (
        Icons.tune_rounded,
        cfo.warning,
        cfo.warningContainer,
      ),
    };
    return IconSquircle(
      icon: icon,
      iconColor: fg,
      backgroundColor: bg,
      size: 36,
    );
  }
}

/// Sleek, compact Home Expense & Budget Guard card with 1-row quick preset strip,
/// inline Budget Spent / Remaining / Safe-per-Day readout, and flat hairline actions.
class _ExpenseAndBudgetCommandCard extends StatelessWidget {
  const _ExpenseAndBudgetCommandCard({
    required this.profile,
    required this.budgets,
    required this.periodSpend,
    required this.masked,
  });

  final FinancialProfile profile;
  final List<BudgetEntity> budgets;
  final Money periodSpend;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final canPost = profile.permissions.canPostTransaction;
    final canManageBudget = profile.permissions.canManageCategoriesAndBudgets;
    final ccy = profile.baseCurrencyCode;

    final nowUtc = GetIt.I<UtcClock>().nowUtc();
    final aggregate = BudgetHealthAggregate.compute(budgets, nowUtc);

    final footerActions = <FintechFlatActionItem>[
      if (canPost)
        FintechFlatActionItem(
          key: const Key('dashboard_track_expense_btn'),
          icon: Icons.north_east_rounded,
          label: 'Track Expense',
          color: cfo.expense,
          onTap: () => openAddTransactionSheet(
            context,
            profile,
            initialType: TransactionType.expense,
          ),
        ),
      if (canManageBudget)
        FintechFlatActionItem(
          key: const Key('dashboard_set_budget_btn'),
          icon: Icons.pie_chart_outline_rounded,
          label: 'Set Budget',
          color: scheme.primary,
          onTap: () => openCreateBudgetModal(
            context,
            profile,
            suggestedName: budgets.isEmpty
                ? 'Monthly Spending'
                : 'Category Cap',
          ),
        ),
    ];

    if (budgets.isEmpty) {
      return PressScaleCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconSquircle(
                        icon: Icons.pie_chart_rounded,
                        iconColor: scheme.primary,
                        backgroundColor: scheme.primaryContainer,
                        size: 32,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Expense & Budget Guard',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            Text(
                              'Set a monthly cap for daily safe-to-spend allowance',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: cfo.subtleText,
                                    fontSize: 11,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (canManageBudget) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        for (final (i, preset) in const [
                          ('15000', '15k'),
                          ('30000', '30k'),
                          ('50000', '50k'),
                        ].indexed) ...[
                          if (i > 0) const SizedBox(width: 7),
                          Expanded(
                            child: Material(
                              color: cfo.surfaceTonal,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppSpacing.radiusFull,
                                ),
                                side: BorderSide(
                                  color: cfo.divider.withValues(alpha: 0.7),
                                ),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                  AppSpacing.radiusFull,
                                ),
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  openCreateBudgetModal(
                                    context,
                                    profile,
                                    suggestedName: 'Monthly Spending',
                                    suggestedLimit: preset.$1,
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6.5,
                                    horizontal: 6,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.bolt_rounded,
                                        size: 13.5,
                                        color: scheme.primary,
                                      ),
                                      const SizedBox(width: 3),
                                      Flexible(
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            '$ccy ${preset.$2}',
                                            maxLines: 1,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (footerActions.isNotEmpty) ...[
              Divider(height: 1, color: cfo.divider),
              FintechFlatActionBar(verticalPadding: 9.5, items: footerActions),
            ],
          ],
        ),
      );
    }

    final totalLimitMinor = aggregate.totalLimitMinor;
    final totalSpentMinor = aggregate.totalSpentMinor;
    final remainingMinor = aggregate.remainingMinor;
    final safePerDayMinor = aggregate.safePerDayMinor;
    final ratio = totalLimitMinor > 0
        ? (totalSpentMinor / totalLimitMinor).clamp(0.0, 1.0)
        : 0.0;

    final (
      Color statusColor,
      Color statusBg,
      String statusLabel,
    ) = remainingMinor < 0
        ? (cfo.expense, cfo.expenseContainer, 'Over Budget')
        : (ratio >= 0.8
              ? (cfo.warning, cfo.warningContainer, 'Near Limit')
              : (cfo.income, cfo.incomeContainer, 'On Track'));

    return PressScaleCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconSquircle(
                      icon: Icons.pie_chart_rounded,
                      iconColor: statusColor,
                      backgroundColor: statusBg,
                      size: 32,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Expense & Budget Guard',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            aggregate.compactDaysLeftLabel,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: cfo.subtleText, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    FintechStatusPill(
                      label: statusLabel,
                      showDot: true,
                      foreground: statusColor,
                      background: statusBg,
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => context.push('/budgets'),
                      child: const Text('All'),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: AnimatedProgressBar(
                    value: masked ? 0.0 : ratio,
                    color: statusColor,
                    height: 5.5,
                  ),
                ),
                const SizedBox(height: 9),
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: cfo.surfaceTonal,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      border: Border.all(
                        color: cfo.divider.withValues(alpha: 0.7),
                      ),
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        children: [
                          Expanded(
                            child: _MiniStatCell(
                              label: 'Budget Spent',
                              money: Money(
                                amountMinor: totalSpentMinor,
                                currencyCode: ccy,
                              ),
                              masked: masked,
                              color: cfo.expense,
                            ),
                          ),
                          VerticalDivider(
                            width: 14,
                            thickness: 1,
                            color: cfo.divider,
                          ),
                          Expanded(
                            child: _MiniStatCell(
                              label: 'Remaining',
                              money: Money(
                                amountMinor: remainingMinor,
                                currencyCode: ccy,
                              ),
                              masked: masked,
                              color: remainingMinor < 0
                                  ? cfo.expense
                                  : cfo.income,
                            ),
                          ),
                          VerticalDivider(
                            width: 14,
                            thickness: 1,
                            color: cfo.divider,
                          ),
                          Expanded(
                            child: _MiniStatCell(
                              label: 'Safe / Day',
                              money: Money(
                                amountMinor: safePerDayMinor,
                                currencyCode: ccy,
                              ),
                              masked: masked,
                              color: scheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (footerActions.isNotEmpty) ...[
            Divider(height: 1, color: cfo.divider),
            FintechFlatActionBar(verticalPadding: 9.5, items: footerActions),
          ],
        ],
      ),
    );
  }
}

class _MiniStatCell extends StatelessWidget {
  const _MiniStatCell({
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: cfo.subtleText,
            fontSize: 10.5,
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: MoneyText(
            money: money,
            masked: masked,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}
