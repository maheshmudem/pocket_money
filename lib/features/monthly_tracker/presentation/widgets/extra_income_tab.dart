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
import '../../../../shared/widgets/trendy_fintech_gauges.dart';
import '../../data/monthly_tracker_service.dart';

/// Tab 2 of Monthly Tracker: This Month's Income Roster, Interactive Live
/// Windfall Simulator, 2x2 Quick Income Launchpad, and Split History.
class ExtraIncomeTab extends StatefulWidget {
  const ExtraIncomeTab({
    required this.data,
    required this.masked,
    required this.canPost,
    required this.onRefresh,
    required this.onAddExtraIncome,
    this.onQuickSplitExtraIncome,
    super.key,
  });

  final MonthlyTrackerViewData data;
  final bool masked;
  final bool canPost;
  final Future<void> Function() onRefresh;
  final VoidCallback onAddExtraIncome;
  final void Function({int? amountMinor, String? sourceLabel, String? preset})?
  onQuickSplitExtraIncome;

  @override
  State<ExtraIncomeTab> createState() => _ExtraIncomeTabState();
}

class _ExtraIncomeTabState extends State<ExtraIncomeTab> {
  static const _presets = [
    (id: 'smart', label: 'Smart CFP'),
    (id: '50_30_20', label: '50 / 30 / 20'),
    (id: 'save_all', label: 'Save All'),
    (id: 'bucket_first', label: 'Bucket First'),
  ];

  int _selectedPresetIndex = 0;
  int _selectedAmountIndex = 1;

  List<int> _presetAmountsMinor(String ccy, CurrencySpec spec) {
    final factor = math.pow(10, spec.minorUnit).toInt();
    final highDenom =
        ccy == 'INR' || ccy == 'JPY' || ccy == 'IDR' || ccy == 'KRW';
    final majors = highDenom
        ? const [5000, 10000, 25000, 50000]
        : const [250, 500, 1000, 2500];
    return [for (final m in majors) m * factor];
  }

