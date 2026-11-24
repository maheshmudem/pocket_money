import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_tokens.dart';
import '../../core/financial_engine/currency.dart';
import '../../core/financial_engine/money.dart';

/// Accessible tabular-numeral money display widget (`DESIGN_SYSTEM.md`, `ACCESSIBILITY_GUIDELINES.md`).
/// Never relies on color alone when [semanticKind] is specified.
class MoneyText extends StatelessWidget {
  const MoneyText({
    required this.money,
    super.key,
    this.style,
    this.showPlusSign = false,
    this.masked = false,
    this.semanticKind,
    this.semanticContextLabel,
    this.maxLines = 1,
  });

  final Money money;
  final TextStyle? style;
  final bool showPlusSign;
  final bool masked;
  final String? semanticKind; // 'income', 'expense', 'transfer', or null
  final String? semanticContextLabel;
  final int maxLines;

  static String computeSemanticLabel({
    required Money money,
    required bool showPlusSign,
    required bool masked,
    String? semanticContextLabel,
  }) {
    if (masked) {
      return '${semanticContextLabel ?? 'Balance'} hidden';
    }
    final spec = CurrencyCatalog.byCode(money.currencyCode);
    final formatted = money.format(spec: spec, showPlusSign: showPlusSign);
    return '${semanticContextLabel != null ? '$semanticContextLabel ' : ''}$formatted ${money.currencyCode}';
  }

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final spec = CurrencyCatalog.byCode(money.currencyCode);
    final formatted = money.format(
      spec: spec,
      showPlusSign: showPlusSign,
      mask: masked,
    );

    final defaultColor =
        style?.color ?? Theme.of(context).colorScheme.onSurface;
    final color = switch (semanticKind) {
      'income' => cfo.income,
      'expense' => cfo.expense,
      'transfer' => cfo.transfer,
      _ => defaultColor,
    };

    final icon = switch (semanticKind) {
      'income' => Icons.arrow_downward_rounded,
      'expense' => Icons.arrow_upward_rounded,
      'transfer' => Icons.swap_horiz_rounded,
      _ => null,
    };

    final effectiveColor = semanticKind != null
        ? color
        : (style?.color ?? defaultColor);

    final effectiveStyle = (style ?? Theme.of(context).textTheme.bodyLarge)
        ?.copyWith(
          color: effectiveColor,
          fontFeatures: const [FontFeature.tabularFigures()],
        );

    final semanticLabel = computeSemanticLabel(
      money: money,
      showPlusSign: showPlusSign,
      masked: masked,
      semanticContextLabel: semanticContextLabel,
    );

    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: (effectiveStyle?.fontSize ?? 16) * 0.92,
                color: effectiveStyle?.color ?? color,
              ),
              const SizedBox(width: 3),
            ],
            Flexible(
              child: Text(
                formatted,
                style: effectiveStyle,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bounded balance interpolation widget (`MOT-001`):
/// Smoothly rolls from the previous confirmed amount to the new amount (`old → new`)
/// whenever balances update, while accessibility services receive the confirmed label immediately.
class AnimatedMoneyText extends StatefulWidget {
  const AnimatedMoneyText({
    required this.money,
    super.key,
    this.style,
    this.showPlusSign = false,
    this.masked = false,
    this.semanticKind,
    this.semanticContextLabel,
    this.maxLines = 1,
  });

  final Money money;
  final TextStyle? style;
  final bool showPlusSign;
  final bool masked;
  final String? semanticKind;
  final String? semanticContextLabel;
  final int maxLines;

  @override
  State<AnimatedMoneyText> createState() => _AnimatedMoneyTextState();
}

class _AnimatedMoneyTextState extends State<AnimatedMoneyText> {
  late double _beginMinor;

  @override
  void initState() {
    super.initState();
    _beginMinor = 0;
  }

  @override
  void didUpdateWidget(covariant AnimatedMoneyText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.money.currencyCode != widget.money.currencyCode) {
      _beginMinor = 0;
    } else if (oldWidget.money.amountMinor != widget.money.amountMinor) {
      _beginMinor = oldWidget.money.amountMinor.toDouble();
    }
  }

  @override
  Widget build(BuildContext context) {
    final semanticLabel = MoneyText.computeSemanticLabel(
      money: widget.money,
      showPlusSign: widget.showPlusSign,
      masked: widget.masked,
      semanticContextLabel: widget.semanticContextLabel,
    );

    final duration = AppMotion.resolve(context, AppMotion.emphasis);
    if (widget.masked || duration == Duration.zero) {
      return MoneyText(
        money: widget.money,
        style: widget.style,
        showPlusSign: widget.showPlusSign,
        masked: widget.masked,
        semanticKind: widget.semanticKind,
        semanticContextLabel: widget.semanticContextLabel,
        maxLines: widget.maxLines,
      );
    }

    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(
            begin: _beginMinor,
            end: widget.money.amountMinor.toDouble(),
          ),
          duration: duration,
          curve: Curves.easeOutCubic,
          builder: (context, val, _) {
            final animatedMoney = Money(
              amountMinor: val.round(),
              currencyCode: widget.money.currencyCode,
            );
            return MoneyText(
              money: animatedMoney,
              style: widget.style,
              showPlusSign: widget.showPlusSign,
              masked: false,
              semanticKind: widget.semanticKind,
              maxLines: widget.maxLines,
            );
          },
        ),
      ),
    );
  }
}

