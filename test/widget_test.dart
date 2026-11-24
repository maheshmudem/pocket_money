import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_money/app/app.dart';
import 'package:pocket_money/app/config/environment_config.dart';
import 'package:pocket_money/bootstrap.dart';
import 'package:pocket_money/core/database/app_database.dart';
import 'package:pocket_money/core/database/encrypted_executor.dart';
import 'package:pocket_money/core/security/key_manager.dart';
import 'package:pocket_money/core/utilities/clock.dart';
import 'package:pocket_money/shared/widgets/modern_dialogs.dart';

void main() {
  setUp(() async {
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
  });

  tearDown(() async {
    if (getIt.isRegistered<AppDatabase>()) {
      await getIt<AppDatabase>().close();
    }
    await getIt.reset();
  });

  testWidgets(
    'Onboarding -> Welcome -> Start Offline Local Workspace -> Create First Profile -> Dashboard',
    (tester) async {
      await tester.pumpWidget(const PocketCfoApp());
      await tester.pumpAndSettle();

      // First-run Onboarding renders cleanly and skips straight to Welcome.
      expect(find.byKey(const Key('onboarding_page')), findsOneWidget);
      await tester.tap(find.byKey(const Key('onboarding_skip_btn')));
      await tester.pumpAndSettle();

      // SCR-ONB-002 Welcome screen renders cleanly.
      expect(find.text('Pocket CFO'), findsOneWidget);
      expect(find.text('Start Offline Local Workspace'), findsOneWidget);

      // Tap offline local workspace.
      await tester.tap(find.text('Start Offline Local Workspace'));
      await tester.pumpAndSettle();

      // First-run empty profiles screen appears.
      expect(find.text('Create Your First Profile'), findsOneWidget);
      await tester.tap(find.text('Create Profile'));
      await tester.pumpAndSettle();

      // Fill profile name and create.
      await tester.enterText(
        find.descendant(
          of: find.byType(ModernDialogShell),
          matching: find.byType(TextField),
        ),
        'Personal Finance',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(ModernDialogShell),
          matching: find.text('Create Profile'),
        ),
      );
      await tester.pumpAndSettle();

      // Lands directly in Dashboard with active profile chip!
      expect(find.text('Personal Finance (INR)'), findsOneWidget);
      expect(find.text('Welcome to Personal Finance'), findsOneWidget);
      expect(find.text('Add First Account'), findsOneWidget);
    },
  );
}
