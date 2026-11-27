import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/financial_engine/currency.dart';
import '../../../../core/financial_engine/money.dart';
import '../../../../core/financial_engine/monthly_tracker_engine.dart';
import '../../../../shared/widgets/enterprise_layout.dart';
import '../../../../shared/widgets/fintech_widgets.dart';
import '../../../../shared/widgets/flagship_visuals.dart';
import '../../../../shared/widgets/modern_dialogs.dart';
import '../../../../shared/widgets/month_spend_heatmap.dart';
import '../../../../shared/widgets/trendy_fintech_gauges.dart';
import '../../data/monthly_tracker_service.dart';

/// Tab 0 of Monthly Tracker: Net Savings Hero, Spend Pace Line Chart, Daily Spend
/// Heatmap, Category Deltas, Upcoming Commitments, and Smart Insights.
class MonthOverviewTab extends StatelessWidget {
  const MonthOverviewTab({
    required this.data,
    required this.masked,
    required this.onRefresh,
    required this.onPlanPurchase,
    required this.onAddExtraIncome,
    this.onOpenRecap,
    this.onCreditSalary,
    super.key,
  });

  final MonthlyTrackerViewData data;
  final bool masked;
  final Future<void> Function() onRefresh;
  final VoidCallback onPlanPurchase;
  final VoidCallback onAddExtraIncome;
  final VoidCallback? onOpenRecap;
  final VoidCallback? onCreditSalary;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final snap = data.snapshot;
    final ccy = snap.currencyCode;
    final spec = CurrencyCatalog.byCode(ccy);

    final heroTone = switch (snap.healthLabel) {
      'Over Plan' => SignatureHeroTone.crimson,
      'Watch' => SignatureHeroTone.amber,
      _ => SignatureHeroTone.emerald,
    };
    final (Color pillFg, IconData pillIcon) = switch (snap.healthLabel) {
      'Over Plan' => (const Color(0xFFFDA4AF), Icons.warning_amber_rounded),
      'Watch' => (const Color(0xFFFDE68A), Icons.visibility_outlined),
      _ => (const Color(0xFF6EE7B7), Icons.verified_rounded),
    };

    final denom = math.max<int>(1, snap.effectiveIncomeMinor);
    final needsPct = snap.needsSpentMinor * 100.0 / denom;
    final wantsPct = snap.wantsSpentMinor * 100.0 / denom;
    final billsPct = snap.committedRemainingMinor * 100.0 / denom;
    final bucketPct = snap.bucketReserveMinor * 100.0 / denom;
    final freePct = math.max<int>(0, snap.freeToSpendMinor) * 100.0 / denom;

    final segments = <MoneyBarSegment>[
      if (needsPct > 0.3)
        MoneyBarSegment(
          label: 'Needs',
          percent: needsPct,
          color: const Color(0xFF818CF8),
        ),
      if (wantsPct > 0.3)
        MoneyBarSegment(
          label: 'Wants',
          percent: wantsPct,
          color: const Color(0xFFFBBF24),
        ),
      if (billsPct > 0.3)
        MoneyBarSegment(
          label: 'Bills ahead',
          percent: billsPct,
          color: const Color(0xFFFB7185),
        ),
      if (bucketPct > 0.3)
        MoneyBarSegment(
          label: 'Bucket',
          percent: bucketPct,
          color: const Color(0xFF38BDF8),
        ),
      if (freePct > 0.3)
        MoneyBarSegment(
          label: 'Free',
          percent: freePct,
          color: const Color(0xFF34D399),
        ),
    ];

    String fmt(int minor, {bool plus = false}) => Money(
      amountMinor: minor,
      currencyCode: ccy,
    ).format(spec: spec, showPlusSign: plus, mask: masked);

    final savingsScore = snap.incomeMinor > 0
        ? snap.savingsRatePct.round().clamp(0, 100)
        : 0;
    final savedColor = snap.savedMinor >= 0
        ? const Color(0xFF6EE7B7)
        : const Color(0xFFFDA4AF);

