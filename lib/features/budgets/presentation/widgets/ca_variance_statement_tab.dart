import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/financial_engine/ca_budget_planner_engine.dart';
import '../../../../core/financial_engine/money.dart';
import '../../../../shared/widgets/enterprise_layout.dart';
import '../../../../shared/widgets/fintech_widgets.dart';
import '../../../../shared/widgets/modern_dialogs.dart';
import '../../data/ca_budget_planner_service.dart';

/// Tab 3 of `BudgetsPage` — Chartered Accountant Budget vs. Actual (BvA)
/// Variance Statement with Favorable `(F)` / Unfavorable `(U)` analysis,
/// Pro-Rata Pace tracking, Indian FY / Calendar cycling, and CA PDF/CSV Export.
class CaVarianceStatementTab extends StatelessWidget {
  const CaVarianceStatementTab({
    required this.snapshot,
    required this.selectedPeriod,
    required this.masked,
    required this.canManageBudget,
    required this.exportingPdf,
    required this.exportingCsv,
    required this.onSelectPeriod,
    required this.onToggleFyCycle,
    required this.onQuickRebalance,
    required this.onCapUnbudgeted,
    required this.onExportPdf,
    required this.onExportCsv,
    required this.onRefresh,
    super.key,
  });

  final CaBudgetWorkspaceSnapshot snapshot;
  final CaFiscalPeriodPreset selectedPeriod;
  final bool masked;
  final bool canManageBudget;
  final bool exportingPdf;
  final bool exportingCsv;
  final ValueChanged<CaFiscalPeriodPreset> onSelectPeriod;
  final VoidCallback onToggleFyCycle;
  final ValueChanged<RebalanceSuggestion> onQuickRebalance;
  final ValueChanged<CaVarianceLineItem> onCapUnbudgeted;
  final VoidCallback onExportPdf;
  final VoidCallback onExportCsv;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final st = snapshot.varianceStatement;
    final ccy = st.currencyCode;

