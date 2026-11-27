import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_money/app/config/environment_config.dart';
import 'package:pocket_money/app/theme/app_theme.dart';
import 'package:pocket_money/bootstrap.dart';
import 'package:pocket_money/core/database/app_database.dart';
import 'package:pocket_money/core/database/encrypted_executor.dart';
import 'package:pocket_money/core/errors/failures.dart';
import 'package:pocket_money/core/notifications/local_notification_service.dart';
import 'package:pocket_money/core/security/key_manager.dart';
import 'package:pocket_money/core/security/privacy_screen_service.dart';
import 'package:pocket_money/core/utilities/clock.dart';
import 'package:pocket_money/core/utilities/profile_scope_controller.dart';
import 'package:pocket_money/features/accounts/domain/entities/financial_account_entity.dart';
import 'package:pocket_money/features/accounts/domain/repositories/account_repository.dart';
import 'package:pocket_money/features/authentication/data/repositories/auth_repository.dart';
import 'package:pocket_money/features/authentication/presentation/bloc/auth_cubit.dart';
import 'package:pocket_money/features/budgets/domain/repositories/budget_repository.dart';
import 'package:pocket_money/features/categories/domain/entities/category_entity.dart';
import 'package:pocket_money/features/categories/domain/repositories/category_repository.dart';
import 'package:pocket_money/features/dashboard/domain/repositories/analytics_repository.dart';
import 'package:pocket_money/features/dashboard/presentation/bloc/dashboard_bloc.dart';
import 'package:pocket_money/features/notifications/data/financial_alerts_coordinator.dart';
import 'package:pocket_money/features/notifications/presentation/bloc/notifications_cubit.dart';
import 'package:pocket_money/features/profiles/domain/entities/profile_entity.dart';
import 'package:pocket_money/features/profiles/domain/repositories/profile_repository.dart';
import 'package:pocket_money/features/profiles/presentation/bloc/active_profile_cubit.dart';
import 'package:pocket_money/features/profiles/presentation/pages/profile_hub_page.dart';
import 'package:pocket_money/features/profiles/presentation/pages/profiles_page.dart';
import 'package:pocket_money/features/security_lock/data/app_lock_service.dart';
import 'package:pocket_money/features/security_lock/presentation/bloc/app_lock_cubit.dart';
import 'package:pocket_money/features/settings/data/settings_repository.dart';
import 'package:pocket_money/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:pocket_money/features/transactions/domain/entities/transaction_entity.dart';
import 'package:pocket_money/features/transactions/domain/repositories/transaction_repository.dart';

