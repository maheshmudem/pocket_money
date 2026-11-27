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
    income: Color(0xFF059669),
    incomeContainer: Color(0xFFE6F7F0),
    expense: Color(0xFFDC2626),
    expenseContainer: Color(0xFFFEECEF),
    warning: Color(0xFFD97706),
    warningContainer: Color(0xFFFEF5E6),
    success: Color(0xFF059669),
    successContainer: Color(0xFFE6F7F0),
    transfer: Color(0xFF2563EB),
    transferContainer: Color(0xFFEBF3FF),
    surfaceElevated: Color(0xFFFFFFFF),
    surfaceTonal: Color(0xFFF1F3F8),
    subtleText: Color(0xFF5E677D),
    divider: Color(0xFFE6E9F0),
    heroGradientStart: Color(0xFF0E131F),
    heroGradientEnd: Color(0xFF1D273B),
    accentCyan: Color(0xFF0284C7),
    cardShadow: Color(0x0D0F172A),
    hoverBorder: Color(0xFFCBD5E1),
    hoverSurface: Color(0xFFF8FAFC),
  );

  static const dark = PocketCfoColors(
    income: Color(0xFF34D399),
    incomeContainer: Color(0xFF0B2920),
    expense: Color(0xFFF87171),
    expenseContainer: Color(0xFF331419),
    warning: Color(0xFFFBBF24),
    warningContainer: Color(0xFF2F210B),
    success: Color(0xFF34D399),
    successContainer: Color(0xFF0B2920),
    transfer: Color(0xFF60A5FA),
    transferContainer: Color(0xFF13223D),
    surfaceElevated: Color(0xFF12141C),
    surfaceTonal: Color(0xFF191C26),
    subtleText: Color(0xFF8E97AB),
    divider: Color(0xFF232735),
    heroGradientStart: Color(0xFF161B26),
    heroGradientEnd: Color(0xFF232B3D),
    accentCyan: Color(0xFF38BDF8),
    cardShadow: Color(0x4D000000),
    hoverBorder: Color(0xFF363D52),
    hoverSurface: Color(0xFF171A24),
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
