import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_money/app/app.dart';
import 'package:pocket_money/app/config/environment_config.dart';
import 'package:pocket_money/bootstrap.dart';
import 'package:pocket_money/core/database/app_database.dart';
import 'package:pocket_money/core/database/encrypted_executor.dart';
import 'package:pocket_money/core/security/key_manager.dart';
import 'package:pocket_money/core/utilities/clock.dart';
import 'package:pocket_money/features/settings/data/settings_repository.dart';
import 'package:pocket_money/shared/widgets/modern_dialogs.dart';

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
      clockOverride: FixedUtcClock(DateTime.utc(2026, 11, 20, 10, 0)),
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

  testWidgets(
    'First-run 4-slide interactive onboarding walkthrough persists completion and routes to Welcome',
    (tester) async {
      await initDeps();

      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const PocketCfoApp());
      await tester.pumpAndSettle();

      // Slide 1: Multi-Profile Vaults interactive preview
      expect(find.byKey(const Key('onboarding_page')), findsOneWidget);
      expect(find.text('MULTI-PROFILE VAULTS'), findsOneWidget);
      expect(find.text('Personal Wealth'), findsOneWidget);
      expect(find.byKey(const Key('onboarding_skip_btn')), findsOneWidget);
      expect(find.byKey(const Key('onboarding_back_btn')), findsNothing);

      // Tap Family & Business preview pills interactively
      await tester.tap(find.byKey(const Key('onboarding_vault_family')));
      await tester.pumpAndSettle();
      expect(find.text('Household Vault'), findsOneWidget);

      await tester.tap(find.byKey(const Key('onboarding_vault_business')));
      await tester.pumpAndSettle();
      expect(find.text('Studio Ledger'), findsOneWidget);

      // Slide 2: Double-Entry Ledger + Interactive QuickBall demo
      await tester.tap(find.byKey(const Key('onboarding_next_btn')));
      await tester.pumpAndSettle();
      expect(find.text('DOUBLE-ENTRY LEDGER'), findsOneWidget);
      expect(
        find.byKey(const Key('onboarding_try_quicklog_btn')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('onboarding_try_quicklog_btn')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Posted -₹250'), findsOneWidget);
      expect(find.byKey(const Key('onboarding_back_btn')), findsOneWidget);

      // Back button returns to Slide 1 cleanly
      await tester.tap(find.byKey(const Key('onboarding_back_btn')));
      await tester.pumpAndSettle();
      expect(find.text('MULTI-PROFILE VAULTS'), findsOneWidget);

      // Jump directly to Slide 3 via top story progress segment
      await tester.tap(find.byKey(const Key('onboarding_dot_2')));
      await tester.pumpAndSettle();
      expect(find.text('SMART CFO INSIGHTS'), findsOneWidget);
      expect(find.byKey(const Key('onboarding_health_gauge')), findsOneWidget);
      expect(find.textContaining('Safe / Day'), findsOneWidget);

      // Slide 4: Privacy & Live Theme Picker
      await tester.tap(find.byKey(const Key('onboarding_next_btn')));
      await tester.pumpAndSettle();
      expect(find.text('PRIVATE & OFFLINE-FIRST'), findsOneWidget);
      expect(find.byKey(const Key('onboarding_skip_btn')), findsNothing);
      expect(
        find.byKey(const Key('onboarding_get_started_btn')),
        findsOneWidget,
      );

      // Toggle live Dark & Light theme options right inside Slide 4
      await tester.tap(find.byKey(const Key('onboarding_theme_dark')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Obsidian Dark'), findsOneWidget);

      await tester.tap(find.byKey(const Key('onboarding_theme_light')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Daylight Light'), findsOneWidget);

      // Complete onboarding -> transitions cleanly to Welcome screen
      await tester.tap(find.byKey(const Key('onboarding_get_started_btn')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Start Offline Local Workspace'), findsOneWidget);
      final persisted = await tester.runAsync(
        () => getIt<SettingsRepository>().getBool('onboarding.completed'),
      );
      expect(persisted, isTrue);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets(
    'Skip completes onboarding immediately; Welcome & Settings replay tours open and return cleanly',
    (tester) async {
      await initDeps();

      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const PocketCfoApp());
      await tester.pumpAndSettle();

      // Skip from Slide 1
      expect(find.byKey(const Key('onboarding_skip_btn')), findsOneWidget);
      await tester.tap(find.byKey(const Key('onboarding_skip_btn')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Start Offline Local Workspace'), findsOneWidget);

      // Replay tour from Welcome header button
      await tester.tap(find.byKey(const Key('welcome_view_tour_btn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('onboarding_page')), findsOneWidget);
      expect(find.byKey(const Key('onboarding_close_btn')), findsOneWidget);

      // Jump to last slide in replay mode -> Done button pops back to Welcome
      await tester.tap(find.byKey(const Key('onboarding_dot_3')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('onboarding_done_btn')), findsOneWidget);
      await tester.tap(find.byKey(const Key('onboarding_done_btn')));
      await tester.pumpAndSettle();

      expect(find.text('Start Offline Local Workspace'), findsOneWidget);

      // Enter workspace -> create profile -> open Settings -> replay tour -> Close returns to Settings
      await tester.tap(find.text('Start Offline Local Workspace'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Personal Wealth'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(ModernDialogShell),
          matching: find.text('Create Profile'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('bottom_nav_profile_switcher')));
      await tester.pumpAndSettle();
      final profileScroll = find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first;
      final settingsTile = find.byKey(const Key('profile_open_settings_tile'));
      await tester.scrollUntilVisible(
        settingsTile,
        180,
        scrollable: profileScroll,
      );
      await tester.tap(settingsTile);
      await tester.pumpAndSettle();

      final settingsScroll = find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .last;
      final tourTile = find.byKey(const Key('settings_replay_onboarding_tile'));
      await tester.scrollUntilVisible(
        tourTile,
        180,
        scrollable: settingsScroll,
      );
      await tester.tap(tourTile);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('onboarding_page')), findsOneWidget);
      expect(find.byKey(const Key('onboarding_close_btn')), findsOneWidget);
      await tester.tap(find.byKey(const Key('onboarding_close_btn')));
      await tester.pumpAndSettle();

      expect(find.text('Settings & Security'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets(
    'Existing upgraded user session bypasses first-run onboarding without disruption',
    (tester) async {
      await initDeps();
      // Simulate existing pre-update user who already started local workspace
      // before the onboarding.completed key existed.
      await getIt<SettingsRepository>().setString('auth.mode', 'local');
      await getIt<SettingsRepository>().setString(
        'auth.user_id',
        'local-owner',
      );

      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const PocketCfoApp());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('onboarding_page')), findsNothing);
      expect(find.text('Create Your First Profile'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets(
    'Responsive & accessibility matrix: 2.0x text scale + Dark Mode + reduced motion across all 4 slides renders zero overflow',
    (tester) async {
      await initDeps();

      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(
            size: Size(360, 800),
            textScaler: TextScaler.linear(2.0),
            disableAnimations: true,
            platformBrightness: Brightness.dark,
          ),
          child: PocketCfoApp(),
        ),
      );
      await tester.pumpAndSettle();

      for (var i = 0; i < 4; i++) {
        expect(find.byKey(const Key('onboarding_page')), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (i < 3) {
          await tester.tap(find.byKey(const Key('onboarding_next_btn')));
          await tester.pumpAndSettle();
        }
      }

      expect(
        find.byKey(const Key('onboarding_get_started_btn')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets(
    'Desktop 1280x840 2-column onboarding renders all 4 slides cleanly in Light and Dark themes',
    (tester) async {
      await initDeps();

      await tester.binding.setSurfaceSize(const Size(1280, 840));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(size: Size(1280, 840), disableAnimations: true),
          child: PocketCfoApp(),
        ),
      );
      await tester.pumpAndSettle();

      for (var i = 0; i < 4; i++) {
        expect(find.byKey(const Key('onboarding_page')), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (i < 3) {
          await tester.tap(find.byKey(const Key('onboarding_next_btn')));
          await tester.pumpAndSettle();
        }
      }

      await tester.tap(find.byKey(const Key('onboarding_theme_dark')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onboarding_get_started_btn')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Workspace Access'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );
}
