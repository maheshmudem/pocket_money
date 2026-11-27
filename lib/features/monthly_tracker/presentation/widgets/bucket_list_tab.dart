import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/financial_engine/currency.dart';
import '../../../../core/financial_engine/money.dart';
import '../../../../core/financial_engine/monthly_tracker_engine.dart';
import '../../../../shared/widgets/enterprise_layout.dart';
import '../../../../shared/widgets/fintech_widgets.dart';
import '../../../../shared/widgets/modern_dialogs.dart';
import '../../data/monthly_tracker_service.dart';
import '../../domain/entities/bucket_list_item_entity.dart';

/// Tab 1 of Monthly Tracker: Priority-aware Bucket List planner, affordability
/// verdicts, 7-day cooling-off rule, and 1-tap Budget / Goal / Ledger actions.
class BucketListTab extends StatefulWidget {
  const BucketListTab({
    required this.data,
    required this.masked,
    required this.canManage,
    required this.onRefresh,
    required this.onAddItem,
    required this.onEditItem,
    required this.onDeleteItem,
    required this.onMarkBought,
    required this.onAddMoney,
    required this.onReserveInBudget,
    required this.onConvertToGoal,
    required this.onPostpone,
    super.key,
  });

  final MonthlyTrackerViewData data;
  final bool masked;
  final bool canManage;
  final Future<void> Function() onRefresh;
  final VoidCallback onAddItem;
  final void Function(BucketListItemEntity item) onEditItem;
  final void Function(BucketListItemEntity item) onDeleteItem;
  final void Function(BucketListItemEntity item) onMarkBought;
  final void Function(BucketListItemEntity item) onAddMoney;
  final void Function(BucketListItemEntity item) onReserveInBudget;
  final void Function(BucketListItemEntity item, BucketItemPlan? plan)
  onConvertToGoal;
  final void Function(BucketListItemEntity item) onPostpone;

  @override
  State<BucketListTab> createState() => _BucketListTabState();
}

class _BucketListTabState extends State<BucketListTab> {
  BucketPriority? _filter;
  bool _showBought = false;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final plan = widget.data.snapshot.bucketPlan;
    final ccy = widget.data.snapshot.currencyCode;
    final spec = CurrencyCatalog.byCode(ccy);

    bool matchesFilter(BucketListItemEntity item) =>
        _filter == null || item.priority == _filter;

    final thisMonth = widget.data.thisMonthItems.where(matchesFilter).toList();
    final upcoming = widget.data.upcomingItems.where(matchesFilter).toList();
    final bought = widget.data.purchasedThisMonthItems
        .where(matchesFilter)
        .toList();

