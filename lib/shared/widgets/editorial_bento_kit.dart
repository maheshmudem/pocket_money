import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_tokens.dart';
import '../../core/financial_engine/money.dart';
import 'fintech_widgets.dart';
import 'flagship_visuals.dart';

/// Shared top background color for seamless Full-Bleed Theater headers
/// (matches the Home & Insights AppBar when theater chrome is active).
const Color kTheaterHeaderBg = Color(0xFF090E24);

/// Full-bleed atmospheric Wealth / Telemetry Theater stage that connects
/// seamlessly with [kTheaterHeaderBg] at the top of the screen and curves
/// smoothly at the bottom, with an optional [floatingDock] straddling the
/// bottom horizon edge.
class FullBleedTheaterStage extends StatelessWidget {
  const FullBleedTheaterStage({
    required this.child,
    super.key,
    this.tone = SignatureHeroTone.indigo,
    this.floatingDock,
    this.isWideCard = false,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 24),
  });

  final Widget child;
  final SignatureHeroTone tone;
  final Widget? floatingDock;
  final bool isWideCard;
  final EdgeInsetsGeometry padding;

  static (List<Color> bg, Color orbA, Color orbB) _palette(
    SignatureHeroTone tone,
  ) => switch (tone) {
    SignatureHeroTone.indigo => (
      const [Color(0xFF0D111A), Color(0xFF151C2B), Color(0xFF1E2A40)],
      const Color(0xFF3B82F6),
      const Color(0xFF94A3B8),
    ),
    SignatureHeroTone.emerald => (
      const [Color(0xFF091714), Color(0xFF0E2A24), Color(0xFF143530)],
      const Color(0xFF10B981),
      const Color(0xFF94A3B8),
    ),
    SignatureHeroTone.amber => (
      const [Color(0xFF17130E), Color(0xFF292016), Color(0xFF1B202D)],
      const Color(0xFFF59E0B),
      const Color(0xFFCBD5E1),
    ),
    SignatureHeroTone.crimson => (
      const [Color(0xFF1A0E14), Color(0xFF321522), Color(0xFF1C1924)],
      const Color(0xFFF43F5E),
      const Color(0xFFCBD5E1),
    ),
    SignatureHeroTone.violet => (
      const [Color(0xFF0F1219), Color(0xFF1B202E), Color(0xFF252D42)],
      const Color(0xFFCBD5E1),
      const Color(0xFF60A5FA),
    ),
    SignatureHeroTone.teal => (
      const [Color(0xFF0C1320), Color(0xFF142238), Color(0xFF1B2E4A)],
      const Color(0xFF38BDF8),
      const Color(0xFFCBD5E1),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (bgColors, orbA, orbB) = _palette(tone);
    final radius = isWideCard
        ? BorderRadius.circular(28)
        : const BorderRadius.vertical(bottom: Radius.circular(34));

    final stageBody = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomRight,
          stops: const [0.0, 0.52, 1.0],
          colors: bgColors,
        ),
        border: isWideCard
            ? Border.all(
                color: Colors.white.withValues(alpha: 0.14),
                width: 1.1,
              )
            : Border(
                bottom: BorderSide(
                  color: orbB.withValues(alpha: isDark ? 0.34 : 0.28),
                  width: 1.2,
                ),
              ),
        boxShadow: [
          BoxShadow(
            color: const Color(
              0xFF0A0F2C,
            ).withValues(alpha: isDark ? 0.52 : 0.24),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _TheaterAtmospherePainter(orbA: orbA, orbB: orbB),
                ),
              ),
            ),
            Padding(
              padding: floatingDock != null
                  ? padding.add(const EdgeInsets.only(bottom: 34))
                  : padding,
              child: child,
            ),
          ],
        ),
      ),
    );

    if (floatingDock == null) return stageBody;

    // Dock straddles the bottom horizon edge cleanly without clipping taps.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 42),
              child: stageBody,
            ),
            Positioned(
              left: isWideCard ? 16 : 16,
              right: isWideCard ? 16 : 16,
              bottom: 0,
              child: floatingDock!,
            ),
          ],
        ),
      ],
    );
  }
}

class _TheaterAtmospherePainter extends CustomPainter {
  const _TheaterAtmospherePainter({required this.orbA, required this.orbB});

  final Color orbA;
  final Color orbB;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Luminous top-right electric cobalt glow
    canvas.drawCircle(
      Offset(size.width * 0.90, size.height * 0.14),
      size.width * 0.56,
      Paint()
        ..shader = RadialGradient(
          colors: [orbA.withValues(alpha: 0.32), orbA.withValues(alpha: 0.0)],
        ).createShader(rect),
    );

