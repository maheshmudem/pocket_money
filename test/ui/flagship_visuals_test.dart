import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_money/app/theme/app_theme.dart';
import 'package:pocket_money/core/financial_engine/money.dart';
import 'package:pocket_money/core/utilities/id_generator.dart';
import 'package:pocket_money/features/accounts/domain/entities/financial_account_entity.dart';
import 'package:pocket_money/shared/widgets/editorial_bento_kit.dart';
import 'package:pocket_money/shared/widgets/fintech_widgets.dart';
import 'package:pocket_money/shared/widgets/flagship_visuals.dart';
import 'package:pocket_money/shared/widgets/modern_dialogs.dart';

void main() {
  testWidgets(
    'Flagship visual primitives render cleanly at 360x800 + 1.5x in Light and Dark themes with zero overflow',
    (tester) async {
      const account = FinancialAccountEntity(
        id: 'acc-1',
        profileId: ProfileId('p-1'),
        ledgerAccountId: 'la-1',
        name: 'Primary Bank',
        accountType: FinancialAccountType.bank,
        currencyCode: 'INR',
        institutionLabel: 'HDFC',
        balance: Money(amountMinor: 11900000, currencyCode: 'INR'),
        baseBalance: Money(amountMinor: 11900000, currencyCode: 'INR'),
        isActive: true,
        version: 1,
        syncStatus: 'local_only',
        createdAtUtc: '2026-11-01T00:00:00Z',
        updatedAtUtc: '2026-11-26T00:00:00Z',
      );

      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        var tappedAction = false;
        var tappedBlock = false;
        await tester.binding.setSurfaceSize(const Size(360, 800));
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                key: ValueKey<Brightness>(theme.brightness),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FintechSignatureHero(
                      tone: SignatureHeroTone.indigo,
                      child: Row(
                        children: const [
                          Expanded(
                            child: HeroGlassPill(
                              label: 'LIVE LEDGER',
                              dotColor: Color(0xFF34D399),
                            ),
                          ),
                          SizedBox(width: 8),
                          MiniSparklineChart(
                            values: [10, 22, 18, 35, 48, 60],
                            color: Color(0xFF34D399),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    CircularActionDock(
                      items: [
                        CircularActionItem(
                          key: const Key('test_circular_spend'),
                          icon: Icons.north_east_rounded,
                          label: 'Spend',
                          color: Colors.redAccent,
                          onTap: () => tappedAction = true,
                        ),
                        CircularActionItem(
                          icon: Icons.south_west_rounded,
                          label: 'Receive',
                          color: Colors.green,
                          onTap: () {},
                        ),
                        CircularActionItem(
                          icon: Icons.swap_horiz_rounded,
                          label: 'Transfer',
                          color: Colors.blue,
                          onTap: () {},
                        ),
                        CircularActionItem(
                          icon: Icons.add_card_rounded,
                          label: 'Vault',
                          color: Colors.indigo,
                          onTap: () {},
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: const [
                        MiniRingGauge(
                          progress: 0.94,
                          color: Colors.green,
                          centerLabel: '94%',
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: VisualFlowRatioBar(
                            primaryMinor: 10000000,
                            secondaryMinor: 600000,
                            primaryColor: Colors.green,
                            secondaryColor: Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const HeroWealthAreaChart(
                      values: [25000, 40000, 52000, 88000, 119000],
                      color: Color(0xFF34D399),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: const [
                        SizedBox(
                          width: 82,
                          child: BentoVerticalFlowBars(
                            incomeMinor: 10000000,
                            expenseMinor: 600000,
                          ),
                        ),
                        SizedBox(width: 12),
                        MiniSpeedometerArc(
                          progress: 0.24,
                          color: Colors.green,
                          centerLabel: '24%',
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: MoneyText(
                            money: Money(
                              amountMinor: 11900050,
                              currencyCode: 'INR',
                            ),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TactileColorBlock(
                      key: const Key('test_tactile_block'),
                      accent: const Color(0xFF7C3AED),
                      onTap: () => tappedBlock = true,
                      child: const Row(
                        children: [
                          Icon(Icons.pie_chart_rounded, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'CRED Tactile Color Block',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    FullBleedTheaterStage(
                      tone: SignatureHeroTone.indigo,
                      isWideCard: true,
                      floatingDock: FloatingStageDock(
                        items: [
                          CircularActionItem(
                            icon: Icons.north_east_rounded,
                            label: 'Spend',
                            color: Colors.redAccent,
                            onTap: () {},
                          ),
                          CircularActionItem(
                            icon: Icons.south_west_rounded,
                            label: 'Receive',
                            color: Colors.green,
                            onTap: () {},
                          ),
                        ],
                      ),
                      child: const Text(
                        'Theater Stage',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Row(
                      children: [
                        CockpitSegmentedArcGauge(
                          progress: 0.42,
                          color: Color(0xFF059669),
                          centerLabel: '42%',
                        ),
                        SizedBox(width: 12),
                        AssetAllocationDonut(
                          slices: [
                            AllocationDonutSlice(
                              value: 80,
                              color: Color(0xFF2563EB),
                            ),
                            AllocationDonutSlice(
                              value: 20,
                              color: Color(0xFF7C3AED),
                            ),
                          ],
                          centerValue: '2',
                          centerCaption: 'VAULTS',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const DualWingCashflowBar(
                      totalCount: 4,
                      inflow: Money(amountMinor: 10000000, currencyCode: 'INR'),
                      outflow: Money(amountMinor: 600000, currencyCode: 'INR'),
                      net: Money(amountMinor: 9400000, currencyCode: 'INR'),
                      masked: false,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: SculptedBentoAppTile(
                            icon: Icons.pie_chart_rounded,
                            title: 'Budgets',
                            subtitle: 'CA ZBB & BvA',
                            accent: const Color(0xFF2563EB),
                            badge: '2',
                            onTap: () {},
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: WatermarkBentoCard(
                            accent: Color(0xFF059669),
                            watermarkIcon: Icons.savings_rounded,
                            child: Text('94%'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    VirtualAccountVaultCard(
                      account: account,
                      baseCurrency: 'INR',
                      sharePercent: 100,
                      masked: false,
                      onTap: () {},
                      bottomBar: HeroGlassActionBar(
                        items: [
                          FintechFlatActionItem(
                            icon: Icons.north_east_rounded,
                            label: 'Spend',
                            color: const Color(0xFFFDA4AF),
                            onTap: () {},
                          ),
                          FintechFlatActionItem(
                            icon: Icons.receipt_long_rounded,
                            label: 'Activity',
                            color: const Color(0xFFC7D2FE),
                            onTap: () {},
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Primary Bank'), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const Key('test_circular_spend')),
        );
        await tester.tap(find.byKey(const Key('test_circular_spend')));
        await tester.pumpAndSettle();
        expect(tappedAction, isTrue);
        await tester.ensureVisible(find.byKey(const Key('test_tactile_block')));
        await tester.tap(find.byKey(const Key('test_tactile_block')));
        await tester.pumpAndSettle();
        expect(tappedBlock, isTrue);
      }

      addTearDown(() => tester.binding.setSurfaceSize(null));
    },
  );
}