    final summaryAccent = plan.urgentShortfallMinor > 0
        ? ModernDialogAccent.danger
        : (plan.deferredCount > 0
              ? ModernDialogAccent.warning
              : ModernDialogAccent.success);
    final coverageRatio = plan.totalPlannedThisMonthMinor > 0
        ? (plan.totalAllocatedMinor / plan.totalPlannedThisMonthMinor).clamp(
            0.0,
            1.0,
          )
        : 1.0;
    final coveragePct = (coverageRatio * 100).round();
    final countsByPriority = <BucketPriority, int>{
      for (final p in BucketPriority.values) p: 0,
    };
    for (final item in [
      ...widget.data.thisMonthItems,
      ...widget.data.upcomingItems,
    ]) {
      countsByPriority[item.priority] =
          (countsByPriority[item.priority] ?? 0) + 1;
    }
    final totalPlannedCount =
        widget.data.thisMonthItems.length + widget.data.upcomingItems.length;

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: SingleChildScrollView(
        key: const Key('monthly_tab_bucket'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EnterprisePageContainer.responsivePadding(context, bottom: 96),
        child: EnterprisePageContainer(
          maxWidth: AppBreakpoints.maxContentWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Plan Summary Hero Card
              StaggeredFadeSlide(
                index: 0,
                child: FintechAccentCard(
                  key: const Key('bucket_plan_summary_card'),
                  accent: summaryAccent,
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
                            'Bucket List Plan',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          FintechStatusPill(
                            icon: Icons.analytics_outlined,
                            label:
                                '${plan.affordableCount} affordable · ${plan.deferredCount} deferred',
                            foreground: plan.urgentShortfallMinor > 0
                                ? cfo.expense
                                : scheme.primary,
                            background: plan.urgentShortfallMinor > 0
                                ? cfo.expenseContainer
                                : scheme.primaryContainer,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 9,
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
                                child: _SummaryMetricTile(
                                  label: 'Planned',
                                  minor: plan.totalPlannedThisMonthMinor,
                                  ccy: ccy,
                                  spec: spec,
                                  masked: widget.masked,
                                  color: scheme.primary,
                                ),
                              ),
                              VerticalDivider(
                                width: 12,
                                thickness: 1,
                                color: cfo.divider,
                              ),
                              Expanded(
                                child: _SummaryMetricTile(
                                  label: 'Reserved',
                                  minor: plan.totalAllocatedMinor,
                                  ccy: ccy,
                                  spec: spec,
                                  masked: widget.masked,
                                  color: cfo.income,
                                ),
                              ),
                              VerticalDivider(
                                width: 12,
                                thickness: 1,
                                color: cfo.divider,
                              ),
                              Expanded(
                                child: _SummaryMetricTile(
                                  label: 'Shortfall',
                                  minor: plan.urgentShortfallMinor,
                                  ccy: ccy,
                                  spec: spec,
                                  masked: widget.masked,
                                  color: plan.urgentShortfallMinor > 0
                                      ? cfo.expense
                                      : cfo.subtleText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: AnimatedProgressBar(
                              value: widget.masked ? 0 : coverageRatio,
                              color: plan.urgentShortfallMinor > 0
                                  ? cfo.warning
                                  : cfo.income,
                              height: 6,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.masked
                                ? '••% covered'
                                : '$coveragePct% covered',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: cfo.subtleText,
                                  fontWeight: FontWeight.w800,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Urgent first → Needs → Nice-to-have within wants cap → Dreams become goals',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cfo.subtleText,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // 2. Single-Row Horizontal Priority Pill Bar
              SingleChildScrollView(
                key: const Key('bucket_priority_filter_bar'),
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterPillChip(
                      label: totalPlannedCount > 0
                          ? 'All · $totalPlannedCount'
                          : 'All',
                      selected: _filter == null,
                      tint: scheme.primary,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _filter = null);
                      },
                    ),
                    for (final p in BucketPriority.values) ...[
                      const SizedBox(width: 6),
                      _FilterPillChip(
                        label: (countsByPriority[p] ?? 0) > 0
                            ? '${p.label} · ${countsByPriority[p]}'
                            : p.label,
                        selected: _filter == p,
                        tint: switch (p) {
                          BucketPriority.urgent => cfo.expense,
                          BucketPriority.essential => scheme.primary,
                          BucketPriority.nice => cfo.warning,
                          BucketPriority.dream => cfo.accentCyan,
                        },
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _filter = _filter == p ? null : p);
                        },
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              if (thisMonth.isEmpty && upcoming.isEmpty && bought.isEmpty)
                EmptyStateView(
                  icon: Icons.checklist_rounded,
                  title: 'No planned purchases yet',
                  description:
                      'Add things you plan to buy this month or later so Pocket CFO can protect essentials, reserve budget, and warn on impulse buys.',
                  actionLabel: widget.canManage ? 'Add to Bucket List' : null,
                  onAction: widget.canManage ? widget.onAddItem : null,
                )
              else ...[
                // 3. This Month Section
                if (thisMonth.isNotEmpty) ...[
                  SectionHeader(
                    title: 'This Month (${thisMonth.length})',
                    subtitle: 'Ranked by priority against free cash flow',
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  for (var i = 0; i < thisMonth.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    StaggeredFadeSlide(
                      index: i,
                      child: _BucketItemCard(
                        item: thisMonth[i],
                        plan: widget.data.planById[thisMonth[i].id],
                        ccy: ccy,
                        spec: spec,
                        masked: widget.masked,
                        canManage: widget.canManage,
                        onMenuAction: (action) => _handleAction(
                          action,
                          thisMonth[i],
                          widget.data.planById[thisMonth[i].id],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                ],

                // 4. Upcoming Months Section
                if (upcoming.isNotEmpty) ...[
                  SectionHeader(
                    title: 'Upcoming Months (${upcoming.length})',
                    subtitle: 'Scheduled ahead with monthly savings targets',
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  for (var i = 0; i < upcoming.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _BucketItemCard(
                      item: upcoming[i],
                      plan: widget.data.planById[upcoming[i].id],
                      ccy: ccy,
                      spec: spec,
                      masked: widget.masked,
                      canManage: widget.canManage,
                      onMenuAction: (action) => _handleAction(
                        action,
                        upcoming[i],
                        widget.data.planById[upcoming[i].id],
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                ],

                // 5. Collapsible Bought This Month Section
                if (bought.isNotEmpty) ...[
                  InkWell(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    onTap: () => setState(() => _showBought = !_showBought),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Icon(
                            _showBought
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            color: cfo.subtleText,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Bought This Month (${bought.length})',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_showBought) ...[
                    const SizedBox(height: 6),
                    for (var i = 0; i < bought.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      _BucketItemCard(
                        item: bought[i],
                        plan: null,
                        ccy: ccy,
                        spec: spec,
                        masked: widget.masked,
                        canManage: widget.canManage,
                        onMenuAction: (action) =>
                            _handleAction(action, bought[i], null),
                      ),
                    ],
                  ],
                  const SizedBox(height: AppSpacing.md),
                ],
              ],

              if (widget.canManage)
                FilledButton.icon(
                  key: const Key('bucket_add_btn'),
                  onPressed: widget.onAddItem,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add to Bucket List'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleAction(
    String action,
    BucketListItemEntity item,
    BucketItemPlan? plan,
  ) {
    switch (action) {
      case 'bought':
        widget.onMarkBought(item);
      case 'fund':
        widget.onAddMoney(item);
      case 'reserve':
        widget.onReserveInBudget(item);
      case 'goal':
        widget.onConvertToGoal(item, plan);
      case 'postpone':
        widget.onPostpone(item);
      case 'edit':
        widget.onEditItem(item);
      case 'delete':
        widget.onDeleteItem(item);
    }
  }
}

class _BucketItemCard extends StatelessWidget {
  const _BucketItemCard({
    required this.item,
    required this.plan,
    required this.ccy,
    required this.spec,
    required this.masked,
    required this.canManage,
    required this.onMenuAction,
  });

  final BucketListItemEntity item;
  final BucketItemPlan? plan;
  final String ccy;
  final CurrencySpec? spec;
  final bool masked;
  final bool canManage;
  final ValueChanged<String> onMenuAction;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final isPurchased = item.status == BucketItemStatus.purchased;

    final (IconData pIcon, Color pFg, Color pBg) = switch (item.priority) {
      BucketPriority.urgent => (
        Icons.priority_high_rounded,
        cfo.expense,
        cfo.expenseContainer,
      ),
      BucketPriority.essential => (
        Icons.verified_outlined,
        scheme.primary,
        scheme.primaryContainer,
      ),
      BucketPriority.nice => (
        Icons.auto_awesome_outlined,
        cfo.warning,
        cfo.warningContainer,
      ),
      BucketPriority.dream => (
        Icons.star_outline_rounded,
        cfo.accentCyan,
        cfo.surfaceTonal,
      ),
    };

    final displayMinor = isPurchased && item.actualAmountMinor != null
        ? item.actualAmountMinor!
        : item.estimatedAmountMinor;
    final pct = (item.savedProgressRatio * 100).round();

    String? dueLabel;
    if (item.dueDateUtc != null) {
      final dt = DateTime.tryParse(item.dueDateUtc!)?.toLocal();
      if (dt != null) {
        dueLabel = DateFormat('d MMM').format(dt);
      }
    }

    final (IconData vIcon, Color vFg, Color vBg) = switch (plan?.verdict) {
      BucketVerdict.buyNow || BucketVerdict.funded => (
        Icons.check_circle_outline,
        cfo.income,
        cfo.incomeContainer,
      ),
      BucketVerdict.urgentShortfall => (
        Icons.warning_amber_rounded,
        cfo.expense,
        cfo.expenseContainer,
      ),
      BucketVerdict.partial || BucketVerdict.defer => (
        Icons.schedule_rounded,
        cfo.warning,
        cfo.warningContainer,
      ),
      BucketVerdict.saveUp ||
      BucketVerdict.scheduled ||
      null => (Icons.savings_outlined, scheme.primary, scheme.primaryContainer),
    };

    return PressScaleCard(
      key: Key('bucket_item_${item.id}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconSquircle(
                icon: isPurchased ? Icons.shopping_bag_rounded : pIcon,
                iconColor: isPurchased ? cfo.income : pFg,
                backgroundColor: isPurchased ? cfo.incomeContainer : pBg,
                size: 36,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        FintechStatusPill(
                          label: item.priority.label,
                          foreground: pFg,
                          background: pBg,
                        ),
                        if (isPurchased)
                          FintechStatusPill(
                            icon: Icons.check_rounded,
                            label: 'Bought',
                            foreground: cfo.income,
                            background: cfo.incomeContainer,
                          )
                        else if (plan != null)
                          FintechStatusPill(
                            icon: vIcon,
                            label: plan!.verdict.label,
                            foreground: vFg,
                            background: vBg,
                          ),
                        if (!isPurchased && (plan?.isOverdue ?? false))
                          FintechStatusPill(
                            label: 'Overdue',
                            foreground: cfo.expense,
                            background: cfo.expenseContainer,
                          )
                        else if (!isPurchased && (plan?.isDueSoon ?? false))
                          FintechStatusPill(
                            label: dueLabel != null
                                ? 'Due $dueLabel'
                                : 'Due soon',
                            foreground: cfo.warning,
                            background: cfo.warningContainer,
                          )
                        else if (dueLabel != null)
                          FintechStatusPill(
                            label: dueLabel,
                            foreground: cfo.subtleText,
                            background: cfo.surfaceTonal,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 108),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: MoneyText(
                    money: Money(amountMinor: displayMinor, currencyCode: ccy),
                    masked: masked,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              if (canManage)
                PopupMenuButton<String>(
                  key: Key('bucket_menu_${item.id}'),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onSelected: onMenuAction,
                  itemBuilder: (_) => [
                    if (!isPurchased) ...[
                      const PopupMenuItem(
                        value: 'bought',
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_outline, size: 18),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Mark as bought',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'fund',
                        child: Row(
                          children: [
                            Icon(Icons.add_card_outlined, size: 18),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Add money',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'reserve',
                        child: Row(
                          children: [
                            Icon(Icons.pie_chart_outline_rounded, size: 18),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Reserve in budget',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'goal',
                        child: Row(
                          children: [
                            Icon(Icons.flag_outlined, size: 18),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Convert to goal',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'postpone',
                        child: Row(
                          children: [
                            Icon(Icons.fast_forward_rounded, size: 18),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Move to next month',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 18),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Edit',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded, size: 18),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Delete',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (!isPurchased && plan != null) ...[
            const SizedBox(height: 8),
            Text(
              masked ? plan!.verdict.label : plan!.headline,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: vFg,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (plan!.coolingOffSuggested) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: cfo.warningContainer.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  border: Border.all(
                    color: cfo.warning.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.hourglass_bottom_rounded,
                      size: 14,
                      color: cfo.warning,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '7-day cooling-off rule: pause before spending >5% of income on an impulse want.',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cfo.warning,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    masked
                        ? 'Saved ••••••'
                        : 'Saved ${Money(amountMinor: math.min<int>(item.savedAmountMinor, item.estimatedAmountMinor), currencyCode: ccy).format(spec: spec)} of ${Money(amountMinor: item.estimatedAmountMinor, currencyCode: ccy).format(spec: spec)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cfo.subtleText,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  masked ? '••%' : '$pct%',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cfo.subtleText,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            AnimatedProgressBar(
              value: item.savedProgressRatio,
              color: item.savedAmountMinor >= item.estimatedAmountMinor
                  ? cfo.income
                  : scheme.primary,
              height: 6,
            ),
          ],
          if (item.reservedInBudgetMinor > 0 ||
              (item.linkedGoalId != null && item.linkedGoalId!.isNotEmpty)) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (item.reservedInBudgetMinor > 0)
                  FintechStatusPill(
                    icon: Icons.lock_outline_rounded,
                    label: masked
                        ? 'Budget reserved'
                        : 'Reserved ${Money(amountMinor: item.reservedInBudgetMinor, currencyCode: ccy).format(spec: spec)}',
                    foreground: scheme.primary,
                    background: scheme.primaryContainer,
                  ),
                if (item.linkedGoalId != null && item.linkedGoalId!.isNotEmpty)
                  FintechStatusPill(
                    icon: Icons.flag_rounded,
                    label: 'Linked to Savings Goal',
                    foreground: cfo.income,
                    background: cfo.incomeContainer,
                  ),
              ],
            ),
          ],
          if (!isPurchased && canManage) ...[
            const SizedBox(height: 10),
            Divider(height: 1, color: cfo.divider),
            FintechFlatActionBar(
              verticalPadding: 8,
              items: [
                FintechFlatActionItem(
                  icon: Icons.add_card_outlined,
                  label: '+ Fund',
                  color: scheme.primary,
                  onTap: () => onMenuAction('fund'),
                ),
                if (item.priority == BucketPriority.dream &&
                    (item.linkedGoalId == null || item.linkedGoalId!.isEmpty))
                  FintechFlatActionItem(
                    icon: Icons.flag_outlined,
                    label: 'Start Goal',
                    color: cfo.accentCyan,
                    onTap: () => onMenuAction('goal'),
                  )
                else if (plan?.verdict == BucketVerdict.defer)
                  FintechFlatActionItem(
                    icon: Icons.fast_forward_rounded,
                    label: 'Next Mo',
                    color: cfo.warning,
                    onTap: () => onMenuAction('postpone'),
                  )
                else if (item.categoryId != null &&
                    item.categoryId!.isNotEmpty &&
                    item.reservedInBudgetMinor < item.remainingMinor)
                  FintechFlatActionItem(
                    icon: Icons.pie_chart_outline_rounded,
                    label: 'Reserve',
                    color: scheme.primary,
                    onTap: () => onMenuAction('reserve'),
                  ),
                FintechFlatActionItem(
                  icon: Icons.check_circle_outline,
                  label: 'Buy',
                  color: cfo.income,
                  onTap: () => onMenuAction('bought'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryMetricTile extends StatelessWidget {
  const _SummaryMetricTile({
    required this.label,
    required this.minor,
    required this.ccy,
    required this.spec,
    required this.masked,
    required this.color,
  });

  final String label;
  final int minor;
  final String ccy;
  final CurrencySpec? spec;
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
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: cfo.subtleText),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: MoneyText(
            money: Money(amountMinor: minor, currencyCode: ccy),
            masked: masked,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _FilterPillChip extends StatelessWidget {
  const _FilterPillChip({
    required this.label,
    required this.selected,
    required this.tint,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final duration = AppMotion.resolve(context, AppMotion.fast);
    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected ? tint.withValues(alpha: 0.14) : cfo.surfaceTonal,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(
          color: selected ? tint : cfo.divider,
          width: selected ? 1.4 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text(
              label,
              maxLines: 1,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: selected ? tint : cfo.subtleText,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
