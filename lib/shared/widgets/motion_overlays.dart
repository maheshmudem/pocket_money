import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_tokens.dart';
import '../../core/financial_engine/alert_evaluation_engine.dart';
import 'fintech_widgets.dart';
import 'modern_dialogs.dart';

/// Animated AppBar notification bell with spring-scaling crimson unread badge
/// and a bounded celebratory/attention bell tilt when [unreadCount] increments.
class AnimatedNotificationBell extends StatefulWidget {
  const AnimatedNotificationBell({
    required this.unreadCount,
    required this.onPressed,
    super.key,
    this.size = 40,
    this.iconSize = 21,
  });

  final int unreadCount;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;

  @override
  State<AnimatedNotificationBell> createState() =>
      _AnimatedNotificationBellState();
}

class _AnimatedNotificationBellState extends State<AnimatedNotificationBell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ringCtrl;
  late final Animation<double> _tilt;

  @override
  void initState() {
    super.initState();
    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _tilt = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.22), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 0.22, end: -0.20), weight: 25),
      TweenSequenceItem(tween: Tween(begin: -0.20, end: 0.12), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 0.12, end: 0.0), weight: 30),
    ]).animate(CurvedAnimation(parent: _ringCtrl, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(covariant AnimatedNotificationBell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.unreadCount > oldWidget.unreadCount &&
        !MediaQuery.disableAnimationsOf(context)) {
      _ringCtrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _ringCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final count = widget.unreadCount;
    final badgeLabel = count > 9 ? '9+' : '$count';
    final duration = AppMotion.resolve(context, AppMotion.fast);

    return Tooltip(
      message: count > 0 ? 'Notifications ($count unread)' : 'Notifications',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          key: const Key('appbar_notifications_btn'),
          customBorder: const CircleBorder(),
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onPressed();
          },
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: _tilt,
                  builder: (_, child) =>
                      Transform.rotate(angle: _tilt.value, child: child),
                  child: Icon(
                    count > 0
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_none_rounded,
                    size: widget.iconSize,
                    color: count > 0 ? scheme.primary : scheme.onSurface,
                  ),
                ),
                Positioned(
                  right: 3,
                  top: 3,
                  child: AnimatedScale(
                    scale: count > 0 ? 1.0 : 0.0,
                    duration: duration,
                    curve: Curves.easeOutBack,
                    child: count > 0
                        ? Container(
                            key: const Key('appbar_notifications_badge'),
                            constraints: const BoxConstraints(
                              minWidth: 17,
                              minHeight: 17,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: cfo.expense,
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusFull,
                              ),
                              border: Border.all(
                                color: cfo.surfaceElevated,
                                width: 1.5,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              badgeLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                height: 1.0,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Spring-animated frosted-glass floating alert banner displayed at the top of the app
/// whenever a budget reaches 80%/100%/crossed, an account hits low balance, or a goal
/// reaches a milestone. Swipe up or tap × to dismiss; tap View to jump directly to the screen.
class InAppAlertBannerOverlay extends StatefulWidget {
  const InAppAlertBannerOverlay({
    required this.alert,
    required this.bannerSeq,
    required this.hideBalances,
    required this.onDismiss,
    required this.onViewRoute,
    super.key,
  });

  final EvaluatedAlert? alert;
  final int bannerSeq;
  final bool hideBalances;
  final VoidCallback onDismiss;
  final ValueChanged<String> onViewRoute;

  @override
  State<InAppAlertBannerOverlay> createState() =>
      _InAppAlertBannerOverlayState();
}

class _InAppAlertBannerOverlayState extends State<InAppAlertBannerOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enterCtrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  Timer? _autoDismissTimer;
  int? _presentedSeq;

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOutBack));
    _fade = CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOutCubic);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.alert != null && _presentedSeq != widget.bannerSeq) {
      _presentedSeq = widget.bannerSeq;
      _presentBanner();
    }
  }

  @override
  void didUpdateWidget(covariant InAppAlertBannerOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.alert != null &&
        (widget.bannerSeq != oldWidget.bannerSeq || oldWidget.alert == null)) {
      _presentedSeq = widget.bannerSeq;
      _presentBanner();
    } else if (widget.alert == null && oldWidget.alert != null) {
      _presentedSeq = null;
      _autoDismissTimer?.cancel();
      _enterCtrl.value = 0.0;
    }
  }

  void _presentBanner() {
    _autoDismissTimer?.cancel();
    final disableAnim = MediaQuery.disableAnimationsOf(context);
    if (disableAnim) {
      _enterCtrl.value = 1.0;
      return;
    }
    _enterCtrl.forward(from: 0.0);
    _autoDismissTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _enterCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alert = widget.alert;
    if (alert == null) return const SizedBox.shrink();

    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final disableAnim = MediaQuery.disableAnimationsOf(context);

    final (
      ModernDialogAccent accent,
      IconData icon,
      Color fg,
      Color bg,
      String badgeText,
    ) = switch (alert.severity) {
      AlertSeverity.critical => (
        ModernDialogAccent.danger,
        Icons.warning_amber_rounded,
        cfo.expense,
        cfo.expenseContainer,
        'LIMIT CROSSED',
      ),
      AlertSeverity.warning => (
        ModernDialogAccent.warning,
        Icons.notifications_active_rounded,
        cfo.warning,
        cfo.warningContainer,
        alert.kind == AlertKind.lowBalance ? 'LOW BALANCE' : 'LIMIT ALERT',
      ),
      AlertSeverity.celebration => (
        ModernDialogAccent.success,
        Icons.emoji_events_rounded,
        cfo.income,
        cfo.incomeContainer,
        'MILESTONE',
      ),
      AlertSeverity.info => (
        ModernDialogAccent.brand,
        Icons.notifications_rounded,
        scheme.primary,
        scheme.primaryContainer,
        'ALERT',
      ),
    };

    final (trimStart, trimEnd, _) = FintechAccentCard.resolveTrim(
      context,
      accent,
    );
    final bodyText = alert.bodyForPrivacy(hideBalances: widget.hideBalances);

    Widget bannerCard = SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Dismissible(
              key: ValueKey<String>('live_banner_${widget.bannerSeq}'),
              direction: DismissDirection.up,
              onDismissed: (_) => widget.onDismiss(),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                child: BackdropFilter(
                  filter: disableAnim
                      ? ImageFilter.blur(sigmaX: 0, sigmaY: 0)
                      : ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: cfo.surfaceElevated.withValues(
                        alpha: isDark ? 0.94 : 0.96,
                      ),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                      border: Border.all(color: fg.withValues(alpha: 0.35)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.45 : 0.14,
                          ),
                          blurRadius: 22,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Material(
                      key: const Key('in_app_alert_banner'),
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          final route = alert.deepLinkRoute;
                          widget.onDismiss();
                          widget.onViewRoute(route);
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              height: 3,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [trimStart, trimEnd],
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                12,
                                10,
                                10,
                                11,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  IconSquircle(
                                    icon: icon,
                                    iconColor: fg,
                                    backgroundColor: bg,
                                    size: 36,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          children: [
                                            FintechStatusPill(
                                              label: badgeText,
                                              showDot: true,
                                              foreground: fg,
                                              background: bg,
                                            ),
                                            const Spacer(),
                                            GestureDetector(
                                              key: const Key(
                                                'in_app_alert_banner_close',
                                              ),
                                              onTap: widget.onDismiss,
                                              child: Padding(
                                                padding: const EdgeInsets.all(
                                                  2,
                                                ),
                                                child: Icon(
                                                  Icons.close_rounded,
                                                  size: 16,
                                                  color: cfo.subtleText,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          alert.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                        const SizedBox(height: 1.5),
                                        Text(
                                          bodyText,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: cfo.subtleText,
                                                height: 1.3,
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
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (disableAnim) {
      return Positioned(top: 0, left: 0, right: 0, child: bannerCard);
    }

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(opacity: _fade, child: bannerCard),
      ),
    );
  }
}

/// Lightweight 60fps `CustomPainter` particle burst triggered on joyful wins
/// (100% Savings Goal achieved, clean Double-Entry Ledger Audit).
/// Strictly finite (`900ms`) and completely skipped when OS reduced motion is active.
class CelebrationBurstOverlay extends StatefulWidget {
  const CelebrationBurstOverlay({required this.tick, super.key});

  final int tick;

  @override
  State<CelebrationBurstOverlay> createState() =>
      _CelebrationBurstOverlayState();
}

class _CelebrationBurstOverlayState extends State<CelebrationBurstOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  final List<_BurstParticle> _particles = [];
  bool _active = false;

  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 900),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            setState(() => _active = false);
          }
        });
  }

  @override
  void didUpdateWidget(covariant CelebrationBurstOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tick != oldWidget.tick &&
        widget.tick > 0 &&
        !MediaQuery.disableAnimationsOf(context)) {
      _spawn();
    }
  }

  void _spawn() {
    const palette = [
      Color(0xFF4F46E5),
      Color(0xFF0EA5E9),
      Color(0xFF10B981),
      Color(0xFFF59E0B),
      Color(0xFFF43F5E),
      Color(0xFF8B5CF6),
    ];
    final rng = math.Random(widget.tick * 37);
    _particles
      ..clear()
      ..addAll(
        List.generate(30, (i) {
          final angle =
              (i / 30.0) * math.pi * 2 + (rng.nextDouble() - 0.5) * 0.3;
          final speed = 130 + rng.nextDouble() * 190;
          return _BurstParticle(
            vx: math.cos(angle) * speed,
            vy: math.sin(angle) * speed - 90,
            size: 5 + rng.nextDouble() * 5,
            spin: (rng.nextDouble() - 0.5) * 8,
            color: palette[i % palette.length],
          );
        }),
      );
    setState(() => _active = true);
    _ctrl.forward(from: 0.0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_active || MediaQuery.disableAnimationsOf(context)) {
      return const SizedBox.shrink();
    }
    return Positioned.fill(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, _) => CustomPaint(
              painter: _CelebrationBurstPainter(
                particles: _particles,
                progress: _ctrl.value,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _BurstParticle {
  const _BurstParticle({
    required this.vx,
    required this.vy,
    required this.size,
    required this.spin,
    required this.color,
  });

  final double vx;
  final double vy;
  final double size;
  final double spin;
  final Color color;
}

class _CelebrationBurstPainter extends CustomPainter {
  const _CelebrationBurstPainter({
    required this.particles,
    required this.progress,
  });

  final List<_BurstParticle> particles;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, size.height * 0.34);
    final opacity = (1.0 - Curves.easeIn.transform(progress)).clamp(0.0, 1.0);
    if (opacity <= 0.01) return;

    final t = progress * 0.9;
    const gravity = 460.0;
    final paint = Paint()..style = PaintingStyle.fill;

    for (final p in particles) {
      final dx = origin.dx + p.vx * t;
      final dy = origin.dy + p.vy * t + 0.5 * gravity * t * t;
      paint.color = p.color.withValues(alpha: opacity);

      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(p.spin * t);
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: p.size,
        height: p.size * 0.55,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _CelebrationBurstPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
