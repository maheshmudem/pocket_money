import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_money/app/app.dart';
import 'package:pocket_money/app/config/environment_config.dart';
import 'package:pocket_money/bootstrap.dart';
import 'package:pocket_money/core/database/app_database.dart';
import 'package:pocket_money/core/database/encrypted_executor.dart';
import 'package:pocket_money/core/security/key_manager.dart';
import 'package:pocket_money/core/utilities/clock.dart';
import 'package:pocket_money/shared/widgets/brand_logo.dart';
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
      clockOverride: FixedUtcClock(DateTime.utc(2026, 11, 19, 10, 0)),
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
    'PocketCfoLogo renders crisply in light & dark themes without duplicating brand text',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: const Scaffold(
            body: Center(child: PocketCfoLogo(size: 64, animateEntrance: true)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PocketCfoLogo), findsOneWidget);
      expect(find.bySemanticsLabel('Pocket CFO logo'), findsOneWidget);
      expect(find.text('Pocket CFO'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Compact 360x800 Neo-Fintech full flow: Welcome -> Profile Template -> Account -> Split Expense -> Ledger -> Insights -> Settings Dark Mode',
    (tester) async {
      await initDeps();

      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const PocketCfoApp());
      await tester.pumpAndSettle();

      // 0. First-run Onboarding -> Skip to Welcome screen.
      expect(find.byKey(const Key('onboarding_page')), findsOneWidget);
      await tester.tap(find.byKey(const Key('onboarding_skip_btn')));
      await tester.pumpAndSettle();

      // 1. Welcome screen shows custom logo and primary workspace CTA.
      expect(find.byType(PocketCfoLogo), findsOneWidget);
      expect(find.text('Pocket CFO'), findsOneWidget);
      await tester.tap(find.text('Start Offline Local Workspace'));
      await tester.pumpAndSettle();

      // 2. First-run profile screen hides duplicate FAB when empty and offers templates.
      expect(find.text('Create Your First Profile'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text('Personal Wealth'), findsOneWidget);

      await tester.tap(find.text('Personal Wealth'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(ModernDialogShell),
          matching: find.text('Create Profile'),
        ),
      );
      await tester.pumpAndSettle();

      // 3. Dashboard empty launchpad -> Add First Account -> Accounts creation.
      expect(find.text('Personal Finance (INR)'), findsOneWidget);
      expect(find.text('Welcome to Personal Finance'), findsOneWidget);
      await tester.tap(find.text('Add First Account'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Account'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'HDFC Savings');
      await tester.enterText(fields.at(1), '50000');
      await tester.ensureVisible(find.text('Save Account'));
      await tester.tap(find.text('Save Account'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Portfolio Overview'), findsOneWidget);
      expect(find.text('HDFC Savings'), findsOneWidget);

      // 4. Switch to Home dock tab -> verify populated Net Worth hero & Bento hub.
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('NET WORTH • INR'), findsOneWidget);
      final verticalList = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      );
      await tester.scrollUntilVisible(
        find.text('Finance Hub'),
        180,
        scrollable: verticalList.first,
      );
      expect(find.text('Finance Hub'), findsOneWidget);

      // 5. Verify bottom-bar '+' is removed; open DraggableQuickBall -> Track Expense -> Multi-Split 1000 (600 + 400).
      expect(find.byTooltip('Add Entry'), findsNothing);
      await tester.tap(find.byKey(const Key('draggable_quick_ball')));
      await tester.pumpAndSettle();
      expect(find.text('QUICK ACTIONS'), findsOneWidget);
      await tester.tap(find.byKey(const Key('quickball_track_expense')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Amount (INR)'),
        '1000',
      );
      await tester.pumpAndSettle();

      final splitSwitch = find.text('Split across multiple categories');
      await tester.ensureVisible(splitSwitch);
      await tester.tap(splitSwitch);
      await tester.pumpAndSettle();

      final splitFields = find.widgetWithText(TextField, 'Amt (INR)');
      expect(splitFields, findsNWidgets(2));
      await tester.enterText(splitFields.at(0), '600');
      await tester.enterText(splitFields.at(1), '400');
      await tester.pumpAndSettle();

      final postBtn = find.text('Post Transaction');
      await tester.ensureVisible(postBtn);
      await tester.tap(postBtn);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      // 6. Visit Ledger dock tab -> verify sleek segmented filter, compact Pulse ribbon, grouped day card & filter transitions.
      await tester.tap(find.text('Ledger').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ledger_segmented_filter')), findsOneWidget);
      expect(find.byKey(const Key('ledger_more_filter_btn')), findsOneWidget);
      expect(find.byKey(const Key('ledger_pulse_strip')), findsOneWidget);
      expect(find.byKey(const Key('ledger_quick_add_btn')), findsOneWidget);
      expect(find.text('Today • 19 Nov'), findsOneWidget);

      // Filter to Expense -> verify posted split expense remains visible
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('ledger_segmented_filter')),
          matching: find.text('Expense'),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Today • 19 Nov'), findsOneWidget);

      // Filter to Income (none posted yet) -> verify clean empty state + Reset Filters action
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('ledger_segmented_filter')),
          matching: find.text('Income'),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('No matching entries'), findsOneWidget);
      await tester.tap(find.text('Reset Filters'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Today • 19 Nov'), findsOneWidget);

      // Open More filters menu (Refunds / Drafts) and dismiss cleanly
      await tester.tap(find.byKey(const Key('ledger_more_filter_btn')));
      await tester.pumpAndSettle();
      expect(find.text('Refunds'), findsOneWidget);
      expect(find.text('Drafts'), findsOneWidget);
      await tester.tap(find.text('Drafts'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Reset Filters'), findsOneWidget);
      await tester.tap(find.text('Reset Filters'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Today • 19 Nov'), findsOneWidget);

      // 7. Visit Insights dock tab -> verify CFO Health Gauge, Smart Signals, Cash-Flow BarChart & Spending Breakdown.
      await tester.tap(find.text('Insights'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('insights_health_gauge')), findsOneWidget);
      expect(find.text('Savings Rate'), findsOneWidget);

      final insightsScroll = find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first;
      await tester.scrollUntilVisible(
        find.byKey(const Key('insights_smart_signals')),
        160,
        scrollable: insightsScroll,
      );
      expect(find.text('Smart CFO Signals'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const Key('insights_cashflow_barchart')),
        160,
        scrollable: insightsScroll,
      );
      expect(find.text('Cash-Flow Momentum'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Spending Breakdown'),
        180,
        scrollable: insightsScroll,
      );
      expect(find.text('Spending Breakdown'), findsOneWidget);

      // 8. Visit bottom-bar Profile tab -> verify Vault Readiness + live Ledger Audit + Vault Roster + Dark theme + Settings (FR-021).
      await tester.tap(find.byKey(const Key('bottom_nav_profile_switcher')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile_vault_readiness')), findsOneWidget);

      final profileScroll = find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first;

      final auditBtn = find.byKey(const Key('profile_run_audit_btn'));
      await tester.scrollUntilVisible(auditBtn, 120, scrollable: profileScroll);
      await tester.tap(auditBtn);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.textContaining('Ledger Balanced'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const Key('profile_vault_roster')),
        160,
        scrollable: profileScroll,
      );
      expect(find.byKey(const Key('profile_vault_roster')), findsOneWidget);

      // Theme & Display must NOT be duplicated in Profile Hub (canonical home is Settings & Security).
      expect(find.text('Theme & Display'), findsNothing);
      expect(find.text('App Theme'), findsNothing);

      final settingsTile = find.byKey(const Key('profile_open_settings_tile'));
      await tester.scrollUntilVisible(
        settingsTile,
        160,
        scrollable: profileScroll,
      );
      expect(
        find.byKey(const Key('profile_workspace_security_card')),
        findsOneWidget,
      );
      await tester.tap(settingsTile);
      await tester.pumpAndSettle();

      // Single canonical App Theme picker lives in Settings & Security.
      expect(find.byKey(const Key('settings_appearance_card')), findsOneWidget);
      expect(find.text('App Theme'), findsOneWidget);
      await tester.tap(find.byKey(const Key('theme_mode_dark')));
      await tester.pumpAndSettle();

      final settingsScroll = find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .last;
      await tester.scrollUntilVisible(
        find.text('Device & Session (FR-021)'),
        160,
        scrollable: settingsScroll,
      );
      expect(find.text('Device & Session (FR-021)'), findsOneWidget);

      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets(
    'Large 1.5x text scale + Dark Mode across Settings, Budgets, Goals, and Loans renders with zero overflow',
    (tester) async {
      await initDeps();

      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(
            size: Size(390, 844),
            textScaler: TextScaler.linear(1.5),
            disableAnimations: true,
            platformBrightness: Brightness.dark,
          ),
          child: PocketCfoApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('onboarding_skip_btn')));
      await tester.pumpAndSettle();

      final startBtn = find.text('Start Offline Local Workspace');
      await tester.ensureVisible(startBtn);
      await tester.tap(startBtn);
      await tester.pumpAndSettle();
      final createBtn = find.text('Create Profile');
      await tester.ensureVisible(createBtn);
      await tester.tap(createBtn);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(ModernDialogShell),
          matching: find.byType(TextField),
        ),
        'Scale Check',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(ModernDialogShell),
          matching: find.text('Create Profile'),
        ),
      );
      await tester.pumpAndSettle();

      final verticalScroll = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      );

      // Visit Budgets via Bento card
      final budgetsBtn = find.text('Budgets');
      await tester.scrollUntilVisible(
        budgetsBtn,
        160,
        scrollable: verticalScroll.first,
      );
      await tester.drag(verticalScroll.first, const Offset(0, -180));
      await tester.pumpAndSettle();
      await tester.tap(budgetsBtn);
      await tester.pumpAndSettle();
      expect(find.text('No budgets configured'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      // Visit Loans via Bento card & check live EMI preview
      final loansBtn = find.text('Loans');
      await tester.scrollUntilVisible(
        loansBtn,
        160,
        scrollable: verticalScroll.first,
      );
      await tester.drag(verticalScroll.first, const Offset(0, -180));
      await tester.pumpAndSettle();
      await tester.tap(loansBtn);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Loan'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Loan Name (e.g., Car Loan)'),
        'Car Loan',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Principal (INR)'),
        '120000',
      );
      await tester.pumpAndSettle();
      expect(find.text('Estimated Monthly EMI'), findsOneWidget);

      await tester.ensureVisible(find.text('Create Loan'));
      await tester.tap(find.text('Create Loan'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Car Loan'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Visit Profile Hub & Settings at 1.5x text scale + Dark Mode -> verify zero overflow
      await tester.tap(find.byKey(const Key('bottom_nav_profile_switcher')));
      await tester.pumpAndSettle();
      final profileScroll15x = find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first;
      final settingsTile15x = find.byKey(
        const Key('profile_open_settings_tile'),
      );
      await tester.scrollUntilVisible(
        settingsTile15x,
        180,
        scrollable: profileScroll15x,
      );
      await tester.tap(settingsTile15x);
      await tester.pumpAndSettle();
      final settingsScroll15x = find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .last;
      await tester.scrollUntilVisible(
        find.byKey(const Key('settings_replay_onboarding_tile')),
        180,
        scrollable: settingsScroll15x,
      );
      expect(
        find.byKey(const Key('settings_replay_onboarding_tile')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets(
    'Desktop 1280x840 enterprise sidebar, centered modals, and multi-column layouts render with zero overflow',
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

      await tester.tap(find.byKey(const Key('onboarding_skip_btn')));
      await tester.pumpAndSettle();

      // 1. Wide 2-column Welcome showcase
      expect(find.text('Pocket CFO'), findsOneWidget);
      expect(find.text('Workspace Access'), findsOneWidget);
      await tester.tap(find.text('Start Offline Local Workspace'));
      await tester.pumpAndSettle();

      // 2. Profile creation via Quick-Start Template
      await tester.tap(find.text('Personal Wealth'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(ModernDialogShell),
          matching: find.text('Create Profile'),
        ),
      );
      await tester.pumpAndSettle();

      // 3. Enterprise Sidebar + Contextual Header verification
      expect(find.text('OVERVIEW'), findsOneWidget);
      expect(find.text('PLANNING'), findsOneWidget);
      expect(find.text('OPERATIONS'), findsOneWidget);
      expect(find.text('Executive Overview'), findsOneWidget);
      expect(find.text('Personal Finance (INR)'), findsOneWidget);
      expect(find.text('New Transaction'), findsOneWidget);

      // 4. Add Account via centered desktop Dialog
      await tester.tap(find.text('Add First Account'));
      await tester.pumpAndSettle();
      expect(find.text('Account Portfolio'), findsOneWidget);

      await tester.tap(find.text('Add Account'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);

      final accountFields = find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(accountFields.at(0), 'Treasury Checking');
      await tester.enterText(accountFields.at(1), '250000');
      await tester.tap(find.text('Save Account'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Net Position'), findsOneWidget);
      expect(find.text('Treasury Checking'), findsOneWidget);

      // 5. Return to Executive Overview & verify LIVE LEDGER Hero card
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('NET WORTH • INR'), findsOneWidget);
      expect(find.text('LIVE LEDGER'), findsOneWidget);

      // 6. Post transaction from Sidebar CTA centered Dialog
      await tester.tap(find.text('New Transaction'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Amount (INR)'),
        '1500',
      );
      await tester.tap(find.text('Post Transaction'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      // 7. Visit Desktop Ledger table & Financial Analytics via Sidebar
      await tester.tap(find.text('Ledger').first);
      await tester.pumpAndSettle();
      expect(find.text('Transaction Journal'), findsOneWidget);
      expect(find.text('TRANSACTION'), findsOneWidget);

      await tester.tap(find.text('Insights').first);
      await tester.pumpAndSettle();
      expect(find.text('Financial Analytics'), findsOneWidget);
      expect(find.text('Spending Breakdown'), findsOneWidget);

      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets(
    'Play Store swipe-down AppBar switch + Instagram bottom-bar flip/long-press switch + Light/Dark toggle + Logout flow',
    (tester) async {
      await initDeps();

      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const PocketCfoApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('onboarding_skip_btn')));
      await tester.pumpAndSettle();

      // 1. Start workspace & create Profile 1 ('Personal Finance')
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
      expect(find.text('Personal Finance (INR)'), findsOneWidget);

      // 2. Verify Dark Mode toggle is removed from the top AppBar (lives only in Profile/Settings)!
      expect(find.byTooltip('Switch to Dark theme'), findsNothing);
      expect(find.byTooltip('Switch to Light theme'), findsNothing);

      // 3. Tap AppBar Profile Header -> Add Profile 2 ('Business Studio')
      await tester.tap(find.byKey(const Key('appbar_profile_switcher')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Profile'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byType(ModernDialogShell),
          matching: find.byType(TextField),
        ),
        'Business Studio',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(ModernDialogShell),
          matching: find.text('Create Profile'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Business Studio (INR)'), findsOneWidget);
      expect(find.text('Welcome to Business Studio'), findsOneWidget);

      // 4. Play Store Swipe-Down on AppBar Header -> auto-switches to 'Personal Finance'
      await tester.drag(
        find.byKey(const Key('appbar_profile_switcher')),
        const Offset(0, 48),
      );
      await tester.pumpAndSettle();
      // Let toast timer finish cleanly if active
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(find.text('Personal Finance (INR)'), findsOneWidget);
      expect(find.text('Welcome to Personal Finance'), findsOneWidget);

      // 5. Instagram Bottom-Bar Double-Tap -> auto-flips to 'Business Studio' & opens Profile Hub
      final bottomProfile = find.byKey(
        const Key('bottom_nav_profile_switcher'),
      );
      await tester.tap(bottomProfile);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(bottomProfile);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(find.text('Business Studio (INR)'), findsOneWidget);
      expect(find.text('Finance Sections & Tools'), findsOneWidget);

      // 6. Instagram Bottom-Bar Long-Press -> opens bottom account switcher sheet
      await tester.longPress(bottomProfile);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('instagram_profile_sheet')), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('instagram_profile_sheet')),
          matching: find.text('Personal Finance'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(find.text('Personal Finance (INR)'), findsOneWidget);

      // 6b. Verify Profile Hero Card removed Next/New/Members buttons & renders live horizontal Family Members Avatar Stack!
      expect(find.text('Next Profile'), findsNothing);
      expect(find.text('New Profile'), findsNothing);
      expect(find.text('Members & Roles'), findsNothing);
      expect(
        find.byKey(const Key('profile_family_members_strip')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('profile_family_avatar_stack')),
        findsOneWidget,
      );

      // 6b. Test redesigned ModernDialogShell Rename Profile popup with live avatar preview!
      await tester.tap(find.byTooltip('Rename profile'));
      await tester.pumpAndSettle();
      expect(find.byType(ModernDialogShell), findsOneWidget);
      expect(find.text('Rename Profile'), findsOneWidget);
      expect(find.text('Preview'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Add 5 family members so total = 6 -> verifies ModernDialogShell + horizontal overlapping stack + '+N' overflow badge!
      for (final memberName in const ['Priya', 'Arjun', 'Mom', 'Dad', 'Riya']) {
        await tester.tap(find.byKey(const Key('profile_add_member_btn')));
        await tester.pumpAndSettle();
        expect(find.byType(ModernDialogShell), findsOneWidget);
        await tester.enterText(
          find.widgetWithText(
            TextField,
            'Member Name (e.g., Mom, Priya, Arjun)',
          ),
          memberName,
        );
        await tester.tap(find.text('Add Member'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        await tester.pumpAndSettle();
      }
      expect(
        find.byKey(const Key('family_stack_overflow_badge')),
        findsOneWidget,
      );

      // 6c. Verify Theme lives exclusively in Settings & Security (not repeated in Profile Hub)
      expect(find.text('Theme & Display'), findsNothing);
      final profileScroll = find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first;
      final settingsTile = find.byKey(const Key('profile_open_settings_tile'));
      await tester.scrollUntilVisible(
        settingsTile,
        160,
        scrollable: profileScroll,
      );
      await tester.tap(settingsTile);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('theme_mode_dark')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('theme_mode_light')));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      // 7. Logout from Profile Hub -> returns cleanly to Welcome screen
      final logoutBtn = find.byKey(const Key('profile_logout_button'));
      await tester.scrollUntilVisible(
        logoutBtn,
        180,
        scrollable: profileScroll,
      );
      await tester.tap(logoutBtn);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_logout_action')));
      await tester.pumpAndSettle();

      expect(find.text('Start Offline Local Workspace'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets(
    'Dashboard Quick Data Access: 1-tap Bank Account template -> Hero & Quick Log Preset posting -> live Burn-Rate & Top Categories Radar',
    (tester) async {
      await initDeps();

      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const PocketCfoApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('onboarding_skip_btn')));
      await tester.pumpAndSettle();

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

      // 1. Empty Dashboard Launchpad renders 1-tap account templates & Workspace Readiness.
      expect(find.text('1-Tap Account Templates'), findsOneWidget);
      expect(find.text('Workspace Readiness'), findsOneWidget);

      // 2. Tap 'Bank Account' preset directly on Dashboard -> pre-fills 'Primary Bank'
      final dashScroll = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      );
      await tester.scrollUntilVisible(
        find.text('Bank Account'),
        150,
        scrollable: dashScroll.first,
      );
      await tester.tap(find.text('Bank Account'));
      await tester.pumpAndSettle();

      expect(find.text('Primary Bank'), findsOneWidget);
      final modalFields = find.byType(TextField);
      await tester.enterText(modalFields.at(1), '80000');
      await tester.ensureVisible(find.text('Save Account'));
      await tester.tap(find.text('Save Account'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      // 3. Dashboard updates in-place with clean header, Hero Quick Actions, Quick Log Grid & Burn-Rate Pulse!
      expect(find.text('Financial Overview'), findsOneWidget);
      expect(find.text('NET WORTH • INR'), findsOneWidget);
      expect(find.text('Spend'), findsOneWidget);
      expect(find.text('Receive'), findsOneWidget);
      expect(find.text('Net Cash Flow'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Food & Cafe'),
        160,
        scrollable: dashScroll.first,
      );
      expect(find.text('QUICK LOG PRESETS'), findsOneWidget);

      // 4. Tap 'Food & Cafe' Quick Log Preset -> pre-fills description 'Food & Dining'
      await tester.tap(find.text('Food & Cafe'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Food & Dining'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Amount (INR)'),
        '1200',
      );
      await tester.ensureVisible(find.text('Post Transaction'));
      await tester.tap(find.text('Post Transaction'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      // 4b. Drag DraggableQuickBall across Home -> magnetic snap -> Set Budget 30,000 -> verify Safe / Day guard!
      await tester.drag(
        find.byKey(const Key('draggable_quick_ball')),
        const Offset(-260, -140),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('draggable_quick_ball')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quickball_set_budget')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Limit (INR)'),
        '30000',
      );
      await tester.ensureVisible(find.text('Save Budget'));
      await tester.tap(find.text('Save Budget'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Expense & Budget Guard'), findsOneWidget);
      expect(find.text('On Track'), findsOneWidget);
      expect(find.text('Budget Spent'), findsOneWidget);
      expect(find.text('Remaining'), findsOneWidget);
      expect(find.text('Safe / Day'), findsOneWidget);

      // 5. Scroll down to verify Account Vaults card, Top Categories Radar, and Recent Activity!
      await tester.scrollUntilVisible(
        find.text('Top Categories'),
        180,
        scrollable: dashScroll.first,
      );
      expect(find.text('Top Categories'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Recent Activity'),
        180,
        scrollable: dashScroll.first,
      );
      expect(find.text('Food & Dining'), findsOneWidget);

      // 6. Visit redesigned Accounts Portfolio tab -> verify Solvency badge, Sliding Segmented Filter, Sort, Archived & Statement Inspector!
      await tester.tap(find.text('Accounts'));
      await tester.pumpAndSettle();
      expect(find.text('Portfolio Overview'), findsOneWidget);
      expect(find.text('Debt-Free Portfolio'), findsOneWidget);
      expect(find.text('Bank & Cash'), findsOneWidget);
      expect(
        find.byKey(const Key('accounts_segmented_filter')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('accounts_sort_btn')), findsOneWidget);
      expect(find.byKey(const Key('accounts_archived_toggle')), findsOneWidget);

      // Test Sort menu interaction
      await tester.tap(find.byKey(const Key('accounts_sort_btn')));
      await tester.pumpAndSettle();
      expect(find.text('Name: A → Z'), findsOneWidget);
      await tester.tap(find.text('Name: A → Z'));
      await tester.pumpAndSettle();

      // Test segmented filter ('Credit' -> empty state -> reset to All)
      await tester.tap(find.text('Credit'));
      await tester.pumpAndSettle();
      expect(find.text('Show All Active Accounts'), findsOneWidget);
      await tester.tap(find.text('Show All Active Accounts'));
      await tester.pumpAndSettle();

      // Test Archived toggle -> empty archived -> toggle back
      await tester.tap(find.byKey(const Key('accounts_archived_toggle')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('No archived accounts'), findsOneWidget);
      await tester.tap(find.byKey(const Key('accounts_archived_toggle')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      final accScroll = find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('Activity'),
        160,
        scrollable: accScroll,
      );
      await tester.tap(find.text('Activity'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Recent Account Activity'), findsOneWidget);
      expect(find.text('Food & Dining'), findsWidgets);
      await tester.tap(find.byTooltip('Edit account details'));
      await tester.pumpAndSettle();
      expect(find.text('Save Changes'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets(
    'Real-time Budget 80% & >100% Limit Alerts fire in-app frosted banner, unread AppBar badge, Notification Centre & Settings test alert',
    (tester) async {
      await initDeps();

      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(size: Size(390, 844), disableAnimations: true),
          child: PocketCfoApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('onboarding_skip_btn')));
      await tester.pumpAndSettle();

      // 1. Create profile & bank account with ₹ 5,000 opening balance
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
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bank Account'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Opening Balance (INR)'),
        '5000',
      );
      await tester.ensureVisible(find.text('Save Account'));
      await tester.tap(find.text('Save Account'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      // 2. Set a ₹ 1,000 monthly budget via Home Expense & Budget Guard
      final setBudgetBtn = find.byKey(const Key('dashboard_set_budget_btn'));
      await tester.ensureVisible(setBudgetBtn);
      await tester.tap(setBudgetBtn);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Limit (INR)'),
        '1000',
      );
      await tester.ensureVisible(find.text('Save Budget'));
      await tester.tap(find.text('Save Budget'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      // 3. Post ₹ 850 expense (85%) -> fires 80% approaching limit banner + unread badge!
      final trackBtn1 = find.byKey(const Key('dashboard_track_expense_btn'));
      await tester.ensureVisible(trackBtn1);
      await tester.tap(trackBtn1);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Amount (INR)'),
        '850',
      );
      await tester.ensureVisible(find.text('Post Transaction'));
      await tester.tap(find.text('Post Transaction'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('in_app_alert_banner')), findsOneWidget);
      expect(find.text('LIMIT ALERT'), findsOneWidget);
      expect(
        find.byKey(const Key('appbar_notifications_badge')),
        findsOneWidget,
      );

      // Dismiss banner cleanly
      await tester.tap(find.byKey(const Key('in_app_alert_banner_close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('in_app_alert_banner')), findsNothing);

      // 4. Post ₹ 250 more (total ₹ 1,100 = 110%) -> fires LIMIT CROSSED critical banner!
      final trackBtn2 = find.byKey(const Key('dashboard_track_expense_btn'));
      await tester.ensureVisible(trackBtn2);
      await tester.tap(trackBtn2);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Amount (INR)'),
        '250',
      );
      await tester.ensureVisible(find.text('Post Transaction'));
      await tester.tap(find.text('Post Transaction'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('in_app_alert_banner')), findsOneWidget);
      expect(find.text('LIMIT CROSSED'), findsOneWidget);
      await tester.tap(find.byKey(const Key('in_app_alert_banner_close')));
      await tester.pumpAndSettle();

      // 5. Open Notification Centre via AppBar AnimatedNotificationBell -> verify both alerts & filter
      await tester.tap(find.byKey(const Key('appbar_notifications_btn')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('notifications_segmented_filter')),
        findsOneWidget,
      );
      expect(find.text('OVER LIMIT'), findsOneWidget);
      expect(find.text('80% WARN'), findsOneWidget);

      await tester.tap(find.text('Mark all read'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Clear read'), findsOneWidget);

      // 6. Visit Alert Settings & trigger 1-tap Send Test Alert
      await tester.tap(find.byTooltip('Alert Preferences'));
      await tester.pumpAndSettle();
      final settingsScroll = find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .last;
      await tester.scrollUntilVisible(
        find.byKey(const Key('settings_send_test_notification_btn')),
        180,
        scrollable: settingsScroll,
      );
      expect(
        find.byKey(const Key('settings_smart_alerts_section')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('settings_send_test_notification_btn')),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('in_app_alert_banner')), findsOneWidget);
      expect(find.text('Pocket CFO Alerts Active'), findsOneWidget);

      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );
}
