import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_tokens.dart';
import '../../features/accounts/presentation/pages/accounts_page.dart';
import '../../features/ai_coach/presentation/pages/ai_coach_page.dart';
import '../../features/analytics/presentation/pages/analytics_reports_page.dart';
import '../../features/authentication/presentation/bloc/auth_cubit.dart';
import '../../features/authentication/presentation/pages/welcome_auth_page.dart';
import '../../features/budgets/presentation/pages/budgets_page.dart';
import '../../features/categories/presentation/pages/categories_page.dart';
import '../../features/dashboard/presentation/pages/dashboard_page.dart';
import '../../features/import_export/presentation/pages/csv_import_page.dart';
import '../../features/life_planner/presentation/pages/life_stage_planner_page.dart';
import '../../features/loans/presentation/pages/loans_page.dart';
import '../../features/monthly_tracker/presentation/pages/monthly_tracker_page.dart';
import '../../features/onboarding/presentation/pages/onboarding_page.dart';
import '../../features/profiles/presentation/bloc/active_profile_cubit.dart';
import '../../features/profiles/presentation/pages/profile_hub_page.dart';
import '../../features/profiles/presentation/pages/profiles_page.dart';
import '../../features/recurring/presentation/pages/recurring_notifications_page.dart';
import '../../features/savings_goals/presentation/pages/savings_goals_page.dart';
import '../../features/security_lock/presentation/bloc/app_lock_cubit.dart';
import '../../features/security_lock/presentation/pages/app_lock_screen.dart';
import '../../features/settings/presentation/bloc/settings_cubit.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/sync/presentation/pages/sync_backup_page.dart';
import '../../features/transactions/presentation/pages/transactions_page.dart';
import '../../shared/widgets/brand_logo.dart';
import '../../shared/widgets/fintech_widgets.dart';
import 'app_shell.dart';

/// Listenable bridging Auth, AppLock, and ActiveProfile BLoC streams into GoRouter redirects (`ADR-011`).
final class RouterRefreshNotifier extends ChangeNotifier {
  RouterRefreshNotifier(List<Stream<dynamic>> streams) {
    for (final s in streams) {
      _subs.add(s.listen((_) => notifyListeners()));
    }
  }

  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}

CustomTransitionPage<void> _buildTransitionPage(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  final duration = AppMotion.resolve(context, AppMotion.page);
  final reverseDuration = AppMotion.resolve(context, AppMotion.pageReverse);
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: duration,
    reverseTransitionDuration: reverseDuration,
    child: child,
    transitionsBuilder: (ctx, animation, secondaryAnimation, pageChild) {
      if (duration == Duration.zero) return pageChild;
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
                begin: const Offset(0.055, 0),
                end: Offset.zero,
              ).animate(enterCurve),
              child: pageChild,
            ),
          ),
        ),
      );
    },
  );
}

CustomTransitionPage<void> _buildFadeScalePage(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  final duration = AppMotion.resolve(context, AppMotion.standard);
  final reverseDuration = AppMotion.resolve(context, AppMotion.fast);
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: duration,
    reverseTransitionDuration: reverseDuration,
    child: child,
    transitionsBuilder: (ctx, animation, _, pageChild) {
      if (duration == Duration.zero) return pageChild;
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotion.curveEmphasized,
        reverseCurve: AppMotion.curveExit,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1.0).animate(curved),
          child: pageChild,
        ),
      );
    },
  );
}

