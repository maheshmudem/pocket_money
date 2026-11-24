import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import 'fintech_widgets.dart';

/// Centers enterprise page content cleanly within a bounded max width and
/// applies breakpoint-appropriate outer padding across mobile, tablet, and desktop.
class EnterprisePageContainer extends StatelessWidget {
  const EnterprisePageContainer({
    required this.child,
    super.key,
    this.maxWidth = AppBreakpoints.maxContentWidth,
  });

  final Widget child;
  final double maxWidth;

  static EdgeInsets responsivePadding(
    BuildContext context, {
    double top = AppSpacing.md,
    double bottom = 36,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = width >= AppBreakpoints.desktop
        ? AppSpacing.xxl
        : width >= AppBreakpoints.tablet
        ? AppSpacing.xl
        : AppSpacing.md;
    return EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom);
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Consistent sub-page AppBar featuring a clean 1px architectural hairline divider
/// separating header chrome from scrolling content.
class EnterpriseAppBar extends StatelessWidget implements PreferredSizeWidget {
  const EnterpriseAppBar({
    required this.title,
    super.key,
    this.actions,
    this.bottom,
    this.automaticallyImplyLeading = true,
  });

  final Widget title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool automaticallyImplyLeading;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0) + 1);

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    return AppBar(
      automaticallyImplyLeading: automaticallyImplyLeading,
      backgroundColor: cfo.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      title: title,
      actions: actions,
      bottom: bottom != null
          ? PreferredSize(
              preferredSize: Size.fromHeight(bottom!.preferredSize.height + 1),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: cfo.divider)),
                ),
                child: bottom,
              ),
            )
          : PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Divider(height: 1, thickness: 1, color: cfo.divider),
            ),
    );
  }
}

/// Opens a responsive adaptive modal:
/// - Bottom sheet (`isScrollControlled: true`, drag handle) on compact screens (`< 680dp`)
/// - Elevated centered desktop/tablet `Dialog` (`>= 680dp`) with constrained max width.
Future<T?> showEnterpriseModal<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double maxWidth = 540,
}) {
  final size = MediaQuery.sizeOf(context);
  if (size.width >= 680) {
    final cfo = context.cfoColors;
    final disableAnim = MediaQuery.disableAnimationsOf(context);
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.48),
      transitionDuration: disableAnim
          ? Duration.zero
          : const Duration(milliseconds: 220),
      pageBuilder: (dialogCtx, _, _) => Dialog(
        backgroundColor: cfo.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(AppSpacing.xl),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          side: BorderSide(color: cfo.divider),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxWidth,
            maxHeight: size.height * 0.88,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 3,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [cfo.heroGradientEnd, cfo.accentCyan],
                  ),
                ),
              ),
              Flexible(child: builder(dialogCtx)),
            ],
          ),
        ),
      ),
      transitionBuilder: (ctx, animation, _, child) {
        if (disableAnim) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: builder,
  );
}

/// Consistent modal sheet / dialog header row with optional icon badge and close control.
class EnterpriseModalHeader extends StatelessWidget {
  const EnterpriseModalHeader({
    required this.title,
    super.key,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.iconBackgroundColor,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final Color? iconBackgroundColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cfo = context.cfoColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              IconSquircle(
                icon: icon!,
                iconColor: iconColor ?? scheme.primary,
                backgroundColor: iconBackgroundColor ?? scheme.primaryContainer,
                size: 40,
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: cfo.subtleText),
                    ),
                ],
              ),
            ),
            Material(
              color: cfo.surfaceTonal,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.of(context).pop(),
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Tooltip(
                    message: 'Close',
                    child: Icon(
                      Icons.close_rounded,
                      size: 17,
                      color: cfo.subtleText,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        const Divider(),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

/// Uniform enterprise KPI card with leading icon badge, label, value widget, and optional chip.
class EnterpriseKpiCard extends StatelessWidget {
  const EnterpriseKpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    super.key,
    this.trailingBadge,
    this.onTap,
  });

  final String label;
  final Widget value;
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final Widget? trailingBadge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    return PressScaleCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconSquircle(
                icon: icon,
                iconColor: iconColor,
                backgroundColor: iconBackground,
                size: 34,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: cfo.subtleText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ?trailingBadge,
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          value,
        ],
      ),
    );
  }
}
