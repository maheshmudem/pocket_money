import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_tokens.dart';
import '../../features/accounts/domain/entities/financial_account_entity.dart';
import 'fintech_widgets.dart';
import 'modern_dialogs.dart';

/// Signature obsidian-aurora palettes for flagship hero surfaces.
/// Delivers high-contrast editorial depth in both Daylight Light and Obsidian Dark
/// without ever using top-only accent bars.
enum SignatureHeroTone { indigo, emerald, teal, amber, crimson, violet }

/// Maps [ModernDialogAccent] to its corresponding [SignatureHeroTone].
SignatureHeroTone heroToneFromAccent(ModernDialogAccent accent) =>
    switch (accent) {
      ModernDialogAccent.brand => SignatureHeroTone.indigo,
      ModernDialogAccent.success => SignatureHeroTone.emerald,
      ModernDialogAccent.warning => SignatureHeroTone.amber,
      ModernDialogAccent.danger => SignatureHeroTone.crimson,
    };

/// Sculpted Obsidian-Aurora Signature Hero Card featuring:
/// - Deep multi-stop obsidian/metallic gradient harmonized for Light & Dark modes
/// - `RepaintBoundary`-isolated subtle topographic waves & dual radial aurora orbs
/// - Uniform `1px` specular hairline rim border (zero top-only strips)
/// - Optional frosted dark-glass [bottomBar]
class FintechSignatureHero extends StatelessWidget {
  const FintechSignatureHero({
    required this.child,
    super.key,
    this.tone = SignatureHeroTone.indigo,
    this.padding = const EdgeInsets.fromLTRB(18, 16, 18, 16),
    this.borderRadius = AppSpacing.radiusXl,
    this.bottomBar,
    this.onTap,
  });

  final Widget child;
  final SignatureHeroTone tone;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Widget? bottomBar;
  final VoidCallback? onTap;

  static (List<Color> bg, Color orbA, Color orbB) palette(
    SignatureHeroTone tone,
  ) => switch (tone) {
    SignatureHeroTone.indigo => (
      const [Color(0xFF07142E), Color(0xFF102858), Color(0xFF1A3F82)],
      const Color(0xFFE5C169),
      const Color(0xFF2DD4A8),
    ),
    SignatureHeroTone.emerald => (
      const [Color(0xFF061E18), Color(0xFF0B362B), Color(0xFF124D3E)],
      const Color(0xFFE5C169),
      const Color(0xFF2DD4A8),
    ),
    SignatureHeroTone.teal => (
      const [Color(0xFF071B2A), Color(0xFF0E324C), Color(0xFF164A6E)],
      const Color(0xFF38BDF8),
      const Color(0xFFE5C169),
    ),
    SignatureHeroTone.amber => (
      const [Color(0xFF1C1509), Color(0xFF33250F), Color(0xFF162544)],
      const Color(0xFFE8C468),
      const Color(0xFF6DA6FF),
    ),
    SignatureHeroTone.crimson => (
      const [Color(0xFF1F0B14), Color(0xFF3D1325), Color(0xFF211730)],
      const Color(0xFFFB7185),
      const Color(0xFFE5C169),
    ),
    SignatureHeroTone.violet => (
      const [Color(0xFF091630), Color(0xFF132B59), Color(0xFF1F427E)],
      const Color(0xFFE8C468),
      const Color(0xFF6DA6FF),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (bgColors, orbA, orbB) = palette(tone);

    final inner = Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _SignatureBackdropPainter(orbA: orbA, orbB: orbB),
            ),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(padding: padding, child: child),
            if (bottomBar != null) ...[
              Container(height: 1, color: Colors.white.withValues(alpha: 0.12)),
              ColoredBox(
                color: Colors.white.withValues(alpha: 0.04),
                child: bottomBar!,
              ),
            ],
          ],
        ),
      ],
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: bgColors,
        ),
        border: Border.all(
          color: orbA.withValues(alpha: isDark ? 0.24 : 0.22),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(
              0xFF061624,
            ).withValues(alpha: isDark ? 0.58 : 0.24),
            blurRadius: isDark ? 26 : 22,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: orbA.withValues(alpha: isDark ? 0.15 : 0.10),
            blurRadius: 28,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Material(
          color: Colors.transparent,
          child: onTap != null
              ? InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onTap!();
                  },
                  splashColor: Colors.white.withValues(alpha: 0.08),
                  highlightColor: Colors.white.withValues(alpha: 0.04),
                  child: inner,
                )
              : inner,
        ),
      ),
    );
  }
}