/// Bounded animated progress indicator (`MOT-005`) respecting reduced motion,
/// with smooth color morphing when transitioning across budget warning/danger tiers.
class AnimatedProgressBar extends StatelessWidget {
  const AnimatedProgressBar({
    required this.value,
    super.key,
    this.color,
    this.backgroundColor,
    this.height = 10,
  });

  final double value;
  final Color? color;
  final Color? backgroundColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 1.0);
    final cfo = context.cfoColors;
    final fillColor = color ?? Theme.of(context).colorScheme.primary;
    final trackColor = backgroundColor ?? cfo.surfaceTonal;
    final duration = AppMotion.resolve(context, AppMotion.standard);

    Widget buildBar(double progress) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        child: Container(
          height: height,
          width: double.infinity,
          color: trackColor,
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: progress,
            heightFactor: 1,
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: fillColor,
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              ),
            ),
          ),
        ),
      );
    }

    if (duration == Duration.zero) {
      return buildBar(clamped);
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: clamped),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => buildBar(v),
    );
  }
}

/// One-shot bounded fade + subtle vertical slide entrance animation (`MOT-008`).
/// Uses an Interval on a finite AnimationController (no timers, safe in widget tests)
/// and short-circuits immediately when OS reduced motion is enabled.
class StaggeredFadeSlide extends StatefulWidget {
  const StaggeredFadeSlide({required this.child, super.key, this.index = 0});

  final Widget child;
  final int index;

  @override
  State<StaggeredFadeSlide> createState() => _StaggeredFadeSlideState();
}

class _StaggeredFadeSlideState extends State<StaggeredFadeSlide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    final delayMs = math.min(widget.index * 35, 140);
    final animMs = 220;
    final totalMs = delayMs + animMs;
    final startFrac = delayMs / totalMs;

    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: totalMs),
    );
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Interval(startFrac, 1.0, curve: Curves.easeOutCubic),
    );
    _opacity = curved;
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(curved);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1.0;
    } else if (_controller.status == AnimationStatus.dismissed) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// Modern elevated fintech card with crisp border, soft shadow, and tactile press feedback.
