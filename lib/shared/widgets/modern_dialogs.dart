import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_tokens.dart';
import 'fintech_widgets.dart';

/// Semantic accent presets for [FintechAccentCard] and [ModernDialogShell].
enum ModernDialogAccent { brand, success, warning, danger }

/// Reusable theme-native elevated card with subtle top-right ambient radial sheen,
/// uniform crisp `1px` hairline border, and optional integrated hairline-separated [bottomBar].
class FintechAccentCard extends StatelessWidget {
  const FintechAccentCard({
    required this.child,
    super.key,
    this.bottomBar,
    this.padding = const EdgeInsets.fromLTRB(16, 13, 16, 13),
    this.borderRadius = AppSpacing.radiusXl,
    this.accent = ModernDialogAccent.brand,
    this.showAmbientGlow = true,
  });

  final Widget child;
  final Widget? bottomBar;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final ModernDialogAccent accent;
  final bool showAmbientGlow;

  static (Color start, Color end, Color glow) resolveTrim(
    BuildContext context,
    ModernDialogAccent accent,
  ) {
    final cfo = context.cfoColors;
    return switch (accent) {
      ModernDialogAccent.brand => (
        cfo.heroGradientEnd,
        cfo.accentCyan,
        cfo.heroGradientEnd,
      ),
      ModernDialogAccent.success => (cfo.income, cfo.accentCyan, cfo.income),
      ModernDialogAccent.warning => (
        cfo.warning,
        const Color(0xFFF59E0B),
        cfo.warning,
      ),
      ModernDialogAccent.danger => (cfo.expense, cfo.warning, cfo.expense),
    };
  }

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (_, _, glowColor) = resolveTrim(context, accent);
    final duration = AppMotion.resolve(context, AppMotion.standard);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: cfo.cardShadow,
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: cfo.surfaceElevated,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          side: BorderSide(color: cfo.divider),
        ),
        child: Stack(
          children: [
            if (showAmbientGlow)
              Positioned.fill(
                child: AnimatedContainer(
                  duration: duration,
                  curve: AppMotion.curveStandard,
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0.95, -0.85),
                      radius: 1.25,
                      colors: [
                        glowColor.withValues(alpha: isDark ? 0.16 : 0.055),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(padding: padding, child: child),
                if (bottomBar != null) ...[
                  Divider(height: 1, color: cfo.divider),
                  bottomBar!,
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact pill status badge with an optional semantic status dot or leading icon.
class FintechStatusPill extends StatelessWidget {
  const FintechStatusPill({
    required this.label,
    required this.foreground,
    required this.background,
    super.key,
    this.icon,
    this.showDot = false,
  });

  final String label;
  final Color foreground;
  final Color background;
  final IconData? icon;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.resolve(context, AppMotion.fast);
    return AnimatedContainer(
      duration: duration,
      curve: AppMotion.curveStandard,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11.5, color: foreground),
            const SizedBox(width: 4),
          ] else if (showDot) ...[
            Container(
              width: 5.5,
              height: 5.5,
              decoration: BoxDecoration(
                color: foreground,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4.5),
          ],
          Flexible(
            child: AnimatedSwitcher(
              duration: duration,
              child: Text(
                label,
                key: ValueKey<String>(label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                  fontSize: 10.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Action descriptor for [FintechFlatActionBar].
class FintechFlatActionItem {
  const FintechFlatActionItem({
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

/// Sleek flat hairline-separated horizontal action strip used inside cards
/// (`Spend | Receive | Transfer | Vault`, `Track Expense | Set Budget`, etc.).
class FintechFlatActionBar extends StatelessWidget {
  const FintechFlatActionBar({
    required this.items,
    super.key,
    this.verticalPadding = 10.5,
    this.iconSize = 14.5,
    this.fontSize = 11.5,
  });

  final List<FintechFlatActionItem> items;
  final double verticalPadding;
  final double iconSize;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    return IntrinsicHeight(
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              VerticalDivider(
                width: 1,
                thickness: 1,
                indent: 7,
                endIndent: 7,
                color: cfo.divider,
              ),
            Expanded(
              child: InkWell(
                key: items[i].key,
                onTap: () {
                  HapticFeedback.selectionClick();
                  items[i].onTap();
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: verticalPadding,
                    horizontal: 5,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        items[i].icon,
                        size: iconSize,
                        color: items[i].color,
                      ),
                      const SizedBox(width: 4.5),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            items[i].label,
                            maxLines: 1,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: fontSize,
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

/// Launches a modern animated Neo-Fintech dialog with subtle backdrop blur,
/// spring-scale entrance, and automatic reduced-motion handling.
Future<T?> showModernDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final duration = AppMotion.resolve(context, AppMotion.standard);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final animate = duration > Duration.zero;

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: isDark ? 0.68 : 0.44),
    transitionDuration: animate ? duration : const Duration(milliseconds: 1),
    pageBuilder: (dialogCtx, _, _) => builder(dialogCtx),
    transitionBuilder: (dialogCtx, anim, _, child) {
      if (!animate) return child;
      final fade = CurvedAnimation(
        parent: anim,
        curve: AppMotion.curveEmphasized,
        reverseCurve: AppMotion.curveExit,
      );
      final slide = Tween<Offset>(
        begin: const Offset(0, 0.028),
        end: Offset.zero,
      ).animate(fade);
      final scale = Tween<double>(begin: 0.955, end: 1.0).animate(
        CurvedAnimation(
          parent: anim,
          curve: AppMotion.curveSpring,
          reverseCurve: AppMotion.curveExit,
        ),
      );
      return BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 4.0 * fade.value,
          sigmaY: 4.0 * fade.value,
        ),
        child: FadeTransition(
          opacity: fade,
          child: SlideTransition(
            position: slide,
            child: ScaleTransition(scale: scale, child: child),
          ),
        ),
      );
    },
  );
}

/// Reusable, trendy Neo-Fintech custom popup box replacing dated raw `AlertDialog`s.
/// Features a `3px` accent hairline trim, icon squircle header, circular close button,
/// keyboard-safe scrollable body, and full-height modern rounded footer actions.
class ModernDialogShell extends StatelessWidget {
  const ModernDialogShell({
    required this.title,
    required this.child,
    super.key,
    this.subtitle,
    this.icon,
    this.accent = ModernDialogAccent.brand,
    this.maxWidth = 430,
    this.showCloseButton = true,
    this.cancelLabel = 'Cancel',
    this.onCancel,
    this.confirmLabel,
    this.confirmKey,
    this.onConfirm,
    this.isConfirmLoading = false,
    this.footer,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final ModernDialogAccent accent;
  final double maxWidth;
  final bool showCloseButton;
  final Widget child;
  final String? cancelLabel;
  final VoidCallback? onCancel;
  final String? confirmLabel;
  final Key? confirmKey;
  final VoidCallback? onConfirm;
  final bool isConfirmLoading;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (_, _, glowColor) = FintechAccentCard.resolveTrim(context, accent);

    final (
      Color iconFg,
      Color iconBg,
      Color primaryBtnBg,
      Color primaryBtnFg,
    ) = switch (accent) {
      ModernDialogAccent.brand => (
        scheme.primary,
        scheme.primaryContainer,
        scheme.primary,
        scheme.onPrimary,
      ),
      ModernDialogAccent.success => (
        cfo.income,
        cfo.incomeContainer,
        cfo.income,
        Colors.white,
      ),
      ModernDialogAccent.warning => (
        cfo.warning,
        cfo.warningContainer,
        cfo.warning,
        Colors.white,
      ),
      ModernDialogAccent.danger => (
        cfo.expense,
        cfo.expenseContainer,
        cfo.expense,
        Colors.white,
      ),
    };

    final viewInsets = MediaQuery.viewInsetsOf(context);
    final screenHeight = MediaQuery.sizeOf(context).height;

    return AnimatedPadding(
      duration: AppMotion.resolve(context, AppMotion.fast),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.fromLTRB(
        20,
        24,
        20,
        viewInsets.bottom > 0 ? viewInsets.bottom + 16 : 24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxWidth,
            maxHeight: (screenHeight - viewInsets.bottom - 48).clamp(
              240.0,
              760.0,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.55 : 0.16),
                  blurRadius: 32,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Material(
              color: cfo.surfaceElevated,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                side: BorderSide(color: cfo.divider),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0.95, -0.9),
                          radius: 1.2,
                          colors: [
                            glowColor.withValues(alpha: isDark ? 0.14 : 0.05),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Sleek header with IconSquircle + Title/Subtitle + Close Pill
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 14, 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (icon != null) ...[
                              IconSquircle(
                                icon: icon!,
                                iconColor: iconFg,
                                backgroundColor: iconBg,
                                size: 40,
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 1),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 17,
                                            letterSpacing: -0.25,
                                          ),
                                    ),
                                    if (subtitle != null &&
                                        subtitle!.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        subtitle!,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: cfo.subtleText,
                                              height: 1.35,
                                            ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            if (showCloseButton) ...[
                              const SizedBox(width: 8),
                              Material(
                                color: cfo.surfaceTonal,
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: isConfirmLoading
                                      ? null
                                      : (onCancel ??
                                            () => Navigator.of(context).pop()),
                                  child: SizedBox(
                                    width: 30,
                                    height: 30,
                                    child: Icon(
                                      Icons.close_rounded,
                                      size: 16,
                                      color: cfo.subtleText,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Divider(height: 1, color: cfo.divider),

                      // Scrollable content body
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                          child: child,
                        ),
                      ),

                      // Clean hairline-separated footer
                      if (footer != null) ...[
                        Divider(height: 1, color: cfo.divider),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                          child: footer!,
                        ),
                      ] else if (confirmLabel != null ||
                          cancelLabel != null) ...[
                        Divider(height: 1, color: cfo.divider),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                          child: Row(
                            children: [
                              if (cancelLabel != null)
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(0, 44),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      side: BorderSide(color: cfo.divider),
                                      foregroundColor: cfo.subtleText,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          AppSpacing.radiusMd,
                                        ),
                                      ),
                                    ),
                                    onPressed: isConfirmLoading
                                        ? null
                                        : (onCancel ??
                                              () =>
                                                  Navigator.of(context).pop()),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(cancelLabel!),
                                    ),
                                  ),
                                ),
                              if (cancelLabel != null && confirmLabel != null)
                                const SizedBox(width: 10),
                              if (confirmLabel != null)
                                Expanded(
                                  flex: 2,
                                  child: FilledButton(
                                    key: confirmKey,
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size(0, 44),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                      backgroundColor: primaryBtnBg,
                                      foregroundColor: primaryBtnFg,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          AppSpacing.radiusMd,
                                        ),
                                      ),
                                    ),
                                    onPressed: isConfirmLoading
                                        ? null
                                        : onConfirm,
                                    child: isConfirmLoading
                                        ? SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.2,
                                              color: primaryBtnFg,
                                            ),
                                          )
                                        : FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              confirmLabel!,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Reusable 1-call confirmation dialog built on [showModernDialog] + [ModernDialogShell].
Future<bool?> showModernConfirmDialog({
  required BuildContext context,
  required String title,
  required String confirmLabel,
  String? subtitle,
  String? message,
  Widget? body,
  IconData icon = Icons.help_outline_rounded,
  ModernDialogAccent accent = ModernDialogAccent.brand,
  String cancelLabel = 'Cancel',
  Key? confirmKey,
  bool canConfirm = true,
}) {
  return showModernDialog<bool>(
    context: context,
    builder: (dialogCtx) => ModernDialogShell(
      title: title,
      subtitle: subtitle,
      icon: icon,
      accent: accent,
      cancelLabel: cancelLabel,
      onCancel: () => Navigator.of(dialogCtx).pop(false),
      confirmLabel: confirmLabel,
      confirmKey: confirmKey,
      onConfirm: canConfirm
          ? () {
              HapticFeedback.selectionClick();
              Navigator.of(dialogCtx).pop(true);
            }
          : null,
      child:
          body ??
          Text(
            message ?? '',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.cfoColors.subtleText,
              height: 1.45,
            ),
          ),
    ),
  );
}
