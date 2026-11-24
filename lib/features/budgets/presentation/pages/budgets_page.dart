import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/financial_engine/currency.dart';
import '../../../../core/financial_engine/money.dart';
import '../../../../core/utilities/clock.dart';
import '../../../../shared/widgets/enterprise_layout.dart';
import '../../../../shared/widgets/fintech_widgets.dart';
import '../../../../shared/widgets/modern_dialogs.dart';
import '../../../../shared/widgets/modern_dropdown.dart';
import '../../../../shared/widgets/modern_inputs.dart';
import '../../../categories/domain/entities/category_entity.dart';
import '../../../categories/domain/repositories/category_repository.dart';
import '../../../dashboard/presentation/bloc/dashboard_bloc.dart';
import '../../../profiles/domain/entities/profile_entity.dart';
import '../../../profiles/presentation/bloc/active_profile_cubit.dart';
import '../../../settings/presentation/bloc/settings_cubit.dart';
import '../../../transactions/domain/entities/transaction_entity.dart';
import '../../../transactions/presentation/pages/transactions_page.dart';
import '../../domain/entities/budget_entity.dart';
import '../../domain/repositories/budget_repository.dart';

/// Reusable `SCR-BUD-002` modal for setting a spending budget from Home, QuickBall, or BudgetsPage.
Future<void> openCreateBudgetModal(
  BuildContext context,
  FinancialProfile profile, {
  String suggestedName = '',
  String suggestedLimit = '',
  BudgetPeriodType initialPeriod = BudgetPeriodType.monthly,
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
    maxWidth: 500,
    builder: (_) => _CreateBudgetSheetBody(
      profile: profile,
      cats: cats,
      suggestedName: suggestedName,
      suggestedLimit: suggestedLimit,
      initialPeriod: initialPeriod,
      onSaved: () async {
        dashBloc?.add(const DashboardRefreshRequested());
        if (onSaved != null) {
          await onSaved();
        }
      },
    ),
  );
}

/// Covers `SCR-BUD-001` (Budgets Overview & Safe-to-Spend Daily Allowance)
/// and `SCR-BUD-002` (Create/Manage Budget).
class BudgetsPage extends StatefulWidget {
  const BudgetsPage({super.key});

  @override
  State<BudgetsPage> createState() => _BudgetsPageState();
}

class _BudgetsPageState extends State<BudgetsPage> {
  List<BudgetEntity>? _budgets;
  bool _loading = true;
  String? _loadedProfileId;