class _SignatureBackdropPainter extends CustomPainter {
  const _SignatureBackdropPainter({required this.orbA, required this.orbB});

  final Color orbA;
  final Color orbB;

  @override
  void paint(Canvas canvas, Size size) {
    // Soft luminous top-right aurora orb
    final orbAPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.88, -0.78),
        radius: 0.95,
        colors: [orbA.withValues(alpha: 0.34), orbA.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), orbAPaint);

    // Subtle bottom-left counter aurora orb
    final orbBPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.85, 0.95),
        radius: 0.85,
        colors: [orbB.withValues(alpha: 0.22), orbB.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), orbBPaint);

    // Subtle diagonal specular sheen
    final sheenPaint = Paint()
      ..shader =
          LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.centerRight,
            colors: [
              Colors.white.withValues(alpha: 0.075),
              Colors.white.withValues(alpha: 0.0),
            ],
          ).createShader(
            Rect.fromLTWH(0, 0, size.width * 0.68, size.height * 0.65),
          );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width * 0.68, size.height * 0.65),
      sheenPaint,
    );

    // Crisp banking topographic ledger waves (cool mint-ice hairline)
    final wavePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.065)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;

    for (var i = 0; i < 4; i++) {
      final offset = i * 14.0;
      final path = Path()
        ..moveTo(-20, size.height * 0.72 + offset)
        ..cubicTo(
          size.width * 0.30,
          size.height * 0.30 + offset,
          size.width * 0.68,
          size.height * 0.92 + offset,
          size.width + 20,
          size.height * 0.18 + offset,
        );
      canvas.drawPath(path, wavePaint);
    }

    // Subtle geometric CRED dot-matrix texture accent in top-right
    final dotPaint = Paint()..color = Colors.white.withValues(alpha: 0.085);
    for (var r = 0; r < 3; r++) {
      for (var c = 0; c < 5; c++) {
        canvas.drawCircle(
          Offset(size.width - 22 - (c * 11.0), 20 + (r * 11.0)),
          1.2,
          dotPaint,
        );
      }
    }

    // Subtle concentric vault watermark rings in upper right
    final ringPaint = Paint()
      ..color = orbA.withValues(alpha: 0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final ringCenter = Offset(size.width * 0.92, size.height * 0.12);
    canvas.drawCircle(ringCenter, size.height * 0.42, ringPaint);
    canvas.drawCircle(ringCenter, size.height * 0.64, ringPaint);
  }

  @override
  bool shouldRepaint(covariant _SignatureBackdropPainter oldDelegate) =>
      oldDelegate.orbA != orbA || oldDelegate.orbB != orbB;
}

/// Translucent frosted glass status pill designed for [FintechSignatureHero].
class HeroGlassPill extends StatelessWidget {
  const HeroGlassPill({
    required this.label,
    super.key,
    this.icon,
    this.dotColor,
    this.foreground = Colors.white,
    this.background,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final Color? dotColor;
  final Color foreground;
  final Color? background;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
      decoration: BoxDecoration(
        color: background ?? Colors.white.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 4),
          ] else if (dotColor != null) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: dotColor!.withValues(alpha: 0.6),
                    blurRadius: 5,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w800,
                fontSize: 10.5,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return pill;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap!();
        },
        child: pill,
      ),
    );
  }
}

/// Recessed frosted dark-glass container for split metrics inside [FintechSignatureHero].
class HeroGlassWell extends StatelessWidget {
  const HeroGlassWell({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.075),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: Colors.white.withValues(alpha: 0.11)),
      ),
      child: child,
    );
  }
}

/// Flat hairline-separated glass action bar tailored for the bottom dock of [FintechSignatureHero].
class HeroGlassActionBar extends StatelessWidget {
  const HeroGlassActionBar({
    required this.items,
    super.key,
    this.verticalPadding = 11,
  });

  final List<FintechFlatActionItem> items;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              VerticalDivider(
                width: 1,
                thickness: 1,
                indent: 8,
                endIndent: 8,
                color: Colors.white.withValues(alpha: 0.13),
              ),
            Expanded(
              child: InkWell(
                key: items[i].key,
                splashColor: Colors.white.withValues(alpha: 0.10),
                onTap: () {
                  HapticFeedback.selectionClick();
                  items[i].onTap();
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: verticalPadding,
                    horizontal: 6,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(items[i].icon, size: 15, color: items[i].color),
                      const SizedBox(width: 5),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            items[i].label,
                            maxLines: 1,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.94),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11.5,
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Descriptor for an open-canvas tactile circular action medallion.
class CircularActionItem {
  const CircularActionItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.key,
  });

  final Key? key;
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
}

/// Open-canvas floating circular action dock (Revolut / Wise / Apple Pay style).
/// Sits cleanly outside cards to break vertical card-stack monotony.
class CircularActionDock extends StatelessWidget {
  const CircularActionDock({required this.items, super.key});