    // Lower-left violet / accent aurora mist
    canvas.drawCircle(
      Offset(size.width * 0.08, size.height * 0.92),
      size.width * 0.52,
      Paint()
        ..shader = RadialGradient(
          colors: [orbB.withValues(alpha: 0.28), orbB.withValues(alpha: 0.0)],
        ).createShader(rect),
    );

    // Architectural concentric radar rings
    final ringPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final origin = Offset(size.width * 0.88, size.height * 0.22);
    for (var i = 1; i <= 4; i++) {
      canvas.drawCircle(origin, i * (size.width * 0.19), ringPaint);
    }

    // Subtle geometric dot-matrix accent in upper-right corner
    final dotPaint = Paint()..color = Colors.white.withValues(alpha: 0.09);
    const cols = 7;
    const rows = 4;
    const spacing = 12.0;
    final startX = size.width - (cols * spacing) - 14;
    const startY = 14.0;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        canvas.drawCircle(
          Offset(startX + c * spacing, startY + r * spacing),
          1.1,
          dotPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TheaterAtmospherePainter oldDelegate) =>
      oldDelegate.orbA != orbA || oldDelegate.orbB != orbB;
}

/// Sculpted floating glass/ceramic action dock that straddles the bottom edge
/// of [FullBleedTheaterStage], giving Home an unmistakable Revolut/CRED look.
class FloatingStageDock extends StatelessWidget {
  const FloatingStageDock({required this.items, super.key});

  final List<CircularActionItem> items;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: cfo.surfaceElevated,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: cfo.divider.withValues(alpha: isDark ? 0.95 : 1.0),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(
              0xFF0F172A,
            ).withValues(alpha: isDark ? 0.42 : 0.10),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: _FloatingDockTile(
                item: items[i],
                labelColor: isDark
                    ? Colors.white.withValues(alpha: 0.92)
                    : Theme.of(context).colorScheme.onSurface,
                dividerColor: cfo.divider,
              ),
            ),
        ],
      ),
    );
  }
}

class _FloatingDockTile extends StatefulWidget {
  const _FloatingDockTile({
    required this.item,
    required this.labelColor,
    required this.dividerColor,
  });

  final CircularActionItem item;
  final Color labelColor;
  final Color dividerColor;

  @override
  State<_FloatingDockTile> createState() => _FloatingDockTileState();
}

class _FloatingDockTileState extends State<_FloatingDockTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final duration = AppMotion.resolve(context, AppMotion.fast);

    final inner = GestureDetector(
      key: item.key,
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        item.onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: item.color.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.16
                    : 0.10,
              ),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: item.color.withValues(
                  alpha: Theme.of(context).brightness == Brightness.dark
                      ? 0.28
                      : 0.18,
                ),
                width: 1.0,
              ),
            ),
            child: Icon(item.icon, size: 19, color: item.color),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              item.label,
              maxLines: 1,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: widget.labelColor,
                fontWeight: FontWeight.w700,
                fontSize: 11,
                letterSpacing: -0.1,
              ),
            ),
          ),
        ],
      ),
    );

    if (duration == Duration.zero) return inner;
    return AnimatedScale(
      scale: _pressed ? 0.90 : 1.0,
      duration: duration,
      curve: AppMotion.curveSpring,
      child: inner,
    );
  }
}

/// Supercar / CRED-style 20-segment luminous LED Cockpit Arc Gauge for Budget Guard.
/// Delivers unmistakable precision instrumentation even at low utilization (e.g., 8%).
class CockpitSegmentedArcGauge extends StatelessWidget {
  const CockpitSegmentedArcGauge({
    required this.progress,
    required this.color,
    required this.centerLabel,
    super.key,
    this.caption = 'USED',
    this.size = 116,
    this.masked = false,
  });

  final double progress;
  final Color color;
  final String centerLabel;
  final String caption;
  final double size;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final duration = AppMotion.resolve(context, AppMotion.emphasis);
    final clamped = masked ? 0.0 : progress.clamp(0.0, 1.0);
    final trackColor = isDark
        ? Colors.white.withValues(alpha: 0.11)
        : const Color(0xFF0F172A).withValues(alpha: 0.09);