  Future<void> _reload(FinancialProfile profile) async {
    _loadedProfileId = profile.id.value;
    setState(() => _loading = true);
    final res = await GetIt.I<BudgetRepository>().listBudgetsWithProgress(
      profile.id,
    );
    if (!mounted) return;
    setState(() {
      _budgets = res.valueOrNull ?? const [];
      _loading = false;
    });
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
          description: 'Select a profile to track budgets.',
        ),
      );
    }
    if (_loadedProfileId != profile.id.value) {
      _loadedProfileId = profile.id.value;
      Future.microtask(() => _reload(profile));
    }

    final budgets = _budgets ?? const [];
    final hasBudgets = budgets.isNotEmpty;
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final canPost = profile.permissions.canPostTransaction;
    final canManageBudget = profile.permissions.canManageCategoriesAndBudgets;

    final nowUtc = GetIt.I<UtcClock>().nowUtc();
    final aggregate = BudgetHealthAggregate.compute(budgets, nowUtc);
    final totalLimitMinor = aggregate.totalLimitMinor;
    final totalSpentMinor = aggregate.totalSpentMinor;
    final remainingMinor = aggregate.remainingMinor;
    final safePerDayMinor = aggregate.safePerDayMinor;

    return Scaffold(
      appBar: EnterpriseAppBar(
        title: const Text('Budgets & Limits'),
        actions: [
          if (canPost && hasBudgets)
            TextButton.icon(
              onPressed: () async {
                await openAddTransactionSheet(
                  context,
                  profile,
                  initialType: TransactionType.expense,
                );
                if (mounted) await _reload(profile);
              },
              icon: const Icon(Icons.north_east_rounded, size: 17),
              label: const Text('Track Spend'),
            ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      floatingActionButton: hasBudgets && canManageBudget
          ? FloatingActionButton.extended(
              onPressed: () => openCreateBudgetModal(
                context,
                profile,
                onSaved: () => _reload(profile),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New Budget'),
            )
          : null,
      body: _loading && _budgets == null
          ? const DashboardSkeletonView()
          : !hasBudgets
          ? EmptyStateView(
              icon: Icons.pie_chart_outline_rounded,
              title: 'No budgets configured',
              description:
                  'Set monthly, weekly, or quarterly spending limits. Transfers are excluded and linked refunds net out automatically.',
              actionLabel: canManageBudget ? 'Create Budget' : null,
              onAction: canManageBudget
                  ? () => openCreateBudgetModal(
                      context,
                      profile,
                      suggestedName: 'Monthly Living',
                      onSaved: () => _reload(profile),
                    )
                  : null,
            )
          : RefreshIndicator(
              onRefresh: () => _reload(profile),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EnterprisePageContainer.responsivePadding(
                  context,
                  bottom: 96,
                ),
                child: EnterprisePageContainer(
                  maxWidth: AppBreakpoints.maxContentWidth,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final twoCols = constraints.maxWidth >= 680;
                      final cardWidth = twoCols
                          ? (constraints.maxWidth - AppSpacing.sm) / 2
                          : constraints.maxWidth;

                      final overallRatio = totalLimitMinor > 0
                          ? (totalSpentMinor / totalLimitMinor).clamp(0.0, 1.0)
                          : 0.0;
                      final statusColor = remainingMinor < 0
                          ? cfo.expense
                          : (overallRatio >= 0.8 ? cfo.warning : cfo.income);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          StaggeredFadeSlide(
                            index: 0,
                            child: PressScaleCard(
                              padding: const EdgeInsets.all(AppSpacing.lg),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      IconSquircle(
                                        icon: Icons.shield_outlined,
                                        iconColor: statusColor,
                                        backgroundColor: statusColor.withValues(
                                          alpha: 0.14,
                                        ),
                                        size: 40,
                                      ),
                                      const SizedBox(width: AppSpacing.sm),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Budget Health (${budgets.length})',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                            ),
                                            Text(
                                              aggregate.daysLeftHeadline,
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
                                      FintechStatusPill(
                                        label: hideBalances
                                            ? '••%'
                                            : '${(overallRatio * 100).round()}% Used',
                                        foreground: statusColor,
                                        background: statusColor.withValues(
                                          alpha: 0.14,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  AnimatedProgressBar(
                                    value: hideBalances ? 0.0 : overallRatio,
                                    color: statusColor,
                                    height: 8,
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _BudgetMetricBox(
                                          label: 'Total Spent',
                                          money: Money(
                                            amountMinor: totalSpentMinor,
                                            currencyCode:
                                                profile.baseCurrencyCode,
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
                                            currencyCode:
                                                profile.baseCurrencyCode,
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
                                            currencyCode:
                                                profile.baseCurrencyCode,
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
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: [
                              for (var idx = 0; idx < budgets.length; idx++)
                                SizedBox(
                                  width: cardWidth,
                                  child: _BudgetCard(
                                    index: idx + 1,
                                    budget: budgets[idx],
                                    nowUtc: nowUtc,
                                    masked: hideBalances,
                                    onDelete: canManageBudget
                                        ? () async {
                                            final target = budgets[idx];
                                            final confirmed =
                                                await showModernConfirmDialog(
                                                  context: context,
                                                  title: 'Delete Budget?',
                                                  message:
                                                      'Remove "${target.name}" spending guard? Existing ledger transactions will remain untouched.',
                                                  icon: Icons
                                                      .delete_outline_rounded,
                                                  accent:
                                                      ModernDialogAccent.danger,
                                                  confirmLabel: 'Delete',
                                                );
                                            if (confirmed != true ||
                                                !context.mounted) {
                                              return;
                                            }
                                            final dashBloc = context
                                                .read<DashboardBloc?>();
                                            await GetIt.I<BudgetRepository>()
                                                .deleteBudget(
                                                  profile.id,
                                                  target.id,
                                                );
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
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
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

class _CreateBudgetSheetBody extends StatefulWidget {
  const _CreateBudgetSheetBody({
    required this.profile,
    required this.cats,
    required this.suggestedName,
    required this.suggestedLimit,
    required this.initialPeriod,
    required this.onSaved,
  });

  final FinancialProfile profile;
  final List<CategoryEntity> cats;
  final String suggestedName;
  final String suggestedLimit;
  final BudgetPeriodType initialPeriod;
  final Future<void> Function() onSaved;

  @override
  State<_CreateBudgetSheetBody> createState() => _CreateBudgetSheetBodyState();
}

class _CreateBudgetSheetBodyState extends State<_CreateBudgetSheetBody> {
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
    _nameCtrl = TextEditingController(
      text: widget.suggestedName.isEmpty
          ? 'Monthly Spending'
          : widget.suggestedName,
    );
    _limitCtrl = TextEditingController(text: widget.suggestedLimit);
    _period = widget.initialPeriod;
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
                title: 'Create Budget',
                subtitle: 'Set a period spending guard with optional rollover.',
                icon: Icons.pie_chart_rounded,
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
              const SizedBox(height: AppSpacing.sm),
              FintechTextField(
                label: 'Limit ($ccy)',
                controller: _limitCtrl,
                autofocus: widget.suggestedLimit.isEmpty,
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
                  for (final preset in ['5000', '15000', '30000', '50000'])
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
                    if (v != null) {
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
                        final limitMinor = parsed.valueOrNull!.amountMinor;
                        setState(() {
                          _saving = true;
                          _errorMsg = null;
                        });
                        final nav = Navigator.of(context);
                        await GetIt.I<BudgetRepository>().createBudget(
                          profileId: profile.id,
                          name: _nameCtrl.text.trim(),
                          periodType: _period,
                          overallLimitMinor: limitMinor,
                          currencyCode: ccy,
                          categoryLimitsMinor: _selectedCatId != null
                              ? {_selectedCatId!: limitMinor}
                              : {},
                          rolloverEnabled: _rollover,
                        );
                        if (!mounted) return;
                        if (nav.canPop()) nav.pop();
                        await widget.onSaved();
                      },
                child: const Text('Save Budget'),
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
    this.onDelete,
  });

  final int index;
  final BudgetEntity budget;
  final DateTime nowUtc;
  final bool masked;
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
                if (onDelete != null)
                  IconButton(
                    tooltip: 'Delete budget',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            AnimatedProgressBar(value: masked ? 0.0 : ratio, color: barColor),
            const SizedBox(height: AppSpacing.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    masked
                        ? 'Spent: ••••'
                        : 'Spent: ${budget.totalSpent.format()}',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    masked
                        ? 'Limit: ••••'
                        : 'Limit: ${budget.overallLimit.format()}',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: cfo.subtleText),
                  ),
                ),
              ],
            ),
            if (budget.allocations.isNotEmpty) ...[
              const Divider(height: 20),
              for (final alloc in budget.allocations)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(child: Text(alloc.categoryName)),
                      Text(
                        masked
                            ? '••••'
                            : '${Money(amountMinor: alloc.spentMinor, currencyCode: alloc.currencyCode).format()} / ${Money(amountMinor: alloc.limitMinor, currencyCode: alloc.currencyCode).format()}',
                        style: TextStyle(
                          color: alloc.isOverspent ? cfo.expense : null,
                          fontWeight: FontWeight.w600,
                        ),
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
