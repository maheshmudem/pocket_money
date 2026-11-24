import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../bootstrap.dart';
import '../core/security/privacy_screen_service.dart';
import '../core/utilities/clock.dart';
import '../core/utilities/profile_scope_controller.dart';
import '../features/authentication/data/repositories/auth_repository.dart';
import '../features/authentication/presentation/bloc/auth_cubit.dart';
import '../features/budgets/domain/repositories/budget_repository.dart';
import '../features/dashboard/domain/repositories/analytics_repository.dart';
import '../features/dashboard/presentation/bloc/dashboard_bloc.dart';
import '../features/notifications/data/financial_alerts_coordinator.dart';
import '../features/notifications/presentation/bloc/notifications_cubit.dart';
import '../features/profiles/domain/repositories/profile_repository.dart';
import '../features/profiles/presentation/bloc/active_profile_cubit.dart';
import '../features/recurring/data/repositories/drift_recurring_repository.dart';
import '../features/security_lock/data/app_lock_service.dart';
import '../features/security_lock/presentation/bloc/app_lock_cubit.dart';
import '../features/settings/data/settings_repository.dart';
import '../features/settings/presentation/bloc/settings_cubit.dart';
import '../features/transactions/domain/repositories/transaction_repository.dart';
import '../features/transactions/presentation/bloc/transactions_bloc.dart';
import '../shared/widgets/motion_overlays.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

class PocketCfoApp extends StatefulWidget {
  const PocketCfoApp({super.key});

  @override
  State<PocketCfoApp> createState() => _PocketCfoAppState();
}

