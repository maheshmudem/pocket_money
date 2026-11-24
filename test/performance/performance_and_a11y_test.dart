import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_money/app/app.dart';
import 'package:pocket_money/app/config/environment_config.dart';
import 'package:pocket_money/bootstrap.dart';
import 'package:pocket_money/core/database/app_database.dart';
import 'package:pocket_money/core/database/encrypted_executor.dart';
import 'package:pocket_money/core/logging/redacting_logger.dart';
import 'package:pocket_money/core/security/key_manager.dart';
import 'package:pocket_money/core/utilities/clock.dart';
import 'package:pocket_money/core/utilities/id_generator.dart';
import 'package:pocket_money/features/accounts/data/repositories/drift_account_repository.dart';
import 'package:pocket_money/features/accounts/domain/entities/financial_account_entity.dart';
import 'package:pocket_money/features/categories/data/repositories/drift_category_repository.dart';
import 'package:pocket_money/features/categories/domain/entities/category_entity.dart';
import 'package:pocket_money/features/dashboard/data/repositories/drift_analytics_repository.dart';
import 'package:pocket_money/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:pocket_money/features/profiles/data/repositories/drift_profile_repository.dart';
import 'package:pocket_money/features/profiles/domain/entities/profile_entity.dart';
import 'package:pocket_money/features/transactions/data/repositories/drift_transaction_repository.dart';
import 'package:pocket_money/features/transactions/domain/entities/transaction_entity.dart';

void main() {
  test(
    'TC-FIN-019 & NFR-002: 500-transaction stress ledger reconciles cleanly and computes dashboard < 1000ms',
    () async {
      final db = AppDatabase(EncryptedDatabaseExecutor.openInMemory());
      final clock = FixedUtcClock(DateTime.utc(2026, 11, 19, 10, 0));
      const idGen = UuidV4Generator();
      final logger = RedactingLogger();

      final profileRepo = DriftProfileRepository(
        db: db,
        idGenerator: idGen,
        clock: clock,
        logger: logger,
      );
      final accRepo = DriftAccountRepository(
        db: db,
        idGenerator: idGen,
        clock: clock,
      );
      final catRepo = DriftCategoryRepository(
        db: db,
        idGenerator: idGen,
        clock: clock,
      );
      final txRepo = DriftTransactionRepository(
        db: db,
        idGenerator: idGen,
        clock: clock,
        logger: logger,
      );
      final analyticsRepo = DriftAnalyticsRepository(
        db: db,
        accountRepository: accRepo,
        transactionRepository: txRepo,
        clock: clock,
      );

      final prof = (await profileRepo.createProfile(
        userId: 'bench-user',
        ownerDisplayName: 'Bench',
        name: 'Stress Profile',
        profileType: ProfileType.business,
        baseCurrencyCode: 'INR',
      )).valueOrNull!;

      final bank = (await accRepo.createAccountWithOpeningBalance(
        profileId: prof.id,
        name: 'Operating Bank',
        accountType: FinancialAccountType.bank,
        currencyCode: 'INR',
        openingBalanceMinor: 100000000, // ₹10,00,000
      )).valueOrNull!;

      final expCat = (await catRepo.listCategories(
        prof.id,
        type: CategoryType.expense,
      )).valueOrNull!.first;

      // Seed 500 posted double-entry expense transactions (1000+ postings).
      const txCount = 500;
      const eachAmount = 10000; // ₹100.00
      for (var i = 0; i < txCount; i++) {
        final res = await txRepo.createTransaction(
          prof.id,
          CreateTransactionCommand(
            type: TransactionType.expense,
            amountMinor: eachAmount,
            currencyCode: 'INR',
            transactionDateUtc: clock.nowIsoUtc(),
            sourceAccountId: bank.id,
            categoryId: expCat.id,
            description: 'Synthetic item #$i',
          ),
        );
        expect(res.isSuccess, isTrue);
      }

      // Measure single local save latency (< 300ms budget).
      final saveSw = Stopwatch()..start();
      final oneMore = await txRepo.createTransaction(
        prof.id,
        CreateTransactionCommand(
          type: TransactionType.expense,
          amountMinor: eachAmount,
          currencyCode: 'INR',
          transactionDateUtc: clock.nowIsoUtc(),
          sourceAccountId: bank.id,
          categoryId: expCat.id,
          description: 'Latency check tx',
        ),
      );
      saveSw.stop();
      expect(oneMore.isSuccess, isTrue);
      expect(saveSw.elapsedMilliseconds, lessThan(300));

      // Measure dashboard aggregation latency (< 1000ms budget) & exact balance match!
      final dashSw = Stopwatch()..start();
      final dash = (await analyticsRepo.computeDashboardSummary(
        prof.id,
        period: DashboardPeriodPreset.thisMonth,
      )).valueOrNull!;
      dashSw.stop();

      expect(dashSw.elapsedMilliseconds, lessThan(1000));
      expect(dash.periodNetExpense.amountMinor, (txCount + 1) * eachAmount);
      expect(
        dash.netWorth.amountMinor,
        100000000 - ((txCount + 1) * eachAmount),
      );

      // Full ledger reconciliation invariant check.
      final recon = (await txRepo.runReconciliationCheck(prof.id)).valueOrNull!;
      expect(recon.isHealthy, isTrue);
      expect(
        recon.postedJournalCount,
        txCount + 2,
      ); // +1 opening balance +1 latency tx
      expect(recon.totalDebitsMinor, recon.totalCreditsMinor);

      await db.close();
    },
  );

  testWidgets(
    'NFR-010 & NFR-011: Dark Theme + 2.0x text scaling + reduced motion renders with zero overflow',
    (tester) async {
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

      addTearDown(() async {
        if (getIt.isRegistered<AppDatabase>()) {
          await getIt<AppDatabase>().close();
        }
        await getIt.reset();
      });

      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(
            size: Size(390, 844),
            textScaler: TextScaler.linear(2.0),
            disableAnimations: true,
            platformBrightness: Brightness.dark,
          ),
          child: PocketCfoApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pocket CFO'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
