import 'package:flutter/material.dart';

/// Semantic Neo-Fintech color extension following `DESIGN_SYSTEM.md` (`UX-001`).
/// Never relies on color alone — always paired with directional icons/labels in shared widgets.
@immutable
final class PocketCfoColors extends ThemeExtension<PocketCfoColors> {
  const PocketCfoColors({
    required this.income,
    required this.incomeContainer,
    required this.expense,
    required this.expenseContainer,
    required this.warning,
    required this.warningContainer,
    required this.success,
    required this.successContainer,
    required this.transfer,
    required this.transferContainer,
    required this.surfaceElevated,
    required this.surfaceTonal,
    required this.subtleText,
    required this.divider,
    required this.heroGradientStart,
    required this.heroGradientEnd,
    required this.accentCyan,
    required this.cardShadow,
    required this.hoverBorder,
    required this.hoverSurface,
  });

  final Color income;
  final Color incomeContainer;
  final Color expense;
  final Color expenseContainer;
  final Color warning;
  final Color warningContainer;
  final Color success;
  final Color successContainer;
  final Color transfer;
  final Color transferContainer;
  final Color surfaceElevated;
  final Color surfaceTonal;
  final Color subtleText;
  final Color divider;
  final Color heroGradientStart;
  final Color heroGradientEnd;
  final Color accentCyan;
  final Color cardShadow;
  final Color hoverBorder;
  final Color hoverSurface;

  static const light = PocketCfoColors(
    income: Color(0xFF047857),
    incomeContainer: Color(0xFFE6F7F1),
    expense: Color(0xFFBE123C),
    expenseContainer: Color(0xFFFDECEF),
    warning: Color(0xFFB47B1C),
    warningContainer: Color(0xFFFDF5E2),
    success: Color(0xFF047857),
    successContainer: Color(0xFFE6F7F1),
    transfer: Color(0xFF1A4596),
    transferContainer: Color(0xFFEBF1FF),
    surfaceElevated: Color(0xFFFFFFFF),
    surfaceTonal: Color(0xFFF0F2F8),
    subtleText: Color(0xFF5A647B),
    divider: Color(0xFFE3E7F2),
    heroGradientStart: Color(0xFF081530),
    heroGradientEnd: Color(0xFF173875),
    accentCyan: Color(0xFFC8962E),
    cardShadow: Color(0x110B1B3D),
    hoverBorder: Color(0xFFC6D0E5),
    hoverSurface: Color(0xFFF8F9FD),
  );

  static const dark = PocketCfoColors(
    income: Color(0xFF2DD4A8),
    incomeContainer: Color(0xFF0A2A22),
    expense: Color(0xFFFB7185),
    expenseContainer: Color(0xFF34131E),
    warning: Color(0xFFE8C468),
    warningContainer: Color(0xFF2D220E),
    success: Color(0xFF2DD4A8),
    successContainer: Color(0xFF0A2A22),
    transfer: Color(0xFF6DA6FF),
    transferContainer: Color(0xFF122344),
    surfaceElevated: Color(0xFF0F1626),
    surfaceTonal: Color(0xFF162036),
    subtleText: Color(0xFF93A1BC),
    divider: Color(0xFF1F2D49),
    heroGradientStart: Color(0xFF0A1836),
    heroGradientEnd: Color(0xFF193C7D),
    accentCyan: Color(0xFFE8C468),
    cardShadow: Color(0x5A020612),
    hoverBorder: Color(0xFF2E4166),
    hoverSurface: Color(0xFF141D31),
  );