    Widget buildGauge(double val) => SizedBox(
      width: size,
      height: size * 0.72,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _CockpitArcPainter(
                  progress: val,
                  activeColor: color,
                  trackColor: trackColor,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    masked ? '••' : centerLabel,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontFamily: 'PlusJakartaSans',
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                      height: 1.0,
                      color: color,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cfo.subtleText,
                    fontWeight: FontWeight.w800,
                    fontSize: 8.5,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (duration == Duration.zero) return buildGauge(clamped);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: clamped),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (_, val, _) => buildGauge(val),
    );
  }
}

class _CockpitArcPainter extends CustomPainter {
  const _CockpitArcPainter({
    required this.progress,
    required this.activeColor,
    required this.trackColor,
  });

  final double progress;
  final Color activeColor;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    const segments = 20;
    const startAngle = math.pi * 0.95; // slightly below left horizontal
    const sweepTotal = math.pi * 1.10; // 198 deg dramatic cockpit sweep
    final center = Offset(size.width / 2, size.height * 0.86);
    final outerRadius = math.min(size.width * 0.46, size.height * 0.78);
    final innerRadius = outerRadius - 12.5;
    final litCount = progress <= 0
        ? 0
        : (progress * segments).ceil().clamp(1, segments);

    for (var i = 0; i < segments; i++) {
      final frac = i / (segments - 1);
      final angle = startAngle + sweepTotal * frac;
      final cosA = math.cos(angle);
      final sinA = math.sin(angle);
      final p1 = Offset(
        center.dx + innerRadius * cosA,
        center.dy + innerRadius * sinA,
      );
      final p2 = Offset(
        center.dx + outerRadius * cosA,
        center.dy + outerRadius * sinA,
      );

      final isLit = i < litCount;
      if (isLit) {
        canvas.drawLine(
          p1,
          p2,
          Paint()
            ..color = activeColor.withValues(alpha: 0.30)
            ..strokeWidth = 6.2
            ..strokeCap = StrokeCap.round,
        );
      }
      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..color = isLit ? activeColor : trackColor
          ..strokeWidth = isLit ? 3.8 : 3.0
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CockpitArcPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.trackColor != trackColor;
}

/// Segment descriptor for [AssetAllocationDonut].
class AllocationDonutSlice {
  const AllocationDonutSlice({required this.value, required this.color});

  final int value;
  final Color color;
}

/// Crisp multi-segment glowing Asset Mix Donut Ring for Accounts open-canvas hero.
class AssetAllocationDonut extends StatelessWidget {
  const AssetAllocationDonut({
    required this.slices,
    required this.centerValue,
    required this.centerCaption,
    super.key,
    this.size = 76,
    this.masked = false,
  });