class PressScaleCard extends StatefulWidget {
  const PressScaleCard({
    required this.child,
    super.key,
    this.onTap,
    this.padding,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius = AppSpacing.radiusLg,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderRadius;

  @override
  State<PressScaleCard> createState() => _PressScaleCardState();
}

class _PressScaleCardState extends State<PressScaleCard> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final duration = AppMotion.resolve(context, AppMotion.fast);
    final isInteractive = widget.onTap != null;

    final content = widget.padding != null
        ? Padding(padding: widget.padding!, child: widget.child)
        : widget.child;

    final resolvedBg =
        (_hovered && isInteractive && widget.backgroundColor == null)
        ? cfo.hoverSurface
        : (widget.backgroundColor ?? cfo.surfaceElevated);
    final resolvedBorder = (_hovered && isInteractive)
        ? cfo.hoverBorder
        : (widget.borderColor ?? cfo.divider);

    final cardBox = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        boxShadow: [
          BoxShadow(
            color: cfo.cardShadow,
            blurRadius: _hovered && isInteractive ? 20 : 14,
            offset: Offset(0, _hovered && isInteractive ? 6 : 4),
          ),
        ],
      ),
      child: Material(
        color: resolvedBg,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          side: BorderSide(color: resolvedBorder),
        ),
        child: isInteractive
            ? InkWell(
                onTap: widget.onTap,
                onHover: (v) {
                  if (_hovered != v) setState(() => _hovered = v);
                },
                onTapDown: (_) => setState(() => _pressed = true),
                onTapUp: (_) => setState(() => _pressed = false),
                onTapCancel: () => setState(() => _pressed = false),
                child: content,
              )
            : content,
      ),
    );

    if (!isInteractive || duration == Duration.zero) {
      return cardBox;
    }

    return AnimatedScale(
      scale: _pressed ? 0.985 : 1.0,
      duration: duration,
      curve: Curves.easeOut,
      child: cardBox,
    );
  }
}

/// Consistent squircle icon avatar container used across accounts, ledger & hub tiles.
class IconSquircle extends StatelessWidget {
  const IconSquircle({
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    super.key,
    this.size = 44,
    this.iconScale = 0.50,
  });

  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final double size;
  final double iconScale;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(size * 0.30),
      ),
      child: Icon(icon, size: size * iconScale, color: iconColor),
    );
  }
}

/// Single-shot entrance skeleton placeholder (`MOT-007`) with zero infinite shimmer loops.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.radius = AppSpacing.radiusMd,
  });

  final double width;
  final double height;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 580),
    );
    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.45, end: 0.92), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 0.92, end: 1.0), weight: 45),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      if (MediaQuery.disableAnimationsOf(context)) {
        _ctrl.value = 1.0;
      } else {
        _ctrl.forward();
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (MediaQuery.disableAnimationsOf(context)) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: cfo.surfaceTonal,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final sweep = -1.2 + (_ctrl.value * 2.4);
        final highlight = isDark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.65);
        return Opacity(
          opacity: _opacity.value,
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              gradient: LinearGradient(
                begin: Alignment(sweep - 0.6, -0.3),
                end: Alignment(sweep + 0.6, 0.3),
                colors: [cfo.surfaceTonal, highlight, cfo.surfaceTonal],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton layout shown while initial dashboard metrics are computing.
class DashboardSkeletonView extends StatelessWidget {
  const DashboardSkeletonView({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: const [
        SkeletonBox(height: 36, width: 220, radius: AppSpacing.radiusFull),
        SizedBox(height: AppSpacing.md),
        SkeletonBox(height: 184, radius: AppSpacing.radiusXl),
        SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: SkeletonBox(height: 92, radius: AppSpacing.radiusLg),
            ),
            SizedBox(width: AppSpacing.sm),
            Expanded(
              child: SkeletonBox(height: 92, radius: AppSpacing.radiusLg),
            ),
          ],
        ),
        SizedBox(height: AppSpacing.md),
        SkeletonBox(height: 220, radius: AppSpacing.radiusLg),
      ],
    );
  }
}