  final List<CircularActionItem> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items)
            Expanded(child: _CircularActionButton(item: item)),
        ],
      ),
    );
  }
}

class _CircularActionButton extends StatefulWidget {
  const _CircularActionButton({required this.item});
  final CircularActionItem item;

  @override
  State<_CircularActionButton> createState() => _CircularActionButtonState();
}

class _CircularActionButtonState extends State<_CircularActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final duration = AppMotion.resolve(context, AppMotion.fast);
    final accent = widget.item.color;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        key: widget.item.key,
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          HapticFeedback.selectionClick();
          widget.item.onTap();
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: _pressed ? 0.91 : 1.0,
              duration: duration,
              curve: AppMotion.curveSpring,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: isDark
                      ? Color.alphaBlend(
                          accent.withValues(alpha: 0.14),
                          cfo.surfaceElevated,
                        )
                      : cfo.surfaceElevated,
                  border: Border.all(
                    color: accent.withValues(alpha: isDark ? 0.42 : 0.28),
                    width: 1.25,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: isDark ? 0.26 : 0.18),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                    BoxShadow(
                      color: cfo.cardShadow,
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          accent,
                          Color.lerp(accent, const Color(0xFF1E1B4B), 0.24)!,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.36),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(
                      widget.item.icon,
                      size: 19,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                widget.item.label,
                maxLines: 1,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Smooth one-shot animated cubic-bezier sparkline with gradient area fade
/// and glowing terminal marker dot (`RepaintBoundary` isolated, zero infinite loops).
class MiniSparklineChart extends StatelessWidget {
  const MiniSparklineChart({
    required this.values,
    required this.color,
    super.key,
    this.width = 96,
    this.height = 38,
    this.strokeWidth = 2.2,
    this.masked = false,
  });

  final List<double> values;
  final Color color;
  final double width;
  final double height;
  final double strokeWidth;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.resolve(context, AppMotion.emphasis);
    final effectiveValues = masked || values.isEmpty
        ? const [0.4, 0.45, 0.42, 0.5, 0.48, 0.55]
        : (values.length == 1 ? [values.first * 0.6, values.first] : values);

    Widget paintAt(double t) => SizedBox(
      width: width,
      height: height,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _SparklinePainter(
            values: effectiveValues,
            color: masked ? color.withValues(alpha: 0.35) : color,
            strokeWidth: strokeWidth,
            progress: t,
          ),
        ),
      ),
    );

    if (duration == Duration.zero) {
      return paintAt(1.0);
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (_, t, _) => paintAt(t),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({
    required this.values,
    required this.color,
    required this.strokeWidth,
    required this.progress,
  });

  final List<double> values;
  final Color color;
  final double strokeWidth;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width <= 4 || size.height <= 4) return;
    final minVal = values.reduce(math.min);
    final maxVal = values.reduce(math.max);
    final span = (maxVal - minVal).abs();
    const padX = 4.0;
    const padY = 5.0;
    final drawW = size.width - padX * 2;
    final drawH = size.height - padY * 2;

    final pts = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final fracX = i / (values.length - 1);
      final normY = span < 1e-6 ? 0.5 : (values[i] - minVal) / span;
      final animatedY = 0.5 + (normY - 0.5) * progress;
      pts.add(Offset(padX + fracX * drawW, padY + (1.0 - animatedY) * drawH));
    }

    final linePath = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = pts[i];
      final p1 = pts[i + 1];
      final midX = (p0.dx + p1.dx) / 2;
      linePath.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
    }

    final fillPath = Path.from(linePath)
      ..lineTo(pts.last.dx, size.height)
      ..lineTo(pts.first.dx, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.28 * progress),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, linePaint);

    // Terminal luminous dot
    final last = pts.last;
    canvas.drawCircle(
      last,
      strokeWidth * 2.1,
      Paint()..color = color.withValues(alpha: 0.24 * progress),
    );
    canvas.drawCircle(last, strokeWidth * 1.15, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.values != values;
}

