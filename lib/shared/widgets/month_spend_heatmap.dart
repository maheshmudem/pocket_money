import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_tokens.dart';
import '../../core/financial_engine/currency.dart';
import '../../core/financial_engine/money.dart';
import 'modern_dialogs.dart';

/// Calendar heatmap (`Mon–Sun`, 7-column grid) highlighting daily spending intensity,
/// zero-spend discipline days, today's outline, and interactive day tap details.
class MonthSpendHeatmap extends StatefulWidget {
  const MonthSpendHeatmap({
    required this.year,
    required this.month,
    required this.dailySpendMinor,
    required this.daysElapsed,
    required this.isCurrentMonth,
    required this.todayDay,
    required this.currencyCode,
    required this.masked,
    required this.noSpendStreak,
    required this.noSpendDays,
    this.safeDailySpendMinor = 0,
    this.biggestDayNumber = 0,
    this.biggestDayMinor = 0,
    super.key,
  });

  final int year;
  final int month;
  final List<int> dailySpendMinor;
  final int daysElapsed;
  final bool isCurrentMonth;
  final int todayDay;
  final String currencyCode;
  final bool masked;
  final int noSpendStreak;
  final int noSpendDays;
  final int safeDailySpendMinor;
  final int biggestDayNumber;
  final int biggestDayMinor;

  @override
  State<MonthSpendHeatmap> createState() => _MonthSpendHeatmapState();
}

class _MonthSpendHeatmapState extends State<MonthSpendHeatmap> {
  int? _selectedDay;