  @override
  PocketCfoColors copyWith({
    Color? income,
    Color? incomeContainer,
    Color? expense,
    Color? expenseContainer,
    Color? warning,
    Color? warningContainer,
    Color? success,
    Color? successContainer,
    Color? transfer,
    Color? transferContainer,
    Color? surfaceElevated,
    Color? surfaceTonal,
    Color? subtleText,
    Color? divider,
    Color? heroGradientStart,
    Color? heroGradientEnd,
    Color? accentCyan,
    Color? cardShadow,
    Color? hoverBorder,
    Color? hoverSurface,
  }) {
    return PocketCfoColors(
      income: income ?? this.income,
      incomeContainer: incomeContainer ?? this.incomeContainer,
      expense: expense ?? this.expense,
      expenseContainer: expenseContainer ?? this.expenseContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      transfer: transfer ?? this.transfer,
      transferContainer: transferContainer ?? this.transferContainer,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceTonal: surfaceTonal ?? this.surfaceTonal,
      subtleText: subtleText ?? this.subtleText,
      divider: divider ?? this.divider,
      heroGradientStart: heroGradientStart ?? this.heroGradientStart,
      heroGradientEnd: heroGradientEnd ?? this.heroGradientEnd,
      accentCyan: accentCyan ?? this.accentCyan,
      cardShadow: cardShadow ?? this.cardShadow,
      hoverBorder: hoverBorder ?? this.hoverBorder,
      hoverSurface: hoverSurface ?? this.hoverSurface,
    );
  }

  @override
  PocketCfoColors lerp(
    covariant ThemeExtension<PocketCfoColors>? other,
    double t,
  ) {
    if (other is! PocketCfoColors) return this;
    return PocketCfoColors(
      income: Color.lerp(income, other.income, t)!,
      incomeContainer: Color.lerp(incomeContainer, other.incomeContainer, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      expenseContainer: Color.lerp(
        expenseContainer,
        other.expenseContainer,
        t,
      )!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      success: Color.lerp(success, other.success, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      transfer: Color.lerp(transfer, other.transfer, t)!,
      transferContainer: Color.lerp(
        transferContainer,
        other.transferContainer,
        t,
      )!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      surfaceTonal: Color.lerp(surfaceTonal, other.surfaceTonal, t)!,
      subtleText: Color.lerp(subtleText, other.subtleText, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      heroGradientStart: Color.lerp(
        heroGradientStart,
        other.heroGradientStart,
        t,
      )!,
      heroGradientEnd: Color.lerp(heroGradientEnd, other.heroGradientEnd, t)!,
      accentCyan: Color.lerp(accentCyan, other.accentCyan, t)!,
      cardShadow: Color.lerp(cardShadow, other.cardShadow, t)!,
      hoverBorder: Color.lerp(hoverBorder, other.hoverBorder, t)!,
      hoverSurface: Color.lerp(hoverSurface, other.hoverSurface, t)!,
    );
  }
}

/// 4-point spacing & refined Neo-Fintech shape tokens (`DESIGN_SYSTEM.md`).
abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 40;

  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 20;
  static const double radiusXl = 28;
  static const double radiusFull = 999;
}

/// Responsive layout breakpoints and max content widths across mobile, tablet, laptop & desktop.
abstract final class AppBreakpoints {
  static const double tablet = 600;
  static const double medium = 760;
  static const double expanded = 880;
  static const double desktop = 1024;
  static const double maxDashboardWidth = 1180;
  static const double maxContentWidth = 1040;
  static const double maxReadingWidth = 920;
}

/// Motion duration & curve tokens respecting OS reduced-motion preferences (`ANIMATION_MOTION_GUIDELINES.md`).
abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration standard = Duration(milliseconds: 220);
  static const Duration emphasis = Duration(milliseconds: 320);
  static const Duration page = Duration(milliseconds: 280);
  static const Duration pageReverse = Duration(milliseconds: 220);

  /// Classic silky deceleration curve for standard UI transitions.
  static const Curve curveStandard = Curves.easeOutCubic;

  /// Classic emphasized decelerate curve (`M3 Emphasized Decelerate`).
  static const Curve curveEmphasized = Cubic(0.2, 0.0, 0.0, 1.0);

  /// Fast accelerate curve for outgoing views.
  static const Curve curveExit = Cubic(0.3, 0.0, 0.8, 0.15);

  /// Refined spring-like settle without cartoonish bounce.
  static const Curve curveSpring = Cubic(0.22, 1.0, 0.36, 1.0);

  static Duration resolve(BuildContext context, Duration preferred) {
    return MediaQuery.disableAnimationsOf(context) ? Duration.zero : preferred;
  }
}

extension PocketCfoThemeExt on BuildContext {
  PocketCfoColors get cfoColors =>
      Theme.of(this).extension<PocketCfoColors>() ?? PocketCfoColors.light;
}