/// Compact animated circular ring meter (`36px–48px`) for KPI tiles & budget gauges.
class MiniRingGauge extends StatelessWidget {
  const MiniRingGauge({
    required this.progress,
    required this.color,
    super.key,
    this.size = 42,
    this.strokeWidth = 4.5,
    this.trackColor,
    this.centerLabel,
    this.centerColor,
    this.masked = false,
  });

  final double progress;
  final Color color;
  final double size;
  final double strokeWidth;
  final Color? trackColor;
  final String? centerLabel;
  final Color? centerColor;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final target = masked ? 0.0 : progress.clamp(0.0, 1.0);
    final duration = AppMotion.resolve(context, AppMotion.emphasis);
    final resolvedTrack = trackColor ?? cfo.surfaceTonal;

    Widget buildRing(double p) => SizedBox(
      width: size,
      height: size,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _MiniRingPainter(
            progress: p,
            color: color,
            trackColor: resolvedTrack,
            strokeWidth: strokeWidth,
          ),
          child: centerLabel != null
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(strokeWidth + 2),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        masked ? '••' : centerLabel!,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: centerColor ?? color,
                          fontWeight: FontWeight.w900,
                          fontSize: 10.5,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                )
              : null,
        ),
      ),
    );

    if (duration == Duration.zero) {
      return buildRing(target);
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: target),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => buildRing(v),
    );
  }
}

class _MiniRingPainter extends CustomPainter {
  const _MiniRingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  final double progress;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    if (radius <= 0) return;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    if (progress <= 0.005) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor;
}

/// Clean rounded dual-tone Inflow vs Outflow proportion bar with proper interior
/// capsule radius (never clips sharply into parent card corners).
class VisualFlowRatioBar extends StatelessWidget {
  const VisualFlowRatioBar({
    required this.primaryMinor,
    required this.secondaryMinor,
    required this.primaryColor,
    required this.secondaryColor,
    super.key,
    this.height = 6,
    this.trackColor,
    this.masked = false,
  });

  final int primaryMinor;
  final int secondaryMinor;
  final Color primaryColor;
  final Color secondaryColor;
  final double height;
  final Color? trackColor;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final a = primaryMinor.abs();
    final b = secondaryMinor.abs();
    final total = a + b;