  final List<AllocationDonutSlice> slices;
  final String centerValue;
  final String centerCaption;
  final double size;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trackColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFF0F172A).withValues(alpha: 0.07);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _AllocationDonutPainter(
                  slices: masked ? const [] : slices,
                  trackColor: trackColor,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    masked ? '••' : centerValue,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontFamily: 'PlusJakartaSans',
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    centerCaption,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cfo.subtleText,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
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

class _AllocationDonutPainter extends CustomPainter {
  const _AllocationDonutPainter({
    required this.slices,
    required this.trackColor,
  });

  final List<AllocationDonutSlice> slices;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 6.5;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8.5,
    );

    final total = slices.fold<int>(0, (s, item) => s + item.value);
    if (total <= 0) return;

    final gapAngle = slices.length > 1 ? 0.09 : 0.0;
    var startAngle = -math.pi / 2;
    for (final s in slices) {
      if (s.value <= 0) continue;
      final sweep = ((s.value / total) * math.pi * 2) - gapAngle;
      if (sweep <= 0.02) continue;

      canvas.drawArc(
        rect,
        startAngle,
        sweep,
        false,
        Paint()
          ..color = s.color.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawArc(
        rect,
        startAngle,
        sweep,
        false,
        Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7.5
          ..strokeCap = StrokeCap.round,
      );
      startAngle += sweep + gapAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _AllocationDonutPainter oldDelegate) =>
      oldDelegate.slices != slices || oldDelegate.trackColor != trackColor;
}

/// Bespoke Dual-Wing Cashflow Statement Bar for the Ledger screen — intentionally
/// crisp architectural Light/Dark ceramic styling (distinct from the dark heroes
/// on Home & Insights) with an oversized Net callout and glowing inflow/outflow wings.
class DualWingCashflowBar extends StatelessWidget {
  const DualWingCashflowBar({
    required this.totalCount,
    required this.inflow,
    required this.outflow,
    required this.net,
    required this.masked,
    super.key,
  });

  final int totalCount;
  final Money inflow;
  final Money outflow;
  final Money net;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalFlow = inflow.amountMinor + outflow.amountMinor;
    final inflowPct = totalFlow > 0
        ? ((inflow.amountMinor / totalFlow) * 100).round()
        : 0;
    final outflowPct = totalFlow > 0 ? (100 - inflowPct) : 0;
    final netColor = net.amountMinor >= 0 ? cfo.income : cfo.expense;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 13),
      decoration: BoxDecoration(
        color: cfo.surfaceElevated,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? cfo.divider.withValues(alpha: 0.95)
              : const Color(0xFFD6DFF5),
          width: 1.15,
        ),
        boxShadow: [
          BoxShadow(
            color: cfo.cardShadow,
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top tier: Statement Net Flow Headline + Count Badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: netColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'NET STATEMENT FLOW',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: cfo.subtleText,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 9.5,
                                  letterSpacing: 1.0,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: AnimatedMoneyText(
                        money: net,
                        showPlusSign: true,
                        masked: masked,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: netColor,
                              fontWeight: FontWeight.w900,
                              fontSize: 24,
                              letterSpacing: -0.6,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: cfo.surfaceTonal,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  border: Border.all(color: cfo.divider),
                ),
                child: Text(
                  '$totalCount entries',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cfo.subtleText,
                    fontWeight: FontWeight.w800,
                    fontSize: 10.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Dual-Wing Thick Flow Bar
          if (totalFlow > 0) ...[
            VisualFlowRatioBar(
              primaryMinor: inflow.amountMinor,
              secondaryMinor: outflow.amountMinor,
              primaryColor: cfo.income,
              secondaryColor: cfo.expense,
              height: 9,
              masked: masked,
            ),
            const SizedBox(height: 11),
          ],

          // Split Inflow / Outflow Wing Readouts
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: cfo.incomeContainer,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(
                          Icons.south_west_rounded,
                          size: 15,
                          color: cfo.income,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              masked || totalFlow == 0
                                  ? 'Inflow'
                                  : 'Inflow · $inflowPct%',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: cfo.subtleText,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 10.5,
                                  ),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: AnimatedMoneyText(
                                money: inflow,
                                masked: masked,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      color: cfo.income,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                VerticalDivider(width: 18, thickness: 1, color: cfo.divider),
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: cfo.expenseContainer,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(
                          Icons.north_east_rounded,
                          size: 15,
                          color: cfo.expense,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              masked || totalFlow == 0
                                  ? 'Outflow'
                                  : 'Outflow · $outflowPct%',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: cfo.subtleText,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 10.5,
                                  ),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: AnimatedMoneyText(
                                money: outflow,
                                masked: masked,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      color: cfo.expense,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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

/// Tall sculpted CRED Club / iOS Control Center Bento app tile with a glossy
/// saturated gradient icon emblem, corner arrow or counter pill, and bold hierarchy.
class SculptedBentoAppTile extends StatelessWidget {
  const SculptedBentoAppTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
    super.key,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return TactileColorBlock(
      accent: accent,
      onTap: onTap,
      borderRadius: 20,
      padding: const EdgeInsets.fromLTRB(13, 13, 12, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.16 : 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: accent.withValues(alpha: isDark ? 0.26 : 0.16),
                    width: 1.0,
                  ),
                ),
                child: Icon(icon, size: 19, color: accent),
              ),
              const Spacer(),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7.5,
                    vertical: 2.5,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.22 : 0.12),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  ),
                  child: Text(
                    badge!,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                    ),
                  ),
                )
              else
                Icon(
                  Icons.north_east_rounded,
                  size: 15,
                  color: cfo.subtleText.withValues(alpha: 0.65),
                ),
            ],
          ),
          const SizedBox(height: 11),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cfo.subtleText,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dimensional Bento card with an oversized subtle decorative background
/// watermark emblem anchored in the lower-right corner (Stripe / CRED craft).
class WatermarkBentoCard extends StatelessWidget {
  const WatermarkBentoCard({
    required this.accent,
    required this.watermarkIcon,
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(14),
    this.borderRadius = 20,
    this.onTap,
  });

  final Color accent;
  final IconData watermarkIcon;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TactileColorBlock(
      accent: accent,
      borderRadius: borderRadius,
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            right: -12,
            bottom: -14,
            child: IgnorePointer(
              child: Transform.rotate(
                angle: -0.22,
                child: Icon(
                  watermarkIcon,
                  size: 68,
                  color: accent.withValues(alpha: isDark ? 0.07 : 0.045),
                ),
              ),
            ),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}