    final netColor = st.isNetFavorable ? cfo.income : cfo.expense;
    final netBg = st.isNetFavorable
        ? cfo.incomeContainer
        : cfo.expenseContainer;
    final netAccent = st.isNetFavorable
        ? ModernDialogAccent.success
        : ModernDialogAccent.danger;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EnterprisePageContainer.responsivePadding(context, bottom: 96),
        child: EnterprisePageContainer(
          maxWidth: AppBreakpoints.maxContentWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Period & Fiscal Year Cycle Strip
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 34,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: CaFiscalPeriodPreset.values.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 6),
                        itemBuilder: (context, idx) {
                          final preset = CaFiscalPeriodPreset.values[idx];
                          final active = preset == selectedPeriod;
                          return Material(
                            color: active
                                ? scheme.primaryContainer
                                : cfo.surfaceTonal,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusFull,
                              ),
                              side: BorderSide(
                                color: active ? scheme.primary : cfo.divider,
                              ),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusFull,
                              ),
                              onTap: () {
                                HapticFeedback.selectionClick();
                                onSelectPeriod(preset);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 11,
                                ),
                                child: Center(
                                  child: Text(
                                    preset.label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: active
                                              ? scheme.primary
                                              : cfo.subtleText,
                                          fontWeight: active
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                        ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    key: const Key('budgets_fy_toggle_btn'),
                    color: cfo.surfaceTonal,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusFull,
                      ),
                      side: BorderSide(color: cfo.divider),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusFull,
                      ),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onToggleFyCycle();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        child: Text(
                          snapshot.fyStartMonth == 4 ? 'FY Apr–Mar' : 'Jan–Dec',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // 2. Executive BvA Variance Summary Hero
              StaggeredFadeSlide(
                index: 0,
                child: FintechAccentCard(
                  key: const Key('budgets_bva_summary_card'),
                  accent: netAccent,
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
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Budget vs. Actual • ${st.window.label}',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              Text(
                                '${st.window.fiscalCycleLabel} • ${(st.window.elapsedRatio * 100).round()}% period elapsed',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: cfo.subtleText),
                              ),
                            ],
                          ),
                          FintechStatusPill(
                            label: st.isNetFavorable
                                ? 'Favorable (F)'
                                : 'Unfavorable (U)',
                            showDot: true,
                            foreground: netColor,
                            background: netBg,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _BvaKpiCell(
                              label: 'Budgeted',
                              money: Money(
                                amountMinor: st.totalBudgetedMinor,
                                currencyCode: ccy,
                              ),
                              masked: masked,
                              color: scheme.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _BvaKpiCell(
                              label: 'Actual',
                              money: Money(
                                amountMinor: st.totalActualMinor,
                                currencyCode: ccy,
                              ),
                              masked: masked,
                              color: cfo.expense,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _BvaKpiCell(
                              label: 'Variance (${st.netCaCode})',
                              money: Money(
                                amountMinor: st.totalVarianceMinor.abs(),
                                currencyCode: ccy,
                              ),
                              masked: masked,
                              color: netColor,
                            ),
                          ),
                        ],
                      ),
                      if (st.totalActualMinor > 0) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            Text(
                              masked
                                  ? 'Fixed Mix: ••%'
                                  : 'Fixed Needs: ${st.fixedCostSharePercent.round()}%',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            Text(
                              masked
                                  ? 'Variable Mix: ••%'
                                  : 'Variable Wants: ${st.variableCostSharePercent.round()}%',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: cfo.warning,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            if (st.unbudgetedSpendMinor > 0)
                              Text(
                                'Uncapped: ${Money(amountMinor: st.unbudgetedSpendMinor, currencyCode: ccy).format(mask: masked)} (${st.unbudgetedCategoryCount})',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: cfo.expense,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // 3. Smart Envelope Rebalance Banner (when an overspent cap can be covered)
              if (st.rebalanceSuggestions.isNotEmpty && canManageBudget) ...[
                StaggeredFadeSlide(
                  index: 1,
                  child: FintechAccentCard(
                    accent: ModernDialogAccent.warning,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            IconSquircle(
                              icon: Icons.swap_horiz_rounded,
                              iconColor: cfo.warning,
                              backgroundColor: cfo.warningContainer,
                              size: 34,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Cover Overspending Instantly',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  Text(
                                    'Move ${Money(amountMinor: st.rebalanceSuggestions.first.suggestedTransferMinor, currencyCode: ccy).format(mask: masked)} from ${st.rebalanceSuggestions.first.fromCategoryName} → ${st.rebalanceSuggestions.first.toCategoryName}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
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
                        const SizedBox(height: 10),
                        FilledButton.tonalIcon(
                          key: const Key('budgets_bva_quick_rebalance_btn'),
                          onPressed: () =>
                              onQuickRebalance(st.rebalanceSuggestions.first),
                          icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                          label: const Text('Rebalance Envelopes'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              // 4. Line-by-Line CA Variance Rows
              SectionHeader(
                title: 'Line-by-Line Variance (${st.lines.length})',
                subtitle: 'F = Favorable (under cap) • U = Unfavorable',
              ),
              const SizedBox(height: AppSpacing.xs),

              if (st.lines.isEmpty)
                const EmptyStateView(
                  icon: Icons.analytics_outlined,
                  title: 'No variance activity in this period',
                  description:
                      'Create a Zero-Based Budget or log expenses to generate line-by-line Chartered Accountant variance reports.',
                )
              else
                for (var i = 0; i < st.lines.length; i++) ...[
                  StaggeredFadeSlide(
                    index: i + 2,
                    child: _VarianceLineCard(
                      line: st.lines[i],
                      currencyCode: ccy,
                      elapsedRatio: st.window.elapsedRatio,
                      masked: masked,
                      canManageBudget: canManageBudget,
                      matchingSuggestion: st.rebalanceSuggestions
                          .where(
                            (r) => r.toCategoryId == st.lines[i].categoryId,
                          )
                          .firstOrNull,
                      onQuickRebalance: onQuickRebalance,
                      onCapUnbudgeted: () => onCapUnbudgeted(st.lines[i]),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],

              const SizedBox(height: AppSpacing.sm),

              // 5. CA Export Pack (PDF + Formula-Safe CSV)
              PressScaleCard(
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
                          size: 36,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'CA Review Export Pack',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              Text(
                                'Share printable BvA PDF or Tally/Excel CSV',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: cfo.subtleText),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          key: const Key('budgets_export_pdf_btn'),
                          onPressed: exportingPdf ? null : onExportPdf,
                          icon: exportingPdf
                              ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.picture_as_pdf_outlined,
                                  size: 18,
                                ),
                          label: const Text('Export BvA PDF'),
                        ),
                        FilledButton.tonalIcon(
                          key: const Key('budgets_export_csv_btn'),
                          onPressed: exportingCsv ? null : onExportCsv,
                          icon: exportingCsv
                              ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.table_chart_outlined,
                                  size: 18,
                                ),
                          label: const Text('Export BvA CSV'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BvaKpiCell extends StatelessWidget {
  const _BvaKpiCell({
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
          const SizedBox(height: 2),
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

class _VarianceLineCard extends StatelessWidget {
  const _VarianceLineCard({
    required this.line,
    required this.currencyCode,
    required this.elapsedRatio,
    required this.masked,
    required this.canManageBudget,
    required this.onQuickRebalance,
    required this.onCapUnbudgeted,
    this.matchingSuggestion,
  });

  final CaVarianceLineItem line;
  final String currencyCode;
  final double elapsedRatio;
  final bool masked;
  final bool canManageBudget;
  final RebalanceSuggestion? matchingSuggestion;
  final ValueChanged<RebalanceSuggestion> onQuickRebalance;
  final VoidCallback onCapUnbudgeted;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;

    final statusColor = line.isUnbudgeted
        ? cfo.warning
        : (line.isFavorable ? cfo.income : cfo.expense);
    final statusBg = line.isUnbudgeted
        ? cfo.warningContainer
        : (line.isFavorable ? cfo.incomeContainer : cfo.expenseContainer);
    final statusText = line.isUnbudgeted
        ? 'Uncapped'
        : masked
        ? '${line.caCode} ••%'
        : '${line.caCode} ${line.variancePercent.abs().round()}%';

    final paceLabel = switch (line.paceStatus) {
      'overspent' => 'Over cap',
      'burning_fast' => 'Burning faster than period pace',
      'ahead_favorable' => 'Under pro-rata pace (favorable)',
      'unbudgeted' => 'Spend recorded without a budget cap',
      _ => 'Tracking on pace',
    };

    final utilRatio = line.budgetedMinor > 0
        ? (line.actualMinor / line.budgetedMinor).clamp(0.0, 1.0)
        : 1.0;

    return PressScaleCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    line.categoryName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  FintechStatusPill(
                    label: line.costClass.label,
                    foreground: scheme.primary,
                    background: scheme.primaryContainer,
                  ),
                ],
              ),
              FintechStatusPill(
                label: statusText,
                showDot: true,
                foreground: statusColor,
                background: statusBg,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Progress bar with Pro-Rata Pace vertical tick mark
          SizedBox(
            height: 10,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tickLeft = (constraints.maxWidth * elapsedRatio).clamp(
                  2.0,
                  constraints.maxWidth - 2.0,
                );
                return Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    AnimatedProgressBar(
                      value: masked ? 0.0 : utilRatio,
                      color: statusColor,
                      height: 6,
                    ),
                    if (!line.isUnbudgeted && !masked)
                      Positioned(
                        left: tickLeft - 1,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 2,
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(
                'Budget: ${Money(amountMinor: line.budgetedMinor, currencyCode: currencyCode).format(mask: masked)}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: cfo.subtleText,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                'Actual: ${Money(amountMinor: line.actualMinor, currencyCode: currencyCode).format(mask: masked)}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                '${line.varianceMinor >= 0 ? 'Left' : 'Over'}: ${Money(amountMinor: line.varianceMinor.abs(), currencyCode: currencyCode).format(mask: masked)}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  paceLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: cfo.subtleText),
                ),
              ),
              if (canManageBudget && matchingSuggestion != null)
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => onQuickRebalance(matchingSuggestion!),
                  child: const Text('Rebalance'),
                )
              else if (canManageBudget && line.isUnbudgeted)
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: onCapUnbudgeted,
                  child: const Text('Set Cap'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