    if (masked || total == 0) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: trackColor ?? cfo.surfaceTonal,
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        ),
      );
    }

    final aFlex = ((a / total) * 1000).round().clamp(a > 0 ? 40 : 0, 1000);
    final bFlex = ((b / total) * 1000).round().clamp(b > 0 ? 40 : 0, 1000);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      child: SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (aFlex > 0)
              Expanded(
                flex: aFlex,
                child: Container(
                  decoration: BoxDecoration(
                    color: primaryColor,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  ),
                ),
              ),
            if (aFlex > 0 && bFlex > 0) const SizedBox(width: 3),
            if (bFlex > 0)
              Expanded(
                flex: bFlex,
                child: Container(
                  decoration: BoxDecoration(
                    color: secondaryColor,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Sleek physical/virtual metallic bank, wallet, cash, investment & card vault widget.
/// Prevents name truncation by giving the vault title full-width visual hierarchy,
/// paired with subtle metallic sheen, EMV chip motif, and tabular balance typography.
class VirtualAccountVaultCard extends StatelessWidget {
  const VirtualAccountVaultCard({
    required this.account,
    required this.baseCurrency,
    required this.sharePercent,
    required this.masked,
    required this.onTap,
    super.key,
    this.trailingMenu,
    this.bottomBar,
    this.compact = false,
    this.onQuickAdd,
  });

  final FinancialAccountEntity account;
  final String baseCurrency;
  final int sharePercent;
  final bool masked;
  final VoidCallback onTap;
  final Widget? trailingMenu;
  final Widget? bottomBar;
  final bool compact;
  final VoidCallback? onQuickAdd;

  static (List<Color> colors, Color glow, IconData icon, bool showChip)
  styleFor(FinancialAccountType type) => switch (type) {
    FinancialAccountType.bank => (
      const [Color(0xFF091734), Color(0xFF112C61), Color(0xFF1C448C)],
      const Color(0xFFE8C468),
      Icons.account_balance_rounded,
      true,
    ),
    FinancialAccountType.cash => (
      const [Color(0xFF06211A), Color(0xFF0C3C2F), Color(0xFF135643)],
      const Color(0xFF5EEAD4),
      Icons.payments_rounded,
      false,
    ),
    FinancialAccountType.wallet => (
      const [Color(0xFF081D2E), Color(0xFF103654), Color(0xFF18517A)],
      const Color(0xFF7DD3FC),
      Icons.account_balance_wallet_rounded,
      false,
    ),
    FinancialAccountType.investment || FinancialAccountType.other => (
      const [Color(0xFF1E0F24), Color(0xFF371A42), Color(0xFF4D255C)],
      const Color(0xFFF0CD7A),
      Icons.trending_up_rounded,
      false,
    ),
    FinancialAccountType.creditCard || FinancialAccountType.loan => (
      const [Color(0xFF1D0D14), Color(0xFF381726), Color(0xFF4C1F33)],
      const Color(0xFFFDA4AF),
      Icons.credit_card_rounded,
      true,
    ),
  };

  String _maskedVaultDigits() {
    final code = (account.id.hashCode.abs() % 9000) + 1000;
    return '•••• $code';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (colors, glow, icon, showChip) = styleFor(account.accountType);
    final subtitle =
        '${account.accountType.label}${account.institutionLabel != null ? ' • ${account.institutionLabel}' : ''}';

    final body = Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _MetalVaultBackdropPainter(
                orbA: glow,
                orbB: colors.last,
              ),
            ),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 14 : 16,
                compact ? 13 : 15,
                trailingMenu != null ? 6 : (compact ? 12 : 16),
                compact ? 13 : 13,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Row 1: Metallic Icon / Chip + Full Un-truncated Vault Name + Currency + Menu
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: compact ? 34 : 38,
                        height: compact ? 34 : 38,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Icon(icon, size: compact ? 18 : 20, color: glow),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              account.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.2,
                                    fontSize: compact ? 14.5 : 16,
                                  ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.68),
                                    fontSize: 11,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (account.isArchived) ...[
                        const HeroGlassPill(
                          label: 'Archived',
                          foreground: Color(0xFFFDE68A),
                        ),
                        const SizedBox(width: 4),
                      ],
                      HeroGlassPill(
                        label: account.currencyCode,
                        foreground: Colors.white.withValues(alpha: 0.92),
                      ),
                      if (onQuickAdd != null) ...[
                        const SizedBox(width: 6),
                        Material(
                          color: Colors.white.withValues(alpha: 0.14),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              onQuickAdd!();
                            },
                            child: Tooltip(
                              message: 'Record entry for ${account.name}',
                              child: const SizedBox(
                                width: 30,
                                height: 30,
                                child: Icon(
                                  Icons.add_rounded,
                                  size: 17,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      ?trailingMenu,
                    ],
                  ),
                  SizedBox(height: compact ? 14 : 16),

                  // Row 2: Luminous Tabular Balance + EMV Chip & Portfolio Share
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              account.isLiability
                                  ? 'CURRENT OWED'
                                  : 'AVAILABLE BALANCE',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.56),
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.9,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: AnimatedMoneyText(
                                money: account.balance,
                                masked: masked,
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.6,
                                      fontSize: compact ? 20 : 24,
                                    ),
                              ),
                            ),
                            if (account.currencyCode != baseCurrency) ...[
                              const SizedBox(height: 1),
                              MoneyText(
                                money: account.baseBalance,
                                masked: masked,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: Colors.white.withValues(
                                        alpha: 0.65,
                                      ),
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (showChip && !compact) ...[
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Transform.rotate(
                                  angle: math.pi / 2,
                                  child: Icon(
                                    Icons.wifi_rounded,
                                    size: 16,
                                    color: glow.withValues(alpha: 0.72),
                                  ),
                                ),
                                const SizedBox(width: 7),
                                SizedBox(
                                  width: 34,
                                  height: 24,
                                  child: CustomPaint(
                                    painter: _EmvChipPainter(accent: glow),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                          ],
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 132),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                masked
                                    ? '•••• ••••'
                                    : '${_maskedVaultDigits()}  •  $sharePercent%',
                                maxLines: 1,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: glow.withValues(alpha: 0.92),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 10.5,
                                      letterSpacing: 0.4,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Glowing allocation share progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                    child: Container(
                      height: 4,
                      color: Colors.white.withValues(alpha: 0.14),
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: masked
                            ? 0.0
                            : (sharePercent / 100).clamp(0.03, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: glow,
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusFull,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (bottomBar != null) ...[
              Container(height: 1, color: Colors.white.withValues(alpha: 0.11)),
              ColoredBox(
                color: Colors.white.withValues(alpha: 0.055),
                child: bottomBar!,
              ),
            ],
          ],
        ),
      ],
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(
          compact ? AppSpacing.radiusLg : AppSpacing.radiusXl,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        border: Border.all(color: glow.withValues(alpha: isDark ? 0.26 : 0.28)),
        boxShadow: [
          BoxShadow(
            color: const Color(
              0xFF0A0B0F,
            ).withValues(alpha: isDark ? 0.56 : 0.26),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          compact ? AppSpacing.radiusLg : AppSpacing.radiusXl,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            splashColor: Colors.white.withValues(alpha: 0.09),
            child: body,
          ),
        ),
      ),
    );
  }
}

/// Realistic brushed-titanium metallic sheen & micro-grain backdrop painter
/// for physical-feel [VirtualAccountVaultCard] surfaces.
class _MetalVaultBackdropPainter extends CustomPainter {
  const _MetalVaultBackdropPainter({required this.orbA, required this.orbB});

  final Color orbA;
  final Color orbB;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Luminous diagonal anodized sheen ribbon
    final sheenPath = Path()
      ..moveTo(size.width * 0.16, 0)
      ..lineTo(size.width * 0.50, 0)
      ..lineTo(size.width * 0.24, size.height)
      ..lineTo(-size.width * 0.08, size.height)
      ..close();
    canvas.drawPath(
      sheenPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.0),
            Colors.white.withValues(alpha: 0.10),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(rect),
    );

    // Subtle horizontal brushed-metal micro lines
    final brushPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.028)
      ..strokeWidth = 0.7;
    for (double y = 6; y < size.height; y += 6.5) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), brushPaint);
    }

    // Radial metallic glow orbs
    canvas.drawCircle(
      Offset(size.width * 0.90, size.height * 0.14),
      size.width * 0.45,
      Paint()
        ..shader = RadialGradient(
          colors: [orbA.withValues(alpha: 0.34), orbA.withValues(alpha: 0.0)],
        ).createShader(rect),
    );
    canvas.drawCircle(
      Offset(size.width * 0.08, size.height * 0.95),
      size.width * 0.36,
      Paint()
        ..shader = RadialGradient(
          colors: [orbB.withValues(alpha: 0.30), orbB.withValues(alpha: 0.0)],
        ).createShader(rect),
    );

    // Fine security guilloche curves
    final arcPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;
    final origin = Offset(size.width * 0.94, size.height * 0.24);
    for (var i = 1; i <= 3; i++) {
      canvas.drawCircle(origin, i * (size.width * 0.18), arcPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MetalVaultBackdropPainter oldDelegate) =>
      oldDelegate.orbA != orbA || oldDelegate.orbB != orbB;
}