/// Honest sync state badge separating local commit from cloud sync (`ARCH-004`).
class SyncStatusBadge extends StatelessWidget {
  const SyncStatusBadge({required this.status, super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;

    final (IconData icon, String label, Color fg, Color bg) = switch (status) {
      'synced' => (
        Icons.cloud_done_outlined,
        'Synced',
        cfo.success,
        cfo.successContainer,
      ),
      'syncing' => (
        Icons.sync_rounded,
        'Syncing',
        cfo.transfer,
        cfo.transferContainer,
      ),
      'pending' => (
        Icons.cloud_upload_outlined,
        'Pending sync',
        cfo.warning,
        cfo.warningContainer,
      ),
      'retryable_error' => (
        Icons.cloud_off_outlined,
        'Retry scheduled',
        cfo.warning,
        cfo.warningContainer,
      ),
      'permanent_error' => (
        Icons.error_outline_rounded,
        'Sync error',
        cfo.expense,
        cfo.expenseContainer,
      ),
      'conflict' => (
        Icons.warning_amber_rounded,
        'Conflict',
        cfo.expense,
        cfo.expenseContainer,
      ),
      _ => (
        Icons.shield_outlined,
        'On-device',
        scheme.onSurfaceVariant,
        cfo.surfaceTonal,
      ),
    };

    return Semantics(
      label: 'Sync status: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    required this.icon,
    required this.title,
    required this.description,
    super.key,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: PressScaleCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: IconSquircle(
                    icon: icon,
                    iconColor: scheme.primary,
                    backgroundColor: scheme.primaryContainer,
                    size: 60,
                    iconScale: 0.48,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.cfoColors.subtleText,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton.icon(
                    onPressed: onAction,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ErrorStateView extends StatelessWidget {
  const ErrorStateView({
    required this.message,
    super.key,
    this.code,
    this.onRetry,
  });

  final String message;
  final String? code;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: PressScaleCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconSquircle(
                  icon: Icons.error_outline_rounded,
                  iconColor: cfo.expense,
                  backgroundColor: cfo.expenseContainer,
                  size: 60,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                if (code != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Code: $code',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: cfo.subtleText),
                  ),
                ],
                if (onRetry != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try again'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    super.key,
    this.subtitle,
    this.trailingLabel,
    this.onTrailingPressed,
  });

  final String title;
  final String? subtitle;
  final String? trailingLabel;
  final VoidCallback? onTrailingPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: context.cfoColors.subtleText,
                  ),
                ),
            ],
          ),
        ),
        if (trailingLabel != null && onTrailingPressed != null)
          TextButton(onPressed: onTrailingPressed, child: Text(trailingLabel!)),
      ],
    );
  }
}

/// Animated radial arc gauge for Financial Health & Vault Readiness scores (`MOT-005`).
/// Respects OS reduced-motion preferences and uses tabular numerals.
class RadialScoreGauge extends StatelessWidget {
  const RadialScoreGauge({
    required this.score,
    required this.label,
    required this.activeColor,
    super.key,
    this.secondaryColor,
    this.trackColor,
    this.textColor,
    this.subtitleColor,
    this.size = 104,
    this.strokeWidth = 9,
    this.masked = false,
  });

  final int score;
  final String label;
  final Color activeColor;
  final Color? secondaryColor;
  final Color? trackColor;
  final Color? textColor;
  final Color? subtitleColor;
  final double size;
  final double strokeWidth;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final clamped = score.clamp(0, 100);
    final cfo = context.cfoColors;
    final resolvedTrack = trackColor ?? cfo.surfaceTonal;
    final resolvedText = textColor ?? Theme.of(context).colorScheme.onSurface;
    final resolvedSub = subtitleColor ?? cfo.subtleText;
    final duration = AppMotion.resolve(context, AppMotion.emphasis);
    final targetFraction = masked ? 0.0 : clamped / 100.0;

    Widget buildGauge(double progress) {
      final shownScore = (progress * 100).round();
      return SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RadialArcPainter(
            progress: progress,
            strokeWidth: strokeWidth,
            trackColor: resolvedTrack,
            startColor: activeColor,
            endColor: secondaryColor ?? activeColor,
          ),
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(strokeWidth + 4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      masked ? '••' : '$shownScore',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: resolvedText,
                            fontWeight: FontWeight.w800,
                            height: 1.0,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label.toUpperCase(),
                      maxLines: 1,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: resolvedSub,
                        fontWeight: FontWeight.w700,
                        fontSize: 9.5,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: Semantics(
        label: masked ? '$label hidden' : '$label $clamped out of 100',
        child: ExcludeSemantics(
          child: duration == Duration.zero
              ? buildGauge(targetFraction)
              : TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.0, end: targetFraction),
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => buildGauge(v),
                ),
        ),
      ),
    );
  }
}

