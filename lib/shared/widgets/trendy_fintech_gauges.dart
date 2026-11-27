import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../../core/financial_engine/life_stage_planner_engine.dart';

/// Maps each [LifeStageStatus] to an expressive icon for bento cards & pills.
IconData lifeStageIcon(LifeStageStatus status) => switch (status) {
  LifeStageStatus.studentStarter => Icons.school_rounded,
  LifeStageStatus.bachelor => Icons.bolt_rounded,
  LifeStageStatus.marriedCouple => Icons.favorite_rounded,
  LifeStageStatus.familyWithKids => Icons.family_restroom_rounded,
  LifeStageStatus.sandwichFamily => Icons.volunteer_activism_rounded,
  LifeStageStatus.freelancerBusiness => Icons.laptop_mac_rounded,
  LifeStageStatus.preRetirement => Icons.shield_moon_rounded,
};

/// Compact semantic pill showing the profile's active [LifeStageStatus].
class LifeStageBadgePill extends StatelessWidget {
  const LifeStageBadgePill({
    required this.status,
    super.key,
    this.compact = false,
  });

  final LifeStageStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            lifeStageIcon(status),
            size: compact ? 13 : 14,
            color: scheme.primary,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              compact ? status.shortLabel : status.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Trendy 180-degree animated semi-circle speedometer visualizing live
/// EMI Debt-to-Income (DTI %) against a profile's safe life-stage ceiling.
class SemiCircleDtiGauge extends StatelessWidget {
  const SemiCircleDtiGauge({
    required this.dtiPercent,
    required this.maxSafeDtiPct,
    required this.dtiStatus,
    super.key,
    this.masked = false,
    this.height = 136,
  });

  final double dtiPercent;
  final int maxSafeDtiPct;

  /// `'healthy'` | `'caution'` | `'stressed'`
  final String dtiStatus;
  final bool masked;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final activeColor = switch (dtiStatus) {
      'stressed' => cfo.expense,
      'caution' => cfo.warning,
      _ => cfo.income,
    };
    const maxScalePct = 60.0;
    final targetProgress = masked
        ? 0.0
        : (dtiPercent / maxScalePct).clamp(0.0, 1.0);
    final ceilingProgress = (maxSafeDtiPct / maxScalePct).clamp(0.05, 0.95);
    final duration = AppMotion.resolve(context, AppMotion.emphasis);

    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: targetProgress),
        duration: duration,
        curve: Curves.easeOutCubic,
        builder: (context, progress, _) {
          return SizedBox(
            height: height,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _SemiCircleDtiPainter(
                      progress: progress,
                      ceilingProgress: ceilingProgress,
                      activeColor: activeColor,
                      trackColor: cfo.surfaceTonal,
                      notchColor: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.72),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          masked ? '••%' : '${dtiPercent.toStringAsFixed(1)}%',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: activeColor,
                                fontWeight: FontWeight.w900,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                        ),
                      ),
                      Text(
                        'EMI-to-Income • Safe <= $maxSafeDtiPct%',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cfo.subtleText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SemiCircleDtiPainter extends CustomPainter {
  const _SemiCircleDtiPainter({
    required this.progress,
    required this.ceilingProgress,
    required this.activeColor,
    required this.trackColor,
    required this.notchColor,
  });

  final double progress;
  final double ceilingProgress;
  final Color activeColor;
  final Color trackColor;
  final Color notchColor;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 13.0;
    final radius = math.min(size.width / 2 - stroke, size.height - stroke - 8);
    if (radius <= 12) return;

    final center = Offset(size.width / 2, size.height - stroke - 4);
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    // 180-degree semi-circle from pi (left) sweeping pi radians to 2*pi (right).
    canvas.drawArc(rect, math.pi, math.pi, false, trackPaint);

    if (progress > 0.005) {
      final activePaint = Paint()
        ..color = activeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, math.pi, math.pi * progress, false, activePaint);
    }

    // Safe ceiling tick mark across the arc.
    final angle = math.pi + (math.pi * ceilingProgress);
    final inner = Offset(
      center.dx + (radius - stroke * 0.72) * math.cos(angle),
      center.dy + (radius - stroke * 0.72) * math.sin(angle),
    );
    final outer = Offset(
      center.dx + (radius + stroke * 0.72) * math.cos(angle),
      center.dy + (radius + stroke * 0.72) * math.sin(angle),
    );
    final notchPaint = Paint()
      ..color = notchColor
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(inner, outer, notchPaint);
  }

  @override
  bool shouldRepaint(covariant _SemiCircleDtiPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.ceilingProgress != ceilingProgress ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.notchColor != notchColor;
}

/// Segment descriptor for [SegmentedMoneyBar].
final class MoneyBarSegment {
  const MoneyBarSegment({
    required this.label,
    required this.percent,
    required this.color,
  });

  final String label;
  final double percent;
  final Color color;
}

/// Sleek multi-segment rounded horizontal bar with animated flex proportions
/// and crisp dot-legend pills for Needs / Wants / Tax / Savings splits.
class SegmentedMoneyBar extends StatelessWidget {
  const SegmentedMoneyBar({
    required this.segments,
    super.key,
    this.height = 12,
    this.showLegend = true,
    this.masked = false,
    this.trackColor,
    this.labelColor,
  });

  final List<MoneyBarSegment> segments;
  final double height;
  final bool showLegend;
  final bool masked;
  final Color? trackColor;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final visible = segments.where((s) => s.percent > 0).toList();
    final total = visible.fold<double>(0.0, (s, e) => s + e.percent);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          child: Container(
            height: height,
            color: trackColor ?? cfo.surfaceTonal,
            child: visible.isEmpty || total <= 0 || masked
                ? const SizedBox.shrink()
                : Row(
                    children: [
                      for (var i = 0; i < visible.length; i++)
                        Expanded(
                          flex: math.max(1, (visible[i].percent * 10).round()),
                          child: Container(
                            margin: EdgeInsets.only(
                              right: i < visible.length - 1 ? 2 : 0,
                            ),
                            color: visible[i].color,
                          ),
                        ),
                    ],
                  ),
          ),
        ),
        if (showLegend && visible.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (final seg in visible)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: seg.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        masked
                            ? '${seg.label} ••%'
                            : '${seg.label} ${seg.percent.round()}%',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: labelColor ?? cfo.subtleText,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}