/// Realistic etched gold EMV smart chip painter for physical-feel bank & card vaults.
class _EmvChipPainter extends CustomPainter {
  const _EmvChipPainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(5.5),
    );
    final fill = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF8E7B9), Color(0xFFE0BA63), Color(0xFFBA8C32)],
      ).createShader(Offset.zero & size);
    canvas.drawRRect(rrect, fill);

    final line = Paint()
      ..color = const Color(0xFF3A290D).withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.85;

    // Inner contact pads motif
    final padRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.28,
        size.height * 0.22,
        size.width * 0.44,
        size.height * 0.56,
      ),
      const Radius.circular(2.2),
    );
    canvas.drawRRect(padRect, line);
    canvas.drawLine(
      Offset(0, size.height * 0.5),
      Offset(size.width * 0.28, size.height * 0.5),
      line,
    );
    canvas.drawLine(
      Offset(size.width * 0.72, size.height * 0.5),
      Offset(size.width, size.height * 0.5),
      line,
    );
    canvas.drawLine(
      Offset(size.width * 0.5, 0),
      Offset(size.width * 0.5, size.height * 0.22),
      line,
    );
    canvas.drawLine(
      Offset(size.width * 0.5, size.height * 0.78),
      Offset(size.width * 0.5, size.height),
      line,
    );

    final rim = Paint()
      ..color = Colors.white.withValues(alpha: 0.42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawRRect(rrect, rim);
  }

  @override
  bool shouldRepaint(covariant _EmvChipPainter oldDelegate) =>
      oldDelegate.accent != accent;
}

/// Full-width sculptural area wealth curve for Obsidian hero stages, featuring
/// subtle hairline reference guides, gradient wash, and a luminous beacon dot.
class HeroWealthAreaChart extends StatelessWidget {
  const HeroWealthAreaChart({
    required this.values,
    required this.color,
    super.key,
    this.height = 56,
    this.masked = false,
  });

