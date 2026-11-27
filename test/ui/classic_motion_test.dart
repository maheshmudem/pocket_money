import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_money/app/config/environment_config.dart';
import 'package:pocket_money/app/theme/app_theme.dart';
import 'package:pocket_money/bootstrap.dart';
import 'package:pocket_money/core/database/app_database.dart';
import 'package:pocket_money/core/database/encrypted_executor.dart';
import 'package:pocket_money/core/security/key_manager.dart';
import 'package:pocket_money/core/security/privacy_screen_service.dart';
import 'package:pocket_money/core/utilities/clock.dart';
import 'package:pocket_money/features/accounts/domain/entities/financial_account_entity.dart';
import 'package:pocket_money/features/accounts/domain/repositories/account_repository.dart';
import 'package:pocket_money/features/authentication/presentation/bloc/auth_cubit.dart';
import 'package:pocket_money/features/budgets/presentation/pages/budgets_page.dart';
import 'package:pocket_money/features/categories/domain/entities/category_entity.dart';
import 'package:pocket_money/features/categories/domain/repositories/category_repository.dart';
import 'package:pocket_money/features/dashboard/presentation/bloc/dashboard_bloc.dart';
import 'package:pocket_money/features/profiles/domain/entities/profile_entity.dart';
import 'package:pocket_money/features/profiles/presentation/bloc/active_profile_cubit.dart';
import 'package:pocket_money/features/security_lock/presentation/bloc/app_lock_cubit.dart';
import 'package:pocket_money/features/settings/data/settings_repository.dart';
import 'package:pocket_money/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:pocket_money/features/settings/presentation/pages/settings_page.dart';
import 'package:pocket_money/features/transactions/domain/entities/transaction_entity.dart';
import 'package:pocket_money/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:pocket_money/features/transactions/presentation/bloc/transactions_bloc.dart';
import 'package:pocket_money/features/transactions/presentation/pages/transactions_page.dart';
import 'package:pocket_money/shared/widgets/classic_motion.dart';

