import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/theme/app_tokens.dart';
import '../../features/profiles/domain/entities/profile_entity.dart';
import '../../features/settings/presentation/bloc/settings_cubit.dart';

/// Crisp circular monogram avatar used across the Play Store-style AppBar
/// switcher, Instagram-style Bottom Navigation Bar item, and Profile Hub.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    required this.profile,
    this.size = 38,
    this.selectedRing = false,
    this.showTypeBadge = false,
    super.key,
  });

  final FinancialProfile? profile;
  final double size;
  final bool selectedRing;
  final bool showTypeBadge;

  static String initialsFor(String rawName) {
    final parts = rawName
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'PC';
    if (parts.length == 1) {
      final word = parts.first.toUpperCase();
      return word.length >= 2 ? word.substring(0, 2) : word;
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  static (Color, Color) paletteFor(FinancialProfile? p) {
    if (p == null) {
      return (const Color(0xFF4338CA), const Color(0xFF0EA5E9));
    }
    final hash = p.id.value.codeUnits.fold<int>(0, (a, b) => a + b);
    return switch (p.profileType) {
      ProfileType.personal =>
        hash.isEven
            ? (const Color(0xFF4338CA), const Color(0xFF0EA5E9))
            : (const Color(0xFF2563EB), const Color(0xFF06B6D4)),
      ProfileType.family =>
        hash.isEven
            ? (const Color(0xFF059669), const Color(0xFF14B8A6))
            : (const Color(0xFF0D9488), const Color(0xFF22C55E)),
      ProfileType.business =>
        hash.isEven
            ? (const Color(0xFF7C3AED), const Color(0xFFEC4899))
            : (const Color(0xFFD97706), const Color(0xFFF43F5E)),
    };
  }

  static IconData iconFor(ProfileType type) => switch (type) {
    ProfileType.personal => Icons.person_rounded,
    ProfileType.family => Icons.family_restroom_rounded,
    ProfileType.business => Icons.business_center_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (startColor, endColor) = paletteFor(profile);
    final initials = initialsFor(profile?.name ?? 'Pocket CFO');
    final fontSize = (size * 0.37).clamp(9.5, 24.0);

    Widget core = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [startColor, endColor],
        ),
        boxShadow: size >= 34
            ? [
                BoxShadow(
                  color: startColor.withValues(alpha: 0.26),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Text(
            initials,
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              height: 1.0,
            ),
          ),
        ),
      ),
    );

    if (selectedRing) {
      final outerSize = size + 6;
      core = Container(
        width: outerSize,
        height: outerSize,
        padding: const EdgeInsets.all(1.8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primary, context.cfoColors.accentCyan],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: context.cfoColors.surfaceElevated,
          ),
          child: Padding(padding: const EdgeInsets.all(1.4), child: core),
        ),
      );
    }

    if (!showTypeBadge || profile == null) {
      return core;
    }

    final badgeSize = (size * 0.40).clamp(13.0, 20.0);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        core,
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: badgeSize,
            height: badgeSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.cfoColors.surfaceElevated,
              border: Border.all(color: context.cfoColors.divider, width: 1),
            ),
            child: Icon(
              iconFor(profile!.profileType),
              size: badgeSize * 0.66,
              color: startColor,
            ),
          ),
        ),
      ],
    );
  }
}

/// Crisp deterministic gradient circular avatar for Family / Profile Members,
/// designed to overlap cleanly in horizontal avatar stacks with a crisp ring cutout.
class MemberCircleAvatar extends StatelessWidget {
  const MemberCircleAvatar({
    required this.displayName,
    this.seedKey,
    this.size = 38,
    this.ringColor,
    this.ringWidth = 2.2,
    super.key,
  });

  final String displayName;
  final String? seedKey;
  final double size;
  final Color? ringColor;
  final double ringWidth;

  static const _palettes = <(Color, Color)>[
    (Color(0xFF4F46E5), Color(0xFF6366F1)),
    (Color(0xFF0284C7), Color(0xFF38BDF8)),
    (Color(0xFF0D9488), Color(0xFF2DD4BF)),
    (Color(0xFF6D28D9), Color(0xFF8B5CF6)),
    (Color(0xFF2563EB), Color(0xFF60A5FA)),
    (Color(0xFF059669), Color(0xFF34D399)),
    (Color(0xFF334155), Color(0xFF64748B)),
  ];

  static (Color, Color) paletteForKey(String raw) {
    final hash = raw.codeUnits.fold<int>(
      0,
      (acc, c) => (acc * 31 + c) & 0x7FFF,
    );
    return _palettes[hash % _palettes.length];
  }

  @override
  Widget build(BuildContext context) {
    final (start, end) = paletteForKey(seedKey ?? displayName);
    final initials = ProfileAvatar.initialsFor(displayName);
    final fontSize = (size * 0.36).clamp(10.0, 20.0);

    return Container(
      width: size,
      height: size,
      padding: ringColor != null ? EdgeInsets.all(ringWidth) : EdgeInsets.zero,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ringColor ?? Colors.transparent,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [start, end],
          ),
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Text(
                initials,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Instant 1-tap Light / Dark theme toggle with animated sun/moon micro-interaction.
class ThemeQuickToggleButton extends StatelessWidget {
  const ThemeQuickToggleButton({this.size = 38, this.iconSize = 20, super.key});

  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final settingsCubit = context.read<SettingsCubit?>();
    if (settingsCubit == null) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final duration = AppMotion.resolve(context, AppMotion.fast);

    return IconButton(
      tooltip: isDark ? 'Switch to Light theme' : 'Switch to Dark theme',
      onPressed: () {
        HapticFeedback.selectionClick();
        settingsCubit.toggleLightDark(Theme.of(context).brightness);
      },
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(width: size, height: size),
      visualDensity: VisualDensity.compact,
      iconSize: iconSize,
      icon: AnimatedSwitcher(
        duration: duration,
        transitionBuilder: (child, anim) => RotationTransition(
          turns: Tween<double>(begin: 0.85, end: 1.0).animate(anim),
          child: FadeTransition(opacity: anim, child: child),
        ),
        child: Icon(
          isDark ? Icons.light_mode_rounded : Icons.dark_mode_outlined,
          key: ValueKey<bool>(isDark),
          color: isDark
              ? const Color(0xFFFBBF24)
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