class _RadialArcPainter extends CustomPainter {
  const _RadialArcPainter({
    required this.progress,
    required this.strokeWidth,
    required this.trackColor,
    required this.startColor,
    required this.endColor,
  });

  final double progress;
  final double strokeWidth;
  final Color trackColor;
  final Color startColor;
  final Color endColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    if (radius <= 0) return;

    const startAngle = 140 * math.pi / 180;
    const totalSweep = 260 * math.pi / 180;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, startAngle, totalSweep, false, trackPaint);

    final clamped = progress.clamp(0.0, 1.0);
    if (clamped <= 0.005) return;

    final sweep = totalSweep * clamped;
    const capPad = 0.14;
    final activePaint = Paint()
      ..shader = SweepGradient(
        startAngle: 0.0,
        endAngle: totalSweep + capPad,
        colors: [startColor, startColor, endColor],
        stops: const [0.0, 0.06, 1.0],
        tileMode: TileMode.clamp,
        transform: const GradientRotation(startAngle - capPad),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, startAngle, sweep, false, activePaint);
  }

  @override
  bool shouldRepaint(covariant _RadialArcPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.startColor != startColor ||
      oldDelegate.endColor != endColor;
}

/// Human-friendly date display utilities keeping UTC audit strings clean in UI.
abstract final class UiDateFormatter {
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String shortDayMonthYear(String isoUtc) {
    final dt = DateTime.tryParse(isoUtc)?.toLocal();
    if (dt == null) {
      return isoUtc.length >= 10 ? isoUtc.substring(0, 10) : isoUtc;
    }
    return '${dt.day} ${_months[dt.month - 1]} ${dt.year}';
  }

  static String shortDayMonth(String isoUtc) {
    final dt = DateTime.tryParse(isoUtc)?.toLocal();
    if (dt == null) {
      return isoUtc.length >= 10 ? isoUtc.substring(0, 10) : isoUtc;
    }
    return '${dt.day} ${_months[dt.month - 1]}';
  }

  static String relativeHeader(String isoUtc, {DateTime? now}) {
    final dt = DateTime.tryParse(isoUtc)?.toLocal();
    if (dt == null) {
      return isoUtc.length >= 10 ? isoUtc.substring(0, 10) : isoUtc;
    }
    final ref = (now ?? DateTime.now()).toLocal();
    final today = DateTime(ref.year, ref.month, ref.day);
    final itemDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(itemDay).inDays;
    if (diff == 0) return 'Today • ${dt.day} ${_months[dt.month - 1]}';
    if (diff == 1) return 'Yesterday • ${dt.day} ${_months[dt.month - 1]}';
    return '${dt.day} ${_months[dt.month - 1]} ${dt.year}';
  }
}

