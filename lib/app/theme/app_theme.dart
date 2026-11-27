import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'app_tokens.dart';

abstract final class AppTypography {
  static const String sansFamily = 'PlusJakartaSans';
  static const String editorialFamily = 'PlusJakartaSans';

  /// Crisp modern fintech display style for page titles, vault names & section headers.
  static TextStyle editorial(
    BuildContext context, {
    double? fontSize,
    Color? color,
    FontWeight fontWeight = FontWeight.w800,
    double letterSpacing = -0.65,
    double? height,
  }) {
    return (Theme.of(context).textTheme.titleLarge ?? const TextStyle())
        .copyWith(
          fontFamily: sansFamily,
          fontSize: fontSize,
          color: color,
          fontWeight: fontWeight,
          letterSpacing: letterSpacing,
          height: height,
        );
  }
}

abstract final class AppTheme {
  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF1D4ED8),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFEDF2FF),
      onPrimaryContainer: Color(0xFF0F2557),
      secondary: Color(0xFF334155),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFFEEF1F6),
      onSecondaryContainer: Color(0xFF0F172A),
      tertiary: Color(0xFF059669),
      onTertiary: Color(0xFFFFFFFF),
      tertiaryContainer: Color(0xFFE6F7F0),
      onTertiaryContainer: Color(0xFF064E3B),
      error: Color(0xFFDC2626),
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFFEECEF),
      onErrorContainer: Color(0xFF7F1D1D),
      surface: Color(0xFFF5F6FA),
      onSurface: Color(0xFF0F1420),
      surfaceContainerHighest: Color(0xFFEBEEF5),
      onSurfaceVariant: Color(0xFF5E677D),
      outline: Color(0xFFCBD2E1),
      outlineVariant: Color(0xFFE6E9F0),
    );
    return _buildTheme(scheme, PocketCfoColors.light);
  }

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF60A5FA),
      onPrimary: Color(0xFF08142B),
      primaryContainer: Color(0xFF172238),
      onPrimaryContainer: Color(0xFFDBEAFE),
      secondary: Color(0xFF94A3B8),
      onSecondary: Color(0xFF0F1420),
      secondaryContainer: Color(0xFF1D2230),
      onSecondaryContainer: Color(0xFFE2E8F0),
      tertiary: Color(0xFF34D399),
      onTertiary: Color(0xFF03261C),
      tertiaryContainer: Color(0xFF0B2920),
      onTertiaryContainer: Color(0xFFD1FAE5),
      error: Color(0xFFF87171),
      onError: Color(0xFF450A0A),
      errorContainer: Color(0xFF331419),
      onErrorContainer: Color(0xFFFEE2E2),
      surface: Color(0xFF08090D),
      onSurface: Color(0xFFF4F6FA),
      surfaceContainerHighest: Color(0xFF191C26),
      onSurfaceVariant: Color(0xFF8E97AB),
      outline: Color(0xFF303647),
      outlineVariant: Color(0xFF232735),
    );
    return _buildTheme(scheme, PocketCfoColors.dark);
  }

  static ThemeData _buildTheme(ColorScheme scheme, PocketCfoColors cfoColors) {
    final typo = scheme.brightness == Brightness.dark
        ? Typography.material2021().white
        : Typography.material2021().black;
    final baseText = typo.apply(
      fontFamily: AppTypography.sansFamily,
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: AppTypography.sansFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      extensions: [cfoColors],
      textTheme: baseText.copyWith(
        displaySmall: baseText.displaySmall?.copyWith(
          fontFamily: AppTypography.sansFamily,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.1,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        headlineMedium: baseText.headlineMedium?.copyWith(
          fontFamily: AppTypography.sansFamily,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.7,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        titleLarge: baseText.titleLarge?.copyWith(
          fontFamily: AppTypography.sansFamily,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
        ),
        titleMedium: baseText.titleMedium?.copyWith(
          fontFamily: AppTypography.sansFamily,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.25,
        ),
        titleSmall: baseText.titleSmall?.copyWith(
          fontFamily: AppTypography.sansFamily,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.15,
        ),
        labelLarge: baseText.labelLarge?.copyWith(
          fontFamily: AppTypography.sansFamily,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: baseText.bodyLarge?.copyWith(height: 1.45),
        bodyMedium: baseText.bodyMedium?.copyWith(height: 1.45),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: baseText.titleLarge?.copyWith(
          fontFamily: AppTypography.sansFamily,
          color: scheme.onSurface,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: cfoColors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          side: BorderSide(color: cfoColors.divider),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cfoColors.surfaceTonal,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: scheme.error),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 2,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: cfoColors.surfaceTonal,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: cfoColors.divider),
        shape: const StadiumBorder(),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cfoColors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusXl),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cfoColors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: cfoColors.divider,
        thickness: 1,
        space: 1,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: cfoColors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 10,
        shadowColor: Colors.black.withValues(
          alpha: scheme.brightness == Brightness.dark ? 0.5 : 0.14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          side: BorderSide(color: cfoColors.divider),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: cfoColors.subtleText,
        indicatorColor: scheme.primary,
        dividerColor: cfoColors.divider,
        labelStyle: baseText.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        unselectedLabelStyle: baseText.labelLarge?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 350),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.brightness == Brightness.dark
              ? cfoColors.surfaceTonal
              : scheme.onSurface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        textStyle: baseText.labelSmall?.copyWith(
          color: scheme.brightness == Brightness.dark
              ? scheme.onSurface
              : scheme.surface,
          fontWeight: FontWeight.w600,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cfoColors.surfaceElevated,
        indicatorColor: scheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _ClassicPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: _ClassicPageTransitionsBuilder(),
          TargetPlatform.linux: _ClassicPageTransitionsBuilder(),
        },
      ),
    );
  }
}

class _ClassicPageTransitionsBuilder extends PageTransitionsBuilder {
  const _ClassicPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final enterCurve = CurvedAnimation(
      parent: animation,
      curve: AppMotion.curveEmphasized,
      reverseCurve: AppMotion.curveExit,
    );
    final exitCurve = CurvedAnimation(
      parent: secondaryAnimation,
      curve: AppMotion.curveEmphasized,
    );
    return SlideTransition(
      position: Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(-0.025, 0),
      ).animate(exitCurve),
      child: ScaleTransition(
        scale: Tween<double>(begin: 1.0, end: 0.985).animate(exitCurve),
        child: FadeTransition(
          opacity: enterCurve,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.05, 0),
              end: Offset.zero,
            ).animate(enterCurve),
            child: child,
          ),
        ),
      ),
    );
  }
}