void main() {
  Future<void> initTestApp() async {
    await configureDependencies(
      config: const EnvironmentConfig(
        environment: AppEnvironment.dev,
        apiBaseUrl: 'http://localhost:8000/api/v1',
        appVersion: '1.0.0+1',
        requireEncryptedDatabase: false,
        analyticsEnabledByDefault: false,
      ),
      databaseExecutorOverride: EncryptedDatabaseExecutor.openInMemory(),
      secureStoreOverride: InMemorySecureKeyValueStore(),
      clockOverride: FixedUtcClock(DateTime.utc(2026, 11, 25, 10, 0)),
    );
  }

  Future<void> cleanDeps() async {
    if (getIt.isRegistered<AppDatabase>()) {
      await getIt<AppDatabase>().close();
    }
    await getIt.reset();
  }

  tearDown(() async {
    await cleanDeps();
  });

  group('ClassicMotion shared primitives', () {
    testWidgets(
      'settles deterministically for tabs, content states, accordions, counters, press-scale & FABs (normal & reduced motion)',
      (tester) async {
        for (final disableAnimations in [false, true]) {
          var tab = 0;
          var stateKey = 'first';
          var expanded = false;
          var count = 5;
          var showFab = false;
          var pressCount = 0;

          await tester.pumpWidget(
            StatefulBuilder(
              builder: (context, setState) {
                return MediaQuery(
                  data: MediaQueryData(
                    size: const Size(360, 800),
                    disableAnimations: disableAnimations,
                  ),
                  child: MaterialApp(
                    theme: AppTheme.light(),
                    home: Scaffold(
                      floatingActionButton: ClassicAnimatedFab(
                        child: showFab
                            ? FloatingActionButton(
                                key: const Key('test_fab'),
                                onPressed: () {},
                                child: const Icon(Icons.add),
                              )
                            : null,
                      ),
                      body: Column(
                        children: [
                          ClassicTabSwitcher(
                            activeIndex: tab,
                            child: Text('Tab-$tab'),
                          ),
                          ClassicContentSwitcher(
                            stateKey: stateKey,
                            child: Text('State-$stateKey'),
                          ),
                          ClassicExpandCollapse(
                            expanded: expanded,
                            child: const Text('Expanded Details'),
                          ),
                          ClassicAnimatedCount(value: count, suffix: ' items'),
                          ClassicPressScale(
                            onTap: () => setState(() => pressCount++),
                            child: const Text('Press Me'),
                          ),
                          ElevatedButton(
                            key: const Key('toggle_all_btn'),
                            onPressed: () => setState(() {
                              tab = tab == 0 ? 1 : 0;
                              stateKey = stateKey == 'first'
                                  ? 'second'
                                  : 'first';
                              expanded = !expanded;
                              count = 42;
                              showFab = !showFab;
                            }),
                            child: const Text('Toggle'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );

          await tester.pumpAndSettle();
          expect(find.text('Tab-0'), findsOneWidget);
          expect(find.text('State-first'), findsOneWidget);
          expect(find.text('5 items'), findsOneWidget);
          expect(find.byKey(const Key('test_fab')), findsNothing);

          await tester.tap(find.text('Press Me'));
          await tester.tap(find.byKey(const Key('toggle_all_btn')));
          await tester.pumpAndSettle();

          expect(pressCount, 1);
          expect(find.text('Tab-1'), findsOneWidget);
          expect(find.text('State-second'), findsOneWidget);
          expect(find.text('Expanded Details'), findsOneWidget);
          expect(find.text('42 items'), findsOneWidget);
          expect(find.byKey(const Key('test_fab')), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      },
    );
  });

  group('Screen classic motion responsive QA', () {
    testWidgets(
      'Settings, Transactions & Budgets render smoothly at 360x800 + 1.5x Dark Mode and 1280x840 Light Mode',
      (tester) async {
        await initTestApp();
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final activeProfileCubit = ActiveProfileCubit(
          repository: getIt(),
          scopeController: getIt(),
          settings: getIt(),
        );
        final settingsCubit = SettingsCubit(
          getIt<SettingsRepository>(),
          privacyScreen: getIt<PrivacyScreenService>(),
        )..load();
        final appLockCubit = AppLockCubit(service: getIt(), clock: getIt());
        final authCubit = AuthCubit(getIt())..initialize();
        final dashboardBloc = DashboardBloc(
          analyticsRepository: getIt(),
          scopeController: getIt(),
          budgetRepository: getIt(),
        );
        addTearDown(() async {
          await activeProfileCubit.close();
          await settingsCubit.close();
          await appLockCubit.close();
          await authCubit.close();
          await dashboardBloc.close();
        });

        final prof = (await activeProfileCubit.createProfile(
          ownerDisplayName: 'Owner',
          name: 'Motion Vault',
          profileType: ProfileType.personal,
          baseCurrencyCode: 'INR',
        )).valueOrNull!;
        final bank =
            (await getIt<AccountRepository>().createAccountWithOpeningBalance(
              profileId: prof.id,
              name: 'Motion Bank',
              accountType: FinancialAccountType.bank,
              currencyCode: 'INR',
              openingBalanceMinor: 5000000,
            )).valueOrNull!;
        final expCats = (await getIt<CategoryRepository>().listCategories(
          prof.id,
          type: CategoryType.expense,
        )).valueOrNull!;
        await getIt<TransactionRepository>().createTransaction(
          prof.id,
          CreateTransactionCommand(
            type: TransactionType.expense,
            amountMinor: 150000,
            currencyCode: 'INR',
            transactionDateUtc: DateTime.utc(2026, 11, 20).toIso8601String(),
            sourceAccountId: bank.id,
            categoryId: expCats.first.id,
            description: 'Coffee & Snacks',
          ),
        );

        Widget wrapProviders(Widget home, {required ThemeData theme}) =>
            MultiBlocProvider(
              providers: [
                BlocProvider.value(value: activeProfileCubit),
                BlocProvider.value(value: settingsCubit),
                BlocProvider.value(value: appLockCubit),
                BlocProvider.value(value: authCubit),
                BlocProvider.value(value: dashboardBloc),
                BlocProvider<TransactionsBloc>(
                  create: (_) => TransactionsBloc(
                    repository: getIt<TransactionRepository>(),
                    scopeController: getIt(),
                  )..add(const TransactionsLoadRequested()),
                ),
              ],
              child: MaterialApp(
                theme: theme,
                builder: (context, w) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(1.5)),
                  child: w!,
                ),
                home: home,
              ),
            );

        // 1. SettingsPage (360x800 + 1.5x Dark Mode) + theme icon switch
        await tester.pumpWidget(
          wrapProviders(const SettingsPage(), theme: AppTheme.dark()),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('settings_appearance_card')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const Key('theme_mode_light')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // 2. BudgetsPage (360x800 + 1.5x Dark Mode) directional tab transitions
        await tester.pumpWidget(
          wrapProviders(const BudgetsPage(), theme: AppTheme.dark()),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Zero-Based'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('CA Variance'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // 3. TransactionsPage (1280x840 Light Mode) filter + pulse strip
        await tester.binding.setSurfaceSize(const Size(1280, 840));
        await tester.pumpWidget(
          wrapProviders(
            const Scaffold(body: TransactionsPage()),
            theme: AppTheme.light(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(TransactionsPage), findsOneWidget);
        expect(find.byKey(const Key('ledger_pulse_strip')), findsOneWidget);
        expect(find.text('Coffee & Snacks'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
      },
    );
  });
}
