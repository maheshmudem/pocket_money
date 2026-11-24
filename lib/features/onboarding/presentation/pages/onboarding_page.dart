import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utilities/id_generator.dart';
import '../../../../shared/widgets/brand_logo.dart';
import '../../../../shared/widgets/fintech_widgets.dart';
import '../../../../shared/widgets/profile_avatar.dart';
import '../../../profiles/domain/entities/profile_entity.dart';
import '../../../settings/presentation/bloc/settings_cubit.dart';

/// Flagship 2026 interactive Onboarding Tour guided by Pocket CFO's 3D
/// Currency Banknote Character across cool, classic studio backdrops:
/// - Light mode: seamless sunlit pearl-mist stage with overlapping bridge dock
///   and 2-column elevated bento capability cards
/// - Dark mode: velvety twilight spotlight vignette seamlessly integrating the
///   character into Obsidian surfaces without harsh white boxes
/// - Motion: real-time swipe parallax, spring entrance bounce, top story bars,
///   interactive frosted-glass controls, and morphing circular progress-ring CTA
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, this.isReplay = false});

  /// When `true`, opened from Welcome or Settings as a revisit tour and pops
  /// back cleanly instead of mutating first-run completion state.
  final bool isReplay;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with SingleTickerProviderStateMixin {
  static const int _pageCount = 4;

  static const _slides = <_SlideMeta>[
    _SlideMeta(
      stepLabel: 'STEP 1',
      assetPath: 'assets/images/onboarding/hero_vaults.jpg',
      eyebrow: 'MULTI-PROFILE VAULTS',
      eyebrowIcon: Icons.layers_rounded,
      headlineLine1: 'Organize wealth,',
      headlineLine2: 'vault by vault.',
      subtitle:
          'Separate Personal, Family & Business finances into isolated multi-currency vaults with dedicated roles.',
      stageBase: Color(0xFFE5E9F6),
      stageTopTint: Color(0xFFE0E5F4),
      darkSpotlightTint: Color(0xFF171B36),
      accentStart: Color(0xFF4338CA),
      accentEnd: Color(0xFF0EA5E9),
      darkAccent: Color(0xFF38BDF8),
      cards: [
        (
          icon: Icons.currency_exchange_rounded,
          title: '15+ Currencies',
          caption: 'INR, USD, EUR & FX',
        ),
        (
          icon: Icons.swipe_down_rounded,
          title: 'Instant Switch',
          caption: 'Swipe to switch',
        ),
      ],
    ),
    _SlideMeta(
      stepLabel: 'STEP 2',
      assetPath: 'assets/images/onboarding/hero_ledger.jpg',
      eyebrow: 'DOUBLE-ENTRY LEDGER',
      eyebrowIcon: Icons.bolt_rounded,
      headlineLine1: 'Track every flow,',
      headlineLine2: 'always balanced.',
      subtitle:
          'Capture expenses, income, transfers & multi-category splits on an immutable double-entry journal.',
      stageBase: Color(0xFFE6F2EF),
      stageTopTint: Color(0xFFE0EFEA),
      darkSpotlightTint: Color(0xFF0E2522),
      accentStart: Color(0xFF059669),
      accentEnd: Color(0xFF10B981),
      darkAccent: Color(0xFF34D399),
      cards: [
        (
          icon: Icons.call_split_rounded,
          title: 'Split Vouchers',
          caption: 'Multi-category logs',
        ),
        (
          icon: Icons.upload_file_rounded,
          title: 'CSV Import',
          caption: 'Smart dedup guard',
        ),
      ],
    ),
    _SlideMeta(
      stepLabel: 'STEP 3',
      assetPath: 'assets/images/onboarding/hero_insights.jpg',
      eyebrow: 'SMART CFO INSIGHTS',
      eyebrowIcon: Icons.insights_rounded,
      headlineLine1: 'Plan your limits,',
      headlineLine2: 'grow your goals.',
      subtitle:
          'Turn live cash flow into daily safe-to-spend caps, 80% & 100% alerts, savings milestones & EMI schedules.',
      stageBase: Color(0xFFE6EAF7),
      stageTopTint: Color(0xFFE0E6F5),
      darkSpotlightTint: Color(0xFF112238),
      accentStart: Color(0xFF0284C7),
      accentEnd: Color(0xFF10B981),
      darkAccent: Color(0xFF2DD4BF),
      cards: [
        (
          icon: Icons.notifications_active_outlined,
          title: 'Limit Alerts',
          caption: '80% & 100% guards',
        ),
        (
          icon: Icons.picture_as_pdf_outlined,
          title: 'EMI & Reports',
          caption: 'PDF & CSV exports',
        ),
      ],
    ),
    _SlideMeta(
      stepLabel: 'STEP 4',
      assetPath: 'assets/images/onboarding/hero_privacy.jpg',
      eyebrow: 'PRIVATE & OFFLINE-FIRST',
      eyebrowIcon: Icons.enhanced_encryption_rounded,
      headlineLine1: 'Sealed on device,',
      headlineLine2: 'truly yours.',
      subtitle:
          'AES-256 encrypted local SQLite vault with zero cloud lock-in. Never collects bank passwords or PINs.',
      stageBase: Color(0xFFE6E9F6),
      stageTopTint: Color(0xFFE1E5F4),
      darkSpotlightTint: Color(0xFF141935),
      accentStart: Color(0xFF059669),
      accentEnd: Color(0xFF4F46E5),
      darkAccent: Color(0xFF818CF8),
      cards: [
        (
          icon: Icons.fingerprint_rounded,
          title: 'Biometric Lock',
          caption: 'PIN & app shield',
        ),
        (
          icon: Icons.backup_outlined,
          title: '.pcfo Backups',
          caption: 'Encrypted files',
        ),
      ],
    ),
  ];

  late final PageController _pageController;
  late final AnimationController _entranceCtrl;

  int _currentPage = 0;
  double _pageOffset = 0.0;
  int _selectedVaultIndex = 0;
  int _demoLoggedCount = 0;
  bool _didPrecache = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController()
      ..addListener(() {
        final next = _pageController.hasClients
            ? (_pageController.page ?? _currentPage.toDouble())
            : _currentPage.toDouble();
        if ((next - _pageOffset).abs() > 0.001) {
          setState(() => _pageOffset = next);
        }
      });
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didPrecache) {
      _didPrecache = true;
      for (final slide in _slides) {
        precacheImage(AssetImage(slide.assetPath), context);
      }
      if (MediaQuery.disableAnimationsOf(context)) {
        _entranceCtrl.value = 1.0;
      } else {
        _entranceCtrl.forward(from: 0.0);
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _entranceCtrl.dispose();
    super.dispose();
  }

  void _triggerCharacterPop() {
    HapticFeedback.lightImpact();
    if (MediaQuery.disableAnimationsOf(context)) return;
    _entranceCtrl.forward(from: 0.25);
  }

  void _goToPage(int index) {
    final target = index.clamp(0, _pageCount - 1);
    if (target == _currentPage) return;
    HapticFeedback.selectionClick();
    final duration = AppMotion.resolve(context, AppMotion.emphasis);
    if (duration == Duration.zero) {
      _pageController.jumpToPage(target);
      setState(() {
        _currentPage = target;
        _pageOffset = target.toDouble();
      });
    } else {
      _pageController.animateToPage(
        target,
        duration: duration,
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _finishOnboarding() async {
    HapticFeedback.mediumImpact();
    if (widget.isReplay) {
      if (mounted && context.canPop()) {
        context.pop();
      } else if (mounted) {
        context.go('/dashboard');
      }
      return;
    }
    await context.read<SettingsCubit>().completeOnboarding();
  }

  Widget _buildTopCornerBadge(
    BuildContext context,
    int index, {
    required bool darkGlass,
  }) {
    return switch (index) {
      0 => _VaultIdentityBadge(
        selectedIndex: _selectedVaultIndex,
        darkGlass: darkGlass,
      ),
      1 => _LedgerStatusBadge(
        loggedCount: _demoLoggedCount,
        darkGlass: darkGlass,
      ),
      2 => _CfoScoreBadge(darkGlass: darkGlass),
      _ => _PrivacyTrustBadge(darkGlass: darkGlass),
    };
  }

  Widget _buildBridgeControl(
    BuildContext context,
    int index, {
    required bool darkGlass,
  }) {
    return switch (index) {
      0 => _VaultsBridgeDock(
        selectedIndex: _selectedVaultIndex,
        darkGlass: darkGlass,
        onSelect: (idx) {
          HapticFeedback.selectionClick();
          setState(() => _selectedVaultIndex = idx);
          _triggerCharacterPop();
        },
      ),
      1 => _QuickBallBridgeButton(
        loggedCount: _demoLoggedCount,
        darkGlass: darkGlass,
        onTryQuickLog: () {
          HapticFeedback.mediumImpact();
          setState(() => _demoLoggedCount++);
          _triggerCharacterPop();
        },
      ),
      2 => _InsightsBridgeRibbon(darkGlass: darkGlass),
      _ => _ThemeStudioBridgeDock(darkGlass: darkGlass),
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cfo = context.cfoColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentSlide = _slides[_currentPage];
    final isLastPage = _currentPage == _pageCount - 1;
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width >= AppBreakpoints.expanded;
    final disableAnim = MediaQuery.disableAnimationsOf(context);
    final morphDuration = AppMotion.resolve(context, AppMotion.standard);

    final statusBarOverlay =
        (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
            .copyWith(statusBarColor: Colors.transparent);

    if (isWide) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: statusBarOverlay,
        child: Scaffold(
          key: const Key('onboarding_page'),
          backgroundColor: scheme.surface,
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Left 54%: Studio Character Showcase with Story Header & Floating Dock
                      Expanded(
                        flex: 11,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(32),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.10)
                                  : cfo.divider,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: isDark
                                    ? currentSlide.accentStart.withValues(
                                        alpha: 0.16,
                                      )
                                    : cfo.cardShadow,
                                blurRadius: 28,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(32),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                _buildCharacterPageView(
                                  context,
                                  isDark: isDark,
                                  isWide: true,
                                  disableAnim: disableAnim,
                                ),
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  right: 0,
                                  child: _TopStoryHeader(
                                    currentPage: _currentPage,
                                    pageCount: _pageCount,
                                    slide: currentSlide,
                                    isReplay: widget.isReplay,
                                    onDarkSurface: isDark,
                                    onSelectSegment: _goToPage,
                                    onSkipOrClose: _finishOnboarding,
                                  ),
                                ),
                                Positioned(
                                  left: AppSpacing.lg,
                                  right: AppSpacing.lg,
                                  bottom: AppSpacing.md,
                                  child: AnimatedSwitcher(
                                    duration: morphDuration,
                                    child: KeyedSubtree(
                                      key: ValueKey<int>(_currentPage),
                                      child: _buildBridgeControl(
                                        context,
                                        _currentPage,
                                        darkGlass: isDark,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xxxl),
                      // Right 46%: Magazine Typography + Bento Cards + Morphing Dock
                      Expanded(
                        flex: 9,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Center(
                                child: SingleChildScrollView(
                                  child: _EditorialCopyPanel(
                                    slide: currentSlide,
                                    pageIndex: _currentPage,
                                    isWide: true,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            _MorphingOnboardingFooter(
                              currentPage: _currentPage,
                              pageCount: _pageCount,
                              slide: currentSlide,
                              isLastPage: isLastPage,
                              isReplay: widget.isReplay,
                              onBack: _currentPage > 0
                                  ? () => _goToPage(_currentPage - 1)
                                  : null,
                              onPrimaryAction: isLastPage
                                  ? _finishOnboarding
                                  : () => _goToPage(_currentPage + 1),
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
      );
    }

    // Mobile / Tablet Architectural Bridge Layout
    // Single unified widget tree so toggling Light/Dark/Auto on Slide 4
    // morphs smoothly without ever unmounting PageView.
    final textScale = MediaQuery.textScalerOf(context).scale(14.0) / 14.0;
    final topInset = MediaQuery.paddingOf(context).top;
    final stageFraction = textScale >= 1.75
        ? 0.31
        : textScale >= 1.35
        ? 0.36
        : 0.42;
    final stageHeight = (size.height * stageFraction).clamp(200.0, 360.0);
    const bridgeOverhang = 24.0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: statusBarOverlay,
      child: Scaffold(
        key: const Key('onboarding_page'),
        backgroundColor: scheme.surface,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Unified Seamless Top Story Bar & Brand Header
            AnimatedContainer(
              duration: morphDuration,
              curve: Curves.easeOutCubic,
              color: isDark ? scheme.surface : currentSlide.stageTopTint,
              padding: EdgeInsets.only(top: topInset),
              child: _TopStoryHeader(
                currentPage: _currentPage,
                pageCount: _pageCount,
                slide: currentSlide,
                isReplay: widget.isReplay,
                onDarkSurface: isDark,
                onSelectSegment: _goToPage,
                onSkipOrClose: _finishOnboarding,
              ),
            ),

            // 2. Unified Hero Stage + Overlapping Floating Bridge Control
            SizedBox(
              height: stageHeight + bridgeOverhang,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: stageHeight,
                    child: AnimatedContainer(
                      duration: morphDuration,
                      curve: Curves.easeOutCubic,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(36),
                        ),
                        boxShadow: isDark
                            ? null
                            : [
                                BoxShadow(
                                  color: const Color(
                                    0xFF0F172A,
                                  ).withValues(alpha: 0.06),
                                  blurRadius: 24,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                      ),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(36),
                        ),
                        child: _buildCharacterPageView(
                          context,
                          isDark: isDark,
                          isWide: false,
                          disableAnim: disableAnim,
                        ),
                      ),
                    ),
                  ),
                  // Interactive Pill Dock straddling the curved arch seam!
                  Positioned(
                    left: AppSpacing.md,
                    right: AppSpacing.md,
                    bottom: 0,
                    child: AnimatedSwitcher(
                      duration: morphDuration,
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: KeyedSubtree(
                        key: ValueKey<int>(_currentPage),
                        child: _buildBridgeControl(
                          context,
                          _currentPage,
                          darkGlass: isDark,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 3. Lower Magazine Editorial Stage + 2-Column Bento Cards
            Expanded(
              child: SafeArea(
                top: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          size.width < 380 ? AppSpacing.md : AppSpacing.xl,
                          textScale >= 1.5 ? AppSpacing.sm : AppSpacing.md,
                          size.width < 380 ? AppSpacing.md : AppSpacing.xl,
                          AppSpacing.xs,
                        ),
                        child: _EditorialCopyPanel(
                          slide: currentSlide,
                          pageIndex: _currentPage,
                          isWide: false,
                        ),
                      ),
                    ),
                    // Crisp Hairline-Separated Bottom Navigation Dock
                    Container(
                      padding: EdgeInsets.fromLTRB(
                        size.width < 380 ? AppSpacing.md : AppSpacing.xl,
                        AppSpacing.sm,
                        size.width < 380 ? AppSpacing.md : AppSpacing.xl,
                        AppSpacing.md,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        border: Border(
                          top: BorderSide(
                            color: cfo.divider.withValues(alpha: 0.65),
                          ),
                        ),
                      ),
                      child: _MorphingOnboardingFooter(
                        currentPage: _currentPage,
                        pageCount: _pageCount,
                        slide: currentSlide,
                        isLastPage: isLastPage,
                        isReplay: widget.isReplay,
                        onBack: _currentPage > 0
                            ? () => _goToPage(_currentPage - 1)
                            : null,
                        onPrimaryAction: isLastPage
                            ? _finishOnboarding
                            : () => _goToPage(_currentPage + 1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCharacterPageView(
    BuildContext context, {
    required bool isDark,
    required bool isWide,
    required bool disableAnim,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final badgeTopPad = isWide ? 74.0 : 8.0;
    final artworkTopPad = isWide ? 72.0 : 12.0;
    final artworkBottomPad = isWide ? 76.0 : 28.0;

    return PageView.builder(
      key: const Key('onboarding_page_view'),
      controller: _pageController,
      itemCount: _pageCount,
      onPageChanged: (index) {
        if (_currentPage != index) {
          setState(() => _currentPage = index);
          if (!disableAnim) {
            _entranceCtrl.forward(from: 0.0);
          }
        }
      },
      itemBuilder: (context, index) {
        final slide = _slides[index];
        final delta = (_pageOffset - index).clamp(-1.0, 1.0);
        final absDelta = delta.abs();

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _triggerCharacterPop,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: isDark
                  ? RadialGradient(
                      center: const Alignment(0, -0.05),
                      radius: 0.96,
                      colors: [slide.darkSpotlightTint, scheme.surface],
                    )
                  : LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [slide.stageTopTint, slide.stageBase],
                    ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Subtle architectural concentric studio rings behind character
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _StudioHaloRingsPainter(
                          color: isDark
                              ? slide.accentEnd.withValues(alpha: 0.09)
                              : slide.accentStart.withValues(alpha: 0.055),
                        ),
                      ),
                    ),
                  ),
                ),

                // Parallax 3D Currency Banknote Character Artwork
                // Fade is folded directly into the ShaderMask alpha to avoid
                // Impeller SetInheritedOpacity validation breaks on swipe.
                AnimatedBuilder(
                  animation: _entranceCtrl,
                  builder: (context, child) {
                    final springT = disableAnim
                        ? 1.0
                        : Curves.easeOutBack.transform(
                            _entranceCtrl.value.clamp(0.0, 1.0),
                          );
                    final enterScale = disableAnim
                        ? 1.0
                        : (0.93 + 0.07 * springT);
                    final swipeScale = 1.0 - (absDelta * 0.07);
                    return Transform.translate(
                      offset: Offset(delta * 42, (1.0 - springT) * 10),
                      child: Transform.scale(
                        scale: (enterScale * swipeScale).clamp(0.86, 1.08),
                        child: child,
                      ),
                    );
                  },
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: artworkTopPad,
                      bottom: artworkBottomPad,
                    ),
                    child: () {
                      final maskAlpha = (1.0 - absDelta * 0.45).clamp(0.4, 1.0);
                      final solidMask = Colors.white.withValues(
                        alpha: maskAlpha,
                      );
                      if (isDark) {
                        // Dark mode: exact 4:3 elliptical spotlight on uncropped
                        // 1200x896 bounds keeps every outer prop 100% visible
                        // while fading seamlessly into Obsidian Dark on all 4 sides.
                        return Center(
                          child: AspectRatio(
                            aspectRatio: 1200 / 896,
                            child: ShaderMask(
                              blendMode: BlendMode.dstIn,
                              shaderCallback: (bounds) => RadialGradient(
                                center: Alignment.center,
                                radius: 0.495,
                                stops: const [0.0, 0.72, 0.89, 1.0],
                                colors: [
                                  solidMask,
                                  solidMask,
                                  Colors.white.withValues(
                                    alpha: 0.55 * maskAlpha,
                                  ),
                                  Colors.transparent,
                                ],
                                transform:
                                    const _EllipticalSpotlightTransform(),
                              ).createShader(bounds),
                              child: ColorFiltered(
                                colorFilter: const ColorFilter.mode(
                                  Color(0xFFEDF1FA),
                                  BlendMode.modulate,
                                ),
                                child: Image.asset(
                                  slide.assetPath,
                                  fit: BoxFit.cover,
                                  filterQuality: FilterQuality.high,
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                      // Light mode: uncropped full-bleed 4:3 artwork with silky
                      // vertical feather into exact-matched sunlit studio canvas.
                      return ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (bounds) => LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0.0, 0.14, 0.86, 1.0],
                          colors: [
                            Colors.transparent,
                            solidMask,
                            solidMask,
                            Colors.transparent,
                          ],
                        ).createShader(bounds),
                        child: Image.asset(
                          slide.assetPath,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      );
                    }(),
                  ),
                ),

                // Orbiting Top Corner Frosted-Glass Live Metric Badge
                Positioned(
                  top: badgeTopPad,
                  left: AppSpacing.md,
                  right: AppSpacing.md,
                  child: Transform.translate(
                    offset: Offset(delta * -56, absDelta * 8),
                    child: Opacity(
                      opacity: (1.0 - absDelta * 1.15).clamp(0.0, 1.0),
                      child: _buildTopCornerBadge(
                        context,
                        index,
                        darkGlass: isDark,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

final class _SlideMeta {
  const _SlideMeta({
    required this.stepLabel,
    required this.assetPath,
    required this.eyebrow,
    required this.eyebrowIcon,
    required this.headlineLine1,
    required this.headlineLine2,
    required this.subtitle,
    required this.stageBase,
    required this.stageTopTint,
    required this.darkSpotlightTint,
    required this.accentStart,
    required this.accentEnd,
    required this.darkAccent,
    required this.cards,
  });

  final String stepLabel;
  final String assetPath;
  final String eyebrow;
  final IconData eyebrowIcon;
  final String headlineLine1;
  final String headlineLine2;
  final String subtitle;
  final Color stageBase;
  final Color stageTopTint;
  final Color darkSpotlightTint;
  final Color accentStart;
  final Color accentEnd;
  final Color darkAccent;
  final List<({IconData icon, String title, String caption})> cards;
}

class _EllipticalSpotlightTransform extends GradientTransform {
  const _EllipticalSpotlightTransform();

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    if (bounds.height <= 0 || bounds.width <= 0) return null;
    final scaleX = bounds.width / bounds.height;
    final cx = bounds.center.dx;
    return Matrix4.fromList(<double>[
      scaleX,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      1,
      0,
      cx * (1 - scaleX),
      0,
      0,
      1,
    ]);
  }
}

class _StudioHaloRingsPainter extends CustomPainter {
  const _StudioHaloRingsPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.48);
    final baseRadius = math.min(size.width, size.height) * 0.34;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    canvas.drawCircle(center, baseRadius, paint);
    canvas.drawCircle(center, baseRadius * 1.38, paint);
  }

  @override
  bool shouldRepaint(covariant _StudioHaloRingsPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Top Story Progress Bars + Floating Classic Header.
class _TopStoryHeader extends StatelessWidget {
  const _TopStoryHeader({
    required this.currentPage,
    required this.pageCount,
    required this.slide,
    required this.isReplay,
    required this.onDarkSurface,
    required this.onSelectSegment,
    required this.onSkipOrClose,
  });

  final int currentPage;
  final int pageCount;
  final _SlideMeta slide;
  final bool isReplay;
  final bool onDarkSurface;
  final ValueChanged<int> onSelectSegment;
  final VoidCallback onSkipOrClose;

  @override
  Widget build(BuildContext context) {
    final isLastPage = currentPage == pageCount - 1;
    final duration = AppMotion.resolve(context, AppMotion.standard);
    final trackColor = onDarkSurface
        ? Colors.white.withValues(alpha: 0.18)
        : const Color(0xFF0F172A).withValues(alpha: 0.11);
    final doneColor = onDarkSurface
        ? Colors.white.withValues(alpha: 0.85)
        : const Color(0xFF334155);
    final brandTextColor = onDarkSurface
        ? Colors.white
        : const Color(0xFF0F172A);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              for (var i = 0; i < pageCount; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: Semantics(
                    label: 'Page ${i + 1} of $pageCount',
                    selected: i == currentPage,
                    button: true,
                    child: GestureDetector(
                      key: Key('onboarding_dot_$i'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onSelectSegment(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusFull,
                          ),
                          child: Container(
                            height: 3.5,
                            color: trackColor,
                            alignment: Alignment.centerLeft,
                            child: AnimatedFractionallySizedBox(
                              duration: duration,
                              curve: Curves.easeOutCubic,
                              widthFactor: i <= currentPage ? 1.0 : 0.0,
                              heightFactor: 1.0,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: i == currentPage
                                      ? LinearGradient(
                                          colors: [
                                            slide.accentStart,
                                            slide.accentEnd,
                                          ],
                                        )
                                      : null,
                                  color: i < currentPage ? doneColor : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const PocketCfoLogo(size: 30, animateEntrance: true),
                    const SizedBox(width: 9),
                    Flexible(
                      child: Text(
                        'Pocket CFO',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: brandTextColor,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _FrostedHeaderThemeButton(onDarkSurface: onDarkSurface),
              if (isReplay || !isLastPage) ...[
                const SizedBox(width: 8),
                _FrostedGlassPillButton(
                  key: isReplay
                      ? const Key('onboarding_close_btn')
                      : const Key('onboarding_skip_btn'),
                  label: isReplay ? 'Close' : 'Skip',
                  onDarkSurface: onDarkSurface,
                  onTap: onSkipOrClose,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _FrostedHeaderThemeButton extends StatelessWidget {
  const _FrostedHeaderThemeButton({required this.onDarkSurface});

  final bool onDarkSurface;

  @override
  Widget build(BuildContext context) {
    final settingsCubit = context.read<SettingsCubit?>();
    if (settingsCubit == null) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Tooltip(
      message: isDark ? 'Switch to Light theme' : 'Switch to Dark theme',
      child: Material(
        color: onDarkSurface
            ? Colors.white.withValues(alpha: 0.11)
            : Colors.white.withValues(alpha: 0.80),
        shape: CircleBorder(
          side: BorderSide(
            color: onDarkSurface
                ? Colors.white.withValues(alpha: 0.18)
                : const Color(0xFF0F172A).withValues(alpha: 0.09),
          ),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            HapticFeedback.selectionClick();
            settingsCubit.toggleLightDark(Theme.of(context).brightness);
          },
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_outlined,
              size: 17,
              color: isDark ? const Color(0xFFFBBF24) : const Color(0xFF334155),
            ),
          ),
        ),
      ),
    );
  }
}

class _FrostedGlassPillButton extends StatelessWidget {
  const _FrostedGlassPillButton({
    required this.label,
    required this.onDarkSurface,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool onDarkSurface;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: onDarkSurface
          ? Colors.white.withValues(alpha: 0.11)
          : Colors.white.withValues(alpha: 0.80),
      shape: StadiumBorder(
        side: BorderSide(
          color: onDarkSurface
              ? Colors.white.withValues(alpha: 0.18)
              : const Color(0xFF0F172A).withValues(alpha: 0.09),
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          child: Text(
            label,
            maxLines: 1,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: onDarkSurface ? Colors.white : const Color(0xFF0F172A),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// Reusable porcelain (Light) / obsidian (Dark) elevated floating glass chip.
/// Uses specular translucent surface gradients without BackdropFilter so it
/// animates cleanly inside Opacity / FadeTransition on Impeller at 120fps.
class _GlassStageChip extends StatelessWidget {
  const _GlassStageChip({
    required this.child,
    required this.darkGlass,
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    this.borderRadius = AppSpacing.radiusFull,
    this.borderColor,
    this.elevated = false,
  });

  final Widget child;
  final bool darkGlass;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? borderColor;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          gradient: darkGlass
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(
                      0xFF1A2236,
                    ).withValues(alpha: elevated ? 0.97 : 0.92),
                    const Color(
                      0xFF111827,
                    ).withValues(alpha: elevated ? 0.96 : 0.89),
                  ],
                )
              : LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: elevated ? 0.98 : 0.95),
                    const Color(
                      0xFFF8FAFC,
                    ).withValues(alpha: elevated ? 0.96 : 0.91),
                  ],
                ),
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color:
                borderColor ??
                (darkGlass
                    ? Colors.white.withValues(alpha: 0.14)
                    : const Color(0xFFCBD5E1).withValues(alpha: 0.88)),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(
                alpha: darkGlass
                    ? (elevated ? 0.48 : 0.30)
                    : (elevated ? 0.12 : 0.07),
              ),
              blurRadius: elevated ? 22 : 14,
              offset: Offset(0, elevated ? 8 : 4),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top Corner Orbiting Live Badges (Slides 1..4)
// ---------------------------------------------------------------------------

class _VaultIdentityBadge extends StatelessWidget {
  const _VaultIdentityBadge({
    required this.selectedIndex,
    required this.darkGlass,
  });

  final int selectedIndex;
  final bool darkGlass;

  static const _items = [
    (
      title: 'Personal Wealth',
      meta: 'INR • ₹4,82,500',
      type: ProfileType.personal,
      showMembers: false,
    ),
    (
      title: 'Household Vault',
      meta: '3 Members • RBAC',
      type: ProfileType.family,
      showMembers: true,
    ),
    (
      title: 'Studio Ledger',
      meta: 'USD • \$18,450',
      type: ProfileType.business,
      showMembers: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final selected = _items[selectedIndex.clamp(0, _items.length - 1)];
    final previewProfile = FinancialProfile(
      id: ProfileId('note-${selected.type.name}'),
      name: selected.title,
      profileType: selected.type,
      baseCurrencyCode: selected.type == ProfileType.business ? 'USD' : 'INR',
      timezone: 'UTC',
      role: ProfileRole.owner,
      editorsCanPost: true,
      createdAtUtc: '',
      updatedAtUtc: '',
      version: 1,
      syncStatus: 'local_only',
    );
    final duration = AppMotion.resolve(context, AppMotion.fast);
    final primaryText = darkGlass ? Colors.white : const Color(0xFF0F172A);
    final metaText = darkGlass
        ? const Color(0xFF93C5FD)
        : const Color(0xFF4338CA);
    final ringCutout = darkGlass ? const Color(0xFF111827) : Colors.white;

    return Align(
      alignment: Alignment.topRight,
      child: AnimatedSwitcher(
        duration: duration,
        child: _GlassStageChip(
          key: ValueKey<int>(selectedIndex),
          darkGlass: darkGlass,
          padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
          borderRadius: AppSpacing.radiusLg,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected.showMembers)
                SizedBox(
                  width: 60,
                  height: 24,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        child: MemberCircleAvatar(
                          displayName: 'Arjun',
                          size: 24,
                          ringColor: ringCutout,
                          ringWidth: 1.4,
                        ),
                      ),
                      Positioned(
                        left: 17,
                        child: MemberCircleAvatar(
                          displayName: 'Priya',
                          size: 24,
                          ringColor: ringCutout,
                          ringWidth: 1.4,
                        ),
                      ),
                      Positioned(
                        left: 34,
                        child: MemberCircleAvatar(
                          displayName: 'Mom',
                          size: 24,
                          ringColor: ringCutout,
                          ringWidth: 1.4,
                        ),
                      ),
                    ],
                  ),
                )
              else
                ProfileAvatar(
                  profile: previewProfile,
                  size: 26,
                  showTypeBadge: false,
                ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selected.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: primaryText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      selected.meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: metaText,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LedgerStatusBadge extends StatelessWidget {
  const _LedgerStatusBadge({
    required this.loggedCount,
    required this.darkGlass,
  });

  final int loggedCount;
  final bool darkGlass;

  @override
  Widget build(BuildContext context) {
    final hasLogged = loggedCount > 0;
    final duration = AppMotion.resolve(context, AppMotion.fast);
    final primaryText = darkGlass ? Colors.white : const Color(0xFF0F172A);
    final accentGreen = darkGlass
        ? const Color(0xFF34D399)
        : const Color(0xFF047857);

    return Align(
      alignment: Alignment.topLeft,
      child: AnimatedSwitcher(
        duration: duration,
        child: _GlassStageChip(
          key: ValueKey<int>(loggedCount),
          darkGlass: darkGlass,
          borderColor: accentGreen.withValues(alpha: 0.45),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified_rounded, size: 14, color: accentGreen),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  hasLogged
                      ? 'Logged ${loggedCount}x • Debits == Credits'
                      : 'Double-Entry • Zero Drift',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: primaryText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CfoScoreBadge extends StatelessWidget {
  const _CfoScoreBadge({required this.darkGlass});

  final bool darkGlass;

  @override
  Widget build(BuildContext context) {
    final primaryText = darkGlass ? Colors.white : const Color(0xFF0F172A);
    final accentGreen = darkGlass
        ? const Color(0xFF34D399)
        : const Color(0xFF059669);

    return Align(
      alignment: Alignment.topLeft,
      child: _GlassStageChip(
        darkGlass: darkGlass,
        padding: const EdgeInsets.all(6),
        borderRadius: AppSpacing.radiusLg,
        child: RadialScoreGauge(
          key: const Key('onboarding_health_gauge'),
          score: 86,
          label: 'CFO',
          size: 58,
          strokeWidth: 5.5,
          activeColor: accentGreen,
          secondaryColor: const Color(0xFF0EA5E9),
          trackColor: darkGlass
              ? const Color(0x33FFFFFF)
              : const Color(0xFFE2E8F0),
          textColor: primaryText,
          subtitleColor: darkGlass
              ? const Color(0xFFBAE6FD)
              : const Color(0xFF475569),
        ),
      ),
    );
  }
}

class _PrivacyTrustBadge extends StatelessWidget {
  const _PrivacyTrustBadge({required this.darkGlass});

  final bool darkGlass;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsCubit>().state;
    final primaryText = darkGlass ? Colors.white : const Color(0xFF0F172A);
    final accentGreen = darkGlass
        ? const Color(0xFF34D399)
        : const Color(0xFF047857);

    final modeLabel = switch (settings.themeMode) {
      ThemeMode.light => 'Daylight Light',
      ThemeMode.dark => 'Obsidian Dark',
      ThemeMode.system => 'Match System',
    };

    return Align(
      alignment: Alignment.topRight,
      child: _GlassStageChip(
        darkGlass: darkGlass,
        borderColor: accentGreen.withValues(alpha: 0.45),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_user_rounded, size: 14, color: accentGreen),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'AES-256 • $modeLabel',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: primaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overlapping Interactive Bridge Controls Straddling the Curved Stage Seam
// ---------------------------------------------------------------------------

class _VaultsBridgeDock extends StatelessWidget {
  const _VaultsBridgeDock({
    required this.selectedIndex,
    required this.darkGlass,
    required this.onSelect,
  });

  final int selectedIndex;
  final bool darkGlass;
  final ValueChanged<int> onSelect;

  static const _vaults = [
    (
      key: Key('onboarding_vault_personal'),
      label: 'Personal',
      type: ProfileType.personal,
    ),
    (
      key: Key('onboarding_vault_family'),
      label: 'Family',
      type: ProfileType.family,
    ),
    (
      key: Key('onboarding_vault_business'),
      label: 'Business',
      type: ProfileType.business,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.resolve(context, AppMotion.fast);
    final inactiveText = darkGlass
        ? Colors.white.withValues(alpha: 0.78)
        : const Color(0xFF475569);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: _GlassStageChip(
          darkGlass: darkGlass,
          elevated: true,
          padding: const EdgeInsets.all(4.5),
          borderRadius: AppSpacing.radiusFull,
          child: Row(
            children: [
              for (var i = 0; i < _vaults.length; i++)
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: _vaults[i].key,
                      customBorder: const StadiumBorder(),
                      onTap: () => onSelect(i),
                      child: AnimatedContainer(
                        duration: duration,
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          gradient: i == selectedIndex
                              ? const LinearGradient(
                                  colors: [
                                    Color(0xFF4338CA),
                                    Color(0xFF0EA5E9),
                                  ],
                                )
                              : null,
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusFull,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              ProfileAvatar.iconFor(_vaults[i].type),
                              size: 14,
                              color: i == selectedIndex
                                  ? Colors.white
                                  : inactiveText,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _vaults[i].label,
                                  maxLines: 1,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: i == selectedIndex
                                            ? Colors.white
                                            : inactiveText,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickBallBridgeButton extends StatelessWidget {
  const _QuickBallBridgeButton({
    required this.loggedCount,
    required this.darkGlass,
    required this.onTryQuickLog,
  });

  final int loggedCount;
  final bool darkGlass;
  final VoidCallback onTryQuickLog;

  @override
  Widget build(BuildContext context) {
    final hasLogged = loggedCount > 0;
    final primaryText = darkGlass ? Colors.white : const Color(0xFF0F172A);
    final accentGreen = darkGlass
        ? const Color(0xFF34D399)
        : const Color(0xFF047857);

    return Center(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('onboarding_try_quicklog_btn'),
          customBorder: const StadiumBorder(),
          onTap: onTryQuickLog,
          child: _GlassStageChip(
            darkGlass: darkGlass,
            elevated: true,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            borderColor: hasLogged
                ? accentGreen.withValues(alpha: 0.70)
                : accentGreen.withValues(alpha: 0.30),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  hasLogged ? Icons.check_circle_rounded : Icons.bolt_rounded,
                  size: 17,
                  color: accentGreen,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      hasLogged
                          ? 'Posted -₹${loggedCount * 250}  •  Tap again'
                          : 'Try QuickBall  •  -₹250 Coffee',
                      maxLines: 1,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: primaryText,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
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

class _InsightsBridgeRibbon extends StatelessWidget {
  const _InsightsBridgeRibbon({required this.darkGlass});

  final bool darkGlass;

  @override
  Widget build(BuildContext context) {
    final primaryText = darkGlass ? Colors.white : const Color(0xFF0F172A);
    final accentGreen = darkGlass
        ? const Color(0xFF34D399)
        : const Color(0xFF059669);

    return Center(
      child: _GlassStageChip(
        darkGlass: darkGlass,
        elevated: true,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: accentGreen,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Safe / Day ₹1,120  •  80% Alerts  •  PDF/CSV',
                  maxLines: 1,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: primaryText,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeStudioBridgeDock extends StatelessWidget {
  const _ThemeStudioBridgeDock({required this.darkGlass});

  final bool darkGlass;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsCubit>().state;
    final duration = AppMotion.resolve(context, AppMotion.fast);
    final inactiveText = darkGlass
        ? Colors.white.withValues(alpha: 0.78)
        : const Color(0xFF475569);

    const options = [
      (
        key: Key('onboarding_theme_light'),
        mode: ThemeMode.light,
        icon: Icons.light_mode_rounded,
        label: 'Light',
      ),
      (
        key: Key('onboarding_theme_dark'),
        mode: ThemeMode.dark,
        icon: Icons.dark_mode_rounded,
        label: 'Dark',
      ),
      (
        key: Key('onboarding_theme_auto'),
        mode: ThemeMode.system,
        icon: Icons.brightness_auto_rounded,
        label: 'Auto',
      ),
    ];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: _GlassStageChip(
          darkGlass: darkGlass,
          elevated: true,
          padding: const EdgeInsets.all(4.5),
          borderRadius: AppSpacing.radiusFull,
          child: Row(
            children: [
              for (final opt in options)
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: opt.key,
                      customBorder: const StadiumBorder(),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        context.read<SettingsCubit>().setThemeMode(opt.mode);
                      },
                      child: AnimatedContainer(
                        duration: duration,
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          gradient: settings.themeMode == opt.mode
                              ? const LinearGradient(
                                  colors: [
                                    Color(0xFF059669),
                                    Color(0xFF4338CA),
                                  ],
                                )
                              : null,
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusFull,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              opt.icon,
                              size: 14,
                              color: settings.themeMode == opt.mode
                                  ? Colors.white
                                  : inactiveText,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  opt.label,
                                  maxLines: 1,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: settings.themeMode == opt.mode
                                            ? Colors.white
                                            : inactiveText,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Magazine Editorial Copy + 2-Column Tactile Bento Capability Cards
// ---------------------------------------------------------------------------

class _EditorialCopyPanel extends StatelessWidget {
  const _EditorialCopyPanel({
    required this.slide,
    required this.pageIndex,
    required this.isWide,
  });

  final _SlideMeta slide;
  final int pageIndex;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final duration = AppMotion.resolve(context, AppMotion.standard);
    final textScale = MediaQuery.textScalerOf(context).scale(14.0) / 14.0;
    final stackBentoVertically = !isWide && textScale >= 1.55;

    final headlineBaseStyle =
        (isWide
                ? Theme.of(context).textTheme.displaySmall
                : Theme.of(context).textTheme.headlineMedium)
            ?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.75,
              height: 1.12,
              color: scheme.onSurface,
            );

    final accentColor = isDark ? slide.darkAccent : slide.accentStart;

    Widget buildBentoTile(({IconData icon, String title, String caption}) c) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        decoration: BoxDecoration(
          color: cfo.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cfo.divider),
          boxShadow: [
            BoxShadow(
              color: cfo.cardShadow,
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: isDark ? 0.18 : 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(c.icon, size: 16, color: accentColor),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.15,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    c.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cfo.subtleText,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) {
        if (duration == Duration.zero) return child;
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        );
      },
      child: Column(
        key: ValueKey<int>(pageIndex),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: isDark ? 0.22 : 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                ),
                child: Text(
                  slide.stepLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: accentColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(slide.eyebrowIcon, size: 14, color: accentColor),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  slide.eyebrow,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: accentColor,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Intentional balanced 2-line magazine headline (zero orphan words!)
          Text.rich(
            TextSpan(
              style: headlineBaseStyle,
              children: [
                TextSpan(text: '${slide.headlineLine1}\n'),
                TextSpan(
                  text: slide.headlineLine2,
                  style: TextStyle(color: accentColor),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            slide.subtitle,
            style:
                (isWide
                        ? Theme.of(context).textTheme.bodyLarge
                        : Theme.of(context).textTheme.bodyMedium)
                    ?.copyWith(color: cfo.subtleText, height: 1.44),
          ),
          const SizedBox(height: 16),
          // 2-Column Tactile Bento Capability Cards
          if (stackBentoVertically)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                buildBentoTile(slide.cards[0]),
                const SizedBox(height: 8),
                buildBentoTile(slide.cards[1]),
              ],
            )
          else
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: buildBentoTile(slide.cards[0])),
                  const SizedBox(width: 10),
                  Expanded(child: buildBentoTile(slide.cards[1])),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Morphing Footer with pill dots + step readout + circular progress-ring CTA.
class _MorphingOnboardingFooter extends StatelessWidget {
  const _MorphingOnboardingFooter({
    required this.currentPage,
    required this.pageCount,
    required this.slide,
    required this.isLastPage,
    required this.isReplay,
    required this.onBack,
    required this.onPrimaryAction,
  });

  final int currentPage;
  final int pageCount;
  final _SlideMeta slide;
  final bool isLastPage;
  final bool isReplay;
  final VoidCallback? onBack;
  final VoidCallback onPrimaryAction;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final duration = AppMotion.resolve(context, AppMotion.standard);
    final progress = (currentPage + 1) / pageCount;

    return Row(
      children: [
        if (onBack != null) ...[
          Material(
            color: cfo.surfaceTonal,
            shape: CircleBorder(side: BorderSide(color: cfo.divider)),
            child: InkWell(
              key: const Key('onboarding_back_btn'),
              customBorder: const CircleBorder(),
              onTap: onBack,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(
                  Icons.arrow_back_rounded,
                  size: 20,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        if (!isLastPage) ...[
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '0${currentPage + 1} / 0$pageCount',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'Swipe or tap to continue',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cfo.subtleText,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _CircularProgressNextButton(
            key: const Key('onboarding_next_btn'),
            progress: progress,
            accentStart: slide.accentStart,
            accentEnd: slide.accentEnd,
            trackColor: cfo.divider,
            onTap: onPrimaryAction,
          ),
        ] else
          Expanded(
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOutCubic,
              height: 54,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [slide.accentStart, slide.accentEnd],
                ),
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                boxShadow: [
                  BoxShadow(
                    color: slide.accentStart.withValues(alpha: 0.30),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: isReplay
                      ? const Key('onboarding_done_btn')
                      : const Key('onboarding_get_started_btn'),
                  customBorder: const StadiumBorder(),
                  onTap: onPrimaryAction,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              isReplay ? 'Done' : 'Get Started',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          isReplay ? Icons.check_rounded : Icons.bolt_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CircularProgressNextButton extends StatelessWidget {
  const _CircularProgressNextButton({
    required this.progress,
    required this.accentStart,
    required this.accentEnd,
    required this.trackColor,
    required this.onTap,
    super.key,
  });

  final double progress;
  final Color accentStart;
  final Color accentEnd;
  final Color trackColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.resolve(context, AppMotion.emphasis);

    return Semantics(
      label: 'Continue to next slide',
      button: true,
      child: RepaintBoundary(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.25, end: progress),
          duration: duration,
          curve: Curves.easeOutCubic,
          builder: (context, animatedProgress, child) {
            return CustomPaint(
              painter: _RingProgressPainter(
                progress: animatedProgress,
                trackColor: trackColor,
                startColor: accentStart,
                endColor: accentEnd,
              ),
              child: child,
            );
          },
          child: SizedBox(
            width: 62,
            height: 62,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [accentStart, accentEnd],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accentStart.withValues(alpha: 0.30),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onTap,
                    child: const SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 22,
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
  }
}

class _RingProgressPainter extends CustomPainter {
  const _RingProgressPainter({
    required this.progress,
    required this.trackColor,
    required this.startColor,
    required this.endColor,
  });

  final double progress;
  final Color trackColor;
  final Color startColor;
  final Color endColor;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 3.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - stroke) / 2;
    if (radius <= 0) return;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(center, radius, trackPaint);

    final sweep = (2 * math.pi) * progress.clamp(0.0, 1.0);
    if (sweep <= 0.01) return;

    const startAngle = -math.pi / 2;
    const capPad = 0.14;
    final activePaint = Paint()
      ..shader = SweepGradient(
        startAngle: 0.0,
        endAngle: (2 * math.pi) + capPad,
        colors: [startColor, startColor, endColor],
        stops: const [0.0, 0.06, 1.0],
        tileMode: TileMode.clamp,
        transform: const GradientRotation(startAngle - capPad),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, startAngle, sweep, false, activePaint);
  }

  @override
  bool shouldRepaint(covariant _RingProgressPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.startColor != startColor ||
      oldDelegate.endColor != endColor;
}