  WindfallSplit _computeSimSplit(int simMinor) {
    final snap = widget.data.snapshot;
    final gap = math.max<int>(0, -snap.freeToSpendMinor);
    final bp = snap.bucketPlan;
    return switch (_presets[_selectedPresetIndex].id) {
      '50_30_20' => MonthlyTrackerEngine.presetSplit(simMinor, 50, 30),
      'save_all' => MonthlyTrackerEngine.presetSplit(simMinor, 100, 0),
      'bucket_first' => MonthlyTrackerEngine.presetSplit(simMinor, 30, 70),
      _ => MonthlyTrackerEngine.suggestWindfallSplit(
        amountMinor: simMinor,
        monthGapMinor: gap,
        urgentShortfallMinor: bp.urgentShortfallMinor,
        essentialUnfundedMinor: bp.essentialUnfundedMinor,
        currencyCode: snap.currencyCode,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final snap = widget.data.snapshot;
    final ccy = snap.currencyCode;
    final spec = CurrencyCatalog.requireByCode(ccy);

    String fmt(int m) => Money(
      amountMinor: m,
      currencyCode: ccy,
    ).format(spec: spec, mask: widget.masked);

    final simAmounts = _presetAmountsMinor(ccy, spec);
    final simMinor =
        simAmounts[_selectedAmountIndex.clamp(0, simAmounts.length - 1)];
    final simSplit = _computeSimSplit(simMinor);
    final simDenom = math.max<int>(1, simSplit.totalMinor);
    final simSavePct = simSplit.toSavingsMinor * 100.0 / simDenom;
    final simBucketPct = simSplit.toBucketMinor * 100.0 / simDenom;
    final simSpendPct = simSplit.toSpendMinor * 100.0 / simDenom;

    final prevInc = snap.previousIncomeMinor;
    final incDeltaPct = prevInc > 0 && snap.incomeMinor > 0
        ? ((snap.incomeMinor - prevInc) / prevInc) * 100.0
        : null;

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: SingleChildScrollView(
        key: const Key('monthly_tab_income'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EnterprisePageContainer.responsivePadding(context, bottom: 96),
        child: EnterprisePageContainer(
          maxWidth: AppBreakpoints.maxContentWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Income This Month Card
              StaggeredFadeSlide(
                index: 0,
                child: FintechAccentCard(
                  accent: ModernDialogAccent.success,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Income this month',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (incDeltaPct != null && !widget.masked)
                                FintechStatusPill(
                                  icon: incDeltaPct >= 0
                                      ? Icons.arrow_upward_rounded
                                      : Icons.arrow_downward_rounded,
                                  label:
                                      '${incDeltaPct >= 0 ? '+' : ''}${incDeltaPct.round()}% vs last mo',
                                  foreground: incDeltaPct >= 0
                                      ? cfo.income
                                      : cfo.warning,
                                  background: incDeltaPct >= 0
                                      ? cfo.incomeContainer
                                      : cfo.warningContainer,
                                ),
                              FintechStatusPill(
                                label:
                                    '${widget.data.incomeTransactions.length} entries',
                                foreground: cfo.income,
                                background: cfo.incomeContainer,
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: AnimatedMoneyText(
                          money: Money(
                            amountMinor: snap.incomeMinor,
                            currencyCode: ccy,
                          ),
                          masked: widget.masked,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: cfo.income,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ),
                      if (widget.data.incomeTransactions.isNotEmpty) ...[
                        const Divider(height: 22),
                        for (
                          var i = 0;
                          i < widget.data.incomeTransactions.length;
                          i++
                        ) ...[
                          if (i > 0) Divider(height: 14, color: cfo.divider),
                          () {
                            final tx = widget.data.incomeTransactions[i];
                            final dt = DateTime.tryParse(
                              tx.transactionDateUtc,
                            )?.toLocal();
                            final dateLabel = dt != null
                                ? DateFormat('d MMM').format(dt)
                                : '';
                            return Row(
                              children: [
                                IconSquircle(
                                  icon: Icons.south_west_rounded,
                                  iconColor: cfo.income,
                                  backgroundColor: cfo.incomeContainer,
                                  size: 30,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        (tx.description ?? '').trim().isNotEmpty
                                            ? tx.description!.trim()
                                            : (tx.categoryName ?? 'Income'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      Text(
                                        '$dateLabel${tx.destinationAccountName != null ? ' · ${tx.destinationAccountName}' : ''}',
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
                                const SizedBox(width: 8),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 112,
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: MoneyText(
                                      money: tx.baseAmount,
                                      masked: widget.masked,
                                      showPlusSign: true,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            color: cfo.income,
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }(),
                        ],
                      ] else ...[
                        const SizedBox(height: 6),
                        Text(
                          'No salary or extra income posted in this month yet.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: cfo.subtleText),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              if (widget.canPost) ...[
                FilledButton.icon(
                  key: const Key('extra_income_add_btn'),
                  onPressed: widget.onAddExtraIncome,
                  icon: const Icon(Icons.add_card_rounded),
                  label: const Text('Add Extra Income & Split'),
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              // 2. Interactive Live Windfall Simulator
              StaggeredFadeSlide(
                index: 1,
                child: PressScaleCard(
                  key: const Key('windfall_simulator_card'),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'What-If Windfall Simulator',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          FintechStatusPill(
                            icon: Icons.auto_awesome_rounded,
                            label: 'Live preview',
                            foreground: scheme.primary,
                            background: scheme.primaryContainer,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (var i = 0; i < simAmounts.length; i++) ...[
                              if (i > 0) const SizedBox(width: 6),
                              ChoiceChip(
                                label: Text(fmt(simAmounts[i])),
                                selected: _selectedAmountIndex == i,
                                onSelected: (_) {
                                  HapticFeedback.selectionClick();
                                  setState(() => _selectedAmountIndex = i);
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (var i = 0; i < _presets.length; i++) ...[
                              if (i > 0) const SizedBox(width: 6),
                              ChoiceChip(
                                label: Text(_presets[i].label),
                                selected: _selectedPresetIndex == i,
                                onSelected: (_) {
                                  HapticFeedback.selectionClick();
                                  setState(() => _selectedPresetIndex = i);
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      SegmentedMoneyBar(
                        height: 9,
                        masked: widget.masked,
                        segments: [
                          if (simSavePct > 0.3)
                            MoneyBarSegment(
                              label: 'Savings',
                              percent: simSavePct,
                              color: cfo.income,
                            ),
                          if (simBucketPct > 0.3)
                            MoneyBarSegment(
                              label: 'Bucket',
                              percent: simBucketPct,
                              color: scheme.primary,
                            ),
                          if (simSpendPct > 0.3)
                            MoneyBarSegment(
                              label: 'Month',
                              percent: simSpendPct,
                              color: cfo.warning,
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
                                child: _SimCell(
                                  label: 'Savings Goal',
                                  value: fmt(simSplit.toSavingsMinor),
                                  color: cfo.income,
                                ),
                              ),
                              VerticalDivider(
                                width: 12,
                                thickness: 1,
                                color: cfo.divider,
                              ),
                              Expanded(
                                child: _SimCell(
                                  label: 'Bucket List',
                                  value: fmt(simSplit.toBucketMinor),
                                  color: scheme.primary,
                                ),
                              ),
                              VerticalDivider(
                                width: 12,
                                thickness: 1,
                                color: cfo.divider,
                              ),
                              Expanded(
                                child: _SimCell(
                                  label: 'Month Cap',
                                  value: fmt(simSplit.toSpendMinor),
                                  color: cfo.warning,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.masked
                            ? 'Disable balance masking to preview simulated amounts.'
                            : simSplit.rationale,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cfo.subtleText,
                          height: 1.35,
                        ),
                      ),
                      if (widget.canPost) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          key: const Key('windfall_sim_apply_btn'),
                          onPressed: () {
                            if (widget.onQuickSplitExtraIncome != null) {
                              widget.onQuickSplitExtraIncome!(
                                amountMinor: simMinor,
                                preset: _presets[_selectedPresetIndex].id,
                              );
                            } else {
                              widget.onAddExtraIncome();
                            }
                          },
                          icon: const Icon(Icons.bolt_rounded, size: 18),
                          label: const Text('Apply Simulated Split'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // 3. 2x2 Quick Income Source Launchpad
              if (widget.canPost) ...[
                StaggeredFadeSlide(
                  index: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionHeader(
                        title: 'Quick Income Launchpad',
                        subtitle: 'Log windfalls cleanly by source',
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final twoCols = constraints.maxWidth >= 290;
                          final w = twoCols
                              ? (constraints.maxWidth - 8) / 2
                              : constraints.maxWidth;
                          final sources = [
                            (
                              source: 'Bonus',
                              title: 'Bonus / Incentive',
                              sub: 'Work payout',
                              icon: Icons.workspace_premium_outlined,
                              color: scheme.primary,
                            ),
                            (
                              source: 'Freelance',
                              title: 'Freelance / Gig',
                              sub: 'Client invoice',
                              icon: Icons.laptop_mac_rounded,
                              color: cfo.income,
                            ),
                            (
                              source: 'Cashback',
                              title: 'Cashback / Reward',
                              sub: 'Card / UPI back',
                              icon: Icons.redeem_rounded,
                              color: cfo.warning,
                            ),
                            (
                              source: 'Gift',
                              title: 'Gift / Dividend',
                              sub: 'Family / yield',
                              icon: Icons.card_giftcard_rounded,
                              color: cfo.accentCyan,
                            ),
                          ];
                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final s in sources)
                                SizedBox(
                                  width: w,
                                  child: PressScaleCard(
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      if (widget.onQuickSplitExtraIncome !=
                                          null) {
                                        widget.onQuickSplitExtraIncome!(
                                          sourceLabel: s.source,
                                        );
                                      } else {
                                        widget.onAddExtraIncome();
                                      }
                                    },
                                    padding: const EdgeInsets.all(10),
                                    child: Row(
                                      children: [
                                        IconSquircle(
                                          icon: s.icon,
                                          iconColor: s.color,
                                          backgroundColor: s.color.withValues(
                                            alpha: 0.14,
                                          ),
                                          size: 32,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                s.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                              ),
                                              Text(
                                                s.sub,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall
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
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              // 4. Windfall Split History
              StaggeredFadeSlide(
                index: 3,
                child: PressScaleCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Extra-Income Split History',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (widget.data.windfalls.isEmpty)
                        Text(
                          'Any bonus, freelance payout, cashback or gift you split with Extra Income appears here with exact Savings / Bucket / Month allocations.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: cfo.subtleText, height: 1.35),
                        )
                      else
                        for (
                          var i = 0;
                          i < widget.data.windfalls.length;
                          i++
                        ) ...[
                          if (i > 0) Divider(height: 18, color: cfo.divider),
                          () {
                            final w = widget.data.windfalls[i];
                            final denom = math.max<int>(1, w.amountMinor);
                            final savePct = w.toSavingsMinor * 100.0 / denom;
                            final bucketPct = w.toBucketMinor * 100.0 / denom;
                            final spendPct = w.toSpendMinor * 100.0 / denom;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    IconSquircle(
                                      icon: Icons.call_split_rounded,
                                      iconColor: cfo.income,
                                      backgroundColor: cfo.incomeContainer,
                                      size: 28,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        w.sourceLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 118,
                                      ),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerRight,
                                        child: MoneyText(
                                          money: Money(
                                            amountMinor: w.amountMinor,
                                            currencyCode: ccy,
                                          ),
                                          masked: widget.masked,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                color: cfo.income,
                                                fontWeight: FontWeight.w900,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                SegmentedMoneyBar(
                                  height: 8,
                                  masked: widget.masked,
                                  segments: [
                                    if (savePct > 0.3)
                                      MoneyBarSegment(
                                        label: 'Savings',
                                        percent: savePct,
                                        color: cfo.income,
                                      ),
                                    if (bucketPct > 0.3)
                                      MoneyBarSegment(
                                        label: 'Bucket',
                                        percent: bucketPct,
                                        color: scheme.primary,
                                      ),
                                    if (spendPct > 0.3)
                                      MoneyBarSegment(
                                        label: 'Month',
                                        percent: spendPct,
                                        color: cfo.warning,
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.masked
                                      ? 'Split recorded silently'
                                      : 'Saved ${fmt(w.toSavingsMinor)} · Bucket ${fmt(w.toBucketMinor)} · Month ${fmt(w.toSpendMinor)}',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(color: cfo.subtleText),
                                ),
                              ],
                            );
                          }(),
                        ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SimCell extends StatelessWidget {
  const _SimCell({
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
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: cfo.subtleText, fontSize: 10),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
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