  final List<double> values;
  final Color color;
  final double height;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.resolve(context, AppMotion.emphasis);
    final effectiveValues = masked || values.isEmpty
        ? const [0.42, 0.48, 0.45, 0.56, 0.53, 0.62, 0.68]
        : (values.length == 1 ? [values.first * 0.7, values.first] : values);

    Widget buildCanvas(double t) => SizedBox(
      height: height,
      width: double.infinity,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _HeroWealthAreaPainter(
            values: effectiveValues,
            color: masked ? color.withValues(alpha: 0.32) : color,
            progress: t,
          ),
        ),
      ),
    );

    if (duration == Duration.zero) return buildCanvas(1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (_, t, _) => buildCanvas(t),
    );
  }
}

class _HeroWealthAreaPainter extends CustomPainter {
  const _HeroWealthAreaPainter({
    required this.values,
    required this.color,
    required this.progress,
  });

  final List<double> values;
  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width <= 8 || size.height <= 8) return;

    // Subtle luxury horizontal reference rules
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.065)
      ..strokeWidth = 0.8;
    for (final frac in const [0.22, 0.58, 0.92]) {
      final y = size.height * frac;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final minVal = values.reduce(math.min);
    final maxVal = values.reduce(math.max);
    final span = (maxVal - minVal).abs();
    const padX = 5.0;
    const padTop = 7.0;
    const padBottom = 6.0;
    final drawW = size.width - padX * 2;
    final drawH = size.height - padTop - padBottom;

    final pts = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final fx = i / (values.length - 1);
      final normY = span < 1e-6 ? 0.55 : (values[i] - minVal) / span;
      final animY = 0.25 + (normY - 0.25) * progress;
      pts.add(Offset(padX + fx * drawW, padTop + (1.0 - animY) * drawH));
    }

    final linePath = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = pts[i];
      final p1 = pts[i + 1];
      final midX = (p0.dx + p1.dx) / 2;
      linePath.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
    }

    final fillPath = Path.from(linePath)
      ..lineTo(pts.last.dx, size.height)
      ..lineTo(pts.first.dx, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.26 * progress),
          color.withValues(alpha: 0.02 * progress),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fillPath, fillPaint);

    // Subtle glow under curve
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.24 * progress)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, glowPaint);

    final strokePaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFE8C468), Color(0xFF60A5FA), Color(0xFF2DD4A8)],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, strokePaint);

    final last = pts.last;
    canvas.drawCircle(
      last,
      7.0,
      Paint()..color = color.withValues(alpha: 0.24 * progress),
    );
    canvas.drawCircle(last, 3.5, Paint()..color = color);
    canvas.drawCircle(last, 1.6, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _HeroWealthAreaPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.values != values;
}

/// Animated dual vertical capsule comparison bars for asymmetric Bento Cash Flow tiles.
class BentoVerticalFlowBars extends StatelessWidget {
  const BentoVerticalFlowBars({
    required this.incomeMinor,
    required this.expenseMinor,
    super.key,
    this.height = 54,
    this.masked = false,
  });

  final int incomeMinor;
  final int expenseMinor;
  final double height;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final maxVal = math.max(1, math.max(incomeMinor.abs(), expenseMinor.abs()));
    final inFrac = masked
        ? 0.35
        : (incomeMinor.abs() / maxVal).clamp(
            incomeMinor > 0 ? 0.14 : 0.06,
            1.0,
          );
    final outFrac = masked
        ? 0.22
        : (expenseMinor.abs() / maxVal).clamp(
            expenseMinor > 0 ? 0.14 : 0.06,
            1.0,
          );
    final duration = AppMotion.resolve(context, AppMotion.emphasis);

    Widget buildBar(double target, Color color, String label) {
      return Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: height,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  height: height,
                  decoration: BoxDecoration(
                    color: cfo.surfaceTonal,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.bottomCenter,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0.0, end: target),
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    builder: (_, v, _) => FractionallySizedBox(
                      heightFactor: v.clamp(0.06, 1.0),
                      widthFactor: 1.0,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(9),
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [color.withValues(alpha: 0.72), color],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 5),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: cfo.subtleText,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        buildBar(inFrac, cfo.income, 'Inflow'),
        const SizedBox(width: 8),
        buildBar(outFrac, cfo.expense, 'Outflow'),
      ],
    );
  }
}

/// Sleek 180-degree semi-circular speedometer arc gauge for compact Bento tiles.
class MiniSpeedometerArc extends StatelessWidget {
  const MiniSpeedometerArc({
    required this.progress,
    required this.color,
    required this.centerLabel,
    super.key,
    this.width = 98,
    this.height = 56,
    this.masked = false,
  });