/// Compact, razor-aligned navigation / action row for Profile & Settings cards.
/// Enforces a uniform 34px [IconSquircle] rail and crisp 13.5sp/11.5sp hierarchy
/// so every card aligns down a single vertical column with zero stock ListTile bloat.
class FintechSettingRow extends StatelessWidget {
  const FintechSettingRow({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    super.key,
    this.subtitle,
    this.trailing,
    this.showChevron = true,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool showChevron;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final textScale = MediaQuery.textScalerOf(context).scale(14.0) / 14.0;
    final titleLines = textScale >= 1.45 ? 2 : 1;

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconSquircle(
            icon: icon,
            iconColor: iconColor,
            backgroundColor: iconBackground,
            size: 34,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: titleLines,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cfo.subtleText,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          if (showChevron && onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 18, color: cfo.subtleText),
          ],
        ],
      ),
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

/// Compact, razor-aligned toggle row sharing the exact 34px [IconSquircle] rail
/// and typography metrics of [FintechSettingRow].
class FintechSwitchRow extends StatelessWidget {
  const FintechSwitchRow({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    required this.value,
    required this.onChanged,
    super.key,
    this.subtitle,
    this.bottomChild,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget? bottomChild;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final textScale = MediaQuery.textScalerOf(context).scale(14.0) / 14.0;
    final titleLines = textScale >= 1.45 ? 2 : 1;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onChanged(!value),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  IconSquircle(
                    icon: icon,
                    iconColor: iconColor,
                    backgroundColor: iconBackground,
                    size: 34,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: titleLines,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.1,
                              ),
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: cfo.subtleText,
                                  fontWeight: FontWeight.w500,
                                  height: 1.3,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Transform.scale(
                    scale: 0.86,
                    alignment: Alignment.centerRight,
                    child: Switch(
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      value: value,
                      onChanged: onChanged,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (bottomChild != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: bottomChild!,
          ),
      ],
    );
  }
}

/// Full-width 3-column Light / Dark / Auto visual theme mode picker with
/// dual-tone color swatches and animated active border.
class FintechThemeModePicker extends StatelessWidget {
  const FintechThemeModePicker({
    required this.selectedMode,
    required this.onChanged,
    super.key,
  });

  final ThemeMode selectedMode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cfo = context.cfoColors;
    final duration = AppMotion.resolve(context, AppMotion.fast);

    const options = [
      (
        key: Key('theme_mode_light'),
        mode: ThemeMode.light,
        label: 'Light',
        icon: Icons.light_mode_rounded,
        swatchA: Color(0xFFF8FAFC),
        swatchB: Color(0xFF4F46E5),
      ),
      (
        key: Key('theme_mode_dark'),
        mode: ThemeMode.dark,
        label: 'Dark',
        icon: Icons.dark_mode_rounded,
        swatchA: Color(0xFF0B0F1A),
        swatchB: Color(0xFF818CF8),
      ),
      (
        key: Key('theme_mode_auto'),
        mode: ThemeMode.system,
        label: 'Auto',
        icon: Icons.brightness_auto_rounded,
        swatchA: Color(0xFFF8FAFC),
        swatchB: Color(0xFF0F172A),
      ),
    ];