  @override
  void didUpdateWidget(covariant MonthSpendHeatmap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.year != widget.year || oldWidget.month != widget.month) {
      _selectedDay = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final spec = CurrencyCatalog.byCode(widget.currencyCode);
    final totalDays = widget.dailySpendMinor.length;
    final firstWeekdayOffset =
        DateTime.utc(widget.year, widget.month, 1).weekday - 1;
    final totalCells = firstWeekdayOffset + totalDays;
    final rowsCount = (totalCells + 6) ~/ 7;

    var maxSpend = 0;
    for (final s in widget.dailySpendMinor) {
      if (s > maxSpend) maxSpend = s;
    }

    Color cellBg(int day, int spend) {
      if (day > widget.daysElapsed) {
        return cfo.surfaceTonal.withValues(alpha: 0.45);
      }
      if (spend <= 0) {
        return cfo.incomeContainer.withValues(alpha: isDark ? 0.45 : 0.72);
      }
      if (maxSpend <= 0) {
        return scheme.primary.withValues(alpha: 0.25);
      }
      final ratio = spend / maxSpend;
      if (ratio >= 0.75) return scheme.primary.withValues(alpha: 0.92);
      if (ratio >= 0.45) return scheme.primary.withValues(alpha: 0.65);
      if (ratio >= 0.20) return scheme.primary.withValues(alpha: 0.40);
      return scheme.primary.withValues(alpha: 0.22);
    }

    Color cellTextColor(int day, int spend) {
      if (day > widget.daysElapsed) {
        return cfo.subtleText.withValues(alpha: 0.5);
      }
      if (spend <= 0) return cfo.income;
      if (maxSpend > 0 && spend / maxSpend >= 0.60) {
        return scheme.onPrimary;
      }
      return scheme.onSurface;
    }

    final selected = _selectedDay;
    String? selectedDetail;
    String? selectedPaceBadge;
    Color? selectedPaceFg;
    Color? selectedPaceBg;
    if (selected != null && selected >= 1 && selected <= totalDays) {
      final dt = DateTime.utc(widget.year, widget.month, selected);
      final dayLabel = DateFormat('EEE d MMM').format(dt);
      final spend = widget.dailySpendMinor[selected - 1];
      if (widget.masked) {
        selectedDetail = '$dayLabel · ••••••';
      } else if (spend == 0) {
        selectedDetail = selected <= widget.daysElapsed
            ? '$dayLabel · Zero-spend day'
            : '$dayLabel · Upcoming day';
        if (selected <= widget.daysElapsed) {
          selectedPaceBadge = 'Win';
          selectedPaceFg = cfo.income;
          selectedPaceBg = cfo.incomeContainer;
        }
      } else {
        final formatted = Money(
          amountMinor: spend,
          currencyCode: widget.currencyCode,
        ).format(spec: spec);
        selectedDetail = '$dayLabel · $formatted';
        if (widget.safeDailySpendMinor > 0) {
          final under = spend <= widget.safeDailySpendMinor;
          selectedPaceBadge = under ? 'Under pace' : 'Above pace';
          selectedPaceFg = under ? cfo.income : cfo.warning;
          selectedPaceBg = under ? cfo.incomeContainer : cfo.warningContainer;
        }
      }
    }

    final peakLabel = widget.biggestDayNumber > 0 && widget.biggestDayMinor > 0
        ? (widget.masked
              ? 'Day ${widget.biggestDayNumber}'
              : 'D${widget.biggestDayNumber} · ${Money(amountMinor: widget.biggestDayMinor, currencyCode: widget.currencyCode).format(spec: spec)}')
        : 'None yet';
    final fastMotion = AppMotion.resolve(context, AppMotion.fast);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Daily Spend Rhythm',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            FintechStatusPill(
              icon: Icons.local_fire_department_rounded,
              label: widget.noSpendStreak > 0
                  ? '${widget.noSpendStreak}-day zero streak'
                  : '${widget.noSpendDays} zero-spend days',
              foreground: cfo.income,
              background: cfo.incomeContainer,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: cfo.surfaceTonal,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: cfo.divider),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _HeatmapStat(
                    label: 'Zero Days',
                    value: '${widget.noSpendDays}',
                    color: cfo.income,
                  ),
                ),
                VerticalDivider(width: 12, thickness: 1, color: cfo.divider),
                Expanded(
                  child: _HeatmapStat(
                    label: 'Best Streak',
                    value: '${widget.noSpendStreak}d',
                    color: scheme.primary,
                  ),
                ),
                VerticalDivider(width: 12, thickness: 1, color: cfo.divider),
                Expanded(
                  child: _HeatmapStat(
                    label: 'Peak Spend',
                    value: peakLabel,
                    color: widget.biggestDayMinor > 0
                        ? cfo.warning
                        : cfo.subtleText,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: const [
            _WeekdayLabel('M'),
            _WeekdayLabel('T'),
            _WeekdayLabel('W'),
            _WeekdayLabel('T'),
            _WeekdayLabel('F'),
            _WeekdayLabel('S'),
            _WeekdayLabel('S'),
          ],
        ),
        const SizedBox(height: 6),
        for (var r = 0; r < rowsCount; r++) ...[
          if (r > 0) const SizedBox(height: 4),
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: c < 6 ? 4 : 0),
                    child: () {
                      final idx = r * 7 + c - firstWeekdayOffset;
                      if (idx < 0 || idx >= totalDays) {
                        return const SizedBox(height: 32);
                      }
                      final day = idx + 1;
                      final spend = widget.dailySpendMinor[idx];
                      final isToday =
                          widget.isCurrentMonth && day == widget.todayDay;
                      final isPicked = selected == day;
                      return AnimatedScale(
                        scale: isPicked ? 1.07 : 1.0,
                        duration: fastMotion,
                        curve: Curves.easeOutCubic,
                        child: Material(
                          color: cellBg(day, spend),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: isPicked
                                  ? scheme.onSurface
                                  : (isToday
                                        ? scheme.primary
                                        : Colors.transparent),
                              width: isPicked || isToday ? 1.5 : 0,
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _selectedDay = _selectedDay == day ? null : day;
                              });
                            },
                            child: SizedBox(
                              height: 32,
                              child: Center(
                                child: Text(
                                  '$day',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: cellTextColor(day, spend),
                                        fontWeight: isToday || isPicked
                                            ? FontWeight.w900
                                            : FontWeight.w700,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }(),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: fastMotion,
              child: selectedDetail != null
                  ? Wrap(
                      key: ValueKey(selectedDetail),
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: cfo.surfaceTonal,
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusFull,
                            ),
                            border: Border.all(color: cfo.divider),
                          ),
                          child: Text(
                            selectedDetail,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                          ),
                        ),
                        if (selectedPaceBadge != null &&
                            selectedPaceFg != null &&
                            selectedPaceBg != null)
                          FintechStatusPill(
                            label: selectedPaceBadge,
                            foreground: selectedPaceFg,
                            background: selectedPaceBg,
                          ),
                      ],
                    )
                  : Text(
                      key: const ValueKey('idle_hint'),
                      'Tap any day to inspect spend',
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: cfo.subtleText),
                    ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '0',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: cfo.subtleText),
                ),
                const SizedBox(width: 4),
                _LegendBox(
                  color: cfo.incomeContainer.withValues(
                    alpha: isDark ? 0.5 : 0.8,
                  ),
                ),
                for (final alpha in const [0.22, 0.42, 0.68, 0.92])
                  Padding(
                    padding: const EdgeInsets.only(left: 3),
                    child: _LegendBox(
                      color: scheme.primary.withValues(alpha: alpha),
                    ),
                  ),
                const SizedBox(width: 4),
                Text(
                  'Max',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: cfo.subtleText),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _WeekdayLabel extends StatelessWidget {
  const _WeekdayLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: context.cfoColors.subtleText,
            fontWeight: FontWeight.w700,
            fontSize: math.max(10.0, 10.5),
          ),
        ),
      ),
    );
  }
}

class _LegendBox extends StatelessWidget {
  const _LegendBox({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

class _HeatmapStat extends StatelessWidget {
  const _HeatmapStat({
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
