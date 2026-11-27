import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_tokens.dart';
import '../../features/notifications/presentation/bloc/notifications_cubit.dart';
import '../../features/profiles/domain/entities/profile_entity.dart';
import '../../features/profiles/presentation/bloc/active_profile_cubit.dart';
import '../../features/profiles/presentation/pages/profiles_page.dart';
import '../../features/settings/presentation/bloc/settings_cubit.dart';
import '../../features/transactions/presentation/pages/transactions_page.dart';
import '../../shared/widgets/brand_logo.dart';
import '../../shared/widgets/draggable_quick_ball.dart';
import '../../shared/widgets/enterprise_layout.dart';
import '../../shared/widgets/fintech_widgets.dart';
import '../../shared/widgets/motion_overlays.dart';
import '../../shared/widgets/profile_avatar.dart';

/// Three-tier responsive Neo-Fintech enterprise shell:
/// - `< 600dp`: Clean Play Store swipe-down Avatar + Profile Name AppBar +
///   Bottom Navigation Bar with Section Tabs, Quick Add `+`, and Instagram-style Profile Switcher
/// - `600..1023dp`: Clean AppBar + Tablet `NavigationRail`
/// - `>= 1024dp`: Persistent 264dp Enterprise Sidebar + 64dp Contextual Header Bar
class AppShell extends StatefulWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  static const _destinations = [
    (
      icon: Icons.space_dashboard_outlined,
      selectedIcon: Icons.space_dashboard_rounded,
      label: 'Home',
      headerTitle: 'Executive Overview',
      headerSubtitle: 'Balance sheet, monthly flow & active vaults',
    ),
    (
      icon: Icons.account_balance_wallet_outlined,
      selectedIcon: Icons.account_balance_wallet_rounded,
      label: 'Accounts',
      headerTitle: 'Account Portfolio',
      headerSubtitle: 'Managed bank, cash, credit & investment ledgers',
    ),
    (
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long_rounded,
      label: 'Ledger',
      headerTitle: 'Transaction Journal',
      headerSubtitle: 'Immutable double-entry postings & split vouchers',
    ),
    (
      icon: Icons.donut_large_outlined,
      selectedIcon: Icons.pie_chart_rounded,
      label: 'Insights',
      headerTitle: 'Financial Analytics',
      headerSubtitle: 'Category breakdowns, savings rate & statements',
    ),
    (
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
      label: 'Profile',
      headerTitle: 'Profile & Workspace Hub',
      headerSubtitle: 'Vault metrics, sections, appearance, security & session',
    ),
  ];

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with SingleTickerProviderStateMixin {
  FinancialProfile? _bannerProfile;
  bool _bannerVisible = false;
  Timer? _bannerTimer;
  int _lastBranchIndex = 0;
  int _slideDirection = 1;
  late final AnimationController _tabAnimCtrl;
  late final Animation<double> _tabAnimCurve;

  @override
  void initState() {
    super.initState();
    _lastBranchIndex = widget.navigationShell.currentIndex;
    _tabAnimCtrl = AnimationController(
      vsync: this,
      duration: AppMotion.standard,
      value: 1.0,
    );
    _tabAnimCurve = CurvedAnimation(
      parent: _tabAnimCtrl,
      curve: AppMotion.curveEmphasized,
    );
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextIdx = widget.navigationShell.currentIndex;
    if (nextIdx != _lastBranchIndex) {
      _slideDirection = nextIdx > _lastBranchIndex ? 1 : -1;
      _lastBranchIndex = nextIdx;
      if (!MediaQuery.disableAnimationsOf(context)) {
        _tabAnimCtrl.forward(from: 0.0);
      } else {
        _tabAnimCtrl.value = 1.0;
      }
    }
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _tabAnimCtrl.dispose();
    super.dispose();
  }

  void _selectBranch(int idx) {
    final current = widget.navigationShell.currentIndex;
    if (idx != current) {
      _slideDirection = idx > current ? 1 : -1;
      _lastBranchIndex = idx;
      if (!MediaQuery.disableAnimationsOf(context)) {
        _tabAnimCtrl.forward(from: 0.0);
      } else {
        _tabAnimCtrl.value = 1.0;
      }
    }
    widget.navigationShell.goBranch(idx, initialLocation: idx == current);
  }

  void _showSwitchedToast(FinancialProfile profile) {
    if (!mounted) return;
    _bannerTimer?.cancel();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return;
    }
    setState(() {
      _bannerProfile = profile;
      _bannerVisible = true;
    });
    _bannerTimer = Timer(const Duration(milliseconds: 1450), () {
      if (mounted) {
        setState(() => _bannerVisible = false);
      }
    });
  }

  Future<void> _handleGestureCycleProfile({required bool reverse}) async {
    final cubit = context.read<ActiveProfileCubit>();
    final state = cubit.state;
    if (state.profiles.length < 2) {
      if (state.activeProfile != null) {
        HapticFeedback.lightImpact();
        await _openPlayStoreProfileModal(
          context,
          state.profiles,
          state.activeProfile!,
        );
      }
      return;
    }
    HapticFeedback.mediumImpact();
    final switched = await cubit.cycleNextProfile(reverse: reverse);
    if (switched != null && mounted) {
      _showSwitchedToast(switched);
    }
  }

  Widget _wrapBodyWithToast(
    Widget child, {
    required FinancialProfile? activeProfile,
    required bool showQuickBall,
    double quickBallBottomClearance = 16.0,
  }) {
    final disableAnim = MediaQuery.disableAnimationsOf(context);

    final animatedBody = disableAnim
        ? child
        : AnimatedBuilder(
            animation: _tabAnimCurve,
            child: child,
            builder: (_, inner) {
              final t = _tabAnimCurve.value;
              return Opacity(
                opacity: (0.85 + 0.15 * t).clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset((1.0 - t) * 16.0 * _slideDirection, 0),
                  child: inner,
                ),
              );
            },
          );

    return Stack(
      children: [
        animatedBody,
        if (showQuickBall &&
            activeProfile != null &&
            activeProfile.permissions.canPostTransaction)
          Positioned.fill(
            child: DraggableQuickBall(
              profile: activeProfile,
              bottomClearance: quickBallBottomClearance,
            ),
          ),
        Positioned(
          top: 10,
          left: 16,
          right: 16,
          child: IgnorePointer(
            child: Center(
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                offset: _bannerVisible ? Offset.zero : const Offset(0, -0.6),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: _bannerVisible && _bannerProfile != null ? 1.0 : 0.0,
                  child: _bannerProfile == null
                      ? const SizedBox.shrink()
                      : _SwitchedProfilePill(profile: _bannerProfile!),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileState = context.watch<ActiveProfileCubit>().state;
    final activeProfile = profileState.activeProfile;
    final profiles = profileState.profiles;
    final hideBalances = context.watch<SettingsCubit>().state.hideBalances;
    final scheme = Theme.of(context).colorScheme;
    final cfo = context.cfoColors;
    final navShell = widget.navigationShell;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= AppBreakpoints.desktop) {
          final currentDest = AppShell._destinations[navShell.currentIndex];
          return Scaffold(
            body: Row(
              children: [
                _EnterpriseSidebar(
                  navigationShell: navShell,
                  activeProfile: activeProfile,
                  profiles: profiles,
                  onSelectBranch: _selectBranch,
                  onSwipeSwitch: (reverse) =>
                      _handleGestureCycleProfile(reverse: reverse),
                  onOpenProfileModal: () {
                    if (activeProfile != null) {
                      _openPlayStoreProfileModal(
                        context,
                        profiles,
                        activeProfile,
                      );
                    }
                  },
                ),
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        height: 64,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                        ),
                        decoration: BoxDecoration(
                          color: cfo.surfaceElevated,
                          border: Border(
                            bottom: BorderSide(color: cfo.divider),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: AnimatedSwitcher(
                                duration: AppMotion.resolve(
                                  context,
                                  AppMotion.fast,
                                ),
                                switchInCurve: AppMotion.curveEmphasized,
                                child: Align(
                                  key: ValueKey<String>(
                                    currentDest.headerTitle,
                                  ),
                                  alignment: Alignment.centerLeft,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        currentDest.headerTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                      Text(
                                        currentDest.headerSubtitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(color: cfo.subtleText),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            ..._buildDesktopHeaderActions(
                              context,
                              hideBalances: hideBalances,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _wrapBodyWithToast(
                          navShell,
                          activeProfile: activeProfile,
                          showQuickBall: false,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        final isTablet = constraints.maxWidth >= AppBreakpoints.tablet;
        final appBar = _buildCleanProfileAppBar(
          context,
          activeProfile: activeProfile,
          profiles: profiles,
          hideBalances: hideBalances,
          isTablet: isTablet,
        );

        if (isTablet) {
          return Scaffold(
            appBar: appBar,
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: navShell.currentIndex,
                  backgroundColor: cfo.surfaceElevated,
                  labelType: NavigationRailLabelType.all,
                  leading:
                      activeProfile != null &&
                          activeProfile.permissions.canPostTransaction
                      ? Padding(
                          padding: const EdgeInsets.only(
                            top: AppSpacing.sm,
                            bottom: AppSpacing.md,
                            left: AppSpacing.xs,
                            right: AppSpacing.xs,
                          ),
                          child: FloatingActionButton.small(
                            tooltip: 'Add Entry',
                            elevation: 0,
                            backgroundColor: scheme.primary,
                            foregroundColor: scheme.onPrimary,
                            onPressed: () =>
                                openAddTransactionSheet(context, activeProfile),
                            child: const Icon(Icons.add_rounded),
                          ),
                        )
                      : const SizedBox(height: AppSpacing.sm),
                  onDestinationSelected: _selectBranch,
                  destinations: [
                    for (var i = 0; i < AppShell._destinations.length; i++)
                      if (i == 4)
                        NavigationRailDestination(
                          icon: ProfileAvatar(
                            profile: activeProfile,
                            size: 24,
                            selectedRing: false,
                          ),
                          selectedIcon: ProfileAvatar(
                            profile: activeProfile,
                            size: 24,
                            selectedRing: true,
                          ),
                          label: Text(AppShell._destinations[i].label),
                        )
                      else
                        NavigationRailDestination(
                          icon: Icon(AppShell._destinations[i].icon),
                          selectedIcon: Icon(
                            AppShell._destinations[i].selectedIcon,
                          ),
                          label: Text(AppShell._destinations[i].label),
                        ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: _wrapBodyWithToast(
                    navShell,
                    activeProfile: activeProfile,
                    showQuickBall: navShell.currentIndex == 0,
                  ),
                ),
              ],
            ),
          );
        }

        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Scaffold(
          appBar: appBar,
          body: _wrapBodyWithToast(
            navShell,
            activeProfile: activeProfile,
            showQuickBall: navShell.currentIndex == 0,
            quickBallBottomClearance: 16.0,
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 9),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(
                        0xFF090A0D,
                      ).withValues(alpha: isDark ? 0.50 : 0.16),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isDark
                              ? [
                                  const Color(
                                    0xFF151822,
                                  ).withValues(alpha: 0.96),
                                  const Color(
                                    0xFF0E1118,
                                  ).withValues(alpha: 0.98),
                                ]
                              : [
                                  const Color(
                                    0xFF0F131D,
                                  ).withValues(alpha: 0.97),
                                  const Color(
                                    0xFF171C29,
                                  ).withValues(alpha: 0.98),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withValues(
                            alpha: isDark ? 0.14 : 0.12,
                          ),
                          width: 1.0,
                        ),
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 62),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: _DockNavItem(
                                  icon: AppShell._destinations[0].icon,
                                  selectedIcon:
                                      AppShell._destinations[0].selectedIcon,
                                  label: AppShell._destinations[0].label,
                                  selected: navShell.currentIndex == 0,
                                  onTap: () => _selectBranch(0),
                                ),
                              ),
                              Expanded(
                                child: _DockNavItem(
                                  icon: AppShell._destinations[1].icon,
                                  selectedIcon:
                                      AppShell._destinations[1].selectedIcon,
                                  label: AppShell._destinations[1].label,
                                  selected: navShell.currentIndex == 1,
                                  onTap: () => _selectBranch(1),
                                ),
                              ),
                              Expanded(
                                child: _DockNavItem(
                                  icon: AppShell._destinations[2].icon,
                                  selectedIcon:
                                      AppShell._destinations[2].selectedIcon,
                                  label: AppShell._destinations[2].label,
                                  selected: navShell.currentIndex == 2,
                                  onTap: () => _selectBranch(2),
                                ),
                              ),
                              Expanded(
                                child: _DockNavItem(
                                  icon: AppShell._destinations[3].icon,
                                  selectedIcon:
                                      AppShell._destinations[3].selectedIcon,
                                  label: AppShell._destinations[3].label,
                                  selected: navShell.currentIndex == 3,
                                  onTap: () => _selectBranch(3),
                                ),
                              ),
                              Expanded(
                                child: _InstagramProfileDockItem(
                                  key: const Key('bottom_nav_profile_switcher'),
                                  activeProfile: activeProfile,
                                  hasMultipleProfiles: profiles.length > 1,
                                  selected: navShell.currentIndex == 4,
                                  onTap: () => _selectBranch(4),
                                  onQuickCycleSwitch: (reverse) =>
                                      _handleGestureCycleProfile(
                                        reverse: reverse,
                                      ),
                                  onLongPressOpenSwitcher: () {
                                    if (activeProfile != null) {
                                      HapticFeedback.selectionClick();
                                      _openInstagramBottomSwitcher(
                                        context,
                                        profiles,
                                        activeProfile,
                                      );
                                    } else {
                                      _selectBranch(4);
                                    }
                                  },
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
        );
      },
    );
  }

  /// Clean modern AppBar showing the active Profile Avatar + Name directly
  /// (zero rounded pill box around the header) with Google Play Store swipe-down switching.
  PreferredSizeWidget _buildCleanProfileAppBar(
    BuildContext context, {
    required FinancialProfile? activeProfile,
    required List<FinancialProfile> profiles,
    required bool hideBalances,
    required bool isTablet,
  }) {
    final actionSize = isTablet ? 40.0 : 38.0;
    final iconSize = isTablet ? 21.0 : 19.5;

    return AppBar(
      toolbarHeight: 62,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      titleSpacing: AppSpacing.md,
      title: activeProfile != null
          ? _PlayStoreProfileAppBarHeader(
              key: const Key('appbar_profile_switcher'),
              activeProfile: activeProfile,
              profilesCount: profiles.length,
              onTap: () =>
                  _openPlayStoreProfileModal(context, profiles, activeProfile),
              onSwipeSwitch: (reverse) =>
                  _handleGestureCycleProfile(reverse: reverse),
            )
          : Row(
              children: [
                const PocketCfoLogo(size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Pocket CFO',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
      actions: [
        _HeaderActionButton(
          size: actionSize,
          iconSize: iconSize,
          tooltip: hideBalances ? 'Show balances' : 'Hide balances',
          onPressed: () => context.read<SettingsCubit>().toggleHideBalances(),
          icon: hideBalances
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
        ),
        const SizedBox(width: 8),
        BlocSelector<NotificationsCubit, NotificationsState, int>(
          selector: (s) => s.unreadCount,
          builder: (context, unreadCount) => AnimatedNotificationBell(
            size: actionSize,
            iconSize: iconSize,
            unreadCount: unreadCount,
            onPressed: () => context.push('/notifications'),
          ),
        ),
        if (isTablet) ...[
          const SizedBox(width: 8),
          _HeaderActionButton(
            size: actionSize,
            iconSize: iconSize,
            tooltip: 'Settings & Security',
            onPressed: () => context.push('/settings'),
            icon: Icons.tune_rounded,
          ),
        ],
        const SizedBox(width: AppSpacing.md),
      ],
    );
  }

  List<Widget> _buildDesktopHeaderActions(
    BuildContext context, {
    required bool hideBalances,
  }) {
    return [
      _HeaderActionButton(
        size: 42,
        iconSize: 22,
        tooltip: hideBalances ? 'Show balances' : 'Hide balances',
        onPressed: () => context.read<SettingsCubit>().toggleHideBalances(),
        icon: hideBalances
            ? Icons.visibility_off_outlined
            : Icons.visibility_outlined,
      ),
      const SizedBox(width: 4),
      _HeaderActionButton(
        size: 42,
        iconSize: 22,
        tooltip: 'All Features',
        onPressed: () => _openFinanceHubSheet(context),
        icon: Icons.grid_view_rounded,
      ),
      const SizedBox(width: 4),
      BlocSelector<NotificationsCubit, NotificationsState, int>(
        selector: (s) => s.unreadCount,
        builder: (context, unreadCount) => AnimatedNotificationBell(
          size: 42,
          iconSize: 22,
          unreadCount: unreadCount,
          onPressed: () => context.push('/notifications'),
        ),
      ),
      const SizedBox(width: 4),
      _HeaderActionButton(
        size: 42,
        iconSize: 22,
        tooltip: 'Settings & Security',
        onPressed: () => context.push('/settings'),
        icon: Icons.tune_rounded,
      ),
    ];
  }

  /// Google Play Store-style Account / Profile Switcher modal.
  Future<void> _openPlayStoreProfileModal(
    BuildContext context,
    List<FinancialProfile> profiles,
    FinancialProfile activeProfile,
  ) async {
    final scheme = Theme.of(context).colorScheme;
    final cfo = context.cfoColors;
    final otherProfiles = profiles
        .where((p) => p.id != activeProfile.id)
        .toList();

    await showEnterpriseModal<void>(
      context: context,
      maxWidth: 460,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const PocketCfoLogo(size: 26),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Pocket CFO Vaults',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(sheetCtx).pop(),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                // Active Profile Card (Play Store style)
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: cfo.surfaceTonal,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                    border: Border.all(color: cfo.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ProfileAvatar(
                            profile: activeProfile,
                            size: 48,
                            selectedRing: true,
                            showTypeBadge: true,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  activeProfile.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                Text(
                                  '${activeProfile.profileType.label} • ${activeProfile.baseCurrencyCode} • ${activeProfile.role.label}',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: cfo.subtleText),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.check_circle_rounded,
                            color: scheme.primary,
                            size: 22,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(40),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(sheetCtx).pop();
                          _selectBranch(4);
                        },
                        child: const Text('View Profile & Workspace Hub'),
                      ),
                    ],
                  ),
                ),
                if (otherProfiles.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'SWITCH TO ANOTHER PROFILE',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cfo.subtleText,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  for (final p in otherProfiles) ...[
                    PressScaleCard(
                      onTap: () async {
                        Navigator.of(sheetCtx).pop();
                        HapticFeedback.mediumImpact();
                        final ok = await context
                            .read<ActiveProfileCubit>()
                            .switchProfile(p.id);
                        if (ok && mounted) {
                          _showSwitchedToast(p);
                        }
                      },
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          ProfileAvatar(profile: p, size: 38),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.name,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  '${p.profileType.label} • ${p.baseCurrencyCode} • ${p.role.label}',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: cfo.subtleText),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 14,
                            color: cfo.subtleText,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                ] else ...[
                  const SizedBox(height: AppSpacing.sm),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'Tip: Add a second profile (e.g., Family or Business) to swipe down on the top avatar and switch instantly like Google Play.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: cfo.subtleText),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.of(sheetCtx).pop();
                          openCreateProfileModal(context);
                        },
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: const Text('Add Profile'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(sheetCtx).pop();
                          context.push('/profiles');
                        },
                        icon: const Icon(Icons.tune_rounded),
                        label: const Text('Manage'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Instagram-style Bottom Account / Profile Switcher Sheet triggered by long-pressing
  /// the Profile avatar on the Bottom Navigation Bar.
  Future<void> _openInstagramBottomSwitcher(
    BuildContext context,
    List<FinancialProfile> profiles,
    FinancialProfile activeProfile,
  ) async {
    final scheme = Theme.of(context).colorScheme;
    final cfo = context.cfoColors;

    await showEnterpriseModal<void>(
      context: context,
      maxWidth: 460,
      builder: (sheetCtx) => SafeArea(
        key: const Key('instagram_profile_sheet'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Switch Profile',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Double-tap the bottom profile avatar anytime for instant flip switch',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: cfo.subtleText),
                ),
                const SizedBox(height: 14),
                for (final p in profiles)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: p.id == activeProfile.id
                          ? scheme.primaryContainer.withValues(alpha: 0.45)
                          : cfo.surfaceTonal,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMd,
                        ),
                        side: BorderSide(
                          color: p.id == activeProfile.id
                              ? scheme.primary.withValues(alpha: 0.45)
                              : cfo.divider.withValues(alpha: 0.7),
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMd,
                        ),
                        onTap: () async {
                          Navigator.of(sheetCtx).pop();
                          if (p.id == activeProfile.id) {
                            _selectBranch(4);
                            return;
                          }
                          HapticFeedback.mediumImpact();
                          final ok = await context
                              .read<ActiveProfileCubit>()
                              .switchProfile(p.id);
                          if (ok && mounted) {
                            _showSwitchedToast(p);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              ProfileAvatar(
                                profile: p,
                                size: 40,
                                selectedRing: p.id == activeProfile.id,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: p.id == activeProfile.id
                                                ? FontWeight.w800
                                                : FontWeight.w700,
                                          ),
                                    ),
                                    Text(
                                      '${p.profileType.label} • ${p.baseCurrencyCode}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: cfo.subtleText),
                                    ),
                                  ],
                                ),
                              ),
                              if (p.id == activeProfile.id)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 3.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(
                                      AppSpacing.radiusFull,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.check_circle_rounded,
                                        size: 13,
                                        color: scheme.primary,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Active',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: scheme.primary,
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                Icon(
                                  Icons.swap_horiz_rounded,
                                  size: 18,
                                  color: cfo.subtleText,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Material(
                  color: scheme.primaryContainer.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    side: BorderSide(
                      color: scheme.primary.withValues(alpha: 0.25),
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    onTap: () {
                      Navigator.of(sheetCtx).pop();
                      openCreateProfileModal(context);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.add_rounded,
                              color: scheme.primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Add Financial Profile',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: scheme.primary,
                                      ),
                                ),
                                Text(
                                  'Create isolated personal, family, or business ledger',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: cfo.subtleText),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: scheme.primary,
                          ),
                        ],
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

  Future<void> _openFinanceHubSheet(BuildContext context) async {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;
    final items = [
      (
        icon: Icons.pie_chart_rounded,
        label: 'Budgets',
        route: '/budgets',
        fg: scheme.primary,
        bg: scheme.primaryContainer,
      ),
      (
        icon: Icons.savings_rounded,
        label: 'Goals',
        route: '/goals',
        fg: cfo.income,
        bg: cfo.incomeContainer,
      ),
      (
        icon: Icons.request_quote_rounded,
        label: 'Loans & EMI',
        route: '/loans',
        fg: cfo.warning,
        bg: cfo.warningContainer,
      ),
      (
        icon: Icons.repeat_rounded,
        label: 'Recurring',
        route: '/recurring',
        fg: cfo.transfer,
        bg: cfo.transferContainer,
      ),
      (
        icon: Icons.upload_file_rounded,
        label: 'CSV Import',
        route: '/import-csv',
        fg: scheme.tertiary,
        bg: scheme.tertiaryContainer,
      ),
      (
        icon: Icons.category_rounded,
        label: 'Categories',
        route: '/categories',
        fg: cfo.expense,
        bg: cfo.expenseContainer,
      ),
      (
        icon: Icons.cloud_sync_rounded,
        label: 'Cloud Sync',
        route: '/sync',
        fg: scheme.primary,
        bg: scheme.primaryContainer,
      ),
      (
        icon: Icons.shield_rounded,
        label: 'Backup',
        route: '/backup',
        fg: cfo.success,
        bg: cfo.successContainer,
      ),
      (
        icon: Icons.layers_rounded,
        label: 'Profiles',
        route: '/profiles',
        fg: cfo.transfer,
        bg: cfo.transferContainer,
      ),
    ];

    await showEnterpriseModal<void>(
      context: context,
      maxWidth: 540,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                EnterpriseModalHeader(
                  title: 'Finance Modules',
                  subtitle:
                      'Jump directly to any planning, import, or vault tool.',
                  icon: Icons.grid_view_rounded,
                  iconColor: scheme.primary,
                  iconBackgroundColor: scheme.primaryContainer,
                ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: AppSpacing.sm,
                    mainAxisSpacing: AppSpacing.sm,
                    childAspectRatio: 1.08,
                  ),
                  itemCount: items.length,
                  itemBuilder: (_, idx) {
                    final item = items[idx];
                    return PressScaleCard(
                      onTap: () {
                        Navigator.of(sheetCtx).pop();
                        context.push(item.route);
                      },
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconSquircle(
                            icon: item.icon,
                            iconColor: item.fg,
                            backgroundColor: item.bg,
                            size: 40,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Google Play Store-inspired AppBar header:
/// Displays Profile Avatar + clean Profile Name (no rounded pill border)
/// and supports vertical swipe-down (or swipe-up) to switch profiles automatically.
class _PlayStoreProfileAppBarHeader extends StatefulWidget {
  const _PlayStoreProfileAppBarHeader({
    required this.activeProfile,
    required this.profilesCount,
    required this.onTap,
    required this.onSwipeSwitch,
    super.key,
  });

  final FinancialProfile activeProfile;
  final int profilesCount;
  final VoidCallback onTap;
  final ValueChanged<bool> onSwipeSwitch;

  @override
  State<_PlayStoreProfileAppBarHeader> createState() =>
      _PlayStoreProfileAppBarHeaderState();
}

class _PlayStoreProfileAppBarHeaderState
    extends State<_PlayStoreProfileAppBarHeader> {
  double _dragDy = 0;
  int _slideDirection = 1;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cfo = context.cfoColors;
    final profile = widget.activeProfile;
    final duration = AppMotion.resolve(context, AppMotion.standard);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onVerticalDragUpdate: (details) {
        setState(() {
          _dragDy = (_dragDy + details.delta.dy * 0.58).clamp(-24.0, 28.0);
        });
      },
      onVerticalDragCancel: () => setState(() => _dragDy = 0),
      onVerticalDragEnd: (details) {
        final dy = _dragDy;
        final vy = details.primaryVelocity ?? 0;
        setState(() => _dragDy = 0);
        if (dy >= 14 || vy >= 190) {
          _slideDirection = 1;
          widget.onSwipeSwitch(false);
        } else if (dy <= -14 || vy <= -190) {
          _slideDirection = -1;
          widget.onSwipeSwitch(true);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _dragDy * 0.45, 0),
        child: AnimatedSwitcher(
          duration: duration,
          transitionBuilder: (child, animation) {
            final isIncoming = child.key == ValueKey<String>(profile.id.value);
            final beginOffset = isIncoming
                ? Offset(0, -0.45 * _slideDirection)
                : Offset(0, 0.45 * _slideDirection);
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(begin: beginOffset, end: Offset.zero)
                    .animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                child: child,
              ),
            );
          },
          child: Row(
            key: ValueKey<String>(profile.id.value),
            children: [
              ProfileAvatar(profile: profile, size: 38, showTypeBadge: true),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            '${profile.name} (${profile.baseCurrencyCode})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: cfo.subtleText,
                        ),
                      ],
                    ),
                    Text(
                      widget.profilesCount > 1
                          ? '${profile.profileType.label} • Swipe down to switch'
                          : '${profile.profileType.label} • ${profile.role.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cfo.subtleText,
                        fontSize: 11,
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

/// Sleek floating pill toast confirming instant profile switches without blocking UI.
class _SwitchedProfilePill extends StatelessWidget {
  const _SwitchedProfilePill({required this.profile});

  final FinancialProfile profile;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;

    return Material(
      elevation: 6,
      shadowColor: cfo.cardShadow,
      color: cfo.surfaceElevated,
      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ProfileAvatar(profile: profile, size: 22),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Switched to ${profile.name} (${profile.baseCurrencyCode})',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.check_circle_rounded, size: 16, color: cfo.success),
          ],
        ),
      ),
    );
  }
}

/// Instagram-inspired Bottom Navigation Bar Profile Avatar Item:
/// - Single tap: navigates immediately (`0ms` delay) to Profile & Workspace Hub
/// - Rapid double-tap or vertical flick: 3D coin-flip animation + instant switch to next profile
/// - Long-press: opens Instagram-style bottom account switcher sheet
class _InstagramProfileDockItem extends StatefulWidget {
  const _InstagramProfileDockItem({
    required this.activeProfile,
    required this.hasMultipleProfiles,
    required this.selected,
    required this.onTap,
    required this.onQuickCycleSwitch,
    required this.onLongPressOpenSwitcher,
    super.key,
  });

  final FinancialProfile? activeProfile;
  final bool hasMultipleProfiles;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<bool> onQuickCycleSwitch;
  final VoidCallback onLongPressOpenSwitcher;

  @override
  State<_InstagramProfileDockItem> createState() =>
      _InstagramProfileDockItemState();
}

class _InstagramProfileDockItemState extends State<_InstagramProfileDockItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flipCtrl;
  DateTime? _lastTapAt;
  double _dragDy = 0;

  @override
  void initState() {
    super.initState();
    _flipCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
  }

  @override
  void didUpdateWidget(covariant _InstagramProfileDockItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeProfile?.id != widget.activeProfile?.id &&
        oldWidget.activeProfile != null &&
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      _flipCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _flipCtrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    final now = DateTime.now();
    if (_lastTapAt != null &&
        now.difference(_lastTapAt!) <= const Duration(milliseconds: 340)) {
      _lastTapAt = null;
      if (!(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
        _flipCtrl.forward(from: 0);
      }
      widget.onQuickCycleSwitch(false);
      return;
    }
    _lastTapAt = now;
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cfo = context.cfoColors;

    return Semantics(
      selected: widget.selected,
      label: 'Profile',
      button: true,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleTap,
          onLongPress: widget.onLongPressOpenSwitcher,
          onVerticalDragUpdate: (d) {
            _dragDy += d.delta.dy;
          },
          onVerticalDragCancel: () => _dragDy = 0,
          onVerticalDragEnd: (d) {
            final dy = _dragDy;
            final vy = d.primaryVelocity ?? 0;
            _dragDy = 0;
            if (dy.abs() >= 14 || vy.abs() >= 180) {
              if (!(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
                _flipCtrl.forward(from: 0);
              }
              widget.onQuickCycleSwitch(dy < 0 || vy < -180);
            }
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedBuilder(
                  animation: _flipCtrl,
                  builder: (context, child) {
                    final angle =
                        Curves.easeOutBack.transform(_flipCtrl.value) *
                        math.pi *
                        2;
                    return Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.002)
                        ..rotateY(angle),
                      child: child,
                    );
                  },
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ProfileAvatar(
                        profile: widget.activeProfile,
                        size: 22,
                        selectedRing: widget.selected,
                      ),
                      if (widget.hasMultipleProfiles && !widget.selected)
                        Positioned(
                          right: -3,
                          top: -2,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: scheme.primary,
                              border: Border.all(
                                color: cfo.surfaceElevated,
                                width: 1.3,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Profile',
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: widget.selected
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.56),
                      fontWeight: widget.selected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      fontSize: 10.5,
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

class _HeaderActionButton extends StatelessWidget {
  const _HeaderActionButton({
    required this.size,
    required this.iconSize,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final double size;
  final double iconSize;
  final String tooltip;
  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cfo.surfaceElevated,
        shape: BoxShape.circle,
        border: Border.all(color: cfo.divider.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: cfo.cardShadow,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(width: size, height: size),
        visualDensity: VisualDensity.compact,
        iconSize: iconSize,
        icon: Icon(icon),
      ),
    );
  }
}

class _EnterpriseSidebar extends StatelessWidget {
  const _EnterpriseSidebar({
    required this.navigationShell,
    required this.activeProfile,
    required this.profiles,
    required this.onSelectBranch,
    required this.onSwipeSwitch,
    required this.onOpenProfileModal,
  });

  final StatefulNavigationShell navigationShell;
  final FinancialProfile? activeProfile;
  final List<FinancialProfile> profiles;
  final ValueChanged<int> onSelectBranch;
  final ValueChanged<bool> onSwipeSwitch;
  final VoidCallback onOpenProfileModal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cfo = context.cfoColors;
    final location = GoRouterState.of(context).matchedLocation;

    return Container(
      width: 264,
      decoration: BoxDecoration(
        color: cfo.surfaceElevated,
        border: Border(right: BorderSide(color: cfo.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: cfo.divider)),
            ),
            child: Row(
              children: [
                const PocketCfoLogo(size: 32),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Pocket CFO',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  ),
                  child: Text(
                    'VAULT',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (activeProfile != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: _PlayStoreProfileAppBarHeader(
                key: const Key('sidebar_profile_switcher'),
                activeProfile: activeProfile!,
                profilesCount: profiles.length,
                onTap: onOpenProfileModal,
                onSwipeSwitch: onSwipeSwitch,
              ),
            ),
          if (activeProfile != null &&
              activeProfile!.permissions.canPostTransaction)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Semantics(
                button: true,
                label: 'Add Entry',
                child: Tooltip(
                  message: 'Add Entry',
                  child: FilledButton.icon(
                    onPressed: () =>
                        openAddTransactionSheet(context, activeProfile!),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('New Transaction'),
                  ),
                ),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.xs,
                AppSpacing.sm,
                AppSpacing.lg,
              ),
              children: [
                const _SidebarSectionLabel('OVERVIEW'),
                for (var i = 0; i < AppShell._destinations.length; i++)
                  _SidebarNavTile(
                    icon: AppShell._destinations[i].icon,
                    selectedIcon: AppShell._destinations[i].selectedIcon,
                    label: AppShell._destinations[i].label,
                    selected: navigationShell.currentIndex == i,
                    onTap: () => onSelectBranch(i),
                  ),
                const SizedBox(height: AppSpacing.md),
                const _SidebarSectionLabel('PLANNING'),
                _SidebarNavTile(
                  icon: Icons.pie_chart_outline_rounded,
                  selectedIcon: Icons.pie_chart_rounded,
                  label: 'Budgets',
                  selected: location == '/budgets',
                  onTap: () => context.push('/budgets'),
                ),
                _SidebarNavTile(
                  icon: Icons.savings_outlined,
                  selectedIcon: Icons.savings_rounded,
                  label: 'Savings Goals',
                  selected: location == '/goals',
                  onTap: () => context.push('/goals'),
                ),
                _SidebarNavTile(
                  icon: Icons.request_quote_outlined,
                  selectedIcon: Icons.request_quote_rounded,
                  label: 'Loans & EMI',
                  selected: location == '/loans',
                  onTap: () => context.push('/loans'),
                ),
                _SidebarNavTile(
                  icon: Icons.repeat_rounded,
                  selectedIcon: Icons.repeat_rounded,
                  label: 'Recurring',
                  selected: location == '/recurring',
                  onTap: () => context.push('/recurring'),
                ),
                const SizedBox(height: AppSpacing.md),
                const _SidebarSectionLabel('OPERATIONS'),
                _SidebarNavTile(
                  icon: Icons.category_outlined,
                  selectedIcon: Icons.category_rounded,
                  label: 'Categories',
                  selected: location == '/categories',
                  onTap: () => context.push('/categories'),
                ),
                _SidebarNavTile(
                  icon: Icons.upload_file_outlined,
                  selectedIcon: Icons.upload_file_rounded,
                  label: 'CSV Import',
                  selected: location == '/import-csv',
                  onTap: () => context.push('/import-csv'),
                ),
                _SidebarNavTile(
                  icon: Icons.cloud_sync_outlined,
                  selectedIcon: Icons.cloud_sync_rounded,
                  label: 'Sync & Backup',
                  selected: location == '/sync' || location == '/backup',
                  onTap: () => context.push('/sync'),
                ),
                _SidebarNavTile(
                  icon: Icons.layers_outlined,
                  selectedIcon: Icons.layers_rounded,
                  label: 'Manage Profiles',
                  selected: location == '/profiles',
                  onTap: () => context.push('/profiles'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarSectionLabel extends StatelessWidget {
  const _SidebarSectionLabel(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.xxs,
      ),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: context.cfoColors.subtleText,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SidebarNavTile extends StatefulWidget {
  const _SidebarNavTile({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SidebarNavTile> createState() => _SidebarNavTileState();
}

class _SidebarNavTileState extends State<_SidebarNavTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cfo = context.cfoColors;
    final bg = widget.selected
        ? scheme.primaryContainer
        : (_hovered ? cfo.surfaceTonal : Colors.transparent);
    final fg = widget.selected ? scheme.primary : scheme.onSurfaceVariant;
    final duration = AppMotion.resolve(context, AppMotion.fast);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: AnimatedContainer(
        duration: duration,
        curve: AppMotion.curveStandard,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            onTap: widget.onTap,
            onHover: (v) {
              if (_hovered != v) setState(() => _hovered = v);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  AnimatedSwitcher(
                    duration: duration,
                    child: Icon(
                      widget.selected ? widget.selectedIcon : widget.icon,
                      key: ValueKey<bool>(widget.selected),
                      size: 20,
                      color: fg,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: widget.selected ? scheme.onPrimaryContainer : fg,
                        fontWeight: widget.selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
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
}

class _DockNavItem extends StatefulWidget {
  const _DockNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_DockNavItem> createState() => _DockNavItemState();
}

class _DockNavItemState extends State<_DockNavItem> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.resolve(context, AppMotion.fast);
    final muted = Colors.white.withValues(alpha: 0.58);

    return Semantics(
      selected: widget.selected,
      label: widget.label,
      button: true,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onHover: (v) {
            if (_hovered != v) setState(() => _hovered = v);
          },
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  scale: _pressed ? 0.92 : (widget.selected ? 1.05 : 1.0),
                  duration: duration,
                  curve: AppMotion.curveSpring,
                  child: AnimatedContainer(
                    duration: duration,
                    curve: AppMotion.curveSpring,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4.5,
                    ),
                    decoration: BoxDecoration(
                      color: widget.selected
                          ? Colors.white.withValues(alpha: 0.16)
                          : (_hovered
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.transparent),
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusFull,
                      ),
                      border: widget.selected
                          ? Border.all(
                              color: Colors.white.withValues(alpha: 0.20),
                              width: 0.9,
                            )
                          : null,
                    ),
                    child: AnimatedSwitcher(
                      duration: duration,
                      child: Icon(
                        widget.selected ? widget.selectedIcon : widget.icon,
                        key: ValueKey<bool>(widget.selected),
                        size: 20,
                        color: widget.selected ? Colors.white : muted,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2.5),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: widget.selected ? Colors.white : muted,
                        fontWeight: widget.selected
                            ? FontWeight.w800
                            : FontWeight.w500,
                        fontSize: 10.5,
                        letterSpacing: widget.selected ? 0.1 : 0,
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
