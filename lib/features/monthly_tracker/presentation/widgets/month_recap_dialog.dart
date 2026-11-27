import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/financial_engine/currency.dart';
import '../../../../core/financial_engine/money.dart';
import '../../../../core/financial_engine/monthly_tracker_engine.dart';
import '../../../../shared/widgets/fintech_widgets.dart';
import '../../../../shared/widgets/modern_dialogs.dart';

/// Monthly CFO Scorecard ("Month Wrapped") modal summarizing savings efficiency,
/// spend pace, zero-spend discipline, and bucket-list execution with 1-tap copy.
class MonthRecapDialog extends StatelessWidget {
  const MonthRecapDialog({
    required this.snapshot,
    required this.boughtBucketCount,
    required this.masked,
    super.key,
  });

  final MonthlyTrackerSnapshot snapshot;
  final int boughtBucketCount;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final scorecard = MonthlyTrackerEngine.buildScorecard(
      snapshot,
      boughtBucketCount: boughtBucketCount,
    );
    final ccy = snapshot.currencyCode;
    final spec = CurrencyCatalog.byCode(ccy);

    String fmt(int minor) => Money(
      amountMinor: minor,
      currencyCode: ccy,
    ).format(spec: spec, mask: masked);

    final (
      ModernDialogAccent accent,
      Color scoreColor,
    ) = switch (scorecard.grade) {
      'A+' || 'A' => (ModernDialogAccent.success, cfo.income),
      'B' => (ModernDialogAccent.brand, scheme.primary),
      'C' => (ModernDialogAccent.warning, cfo.warning),
      _ => (ModernDialogAccent.danger, cfo.expense),
    };

    return ModernDialogShell(
      title: 'Monthly CFO Scorecard',
      subtitle:
          '${MonthlyTrackerEngine.monthKey(snapshot.year, snapshot.month)} · Score & Highlights',
      icon: Icons.auto_awesome_rounded,
      accent: accent,
      confirmLabel: 'Copy Recap',
      confirmKey: const Key('monthly_recap_copy_btn'),
      cancelLabel: 'Close',
      onConfirm: () async {
        HapticFeedback.selectionClick();
        final text = masked
            ? 'Pocket CFO Recap (${MonthlyTrackerEngine.monthKey(snapshot.year, snapshot.month)}): Balances hidden.'
            : scorecard.shareSummary;
        await Clipboard.setData(ClipboardData(text: text));
        if (context.mounted) {
          showFintechToast(
            context,
            'Monthly scorecard copied to clipboard.',
            tone: FintechToastTone.success,
          );
          Navigator.of(context).pop();
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: RadialScoreGauge(
              score: masked ? 0 : scorecard.score,
              label: masked ? 'HIDDEN' : 'GRADE ${scorecard.grade}',
              activeColor: scoreColor,
              secondaryColor: cfo.accentCyan,
              size: 98,
              strokeWidth: 9,
              masked: masked,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            scorecard.headline,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: cfo.subtleText,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cfo.surfaceTonal,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: cfo.divider),
            ),
            child: Column(
              children: [
                _ScorePillarBar(
                  label: 'Savings Velocity',
                  points: scorecard.savingsPoints,
                  maxPoints: 40,
                  color: cfo.income,
                  masked: masked,
                ),
                const SizedBox(height: 8),
                _ScorePillarBar(
                  label: 'Monthly Pace Control',
                  points: scorecard.pacePoints,
                  maxPoints: 30,
                  color: scheme.primary,
                  masked: masked,
                ),
                const SizedBox(height: 8),
                _ScorePillarBar(
                  label: 'Zero-Spend Discipline',
                  points: scorecard.disciplinePoints,
                  maxPoints: 15,
                  color: cfo.accentCyan,
                  masked: masked,
                ),
                const SizedBox(height: 8),
                _ScorePillarBar(
                  label: 'Bucket Plan Health',
                  points: scorecard.bucketPoints,
                  maxPoints: 15,
                  color: cfo.warning,
                  masked: masked,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoCols = constraints.maxWidth >= 280;
              final tileWidth = twoCols
                  ? (constraints.maxWidth - 8) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: tileWidth,
                    child: _HighlightBentoTile(
                      icon: Icons.savings_outlined,
                      label: 'Savings Rate',
                      value: masked
                          ? '••%'
                          : (snapshot.incomeMinor > 0
                                ? '${snapshot.savingsRatePct.toStringAsFixed(0)}%'
                                : 'Planned'),
                      color: cfo.income,
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _HighlightBentoTile(
                      icon: Icons.local_fire_department_rounded,
                      label: 'Zero-Spend',
                      value: snapshot.noSpendStreak > 0
                          ? '${snapshot.noSpendStreak}d streak'
                          : '${snapshot.noSpendDays} days',
                      color: cfo.accentCyan,
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _HighlightBentoTile(
                      icon: Icons.shopping_bag_outlined,
                      label: 'Bucket Wins',
                      value: '$boughtBucketCount bought',
                      color: scheme.primary,
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _HighlightBentoTile(
                      icon: Icons.today_rounded,
                      label: 'Daily Safe Pace',
                      value: fmt(snapshot.safeDailySpendMinor),
                      color: cfo.warning,
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

class _ScorePillarBar extends StatelessWidget {
  const _ScorePillarBar({
    required this.label,
    required this.points,
    required this.maxPoints,
    required this.color,
    required this.masked,
  });

  final String label;
  final int points;
  final int maxPoints;
  final Color color;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final ratio = masked ? 0.0 : (points / maxPoints).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              masked ? '•• / $maxPoints' : '$points / $maxPoints',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        AnimatedProgressBar(value: ratio, color: color, height: 6),
      ],
    );
  }
}

class _HighlightBentoTile extends StatelessWidget {
  const _HighlightBentoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cfo.surfaceTonal,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: cfo.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13.5, color: color),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: cfo.subtleText),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
