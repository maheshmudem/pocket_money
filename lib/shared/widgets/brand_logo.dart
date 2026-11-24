import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';

/// Bespoke geometric vector logo for Pocket CFO:
/// A rounded squircle vault housing an interlocking white "P" ledger monogram
/// paired with an ascending emerald-mint growth chevron.
class PocketCfoLogo extends StatelessWidget {
  const PocketCfoLogo({
    super.key,
    this.size = 44,
    this.animateEntrance = false,
    this.monochrome = false,
  });

  final double size;
  final bool animateEntrance;
  final bool monochrome;

  @override
  Widget build(BuildContext context) {
    final painterWidget = Semantics(
      label: 'Pocket CFO logo',
      image: true,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: _PocketCfoLogoPainter(
              monochrome: monochrome,
              monochromeColor: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
        ),
      ),
    );

    if (!animateEntrance || MediaQuery.disableAnimationsOf(context)) {
      return painterWidget;
    }

    final duration = AppMotion.resolve(context, AppMotion.emphasis);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        final scale = 0.86 + (0.14 * t);
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: painterWidget,
    );
  }
}

class _PocketCfoLogoPainter extends CustomPainter {
  const _PocketCfoLogoPainter({
    required this.monochrome,
    required this.monochromeColor,
  });

  final bool monochrome;
  final Color monochromeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final rect = Offset.zero & Size.square(s);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(s * 0.28));

    if (!monochrome) {
      // Rich indigo-to-cyan Neo-Fintech squircle base.
      final bgPaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E1B4B), Color(0xFF4338CA), Color(0xFF0EA5E9)],
          stops: [0.0, 0.56, 1.0],
        ).createShader(rect);
      canvas.drawRRect(rrect, bgPaint);

      // Subtle inner specular highlight border along top/left edges.
      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, s * 0.028)
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.36),
            Colors.white.withValues(alpha: 0.04),
          ],
        ).createShader(rect);
      canvas.drawRRect(rrect.deflate(s * 0.015), borderPaint);
    }

    final stroke = s * 0.095;

    // Geometric "P" stem + bowl with generous breathing room inside squircle.
    final pPaint = Paint()
      ..color = monochrome ? monochromeColor : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final pPath = Path()
      ..moveTo(s * 0.32, s * 0.72)
      ..lineTo(s * 0.32, s * 0.28)
      ..lineTo(s * 0.51, s * 0.28)
      ..cubicTo(s * 0.67, s * 0.28, s * 0.67, s * 0.51, s * 0.51, s * 0.51)
      ..lineTo(s * 0.39, s * 0.51);
    canvas.drawPath(pPath, pPaint);

    // Ascending emerald-mint ledger chevron / balanced tick cleanly tucked in lower-right.
    final mintColor = monochrome
        ? monochromeColor.withValues(alpha: 0.85)
        : const Color(0xFF34D399);
    final accentPaint = Paint()
      ..color = mintColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 0.86
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final accentPath = Path()
      ..moveTo(s * 0.48, s * 0.71)
      ..lineTo(s * 0.58, s * 0.61)
      ..lineTo(s * 0.70, s * 0.71);
    canvas.drawPath(accentPath, accentPaint);

    // Crisp emerald coin node cleanly offset in upper-right quadrant.
    final dotPaint = Paint()
      ..color = mintColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(s * 0.73, s * 0.29), s * 0.048, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _PocketCfoLogoPainter oldDelegate) {
    return oldDelegate.monochrome != monochrome ||
        oldDelegate.monochromeColor != monochromeColor;
  }
}