void main() {
  Future<void> initDeps() async {
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
      clockOverride: FixedUtcClock(DateTime.utc(2026, 11, 26, 10, 0)),
      notificationDispatcherOverride: InMemoryNotificationDispatcher(),
    );
  }

  tearDown(() async {
    if (getIt.isRegistered<AppDatabase>()) {
      await getIt<AppDatabase>().close();
    }
    await getIt.reset();
  });

  group('Edit Profile Repository, RBAC, History & Responsive UI', () {
    test(
      'updateProfile updates name, type, currency (preserving ledger history), timezone, editorsCanPost & enforces validation/RBAC',
      () async {
        await initDeps();

        final profileRepo = getIt<ProfileRepository>();
        final accRepo = getIt<AccountRepository>();
        final catRepo = getIt<CategoryRepository>();
        final txRepo = getIt<TransactionRepository>();

        final created = (await profileRepo.createProfile(
          userId: 'owner-1',
          ownerDisplayName: 'Owner',
          name: 'My Personal Vault',
          profileType: ProfileType.personal,
          baseCurrencyCode: 'INR',
          timezone: 'Asia/Kolkata',
          editorsCanPost: true,
        )).valueOrNull!;

        final bank = (await accRepo.createAccountWithOpeningBalance(
          profileId: created.id,
          name: 'HDFC',
          accountType: FinancialAccountType.bank,
          currencyCode: 'INR',
          openingBalanceMinor: 5000000,
        )).valueOrNull!;
        final expCats = (await catRepo.listCategories(
          created.id,
          type: CategoryType.expense,
        )).valueOrNull!;
        await txRepo.createTransaction(
          created.id,
          CreateTransactionCommand(
            type: TransactionType.expense,
            amountMinor: 250000,
            currencyCode: 'INR',
            transactionDateUtc: DateTime.utc(2026, 11, 26).toIso8601String(),
            sourceAccountId: bank.id,
            categoryId: expCats.first.id,
            description: 'Historical INR purchase',
          ),
        );

        // Blank name rejected
        final invalid = await profileRepo.updateProfile(
          profileId: created.id,
          userId: 'owner-1',
          name: '   ',
          profileType: ProfileType.family,
        );
        expect(invalid.isFailure, isTrue);
        expect(invalid.failureOrNull, isA<ValidationFailure>());

        // Add Viewer member -> must be blocked from editing profile
        await profileRepo.addOrUpdateMember(
          profileId: created.id,
          requestingUserId: 'owner-1',
          memberUserId: 'viewer-1',
          displayName: 'Guest Viewer',
          role: ProfileRole.viewer,
        );
        final unauth = await profileRepo.updateProfile(
          profileId: created.id,
          userId: 'viewer-1',
          name: 'Hacked Vault',
          profileType: ProfileType.business,
        );
        expect(unauth.isFailure, isTrue);
        expect(unauth.failureOrNull, isA<AuthorizationFailure>());

        // Owner updates all editable fields cleanly
        final updated = (await profileRepo.updateProfile(
          profileId: created.id,
          userId: 'owner-1',
          name: 'Family Office Vault',
          profileType: ProfileType.family,
          baseCurrencyCode: 'USD',
          timezone: 'America/New_York',
          editorsCanPost: false,
        )).valueOrNull!;

        expect(updated.name, 'Family Office Vault');
        expect(updated.profileType, ProfileType.family);
        expect(updated.baseCurrencyCode, 'USD');
        expect(updated.timezone, 'America/New_York');
        expect(updated.editorsCanPost, isFalse);
        expect(updated.version, created.version + 1);

        // Historical INR transaction preserved & ledger stays 100% balanced
        final txs = (await txRepo.queryTransactions(
          created.id,
        )).valueOrNull!.items;
        expect(txs.first.baseAmount.currencyCode, 'INR');
        final recon = (await txRepo.runReconciliationCheck(
          created.id,
        )).valueOrNull!;
        expect(recon.isHealthy, isTrue);

        // Last-profile archive guard via ActiveProfileCubit + multi-profile archive
        final cubit = ActiveProfileCubit(
          repository: profileRepo,
          scopeController: getIt<ProfileScopeController>(),
          settings: getIt<SettingsRepository>(),
        );
        await cubit.loadProfiles(userId: 'owner-1');
        final lastGuard = await cubit.archiveProfile(created.id);
        expect(lastGuard.isFailure, isTrue);

        final second = (await cubit.createProfile(
          ownerDisplayName: 'Owner',
          name: 'Side Hustle',
          profileType: ProfileType.business,
          baseCurrencyCode: 'INR',
        )).valueOrNull!;
        expect(cubit.state.profiles.length, 2);

        final archivedRes = await cubit.archiveProfile(second.id);
        expect(archivedRes.isSuccess, isTrue);
        expect(cubit.state.profiles.length, 1);
        await cubit.close();
      },
    );

    testWidgets(
      'Edit Profile works from ProfileHub Hero & ProfilesPage menu at 360x800 + 1.5x in Light and Dark themes',
      (tester) async {
        await initDeps();
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final activeProfileCubit = ActiveProfileCubit(
          repository: getIt<ProfileRepository>(),
          scopeController: getIt<ProfileScopeController>(),
          settings: getIt<SettingsRepository>(),
        );
        final settingsCubit = SettingsCubit(
          getIt<SettingsRepository>(),
          privacyScreen: getIt<PrivacyScreenService>(),
        );
        final dashboardBloc = DashboardBloc(
          analyticsRepository: getIt<AnalyticsRepository>(),
          scopeController: getIt<ProfileScopeController>(),
          budgetRepository: getIt<BudgetRepository>(),
        );
        final authCubit = AuthCubit(getIt<AuthRepository>());
        final lockCubit = AppLockCubit(
          service: getIt<AppLockService>(),
          clock: getIt<UtcClock>(),
        );
        final notifCubit = NotificationsCubit(
          coordinator: getIt<FinancialAlertsCoordinator>(),
          scopeController: getIt<ProfileScopeController>(),
        );
        addTearDown(() async {
          await activeProfileCubit.close();
          await settingsCubit.close();
          await dashboardBloc.close();
          await authCubit.close();
          await lockCubit.close();
          await notifCubit.close();
        });

        await activeProfileCubit.loadProfiles(userId: 'local-owner');
        final prof = (await activeProfileCubit.createProfile(
          ownerDisplayName: 'Owner',
          name: 'Starter Vault',
          profileType: ProfileType.personal,
          baseCurrencyCode: 'INR',
        )).valueOrNull!;

        Widget wrapWithProviders(Widget home, ThemeData theme) {
          return MultiBlocProvider(
            providers: [
              BlocProvider.value(value: activeProfileCubit),
              BlocProvider.value(value: settingsCubit),
              BlocProvider.value(value: dashboardBloc),
              BlocProvider.value(value: authCubit),
              BlocProvider.value(value: lockCubit),
              BlocProvider.value(value: notifCubit),
            ],
            child: MaterialApp(
              theme: theme,
              builder: (context, w) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.5)),
                child: w!,
              ),
              home: Scaffold(body: home),
            ),
          );
        }

        // 1. Edit active profile from ProfileHubPage (Light mode, 360x800, 1.5x scale)
        await tester.pumpWidget(
          wrapWithProviders(const ProfileHubPage(), AppTheme.light()),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const Key('profile_hub_edit_btn')));
        await tester.pumpAndSettle();
        expect(find.text('Edit Profile'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.enterText(
          find.byKey(const Key('edit_profile_name_field')),
          'Updated Household',
        );
        final familyChip = find.byKey(const Key('edit_profile_type_family'));
        await tester.ensureVisible(familyChip);
        await tester.tap(familyChip);
        await tester.pumpAndSettle();

        final editorSwitch = find.byKey(
          const Key('edit_profile_editors_can_post_switch'),
        );
        await tester.ensureVisible(editorSwitch);
        await tester.tap(editorSwitch);
        await tester.pumpAndSettle();

        final saveBtn = find.byKey(const Key('edit_profile_save_btn'));
        await tester.ensureVisible(saveBtn);
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        expect(
          activeProfileCubit.state.activeProfile?.name,
          'Updated Household',
        );
        expect(
          activeProfileCubit.state.activeProfile?.profileType,
          ProfileType.family,
        );
        expect(activeProfileCubit.state.activeProfile?.editorsCanPost, isFalse);
        expect(find.text('Updated Household'), findsWidgets);
        expect(tester.takeException(), isNull);

        // 2. Open Edit Profile from ProfilesPage popup menu (Dark mode, 360x800, 1.5x)
        await tester.pumpWidget(
          wrapWithProviders(const ProfilesPage(), AppTheme.dark()),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(Key('profile_menu_${prof.id.value}')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit profile'));
        await tester.pumpAndSettle();
        expect(find.text('Edit Profile'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