GoRouter buildAppRouter({
  required AuthCubit authCubit,
  required AppLockCubit appLockCubit,
  required ActiveProfileCubit profileCubit,
  required SettingsCubit settingsCubit,
  required Listenable refreshListenable,
}) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final isReplayTour = state.uri.queryParameters['replay'] == 'true';
      final authState = authCubit.state;
      final lockState = appLockCubit.state;
      final profState = profileCubit.state;
      final settingsState = settingsCubit.state;

      if (authState.status == AuthStatus.initializing ||
          authState.status == AuthStatus.initFailure ||
          !settingsState.isLoaded) {
        return loc == '/splash' ? null : '/splash';
      }

      if (authState.status == AuthStatus.unauthenticated) {
        if (!settingsState.hasCompletedOnboarding) {
          return loc == '/onboarding' ? null : '/onboarding';
        }
        if (loc == '/onboarding' && isReplayTour) {
          return null;
        }
        return loc == '/welcome' ? null : '/welcome';
      }

      if (lockState.isLocked) {
        return loc == '/lock' ? null : '/lock';
      }

      if (profState.status == ActiveProfileStatus.empty &&
          profState.profiles.isEmpty) {
        return loc == '/setup-profile' ? null : '/setup-profile';
      }

      if (loc == '/onboarding' && isReplayTour) {
        return null;
      }

      if (loc == '/splash' ||
          loc == '/onboarding' ||
          loc == '/welcome' ||
          loc == '/lock' ||
          loc == '/setup-profile') {
        return '/dashboard';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const _SplashRoutePage()),
      GoRoute(
        path: '/onboarding',
        pageBuilder: (ctx, state) => _buildTransitionPage(
          ctx,
          state,
          OnboardingPage(
            isReplay: state.uri.queryParameters['replay'] == 'true',
          ),
        ),
      ),
      GoRoute(
        path: '/welcome',
        pageBuilder: (ctx, state) =>
            _buildFadeScalePage(ctx, state, const WelcomeAuthPage()),
      ),
      GoRoute(
        path: '/lock',
        pageBuilder: (ctx, state) =>
            _buildFadeScalePage(ctx, state, const AppLockGateScreen()),
      ),
      GoRoute(
        path: '/setup-profile',
        pageBuilder: (ctx, state) => _buildFadeScalePage(
          ctx,
          state,
          const ProfilesPage(isInitialSetup: true),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/dashboard',
                builder: (_, _) => const DashboardPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/accounts',
                builder: (_, _) => const AccountsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/transactions',
                builder: (_, _) => const TransactionsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/insights',
                builder: (_, _) => const AnalyticsReportsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (_, _) => const ProfileHubPage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/profiles',
        pageBuilder: (ctx, state) =>
            _buildTransitionPage(ctx, state, const ProfilesPage()),
      ),
      GoRoute(
        path: '/categories',
        pageBuilder: (ctx, state) =>
            _buildTransitionPage(ctx, state, const CategoriesPage()),
      ),
      GoRoute(
        path: '/budgets',
        pageBuilder: (ctx, state) {
          final tab =
              int.tryParse(state.uri.queryParameters['tab'] ?? '0') ?? 0;
          return _buildTransitionPage(ctx, state, BudgetsPage(initialTab: tab));
        },
      ),
      GoRoute(
        path: '/goals',
        pageBuilder: (ctx, state) =>
            _buildTransitionPage(ctx, state, const SavingsGoalsPage()),
      ),
      GoRoute(
        path: '/import-csv',
        pageBuilder: (ctx, state) =>
            _buildTransitionPage(ctx, state, const CsvImportPage()),
      ),
      GoRoute(
        path: '/recurring',
        pageBuilder: (ctx, state) => _buildTransitionPage(
          ctx,
          state,
          const RecurringNotificationsPage(initialTab: 0),
        ),
      ),
      GoRoute(
        path: '/notifications',
        pageBuilder: (ctx, state) => _buildTransitionPage(
          ctx,
          state,
          const RecurringNotificationsPage(initialTab: 1),
        ),
      ),
      GoRoute(
        path: '/loans',
        pageBuilder: (ctx, state) =>
            _buildTransitionPage(ctx, state, const LoansPage()),
      ),
      GoRoute(
        path: '/sync',
        pageBuilder: (ctx, state) => _buildTransitionPage(
          ctx,
          state,
          const SyncBackupPage(initialTab: 0),
        ),
      ),
      GoRoute(
        path: '/backup',
        pageBuilder: (ctx, state) => _buildTransitionPage(
          ctx,
          state,
          const SyncBackupPage(initialTab: 1),
        ),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (ctx, state) =>
            _buildTransitionPage(ctx, state, const SettingsPage()),
      ),
      GoRoute(
        path: '/coach',
        pageBuilder: (ctx, state) {
          final tab =
              int.tryParse(state.uri.queryParameters['tab'] ?? '0') ?? 0;
          return _buildTransitionPage(ctx, state, AiCoachPage(initialTab: tab));
        },
      ),
      GoRoute(
        path: '/life-planner',
        pageBuilder: (ctx, state) {
          final tab =
              int.tryParse(state.uri.queryParameters['tab'] ?? '0') ?? 0;
          return _buildTransitionPage(
            ctx,
            state,
            LifeStagePlannerPage(initialTab: tab),
          );
        },
      ),
      GoRoute(
        path: '/monthly',
        pageBuilder: (ctx, state) {
          final tab =
              int.tryParse(state.uri.queryParameters['tab'] ?? '0') ?? 0;
          return _buildTransitionPage(
            ctx,
            state,
            MonthlyTrackerPage(initialTab: tab),
          );
        },
      ),
    ],
  );
}

class _SplashRoutePage extends StatelessWidget {
  const _SplashRoutePage();

  @override
  Widget build(BuildContext context) {
    final cfo = context.cfoColors;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: BlocBuilder<AuthCubit, AuthState>(
        builder: (context, state) {
          if (state.status == AuthStatus.initFailure) {
            return ErrorStateView(
              message:
                  state.failure?.message ??
                  'Unable to initialize secure local database.',
              code: state.failure?.code,
              onRetry: () => context.read<AuthCubit>().initialize(),
            );
          }
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.25),
                radius: 1.0,
                colors: [
                  scheme.primaryContainer.withValues(alpha: 0.55),
                  scheme.surface,
                ],
              ),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const PocketCfoLogo(size: 76, animateEntrance: true),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Pocket CFO',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'Private Multi-Profile Financial Vault',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: cfo.subtleText),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    SizedBox(
                      width: 140,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusFull,
                        ),
                        child: const LinearProgressIndicator(minHeight: 4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
