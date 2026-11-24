import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_money/app/theme/app_theme.dart';
import 'package:pocket_money/shared/widgets/modern_dropdown.dart';

void main() {
  testWidgets(
    'FintechDropdownField anchors cleanly below top trigger, filters via search, and updates selection',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      String selected = 'INR';

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: Padding(
                padding: const EdgeInsets.fromLTRB(20, 80, 20, 20),
                child: FintechDropdownField<String>(
                  key: const Key('top_currency_dd'),
                  label: 'Base Currency',
                  value: selected,
                  searchable: true,
                  searchHint: 'Search currency...',
                  options: FintechDropdownOption.builtInCurrencies(),
                  onChanged: (v) => setState(() => selected = v),
                ),
              ),
            ),
          ),
        ),
      );

      final triggerFinder = find.byKey(const Key('top_currency_dd'));
      final triggerRect = tester.getRect(triggerFinder);

      await tester.tap(triggerFinder);
      await tester.pumpAndSettle();

      final popoverFinder = find.byKey(const Key('fintech_dropdown_popover'));
      expect(popoverFinder, findsOneWidget);

      final popoverRect = tester.getRect(popoverFinder);
      // Placed cleanly below trigger without overlapping trigger and matching trigger width.
      expect(popoverRect.top, greaterThanOrEqualTo(triggerRect.bottom));
      expect(popoverRect.width, closeTo(triggerRect.width, 1.0));
      expect(popoverRect.left, closeTo(triggerRect.left, 1.0));

      // Filter currencies via inline search field and pick USD.
      await tester.enterText(
        find.byKey(const Key('fintech_dropdown_search_field')),
        'zzz_nope',
      );
      await tester.pumpAndSettle();
      expect(find.text('No matching options'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('fintech_dropdown_search_field')),
        'USD',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('USD').last);
      await tester.pumpAndSettle();

      expect(selected, 'USD');
      expect(find.text('USD (\$)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'FintechDropdownField flips smoothly ABOVE bottom trigger and handles nullable options in Dark Mode + 1.5x text scale',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      String? selectedCat = 'food';

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 800),
            textScaler: TextScaler.linear(1.5),
            disableAnimations: true,
          ),
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                    child: FintechDropdownField<String?>(
                      key: const Key('bottom_cat_dd'),
                      label: 'Category Scope (optional)',
                      value: selectedCat,
                      options: const [
                        FintechDropdownOption<String?>(
                          value: null,
                          label: 'All Expense Categories',
                          subtitle: 'Track total spending',
                          icon: Icons.all_inclusive_rounded,
                        ),
                        FintechDropdownOption<String?>(
                          value: 'food',
                          label: 'Dining & Food',
                          icon: Icons.restaurant_rounded,
                        ),
                        FintechDropdownOption<String?>(
                          value: 'travel',
                          label: 'Transport & Fuel',
                          icon: Icons.directions_car_rounded,
                        ),
                      ],
                      onChanged: (v) => setState(() => selectedCat = v),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final triggerFinder = find.byKey(const Key('bottom_cat_dd'));
      final triggerRect = tester.getRect(triggerFinder);

      await tester.tap(triggerFinder);
      await tester.pumpAndSettle();

      final popoverFinder = find.byKey(const Key('fintech_dropdown_popover'));
      expect(popoverFinder, findsOneWidget);
      final popoverRect = tester.getRect(popoverFinder);

      // Must flip cleanly ABOVE the bottom trigger without overlapping it.
      expect(popoverRect.bottom, lessThanOrEqualTo(triggerRect.top));
      expect(popoverRect.top, greaterThanOrEqualTo(0));

      // Selecting nullable value (`null`) must propagate cleanly instead of being treated as cancel.
      await tester.tap(find.text('All Expense Categories'));
      await tester.pumpAndSettle();

      expect(selectedCat, isNull);
      expect(find.text('All Expense Categories'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