    final elapsedRatio = (snap.daysElapsed / math.max<int>(1, snap.daysInMonth))
        .clamp(0.0, 1.0);
    final freeColor = snap.freeToSpendMinor >= 0
        ? Colors.white
        : const Color(0xFFFDA4AF);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: SingleChildScrollView(
        key: const Key('monthly_tab_overview'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EnterprisePageContainer.responsivePadding(context, bottom: 96),
        child: EnterprisePageContainer(
          maxWidth: AppBreakpoints.maxContentWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Month Proactive Safe-to-Spend & Cash-Flow Obsidian Signature Hero
              StaggeredFadeSlide(
                index: 0,
                child: FintechSignatureHero(
                  key: const Key('monthly_hero_card'),
                  tone: heroTone,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  bottomBar: HeroGlassActionBar(
                    items: [
                      FintechFlatActionItem(
                        key: const Key('monthly_cta_extra_income'),
                        icon: Icons.savings_outlined,
                        label: 'Extra Income',
                        color: const Color(0xFF6EE7B7),
                        onTap: onAddExtraIncome,
                      ),
                      FintechFlatActionItem(
                        key: const Key('monthly_cta_plan_purchase'),
                        icon: Icons.checklist_rounded,
                        label: 'Plan Buy',
                        color: const Color(0xFFC7D2FE),
                        onTap: onPlanPurchase,
                      ),
                      if (onOpenRecap != null)
                        FintechFlatActionItem(
                          key: const Key('monthly_hero_recap_btn'),
                          icon: Icons.auto_awesome_rounded,
                          label: 'Recap',
                          color: const Color(0xFF7DD3FC),
                          onTap: onOpenRecap!,
                        ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          RadialScoreGauge(
                            score: masked ? 0 : savingsScore,
                            label: 'SAVED',
                            activeColor: savedColor,
                            secondaryColor: const Color(0xFF38BDF8),
                            trackColor: Colors.white.withValues(alpha: 0.14),
                            textColor: Colors.white,
                            subtitleColor: Colors.white.withValues(alpha: 0.68),
                            size: 86,
                            strokeWidth: 7.5,
                            masked: masked,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      'Free to spend',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: Colors.white.withValues(
                                              alpha: 0.72,
                                            ),
                                          ),
                                    ),
                                    HeroGlassPill(
                                      icon: pillIcon,
                                      label: snap.healthLabel,
                                      foreground: pillFg,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: AnimatedMoneyText(
                                    money: Money(
                                      amountMinor: snap.freeToSpendMinor,
                                      currencyCode: ccy,
                                    ),
                                    masked: masked,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium
                                        ?.copyWith(
                                          color: freeColor,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: -0.6,
                                        ),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Saved this month: ${fmt(snap.savedMinor, plus: snap.savedMinor > 0)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: savedColor,
                                        fontWeight: FontWeight.w700,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                ),
                                if (snap.incomeMinor == 0 &&
                                    snap.effectiveIncomeMinor > 0) ...[
                                  const SizedBox(height: 7),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.10,
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        AppSpacing.radiusSm,
                                      ),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.18,
                                        ),
                                      ),
                                    ),
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.account_balance_outlined,
                                              size: 13,
                                              color: Color(0xFF93C5FD),
                                            ),
                                            const SizedBox(width: 5),
                                            Flexible(
                                              child: Text(
                                                'Using planned salary · Not credited to bank yet',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      color: Colors.white
                                                          .withValues(
                                                            alpha: 0.90,
                                                          ),
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 10.5,
                                                    ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (onCreditSalary != null)
                                          FilledButton.icon(
                                            key: const Key(
                                              'monthly_credit_salary_btn',
                                            ),
                                            style: FilledButton.styleFrom(
                                              backgroundColor: Colors.white,
                                              foregroundColor: const Color(
                                                0xFF0C1226,
                                              ),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              minimumSize: const Size(0, 32),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4,
                                                  ),
                                            ),
                                            onPressed: onCreditSalary,
                                            icon: const Icon(
                                              Icons.payments_outlined,
                                              size: 14,
                                            ),
                                            label: const Text(
                                              'Credit Salary',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Month Cycle Runway Frosted Glass Bar
                      HeroGlassWell(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.today_rounded,
                                  size: 14,
                                  color: Color(0xFF7DD3FC),
                                ),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    snap.daysLeft > 0
                                        ? 'Safe pace ${fmt(snap.safeDailySpendMinor)}/day'
                                        : 'Month complete',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      snap.daysLeft > 0
                                          ? 'Day ${snap.daysElapsed} of ${snap.daysInMonth} · ${snap.daysLeft}d left'
                                          : '${snap.daysInMonth} days closed',
                                      maxLines: 1,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: Colors.white.withValues(
                                              alpha: 0.72,
                                            ),
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
                            const SizedBox(height: 6),
                            AnimatedProgressBar(
                              value: elapsedRatio,
                              color: const Color(0xFF38BDF8),
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.14,
                              ),
                              height: 5,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Unified 3-Column Frosted Glass Bento Strip
                      HeroGlassWell(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 9,
                        ),
                        child: IntrinsicHeight(
                          child: Row(
                            children: [
                              Expanded(
                                child: _MiniTile(
                                  label: 'Income',
                                  minor: snap.incomeMinor,
                                  ccy: ccy,
                                  masked: masked,
                                  color: const Color(0xFF6EE7B7),
                                  onDark: true,
                                ),
                              ),
                              VerticalDivider(
                                width: 12,
                                thickness: 1,
                                color: Colors.white.withValues(alpha: 0.14),
                              ),
                              Expanded(
                                child: _MiniTile(
                                  label: 'Spent',
                                  minor: snap.spentMinor,
                                  ccy: ccy,
                                  masked: masked,
                                  color: const Color(0xFFFDA4AF),
                                  onDark: true,
                                ),
                              ),
                              VerticalDivider(
                                width: 12,
                                thickness: 1,
                                color: Colors.white.withValues(alpha: 0.14),
                              ),
                              Expanded(
                                child: _MiniTile(
                                  label: 'Bills ahead',
                                  minor: snap.committedRemainingMinor,
                                  ccy: ccy,
                                  masked: masked,
                                  color: const Color(0xFFFDE68A),
                                  onDark: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (segments.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        SegmentedMoneyBar(
                          segments: segments,
                          masked: masked,
                          trackColor: Colors.white.withValues(alpha: 0.14),
                          labelColor: Colors.white.withValues(alpha: 0.78),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // 2. Interactive Touch-Scrubbing Spend Pace Line Chart
              StaggeredFadeSlide(
                index: 1,
                child: PressScaleCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: _PaceChartCardContent(
                    snapshot: snap,
                    ccy: ccy,
                    masked: masked,
                    fmt: fmt,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // 3. Calendar Spend Heatmap
              StaggeredFadeSlide(
                index: 2,
                child: PressScaleCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: MonthSpendHeatmap(
                    key: const Key('monthly_heatmap'),
                    year: snap.year,
                    month: snap.month,
                    dailySpendMinor: snap.dailySpendMinor,
                    daysElapsed: snap.daysElapsed,
                    isCurrentMonth: snap.isCurrentMonth,
                    todayDay: snap.isCurrentMonth ? snap.daysElapsed : 0,
                    currencyCode: ccy,
                    masked: masked,
                    noSpendStreak: snap.noSpendStreak,
                    noSpendDays: snap.noSpendDays,
                    safeDailySpendMinor: snap.safeDailySpendMinor,
                    biggestDayNumber: snap.biggestDayNumber,
                    biggestDayMinor: snap.biggestDayMinor,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // 4. Top Categories with MoM Delta
              if (snap.topCategories.isNotEmpty) ...[
                StaggeredFadeSlide(
                  index: 3,
                  child: PressScaleCard(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Top Categories This Month',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 10),
                        for (var i = 0; i < snap.topCategories.length; i++) ...[
                          if (i > 0) Divider(height: 14, color: cfo.divider),
                          _CategoryStatRow(
                            stat: snap.topCategories[i],
                            ccy: ccy,
                            masked: masked,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              // 5. Upcoming Commitments This Month
              StaggeredFadeSlide(
                index: 4,
                child: PressScaleCard(
                  key: const Key('monthly_upcoming_card'),
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
                            'Upcoming Bills & EMIs',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            fmt(snap.committedRemainingMinor),
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: cfo.warning,
                                  fontWeight: FontWeight.w800,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (data.upcomingCommitments.isEmpty)
                        Text(
                          'No recurring bills or loan EMIs remaining this month.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: cfo.subtleText),
                        )
                      else
                        for (
                          var i = 0;
                          i < data.upcomingCommitments.length;
                          i++
                        ) ...[
                          if (i > 0) Divider(height: 14, color: cfo.divider),
                          _UpcomingRow(
                            item: data.upcomingCommitments[i],
                            ccy: ccy,
                            masked: masked,
                          ),
                        ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // 6. Smart Month Insights
              StaggeredFadeSlide(
                index: 5,
                child: PressScaleCard(
                  key: const Key('monthly_insights_card'),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Month Insights',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (snap.insights.isEmpty)
                        Text(
                          'Log transactions or add planned items to unlock tailored monthly alerts.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: cfo.subtleText),
                        )
                      else
                        for (var i = 0; i < snap.insights.length; i++) ...[
                          if (i > 0) const SizedBox(height: 10),
                          _InsightRow(
                            insight: snap.insights[i],
                            masked: masked,
                          ),
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

class _MiniTile extends StatelessWidget {
  const _MiniTile({
    required this.label,
    required this.minor,
    required this.ccy,
    required this.masked,
    required this.color,
    this.onDark = false,
  });

  final String label;
  final int minor;
  final String ccy;
  final bool masked;
  final Color color;
  final bool onDark;

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
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: onDark
                      ? Colors.white.withValues(alpha: 0.70)
                      : cfo.subtleText,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
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

class _PaceChartCardContent extends StatefulWidget {
  const _PaceChartCardContent({
    required this.snapshot,
    required this.ccy,
    required this.masked,
    required this.fmt,
  });

  final MonthlyTrackerSnapshot snapshot;
  final String ccy;
  final bool masked;
  final String Function(int minor, {bool plus}) fmt;

  @override
  State<_PaceChartCardContent> createState() => _PaceChartCardContentState();
}

class _PaceChartCardContentState extends State<_PaceChartCardContent> {
  int? _touchedDayIndex;

  @override
  void didUpdateWidget(covariant _PaceChartCardContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot.year != widget.snapshot.year ||
        oldWidget.snapshot.month != widget.snapshot.month) {
      _touchedDayIndex = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final snapshot = widget.snapshot;
    final days = snapshot.daysInMonth;
    final elapsed = snapshot.daysElapsed;
    final idealEnd = math.max<double>(
      1.0,
      math
          .max<int>(
            snapshot.spentMinor,
            snapshot.effectiveIncomeMinor - snapshot.savingsTargetMinor,
          )
          .toDouble(),
    );

    final actualSpots = <FlSpot>[const FlSpot(0, 0)];
    final cumByDay = <int>[0];
    var cum = 0;
    for (var i = 0; i < elapsed && i < snapshot.dailySpendMinor.length; i++) {
      cum += snapshot.dailySpendMinor[i];
      cumByDay.add(cum);
      actualSpots.add(FlSpot((i + 1).toDouble(), cum.toDouble()));
    }
    final idealSpots = [const FlSpot(0, 0), FlSpot(days.toDouble(), idealEnd)];

    final delta = snapshot.spendDeltaVsLastMonthPct;
    final isUp = (delta ?? 0) > 0;
    final touchedDay =
        _touchedDayIndex != null &&
            _touchedDayIndex! >= 0 &&
            _touchedDayIndex! < cumByDay.length
        ? _touchedDayIndex!
        : null;
    final idealAtTouched = touchedDay != null
        ? ((idealEnd * touchedDay) / math.max<int>(1, days)).round()
        : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              touchedDay != null && !widget.masked
                  ? 'Day $touchedDay spend · ${widget.fmt(cumByDay[touchedDay])}'
                  : 'On pace to spend ${widget.fmt(snapshot.projectedMonthEndSpendMinor)} by month end',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (touchedDay != null && !widget.masked) ...[
              const SizedBox(height: 6),
              FintechStatusPill(
                icon: Icons.timeline_rounded,
                label: 'Ideal pace ${widget.fmt(idealAtTouched)}',
                foreground: cumByDay[touchedDay] <= idealAtTouched
                    ? cfo.income
                    : cfo.warning,
                background: cumByDay[touchedDay] <= idealAtTouched
                    ? cfo.incomeContainer
                    : cfo.warningContainer,
              ),
            ] else if (delta != null && !widget.masked) ...[
              const SizedBox(height: 6),
              FintechStatusPill(
                icon: isUp
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                label: '${isUp ? '+' : ''}${delta.round()}% vs last mo',
                foreground: isUp ? cfo.expense : cfo.income,
                background: isUp ? cfo.expenseContainer : cfo.incomeContainer,
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 4,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _PaceLegendItem(color: scheme.primary, label: 'Actual'),
                _PaceLegendItem(
                  color: cfo.subtleText.withValues(alpha: 0.55),
                  label: 'Ideal pace',
                  dashed: true,
                ),
              ],
            ),
            Text(
              'Safe cap ${widget.fmt(idealEnd.round())}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: cfo.subtleText,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        RepaintBoundary(
          child: SizedBox(
            height: 118,
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  enabled: !widget.masked,
                  handleBuiltInTouches: true,
                  touchSpotThreshold: 22,
                  touchCallback: (event, response) {
                    if (!event.isInterestedForInteractions ||
                        response?.lineBarSpots == null ||
                        response!.lineBarSpots!.isEmpty) {
                      if (_touchedDayIndex != null) {
                        setState(() => _touchedDayIndex = null);
                      }
                      return;
                    }
                    final dayIdx = response.lineBarSpots!.first.x.round().clamp(
                      0,
                      cumByDay.length - 1,
                    );
                    if (_touchedDayIndex != dayIdx) {
                      HapticFeedback.selectionClick();
                      setState(() => _touchedDayIndex = dayIdx);
                    }
                  },
                  touchTooltipData: LineTouchTooltipData(
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    tooltipBorderRadius: BorderRadius.circular(8),
                    tooltipPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    getTooltipColor: (_) => scheme.inverseSurface,
                    getTooltipItems: (spots) {
                      return spots.map((s) {
                        if (s.barIndex != 1) return null;
                        final d = s.x.round();
                        return LineTooltipItem(
                          'Day $d · ${widget.fmt(s.y.round())}',
                          Theme.of(context).textTheme.labelSmall!.copyWith(
                            color: scheme.onInverseSurface,
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                minX: 0,
                maxX: days.toDouble(),
                minY: 0,
                maxY: math.max(idealEnd, cum.toDouble()) * 1.1 + 1,
                lineBarsData: [
                  LineChartBarData(
                    spots: idealSpots,
                    isCurved: false,
                    color: cfo.subtleText.withValues(alpha: 0.45),
                    barWidth: 2,
                    dashArray: const [5, 4],
                    dotData: const FlDotData(show: false),
                  ),
                  LineChartBarData(
                    spots: actualSpots,
                    isCurved: true,
                    color: scheme.primary,
                    barWidth: 3,
                    dotData: FlDotData(
                      show: true,
                      checkToShowDot: (spot, _) => spot.x.round() == elapsed,
                      getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                        radius: 4.5,
                        color: scheme.primary,
                        strokeWidth: 2.5,
                        strokeColor: scheme.surface,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          scheme.primary.withValues(alpha: 0.22),
                          scheme.primary.withValues(alpha: 0.02),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PaceLegendItem extends StatelessWidget {
  const _PaceLegendItem({
    required this.color,
    required this.label,
    this.dashed = false,
  });

  final Color color;
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: dashed ? 12 : 8,
          height: dashed ? 2 : 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: cfo.subtleText,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _CategoryStatRow extends StatelessWidget {
  const _CategoryStatRow({
    required this.stat,
    required this.ccy,
    required this.masked,
  });

  final MonthCategoryStat stat;
  final String ccy;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final d = stat.deltaPct;
    final up = (d ?? 0) > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    stat.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (d != null && !masked)
                    FintechStatusPill(
                      icon: up
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      label: '${up ? '+' : ''}${d.round()}%',
                      foreground: up ? cfo.expense : cfo.income,
                      background: up
                          ? cfo.expenseContainer
                          : cfo.incomeContainer,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 112),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: MoneyText(
                  money: Money(
                    amountMinor: stat.amountMinor,
                    currencyCode: ccy,
                  ),
                  masked: masked,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Expanded(
              child: AnimatedProgressBar(
                value: (stat.sharePct / 100.0).clamp(0.0, 1.0),
                color: stat.isEssential ? scheme.primary : cfo.warning,
                height: 6,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              masked ? '••%' : '${stat.sharePct.round()}%',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: cfo.subtleText,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({
    required this.item,
    required this.ccy,
    required this.masked,
  });

  final UpcomingCommitment item;
  final String ccy;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final dt = DateTime.tryParse(item.dueDateUtc)?.toLocal();
    final dateLabel = dt != null ? DateFormat('d MMM').format(dt) : 'Soon';
    final isEmi = item.kind == 'emi';
    final nowLocal = DateTime.now();
    final daysAway = dt != null
        ? DateTime(dt.year, dt.month, dt.day)
              .difference(DateTime(nowLocal.year, nowLocal.month, nowLocal.day))
              .inDays
        : null;
    final countdown = switch (daysAway) {
      null => null,
      <= 0 => 'Today',
      1 => 'Tomorrow',
      <= 7 => 'In ${daysAway}d',
      _ => null,
    };

    return Row(
      children: [
        IconSquircle(
          icon: isEmi ? Icons.account_balance_outlined : Icons.repeat_rounded,
          iconColor: isEmi ? cfo.expense : cfo.warning,
          backgroundColor: isEmi ? cfo.expenseContainer : cfo.warningContainer,
          size: 30,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${isEmi ? 'Loan EMI' : 'Recurring'} · Due $dateLabel',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: cfo.subtleText),
                  ),
                  if (countdown != null)
                    FintechStatusPill(
                      label: countdown,
                      foreground: (daysAway ?? 9) <= 2
                          ? cfo.expense
                          : cfo.warning,
                      background: (daysAway ?? 9) <= 2
                          ? cfo.expenseContainer
                          : cfo.warningContainer,
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 110),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: MoneyText(
              money: Money(amountMinor: item.amountMinor, currencyCode: ccy),
              masked: masked,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({required this.insight, required this.masked});

  final MonthInsight insight;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, Color fg, Color bg) = switch (insight.severity) {
      'positive' => (
        Icons.check_circle_outline_rounded,
        cfo.income,
        cfo.incomeContainer,
      ),
      'danger' => (
        Icons.warning_amber_rounded,
        cfo.expense,
        cfo.expenseContainer,
      ),
      'warning' => (
        Icons.lightbulb_outline_rounded,
        cfo.warning,
        cfo.warningContainer,
      ),
      _ => (
        Icons.info_outline_rounded,
        scheme.primary,
        scheme.primaryContainer,
      ),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconSquircle(icon: icon, iconColor: fg, backgroundColor: bg, size: 32),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                insight.title,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                masked
                    ? 'Disable balance masking to inspect exact monthly amounts.'
                    : insight.detail,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cfo.subtleText,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
