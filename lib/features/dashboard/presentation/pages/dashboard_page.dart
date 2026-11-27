import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/financial_engine/currency.dart';
import '../../../../core/financial_engine/money.dart';
import '../../../../core/utilities/clock.dart';
import '../../../../shared/widgets/editorial_bento_kit.dart';
import '../../../../shared/widgets/enterprise_layout.dart';
import '../../../../shared/widgets/fintech_widgets.dart';
import '../../../../shared/widgets/flagship_visuals.dart';
import '../../../../shared/widgets/modern_dialogs.dart';
import '../../../../shared/widgets/trendy_fintech_gauges.dart';
import '../../../accounts/domain/entities/financial_account_entity.dart';
import '../../../accounts/presentation/pages/accounts_page.dart';
import '../../../budgets/domain/entities/budget_entity.dart';
import '../../../budgets/presentation/pages/budgets_page.dart';
import '../../../monthly_tracker/data/monthly_tracker_service.dart';
import '../../../profiles/domain/entities/profile_entity.dart';
import '../../../profiles/presentation/bloc/active_profile_cubit.dart';
import '../../../settings/presentation/bloc/settings_cubit.dart';
import '../../../transactions/domain/entities/transaction_entity.dart';
import '../../../transactions/presentation/pages/transactions_page.dart';
import '../../domain/entities/dashboard_summary.dart';
import '../bloc/dashboard_bloc.dart';

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
                      top: 8,
                      bottom: 44,
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

                                // 1. Brushed Titanium Net Worth Hero + Hybrid Cash-Flow Bento + LED Budget Cockpit
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
                                  const SizedBox(height: 14),
                                  if (canPost) ...[
                                    StaggeredFadeSlide(
                                      index: 1,
                                      child: _QuickEntryPresetsStrip(
                                        profile: activeProfile,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                  ],
                                  StaggeredFadeSlide(
                                    index: 2,
                                    child: _CashFlowPulseCard(
                                      summary: summary,
                                      activeProfile: activeProfile,
                                      masked: hideBalances,
                                      canPost: canPost,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  StaggeredFadeSlide(
                                    index: 3,
                                    child: _ExpenseAndBudgetCommandCard(
                                      profile: activeProfile,
                                      budgets: state.budgets,
                                      periodSpend: summary.periodNetExpense,
                                      masked: hideBalances,
                                    ),
                                  ),
                                ],

                                // 2. Compact 1-Tap Quick Log Presets (Wide Layout)
                                if (isWide && canPost) ...[
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

                                // 6. This Month Pulse + Smart CFO Coach + Finance Hub Bento Grid
                                const SizedBox(height: 12),
                                StaggeredFadeSlide(
                                  index: 7,
                                  child: _ThisMonthPulseCard(
                                    profile: activeProfile,
                                    masked: hideBalances,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const StaggeredFadeSlide(
                                  index: 8,
                                  child: _SmartCfoCoachCard(),
                                ),
                                const SizedBox(height: 14),
                                const SectionHeader(
                                  title: 'Finance Hub',
                                  subtitle:
                                      'Planning, automation, imports & backups',
                                ),
                                const SizedBox(height: 8),
                                const StaggeredFadeSlide(
                                  index: 8,
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

    final heroContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            HeroGlassPill(
              label:
                  '${activeProfile.profileType.label.toUpperCase()} • ${activeProfile.baseCurrencyCode}',
              foreground: const Color(0xFFCBD5E1),
            ),
            const HeroGlassPill(
              label: 'Vault Active',
              dotColor: Color(0xFF34D399),
              foreground: Color(0xFFA7F3D0),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Welcome to ${activeProfile.name}',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Add your first bank, cash, wallet, or card account to unlock live net worth, cash-flow tracking, and 1-tap logging.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.76),
            height: 1.4,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0C1226),
                minimumSize: const Size(0, 42),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
              onPressed: () => context.go('/accounts'),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text(
                'Add First Account',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            if (canPost)
              OutlinedButton.icon(
                key: const Key('dashboard_quick_setup_btn'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
                onPressed: () => openAddAccountModal(context, activeProfile),
                icon: const Icon(Icons.bolt_rounded, size: 17),
                label: const Text(
                  'Instant Setup',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
      ],
    );

    return RefreshIndicator(
      onRefresh: () async =>
          context.read<DashboardBloc>().add(const DashboardRefreshRequested()),
      child: CustomScrollView(
        scrollCacheExtent: const ScrollCacheExtent.pixels(640),
        slivers: [
          SliverPadding(
            padding: EnterprisePageContainer.responsivePadding(
              context,
              top: 8,
              bottom: 44,
            ),
            sliver: SliverToBoxAdapter(
              child: EnterprisePageContainer(
                maxWidth: AppBreakpoints.maxDashboardWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PeriodBar(selected: selectedPeriod),
                    const SizedBox(height: 10),
                    StaggeredFadeSlide(
                      index: 0,
                      child: FullBleedTheaterStage(
                        tone: SignatureHeroTone.indigo,
                        isWideCard: true,
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                        child: heroContent,
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

/// Compact single-row overview title + crisp hairline pill period selector.
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Financial Overview',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.editorial(
                    context,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Balance sheet • Cash flow & vaults',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cfo.subtleText,
                    fontSize: 11,
                  ),
                ),
              ],
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

/// Brushed Black-Titanium Net Worth Hero Card + Straddling Ceramic Floating Dock.
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

    final liabMinor = summary.totalLiabilities.amountMinor.abs();
    final canPost = activeProfile.permissions.canPostTransaction;

    final sparkPoints = <double>[];
    var running =
        (summary.netWorth.amountMinor -
                summary.monthlyCashFlow.fold<int>(
                  0,
                  (s, pt) => s + (pt.incomeMinor - pt.expenseMinor),
                ))
            .toDouble();
    for (final pt in summary.monthlyCashFlow) {
      running += (pt.incomeMinor - pt.expenseMinor).toDouble();
      sparkPoints.add(running);
    }
    if (sparkPoints.length < 2) {
      final nw = summary.netWorth.amountMinor.toDouble();
      sparkPoints
        ..clear()
        ..addAll([nw * 0.72, nw * 0.78, nw * 0.85, nw * 0.92, nw]);
    }
    final sparkColor = summary.netWorth.amountMinor >= 0
        ? const Color(0xFF34D399)
        : const Color(0xFFF87171);

    final actionItems = [
      CircularActionItem(
        icon: Icons.north_east_rounded,
        label: 'Spend',
        color: cfo.expense,
        onTap: () => openAddTransactionSheet(
          context,
          activeProfile,
          initialType: TransactionType.expense,
        ),
      ),
      CircularActionItem(
        icon: Icons.south_west_rounded,
        label: 'Receive',
        color: cfo.income,
        onTap: () => openAddTransactionSheet(
          context,
          activeProfile,
          initialType: TransactionType.income,
        ),
      ),
      CircularActionItem(
        icon: Icons.swap_horiz_rounded,
        label: 'Transfer',
        color: cfo.transfer,
        onTap: () => openAddTransactionSheet(
          context,
          activeProfile,
          initialType: TransactionType.transfer,
        ),
      ),
      CircularActionItem(
        icon: Icons.add_card_rounded,
        label: 'Vault',
        color: scheme.secondary,
        onTap: () => openAddAccountModal(context, activeProfile),
      ),
    ];

    return FullBleedTheaterStage(
      tone: summary.netWorth.amountMinor >= 0
          ? SignatureHeroTone.indigo
          : SignatureHeroTone.crimson,
      isWideCard: true,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      floatingDock: canPost ? FloatingStageDock(items: actionItems) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row 1: NET WORTH • INR + Savings & Live Ledger platinum pills
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'NET WORTH • ${summary.baseCurrencyCode}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: const Color(0xFFF0CF7E),
                        letterSpacing: 1.25,
                        fontWeight: FontWeight.w800,
                        fontSize: 10.5,
                      ),
                    ),
                    if (savingsPct != null && !hideBalances)
                      HeroGlassPill(
                        label: savingsPct >= 0
                            ? 'Saved $savingsPct%'
                            : 'Overspent',
                        foreground: savingsPct >= 0
                            ? const Color(0xFF6EE7B7)
                            : const Color(0xFFFDA4AF),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const HeroGlassPill(
                label: 'LIVE LEDGER',
                dotColor: Color(0xFF2DD4A8),
                foreground: Color(0xFFF6E2A8),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Row 2: Monumental 38px Split-Decimal Net Worth Display
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedMoneyText(
              money: summary.netWorth,
              masked: hideBalances,
              semanticContextLabel: 'Net worth',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontSize: 38,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.3,
                height: 1.06,
                color: summary.netWorth.amountMinor >= 0
                    ? Colors.white
                    : const Color(0xFFFCA5A5),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Valued ${UiDateFormatter.shortDayMonth(summary.valuationTimestampUtc)}  •  Double-entry verified',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.54),
              fontSize: 10.5,
              letterSpacing: 0.15,
            ),
          ),
          const SizedBox(height: 10),

          // Row 3: Full-Width Glowing Wealth Ribbon Curve
          HeroWealthAreaChart(
            values: sparkPoints,
            color: sparkColor,
            height: 52,
            masked: hideBalances,
          ),
          const SizedBox(height: 10),

          // Row 4: Sleek Frosted Glass Assets | Liabilities Strip
          HeroGlassWell(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: _HeroSplitCell(
                    label: 'Assets',
                    money: summary.totalAssets,
                    masked: hideBalances,
                    dotColor: const Color(0xFF34D399),
                    amountColor: Colors.white,
                    labelColor: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
                Container(
                  width: 1,
                  height: 28,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  color: Colors.white.withValues(alpha: 0.14),
                ),
                Expanded(
                  child: _HeroSplitCell(
                    label: 'Liabilities',
                    money: summary.totalLiabilities,
                    masked: hideBalances,
                    dotColor: const Color(0xFFF87171),
                    amountColor: liabMinor > 0
                        ? const Color(0xFFFCA5A5)
                        : Colors.white.withValues(alpha: 0.78),
                    labelColor: Colors.white.withValues(alpha: 0.72),
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
    this.labelColor,
  });

  final String label;
  final Money money;
  final bool masked;
  final Color dotColor;
  final Color amountColor;
  final Color? labelColor;

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
                  color: labelColor ?? cfo.subtleText,
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

/// Lightweight Ceramic Asymmetric 2-Column Cash-Flow Bento combining the beloved
/// visual vertical Inflow/Outflow comparison pillars on the left with stacked
/// interactive Income & Net Expense ceramic cards on the right.
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
    final income = summary.periodIncome.amountMinor;
    final spend = summary.periodNetExpense.amountMinor;
    final netFlow = summary.periodNetCashFlow;
    final isPositive = netFlow.amountMinor >= 0;

    final int retainedPct = income > 0
        ? (100 - ((spend / income) * 100).round()).clamp(0, 100)
        : 0;

    final (String badgeText, Color badgeFg, Color badgeBg) = switch ((
      income,
      spend,
    )) {
      (0, 0) => ('No flow yet', cfo.subtleText, cfo.surfaceTonal),
      _ when spend <= income * 0.7 => (
        'Healthy Pace',
        cfo.income,
        cfo.incomeContainer,
      ),
      _ when spend <= income => (
        'Watch Spend',
        cfo.warning,
        cfo.warningContainer,
      ),
      _ => ('Deficit Period', cfo.expense, cfo.expenseContainer),
    };

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // LEFT CERAMIC BENTO CARD: Visual Vertical Inflow/Outflow Pillars + Net Delta
          Expanded(
            flex: 12,
            child: TactileColorBlock(
              accent: isPositive ? cfo.income : cfo.expense,
              borderRadius: 20,
              padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
              onTap: () => context.go('/insights'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Net Cash Flow',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Icon(
                        Icons.north_east_rounded,
                        size: 14,
                        color: cfo.subtleText,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      SizedBox(
                        width: 68,
                        child: BentoVerticalFlowBars(
                          incomeMinor: income,
                          expenseMinor: spend,
                          height: 54,
                          masked: masked,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              masked
                                  ? 'NET DELTA'
                                  : (income > 0
                                        ? '$retainedPct% RETAINED'
                                        : 'NET DELTA'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: cfo.subtleText,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.7,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: AnimatedMoneyText(
                                money: netFlow,
                                showPlusSign: true,
                                masked: masked,
                                semanticContextLabel: 'Net Delta',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: isPositive
                                          ? cfo.income
                                          : cfo.expense,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 18,
                                      letterSpacing: -0.4,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            FintechStatusPill(
                              label: badgeText,
                              showDot: true,
                              foreground: badgeFg,
                              background: badgeBg,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),

          // RIGHT STACKED CERAMIC MINI CARDS: Income + Net Expense
          Expanded(
            flex: 9,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: WatermarkBentoCard(
                    accent: cfo.income,
                    watermarkIcon: Icons.south_west_rounded,
                    borderRadius: 18,
                    padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                    onTap: canPost
                        ? () => openAddTransactionSheet(
                            context,
                            activeProfile,
                            initialType: TransactionType.income,
                          )
                        : null,
                    child: _BentoCashFlowMiniStat(
                      label: 'Income',
                      money: summary.periodIncome,
                      masked: masked,
                      color: cfo.income,
                      showQuickAdd: canPost,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: WatermarkBentoCard(
                    accent: cfo.expense,
                    watermarkIcon: Icons.north_east_rounded,
                    borderRadius: 18,
                    padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                    onTap: canPost
                        ? () => openAddTransactionSheet(
                            context,
                            activeProfile,
                            initialType: TransactionType.expense,
                          )
                        : null,
                    child: _BentoCashFlowMiniStat(
                      label: 'Net Expense',
                      money: summary.periodNetExpense,
                      masked: masked,
                      color: cfo.expense,
                      showQuickAdd: canPost,
                    ),
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

class _BentoCashFlowMiniStat extends StatelessWidget {
  const _BentoCashFlowMiniStat({
    required this.label,
    required this.money,
    required this.masked,
    required this.color,
    this.showQuickAdd = false,
  });

  final String label;
  final Money money;
  final bool masked;
  final Color color;
  final bool showQuickAdd;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
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
                  fontWeight: FontWeight.w800,
                  fontSize: 10.5,
                ),
              ),
            ),
            if (showQuickAdd)
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.add_rounded, size: 13, color: color),
              ),
          ],
        ),
        const SizedBox(height: 5),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: AnimatedMoneyText(
            money: money,
            masked: masked,
            semanticContextLabel: label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 17,
              letterSpacing: -0.3,
            ),
          ),
        ),
      ],
    );
  }
}

/// Open-canvas horizontal scrollable 1-tap Quick Log Preset pill strip
/// (eliminates card-inside-card clutter & prevents QuickBall overlap).
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            children: [
              Icon(Icons.flash_on_rounded, size: 14, color: scheme.primary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'QUICK LOG PRESETS',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cfo.subtleText,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.85,
                    fontSize: 10.5,
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
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < presets.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Builder(
                  builder: (context) {
                    final p = presets[i];
                    return Material(
                      color: cfo.surfaceElevated,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusFull,
                        ),
                        side: BorderSide(color: cfo.divider, width: 1.0),
                      ),
                      elevation: 0,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusFull,
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
                          padding: const EdgeInsets.fromLTRB(6, 5, 12, 5),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: p.bg,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(p.icon, size: 14, color: p.fg),
                              ),
                              const SizedBox(width: 7),
                              Text(
                                p.label,
                                maxLines: 1,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Swipeable Physical/Virtual Metallic Account Vault Deck right on the Home canvas.
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            children: [
              Expanded(
                child: EditorialSectionHeader(
                  title: 'Account Vaults',
                  count: accounts.length,
                  accentColor: scheme.primary,
                ),
              ),
              if (canPost) ...[
                InkWell(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    openAddAccountModal(context, profile);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4.5,
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
              ],
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
        const SizedBox(height: 8),
        if (preview.length == 1)
          VirtualAccountVaultCard(
            account: preview.first,
            baseCurrency: profile.baseCurrencyCode,
            sharePercent: 100,
            masked: masked,
            compact: true,
            onTap: () => context.go('/accounts'),
            onQuickAdd: canPost
                ? () => openAddTransactionSheet(
                    context,
                    profile,
                    initialSourceAccountId: preview.first.id,
                  )
                : null,
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < preview.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  SizedBox(
                    width: 256,
                    child: VirtualAccountVaultCard(
                      account: preview[i],
                      baseCurrency: profile.baseCurrencyCode,
                      sharePercent: totalAbsMinor > 0
                          ? ((preview[i].baseBalance.amountMinor.abs() /
                                        totalAbsMinor) *
                                    100)
                                .round()
                          : 0,
                      masked: masked,
                      compact: true,
                      onTap: () => context.go('/accounts'),
                      onQuickAdd: canPost
                          ? () => openAddTransactionSheet(
                              context,
                              profile,
                              initialSourceAccountId: preview[i].id,
                            )
                          : null,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
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
    Color(0xFF1D4ED8),
    Color(0xFF059669),
    Color(0xFF0284C7),
    Color(0xFFD97706),
    Color(0xFFDC2626),
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

class _ThisMonthPulseCard extends StatefulWidget {
  const _ThisMonthPulseCard({required this.profile, required this.masked});

  final FinancialProfile profile;
  final bool masked;

  @override
  State<_ThisMonthPulseCard> createState() => _ThisMonthPulseCardState();
}

class _ThisMonthPulseCardState extends State<_ThisMonthPulseCard> {
  MonthlyPulseSummary? _pulse;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _ThisMonthPulseCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.id != widget.profile.id) {
      _load();
    }
  }

  Future<void> _load() async {
    if (!GetIt.I.isRegistered<MonthlyTrackerService>()) return;
    final epoch = ++_epoch;
    final res = await GetIt.I<MonthlyTrackerService>().loadPulse(
      widget.profile,
    );
    if (!mounted || epoch != _epoch) return;
    setState(() => _pulse = res.valueOrNull);
  }

  @override
  Widget build(BuildContext context) {
    final pulse = _pulse;
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;

    return BlocListener<DashboardBloc, DashboardState>(
      listener: (context, _) => _load(),
      child: pulse == null
          ? const SizedBox.shrink()
          : () {
              final spec = CurrencyCatalog.byCode(pulse.currencyCode);
              String fmt(int minor) => Money(
                amountMinor: minor,
                currencyCode: pulse.currencyCode,
              ).format(spec: spec, mask: widget.masked);

              final monthShort = DateFormat(
                'MMM',
              ).format(DateTime.utc(pulse.year, pulse.month, 1));
              final denom = math.max<int>(
                1,
                math.max<int>(pulse.incomeMinor, pulse.spentMinor),
              );
              final spentPct = pulse.spentMinor * 100.0 / denom;
              final savedPct =
                  math.max<int>(0, pulse.savedMinor) * 100.0 / denom;

              final (
                Color badgeFg,
                Color badgeBg,
              ) = switch (pulse.healthLabel) {
                'Over Plan' => (cfo.expense, cfo.expenseContainer),
                'Watch' => (cfo.warning, cfo.warningContainer),
                _ => (cfo.income, cfo.incomeContainer),
              };

              return TactileColorBlock(
                key: const Key('dashboard_open_monthly_tracker_card'),
                accent: scheme.primary,
                onTap: () {
                  HapticFeedback.selectionClick();
                  context.push('/monthly');
                },
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconSquircle(
                          icon: Icons.calendar_month_rounded,
                          iconColor: scheme.primary,
                          backgroundColor: scheme.primaryContainer,
                          size: 34,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                'This Month · $monthShort',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              FintechStatusPill(
                                label: pulse.healthLabel,
                                foreground: badgeFg,
                                background: badgeBg,
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: cfo.subtleText,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: cfo.surfaceTonal,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMd,
                        ),
                        border: Border.all(color: cfo.divider),
                      ),
                      child: IntrinsicHeight(
                        child: Row(
                          children: [
                            Expanded(
                              child: _PulseStat(
                                label: 'Income',
                                value: fmt(pulse.incomeMinor),
                                color: cfo.income,
                              ),
                            ),
                            VerticalDivider(
                              width: 12,
                              thickness: 1,
                              color: cfo.divider,
                            ),
                            Expanded(
                              child: _PulseStat(
                                label: 'Spent',
                                value: fmt(pulse.spentMinor),
                                color: cfo.expense,
                              ),
                            ),
                            VerticalDivider(
                              width: 12,
                              thickness: 1,
                              color: cfo.divider,
                            ),
                            Expanded(
                              child: _PulseStat(
                                label: 'Saved',
                                value: fmt(pulse.savedMinor),
                                color: pulse.savedMinor >= 0
                                    ? scheme.primary
                                    : cfo.expense,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedMoneyBar(
                      height: 6,
                      showLegend: false,
                      masked: widget.masked,
                      segments: [
                        MoneyBarSegment(
                          label: 'Spent',
                          percent: spentPct,
                          color: cfo.expense,
                        ),
                        MoneyBarSegment(
                          label: 'Saved',
                          percent: savedPct,
                          color: cfo.income,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Bucket: ${pulse.plannedBucketCount} planned · ${pulse.dueSoonBucketCount} due soon',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: cfo.subtleText,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        if (pulse.safeDailySpendMinor > 0 &&
                            !widget.masked) ...[
                          const SizedBox(width: 6),
                          FintechStatusPill(
                            label: '${fmt(pulse.safeDailySpendMinor)}/day',
                            foreground: scheme.primary,
                            background: scheme.primaryContainer,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              );
            }(),
    );
  }
}

class _PulseStat extends StatelessWidget {
  const _PulseStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: cfo.subtleText),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _SmartCfoCoachCard extends StatelessWidget {
  const _SmartCfoCoachCard();

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    return FintechAccentCard(
      key: const Key('dashboard_open_coach_card'),
      accent: ModernDialogAccent.brand,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                context.push('/coach');
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    IconSquircle(
                      icon: Icons.auto_awesome_rounded,
                      iconColor: scheme.primary,
                      backgroundColor: scheme.primaryContainer,
                      size: 38,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  'Smart CFO Coach',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                              const SizedBox(width: 6),
                              FintechStatusPill(
                                label: 'FREE AI',
                                foreground: cfo.income,
                                background: cfo.incomeContainer,
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Monthly spend audit, smart budget caps & offline Q&A',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: cfo.subtleText, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: cfo.subtleText,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Divider(height: 1, color: cfo.divider),
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: const Key('dashboard_open_life_planner_tile'),
              onTap: () {
                HapticFeedback.selectionClick();
                context.push('/life-planner');
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    IconSquircle(
                      icon: Icons.family_restroom_rounded,
                      iconColor: cfo.income,
                      backgroundColor: cfo.incomeContainer,
                      size: 38,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  'Life & EMI Planner',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                              const SizedBox(width: 6),
                              FintechStatusPill(
                                label: 'STATUS PLAN',
                                foreground: scheme.primary,
                                background: scheme.primaryContainer,
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Bachelor, Family & Freelancer budgets, EMI guard & shield',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: cfo.subtleText, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: cfo.subtleText,
                    ),
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

class _QuickModulesBento extends StatelessWidget {
  const _QuickModulesBento();

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final featuredShortcut = (
      icon: Icons.calendar_month_rounded,
      label: 'Month Tracker',
      subtitle: 'Income, spend & bucket list',
      route: '/monthly',
      fg: scheme.primary,
      bg: scheme.primaryContainer,
    );
    final shortcuts = [
      (
        icon: Icons.pie_chart_rounded,
        label: 'Budgets',
        subtitle: 'CA ZBB & BvA',
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
        fg: scheme.secondary,
        bg: scheme.secondaryContainer,
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
            SizedBox(
              width: constraints.maxWidth,
              child: FintechSignatureHero(
                tone: SignatureHeroTone.indigo,
                borderRadius: 20,
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 14,
                ),
                onTap: () => context.push(featuredShortcut.route),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.28),
                        ),
                      ),
                      child: Icon(
                        featuredShortcut.icon,
                        color: Colors.white,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            featuredShortcut.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            featuredShortcut.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.76),
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            for (final s in shortcuts)
              SizedBox(
                width: tileWidth,
                child: SculptedBentoAppTile(
                  icon: s.icon,
                  title: s.label,
                  subtitle: s.subtitle,
                  accent: s.fg,
                  onTap: () => context.push(s.route),
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
                  final mag = tx.amount.amountMinor.abs();
                  final signedMinor = switch (tx.type) {
                    TransactionType.expense => -mag,
                    TransactionType.adjustment =>
                      tx.runningBalanceBefore != null &&
                              tx.runningBalanceAfter != null &&
                              (tx.runningBalanceAfter!.amountMinor -
                                      tx.runningBalanceBefore!.amountMinor) <
                                  0
                          ? -mag
                          : mag,
                    _ => mag,
                  };
                  final signedMoney = Money(
                    amountMinor: signedMinor,
                    currencyCode: tx.amount.currencyCode,
                  );
                  final showPlus =
                      tx.type != TransactionType.transfer && signedMinor > 0;
                  final semanticKind = switch (tx.type) {
                    TransactionType.income ||
                    TransactionType.refund => 'income',
                    TransactionType.expense => 'expense',
                    TransactionType.transfer => 'transfer',
                    _ => null,
                  };
                  final (
                    String flowTag,
                    Color flowFg,
                    Color flowBg,
                  ) = switch (tx.type) {
                    TransactionType.expense => (
                      'Deducted',
                      cfo.expense,
                      cfo.expenseContainer,
                    ),
                    TransactionType.income => (
                      'Income',
                      cfo.income,
                      cfo.incomeContainer,
                    ),
                    TransactionType.refund => (
                      'Refund',
                      cfo.income,
                      cfo.incomeContainer,
                    ),
                    TransactionType.transfer => (
                      'Transfer',
                      cfo.transfer,
                      cfo.transferContainer,
                    ),
                    TransactionType.openingBalance => (
                      'Opening',
                      cfo.warning,
                      cfo.warningContainer,
                    ),
                    TransactionType.adjustment => (
                      'Adjusted',
                      cfo.warning,
                      cfo.warningContainer,
                    ),
                  };
                  final balAfter = tx.runningBalanceAfter;
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
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5.5,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: flowBg,
                                        borderRadius: BorderRadius.circular(
                                          AppSpacing.radiusFull,
                                        ),
                                      ),
                                      child: Text(
                                        flowTag,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: flowFg,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 9.5,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Expanded(
                                      child: Text(
                                        _smartSubtitle(tx, title),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: cfo.subtleText,
                                              fontSize: 11,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 116),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: MoneyText(
                                    money: signedMoney,
                                    showPlusSign: showPlus,
                                    showSemanticIcon: false,
                                    masked: masked,
                                    semanticKind: semanticKind,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: semanticKind == null
                                              ? flowFg
                                              : null,
                                        ),
                                  ),
                                ),
                                if (balAfter != null) ...[
                                  const SizedBox(height: 1.5),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      'Bal ${balAfter.format(mask: masked)}',
                                      maxLines: 1,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: cfo.subtleText,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                    ),
                                  ),
                                ],
                              ],
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
      return TactileColorBlock(
        accent: scheme.secondary,
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

    return TactileColorBlock(
      accent: remainingMinor < 0
          ? cfo.expense
          : (ratio >= 0.8 ? cfo.warning : scheme.secondary),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 13),
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
                const SizedBox(height: 12),

                // Supercar 20-Segment LED Cockpit Arc Gauge + Remaining Hero Display
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CockpitSegmentedArcGauge(
                      progress: ratio,
                      color: statusColor,
                      centerLabel: '${(ratio * 100).round()}%',
                      caption: 'USED',
                      size: 112,
                      masked: masked,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Remaining',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: cfo.subtleText,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: MoneyText(
                              money: Money(
                                amountMinor: remainingMinor,
                                currencyCode: ccy,
                              ),
                              masked: masked,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    fontFamily: AppTypography.sansFamily,
                                    color: remainingMinor < 0
                                        ? cfo.expense
                                        : cfo.income,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 23,
                                    letterSpacing: -0.5,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(height: 1, color: cfo.divider),
                const SizedBox(height: 9),
                Padding(
                  padding: const EdgeInsets.only(right: 4),
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
                          width: 16,
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
              ],
            ),
          ),
          if (footerActions.isNotEmpty) ...[
            Divider(height: 1, color: cfo.divider),
            FintechFlatActionBar(verticalPadding: 10, items: footerActions),
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