class _PocketCfoAppState extends State<PocketCfoApp>
    with WidgetsBindingObserver {
  late final GoRouter _router;
  late final RouterRefreshNotifier _routerRefresh;
  late final SettingsCubit _settingsCubit;
  late final AppLockCubit _appLockCubit;
  late final AuthCubit _authCubit;
  late final ActiveProfileCubit _profileCubit;
  late final DashboardBloc _dashboardBloc;
  late final TransactionsBloc _transactionsBloc;
  late final NotificationsCubit _notificationsCubit;
  bool _inBackgroundPrivacyShield = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _settingsCubit = SettingsCubit(
      getIt<SettingsRepository>(),
      alertsCoordinator: getIt<FinancialAlertsCoordinator>(),
      privacyScreen: getIt<PrivacyScreenService>(),
    )..load();
    _appLockCubit = AppLockCubit(
      service: getIt<AppLockService>(),
      clock: getIt<UtcClock>(),
    )..initialize();
    _authCubit = AuthCubit(getIt<AuthRepository>())..initialize();
    _profileCubit = ActiveProfileCubit(
      repository: getIt<ProfileRepository>(),
      scopeController: getIt<ProfileScopeController>(),
      settings: getIt<SettingsRepository>(),
    );
    _dashboardBloc = DashboardBloc(
      analyticsRepository: getIt<AnalyticsRepository>(),
      budgetRepository: getIt<BudgetRepository>(),
      scopeController: getIt<ProfileScopeController>(),
    );
    _transactionsBloc = TransactionsBloc(
      repository: getIt<TransactionRepository>(),
      scopeController: getIt<ProfileScopeController>(),
    );
    _notificationsCubit = NotificationsCubit(
      coordinator: getIt<FinancialAlertsCoordinator>(),
      scopeController: getIt<ProfileScopeController>(),
    );
    _routerRefresh = RouterRefreshNotifier([
      _authCubit.stream,
      _appLockCubit.stream,
      _settingsCubit.stream
          .map((s) => (s.isLoaded, s.hasCompletedOnboarding))
          .distinct(),
      _profileCubit.stream
          .map(
            (s) => s.status == ActiveProfileStatus.empty && s.profiles.isEmpty,
          )
          .distinct(),
    ]);
    _router = buildAppRouter(
      authCubit: _authCubit,
      appLockCubit: _appLockCubit,
      profileCubit: _profileCubit,
      settingsCubit: _settingsCubit,
      refreshListenable: _routerRefresh,
    );
    getIt<FinancialAlertsCoordinator>().initialize(
      onTap: (route) {
        if (route != null && route.isNotEmpty) {
          _router.push(route);
        }
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final curtainOn = _settingsCubit.state.privacyCurtainEnabled;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _appLockCubit.onAppBackgrounded();
      if (curtainOn && !_inBackgroundPrivacyShield) {
        setState(() => _inBackgroundPrivacyShield = true);
      }
    } else if (state == AppLifecycleState.resumed) {
      _appLockCubit.onAppResumed();
      if (_inBackgroundPrivacyShield) {
        setState(() => _inBackgroundPrivacyShield = false);
      }
      _processDueRecurringForActiveProfile();
    }
  }

  Future<void> _processDueRecurringForActiveProfile() async {
    final activeProfile = _profileCubit.state.activeProfile;
    if (activeProfile == null ||
        !getIt.isRegistered<DriftRecurringRepository>()) {
      return;
    }
    try {
      final res = await getIt<DriftRecurringRepository>().processDueRules(
        activeProfile.id,
      );
      if (mounted && (res.valueOrNull ?? 0) > 0) {
        _dashboardBloc.add(const DashboardRefreshRequested());
        _transactionsBloc.add(const TransactionsLoadRequested());
      }
    } catch (_) {
      // Non-fatal background catch-up; manual Run Due remains available.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    _routerRefresh.dispose();
    _settingsCubit.close();
    _appLockCubit.close();
    _authCubit.close();
    _profileCubit.close();
    _dashboardBloc.close();
    _transactionsBloc.close();
    _notificationsCubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _settingsCubit),
        BlocProvider.value(value: _appLockCubit),
        BlocProvider.value(value: _authCubit),
        BlocProvider.value(value: _profileCubit),
        BlocProvider.value(value: _dashboardBloc),
        BlocProvider.value(value: _transactionsBloc),
        BlocProvider.value(value: _notificationsCubit),
      ],
      child: BlocListener<AuthCubit, AuthState>(
        listenWhen: (prev, curr) =>
            prev.status != curr.status || prev.user?.id != curr.user?.id,
        listener: (context, authState) {
          if (authState.status == AuthStatus.authenticated &&
              authState.user != null) {
            _profileCubit.loadProfiles(userId: authState.user!.id);
          } else if (authState.status == AuthStatus.unauthenticated) {
            _profileCubit.clearOnLogout();
          }
        },
        child: BlocListener<ActiveProfileCubit, ActiveProfileState>(
          listenWhen: (prev, curr) =>
              prev.activeProfile?.id != curr.activeProfile?.id &&
              curr.activeProfile != null,
          listener: (_, _) => _processDueRecurringForActiveProfile(),
          child: BlocBuilder<SettingsCubit, SettingsState>(
            builder: (context, settings) {
              return MaterialApp.router(
                title: 'Pocket CFO',
                debugShowCheckedModeBanner: false,
                scrollBehavior: const _PocketCfoScrollBehavior(),
                theme: AppTheme.light(),
                darkTheme: AppTheme.dark(),
                themeMode: settings.themeMode,
                themeAnimationDuration: const Duration(milliseconds: 220),
                themeAnimationCurve: Curves.easeOutCubic,
                routerConfig: _router,
                builder: (context, child) {
                  return BlocBuilder<NotificationsCubit, NotificationsState>(
                    builder: (context, notifState) {
                      return Stack(
                        children: [
                          child ?? const SizedBox.shrink(),
                          CelebrationBurstOverlay(
                            tick: notifState.celebrationTick,
                          ),
                          InAppAlertBannerOverlay(
                            alert: notifState.activeBanner,
                            bannerSeq: notifState.bannerSeq,
                            hideBalances: settings.hideBalances,
                            onDismiss: _notificationsCubit.dismissBanner,
                            onViewRoute: (route) => _router.push(route),
                          ),
                          if (_inBackgroundPrivacyShield)
                            Positioned.fill(
                              child: ColoredBox(
                                color: Theme.of(context).colorScheme.surface,
                                child: const Center(
                                  child: Icon(
                                    Icons.lock_outline_rounded,
                                    size: 56,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Unified smooth elastic scroll physics across all tabs, segments, and modal sheets.
class _PocketCfoScrollBehavior extends MaterialScrollBehavior {
  const _PocketCfoScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(
        decelerationRate: ScrollDecelerationRate.normal,
        parent: AlwaysScrollableScrollPhysics(),
      );

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