  final double progress;
  final Color color;
  final String centerLabel;
  final double width;
  final double height;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final target = masked ? 0.0 : progress.clamp(0.0, 1.0);
    final duration = AppMotion.resolve(context, AppMotion.emphasis);

    Widget buildArc(double p) => SizedBox(
      width: width,
      height: height,
      child: RepaintBoundary(
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _MiniSpeedometerPainter(
                  progress: p,
                  color: color,
                  trackColor: cfo.surfaceTonal,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  masked ? '••%' : centerLabel,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (duration == Duration.zero) return buildArc(target);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: target),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => buildArc(v),
    );
  }
}

class _MiniSpeedometerPainter extends CustomPainter {
  const _MiniSpeedometerPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  final double progress;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 9.0;
    final radius = math.min(
      size.width / 2 - stroke,
      size.height - stroke / 2 - 2,
    );
    if (radius <= 8) return;
    final center = Offset(size.width / 2, size.height - stroke / 2 - 1);
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(
      rect,
      math.pi,
      math.pi,
      false,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );

    if (progress <= 0.005) return;
    final sweep = math.pi * progress;
    canvas.drawArc(
      rect,
      math.pi,
      sweep,
      false,
      Paint()
        ..color = color.withValues(alpha: 0.24)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke + 5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawArc(
      rect,
      math.pi,
      sweep,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );

    // Glowing terminal indicator dot
    final endAngle = math.pi + sweep;
    final tip = Offset(
      center.dx + radius * math.cos(endAngle),
      center.dy + radius * math.sin(endAngle),
    );
    canvas.drawCircle(tip, 3.0, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _MiniSpeedometerPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor;
}

/// CRED-style bold tactile color-coded Bento surface primitive with rich
/// category tinting, specular rim border, layered drop shadow, and spring press.
class TactileColorBlock extends StatefulWidget {
  const TactileColorBlock({
    required this.accent,
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(14),
    this.borderRadius = AppSpacing.radiusLg,
    this.onTap,
  });

  final Color accent;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final VoidCallback? onTap;

  @override
  State<TactileColorBlock> createState() => _TactileColorBlockState();
}

class _TactileColorBlockState extends State<TactileColorBlock> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final duration = AppMotion.resolve(context, AppMotion.fast);
    final accent = widget.accent;

    final startBg = isDark
        ? Color.alphaBlend(accent.withValues(alpha: 0.045), cfo.surfaceElevated)
        : Color.alphaBlend(
            accent.withValues(alpha: 0.018),
            cfo.surfaceElevated,
          );
    final endBg = cfo.surfaceElevated;

    final box = AnimatedContainer(
      duration: duration,
      curve: AppMotion.curveStandard,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [startBg, endBg],
        ),
        border: Border.all(
          color: cfo.divider.withValues(alpha: isDark ? 0.95 : 1.0),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: cfo.cardShadow,
            blurRadius: isDark ? 12 : 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
        child: widget.onTap != null
            ? InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onTap!();
                },
                onTapDown: (_) => setState(() => _pressed = true),
                onTapUp: (_) => setState(() => _pressed = false),
                onTapCancel: () => setState(() => _pressed = false),
                child: Padding(padding: widget.padding, child: widget.child),
              )
            : Padding(padding: widget.padding, child: widget.child),
      ),
    );

    if (widget.onTap == null || duration == Duration.zero) return box;
    return AnimatedScale(
      scale: _pressed ? 0.975 : 1.0,
      duration: duration,
      curve: AppMotion.curveSpring,
      child: box,
    );
  }
}

/// Polished editorial section header with a subtle semantic dot indicator and
/// optional tonal pill CTA.
class EditorialSectionHeader extends StatelessWidget {
  const EditorialSectionHeader({
    required this.title,
    super.key,
    this.subtitle,
    this.accentColor,
    this.count,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final Color? accentColor;
  final int? count;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final dot = accentColor ?? scheme.primary;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  if (count != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6.5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: cfo.surfaceTonal,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusFull,
                        ),
                      ),
                      child: Text(
                        '$count',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cfo.subtleText,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 1),
                Padding(
                  padding: const EdgeInsets.only(left: 13),
                  child: Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cfo.subtleText,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(width: 8),
          Material(
            color: scheme.primaryContainer.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              onTap: () {
                HapticFeedback.selectionClick();
                onAction!();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 5,
                ),
                child: Text(
                  actionLabel!,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