    return Row(
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Builder(
              builder: (context) {
                final opt = options[i];
                final active = selectedMode == opt.mode;
                return Material(
                  color: active ? scheme.primaryContainer : cfo.surfaceTonal,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  child: InkWell(
                    key: opt.key,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    onTap: () => onChanged(opt.mode),
                    child: AnimatedContainer(
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(
                        vertical: 9,
                        horizontal: 8,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMd,
                        ),
                        border: Border.all(
                          color: active ? scheme.primary : cfo.divider,
                          width: active ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 15,
                                height: 15,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [opt.swatchA, opt.swatchB],
                                  ),
                                  border: Border.all(color: cfo.divider),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                opt.icon,
                                size: 16,
                                color: active ? scheme.primary : cfo.subtleText,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              opt.label,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: active
                                        ? scheme.onPrimaryContainer
                                        : scheme.onSurface,
                                    fontWeight: active
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

/// Option descriptor for [FintechSegmentedControl].
final class FintechSegmentOption<T> {
  const FintechSegmentOption({
    required this.value,
    required this.label,
    this.icon,
    this.badgeCount,
  });

  final T value;
  final String label;
  final IconData? icon;
  final int? badgeCount;
}

/// Reusable animated sliding-pill segmented control replacing duplicate filter
/// bars and stock Material [SegmentedButton] widgets across the app.
class FintechSegmentedControl<T> extends StatelessWidget {
  const FintechSegmentedControl({
    required this.options,
    required this.selected,
    required this.onChanged,
    super.key,
    this.height = 38,
  });

  final List<FintechSegmentOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final duration = AppMotion.resolve(context, AppMotion.fast);
    final selectedIdx = options
        .indexWhere((o) => o.value == selected)
        .clamp(0, math.max(0, options.length - 1));
    final alignmentX = options.length <= 1
        ? 0.0
        : -1.0 + (2.0 * selectedIdx / (options.length - 1));

    return Container(
      height: height,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: cfo.surfaceTonal,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: cfo.divider),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segWidth = options.isEmpty
              ? constraints.maxWidth
              : constraints.maxWidth / options.length;
          return Stack(
            children: [
              if (options.isNotEmpty)
                AnimatedAlign(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  alignment: Alignment(alignmentX, 0),
                  child: Container(
                    width: segWidth,
                    height: double.infinity,
                    decoration: BoxDecoration(
                      color: cfo.surfaceElevated,
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusSm + 1,
                      ),
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.25),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: cfo.cardShadow,
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              Row(
                children: [
                  for (final opt in options)
                    Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusSm,
                          ),
                          onTap: () {
                            if (opt.value != selected) {
                              HapticFeedback.selectionClick();
                              onChanged(opt.value);
                            }
                          },
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (opt.icon != null) ...[
                                      Icon(
                                        opt.icon,
                                        size: 14,
                                        color: opt.value == selected
                                            ? scheme.primary
                                            : cfo.subtleText,
                                      ),
                                      const SizedBox(width: 4),
                                    ],
                                    Text(
                                      opt.label,
                                      maxLines: 1,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: opt.value == selected
                                                ? scheme.onSurface
                                                : cfo.subtleText,
                                            fontWeight: opt.value == selected
                                                ? FontWeight.w800
                                                : FontWeight.w600,
                                          ),
                                    ),
                                    if (opt.badgeCount != null &&
                                        opt.badgeCount! > 0) ...[
                                      const SizedBox(width: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: opt.value == selected
                                              ? scheme.primaryContainer
                                              : cfo.divider,
                                          borderRadius: BorderRadius.circular(
                                            AppSpacing.radiusFull,
                                          ),
                                        ),
                                        child: Text(
                                          '${opt.badgeCount}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w800,
                                                color: opt.value == selected
                                                    ? scheme.primary
                                                    : cfo.subtleText,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures(),
                                                ],
                                              ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Compact tonal-surface switch toggle for dialogs and forms, replacing raw
/// Material [SwitchListTile] boilerplate with consistent typography & alignment.
class FintechSwitchCard extends StatelessWidget {
  const FintechSwitchCard({
    required this.title,
    required this.value,
    required this.onChanged,
    super.key,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.iconBackground,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final Color? iconBackground;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final enabled = onChanged != null;

    return Material(
      color: cfo.surfaceTonal,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        side: BorderSide(color: cfo.divider.withValues(alpha: 0.75)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                onChanged!(!value);
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
          child: Row(
            children: [
              if (icon != null) ...[
                IconSquircle(
                  icon: icon!,
                  iconColor: iconColor ?? scheme.primary,
                  backgroundColor: iconBackground ?? scheme.primaryContainer,
                  size: 32,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: enabled ? null : cfo.subtleText,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cfo.subtleText,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Transform.scale(
                scale: 0.84,
                alignment: Alignment.centerRight,
                child: Switch(
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  value: value,
                  onChanged: enabled
                      ? (v) {
                          HapticFeedback.selectionClick();
                          onChanged!(v);
                        }
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum FintechToastTone { info, success, warning, danger }

/// Displays a consistent floating toast notification with semantic icon and
/// optional action button (e.g., Undo).
void showFintechToast(
  BuildContext context,
  String message, {
  FintechToastTone tone = FintechToastTone.info,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 3),
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final cfo = context.cfoColors;
  final scheme = Theme.of(context).colorScheme;
  final (IconData icon, Color tint) = switch (tone) {
    FintechToastTone.success => (Icons.check_circle_rounded, cfo.income),
    FintechToastTone.warning => (Icons.warning_amber_rounded, cfo.warning),
    FintechToastTone.danger => (Icons.error_outline_rounded, cfo.expense),
    FintechToastTone.info => (Icons.info_outline_rounded, scheme.primary),
  };

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: duration,
        content: Row(
          children: [
            Icon(icon, size: 18, color: tint),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        action: actionLabel != null && onAction != null
            ? SnackBarAction(label: actionLabel, onPressed: onAction)
            : null,
      ),
    );
}
