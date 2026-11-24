import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_money/app/theme/app_theme.dart';
import 'package:pocket_money/shared/widgets/modern_inputs.dart';

void main() {
  testWidgets(
    'FintechTextField renders clean internal label without border notch, supports clear & obscure toggle',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final nameCtrl = TextEditingController();
      final pinCtrl = TextEditingController();
      addTearDown(() {
        nameCtrl.dispose();
        pinCtrl.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  FintechTextField(
                    label: 'Profile Name',
                    hintText: 'Personal Vault',
                    controller: nameCtrl,
                    leadingIcon: Icons.badge_outlined,
                    showClearButton: true,
                  ),
                  const SizedBox(height: 12),
                  FintechTextField(
                    label: 'Fallback PIN',
                    controller: pinCtrl,
                    leadingIcon: Icons.pin_outlined,
                    obscureText: true,
                    enableObscureToggle: true,
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Compatible with standard find.widgetWithText(TextField, label) locators.
      final nameFinder = find.widgetWithText(TextField, 'Profile Name');
      expect(nameFinder, findsOneWidget);
      await tester.enterText(nameFinder, 'Family Vault');
      await tester.pumpAndSettle();
      expect(nameCtrl.text, 'Family Vault');

      // Clear button appears and empties field cleanly.
      await tester.tap(find.byTooltip('Clear'));
      await tester.pumpAndSettle();
      expect(nameCtrl.text, isEmpty);

      // Obscure toggle flips visibility without external boilerplate state.
      final pinFinder = find.widgetWithText(TextField, 'Fallback PIN');
      expect(tester.widget<TextField>(pinFinder).obscureText, isTrue);
      await tester.tap(find.byTooltip('Show'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(pinFinder).obscureText, isFalse);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'FintechTextFormField validates cleanly & FintechSearchField clears under Dark Mode + 1.5x text scale',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final formKey = GlobalKey<FormState>();
      final emailCtrl = TextEditingController();
      final searchCtrl = TextEditingController();
      var clearedCount = 0;
      addTearDown(() {
        emailCtrl.dispose();
        searchCtrl.dispose();
      });

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 800),
            textScaler: TextScaler.linear(1.5),
            disableAnimations: true,
          ),
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: formKey,
                  child: Column(
                    children: [
                      FintechSearchField(
                        key: const Key('test_search_pill'),
                        controller: searchCtrl,
                        hintText: 'Search ledger...',
                        onClear: () => clearedCount++,
                      ),
                      const SizedBox(height: 16),
                      FintechTextFormField(
                        label: 'Email Address',
                        controller: emailCtrl,
                        leadingIcon: Icons.email_outlined,
                        validator: (v) => (v == null || !v.contains('@'))
                            ? 'Enter a valid email address'
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Form validation surfaces clean inline error message.
      expect(formKey.currentState!.validate(), isFalse);
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid email address'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Email Address'),
        'user@pocketcfo.app',
      );
      expect(formKey.currentState!.validate(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid email address'), findsNothing);

      // Search pill types and clears cleanly.
      await tester.enterText(
        find.byKey(const Key('test_search_pill')),
        'Groceries',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(searchCtrl.text, isEmpty);
      expect(clearedCount, 1);

      expect(tester.takeException(), isNull);
    },
  );
}
