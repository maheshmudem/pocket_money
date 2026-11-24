import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_money/core/database/app_database.dart';
import 'package:pocket_money/core/database/encrypted_executor.dart';

void main() {
  late AppDatabase db;
  const now = '2026-11-19T07:00:00Z';

  setUp(() async {
    db = AppDatabase(EncryptedDatabaseExecutor.openInMemory());
    // Seed two distinct profiles to test cross-profile isolation & ledger triggers.
    for (final id in ['prof-a', 'prof-b']) {
      await db
          .into(db.profiles)
          .insert(
            ProfilesCompanion.insert(
              id: id,
              name: 'Profile $id',
              profileType: 'personal',
              baseCurrencyCode: 'INR',
              createdAtUtc: now,
              updatedAtUtc: now,
            ),
          );
      await db
          .into(db.ledgerAccounts)
          .insert(
            LedgerAccountsCompanion.insert(
              id: 'la-cash-$id',
              profileId: id,
              name: 'Cash',
              accountType: 'asset',
              normalBalance: 'debit',
              createdAtUtc: now,
            ),
          );
      await db
          .into(db.ledgerAccounts)
          .insert(
            LedgerAccountsCompanion.insert(
              id: 'la-exp-$id',
              profileId: id,
              name: 'Food',
              accountType: 'expense',
              normalBalance: 'debit',
              createdAtUtc: now,
            ),
          );
      await db
          .into(db.financialAccounts)
          .insert(
            FinancialAccountsCompanion.insert(
              id: 'fa-cash-$id',
              profileId: id,
              ledgerAccountId: 'la-cash-$id',
              name: 'Wallet',
              accountType: 'cash',
              currencyCode: 'INR',
              createdAtUtc: now,
              updatedAtUtc: now,
            ),
          );
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: 'cat-food-$id',
              profileId: id,
              ledgerAccountId: 'la-exp-$id',
              name: 'Food',
              categoryType: 'expense',
              createdAtUtc: now,
              updatedAtUtc: now,
            ),
          );
    }
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'seeds built-in ISO currencies including INR, JPY(0), KWD(3), CLF(4)',
    () async {
      final all = await db.select(db.currencies).get();
      final byCode = {for (final c in all) c.code: c};
      expect(byCode['INR']?.minorUnit, 2);
      expect(byCode['JPY']?.minorUnit, 0);
      expect(byCode['KWD']?.minorUnit, 3);
      expect(byCode['CLF']?.minorUnit, 4);
    },
  );

  test(
    'R-003 composite FK blocks cross-profile transaction referencing another profile account',
    () async {
      await expectLater(
        () => db
            .into(db.transactions)
            .insert(
              TransactionsCompanion.insert(
                id: 'tx-cross-1',
                profileId: 'prof-a',
                transactionType: 'expense',
                status: 'posted',
                transactionDateUtc: now,
                amountMinor: 50000,
                currencyCode: 'INR',
                baseCurrencyCode: 'INR',
                baseAmountMinor: 50000,
                fxRateScaled: 100000000,
                fxRateScale: 100000000,
                sourceAccountId: const Value('fa-cash-prof-b'),
                categoryId: const Value('cat-food-prof-a'),
                createdAtUtc: now,
                updatedAtUtc: now,
              ),
            ),
        throwsA(anything),
      );
    },
  );

  test(
    'TC-FIN-008 SQLite trigger blocks posting unbalanced journal (debit 1000 != credit 999)',
    () async {
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: 'tx-unbal-1',
              profileId: 'prof-a',
              transactionType: 'expense',
              status: 'posted',
              transactionDateUtc: now,
              amountMinor: 1000,
              currencyCode: 'INR',
              baseCurrencyCode: 'INR',
              baseAmountMinor: 1000,
              fxRateScaled: 100000000,
              fxRateScale: 100000000,
              sourceAccountId: const Value('fa-cash-prof-a'),
              categoryId: const Value('cat-food-prof-a'),
              createdAtUtc: now,
              updatedAtUtc: now,
            ),
          );

      // Direct posted insert MUST fail.
      await expectLater(
        () => db
            .into(db.journalEntries)
            .insert(
              JournalEntriesCompanion.insert(
                id: 'je-direct-bad',
                profileId: 'prof-a',
                transactionId: 'tx-unbal-1',
                status: 'posted',
                effectiveAtUtc: now,
                createdAtUtc: now,
              ),
            ),
        throwsA(anything),
      );

      // Insert draft + unbalanced postings, then attempt to post -> MUST abort.
      await db
          .into(db.journalEntries)
          .insert(
            JournalEntriesCompanion.insert(
              id: 'je-unbal-1',
              profileId: 'prof-a',
              transactionId: 'tx-unbal-1',
              status: 'draft',
              effectiveAtUtc: now,
              createdAtUtc: now,
            ),
          );
      await db
          .into(db.ledgerPostings)
          .insert(
            LedgerPostingsCompanion.insert(
              id: 'lp-1',
              profileId: 'prof-a',
              journalEntryId: 'je-unbal-1',
              ledgerAccountId: 'la-exp-prof-a',
              side: 'debit',
              baseAmountMinor: 1000,
              currencyCode: 'INR',
              originalAmountMinor: 1000,
            ),
          );
      await db
          .into(db.ledgerPostings)
          .insert(
            LedgerPostingsCompanion.insert(
              id: 'lp-2',
              profileId: 'prof-a',
              journalEntryId: 'je-unbal-1',
              ledgerAccountId: 'la-cash-prof-a',
              side: 'credit',
              baseAmountMinor: 999,
              currencyCode: 'INR',
              originalAmountMinor: 999,
            ),
          );

      await expectLater(
        () =>
            (db.update(db.journalEntries)
                  ..where((j) => j.id.equals('je-unbal-1')))
                .write(const JournalEntriesCompanion(status: Value('posted'))),
        throwsA(anything),
      );
    },
  );

  test(
    'TC-FIN-011 SQLite triggers enforce strict immutability of posted journals and postings',
    () async {
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: 'tx-imm-1',
              profileId: 'prof-a',
              transactionType: 'expense',
              status: 'posted',
              transactionDateUtc: now,
              amountMinor: 50000,
              currencyCode: 'INR',
              baseCurrencyCode: 'INR',
              baseAmountMinor: 50000,
              fxRateScaled: 100000000,
              fxRateScale: 100000000,
              sourceAccountId: const Value('fa-cash-prof-a'),
              categoryId: const Value('cat-food-prof-a'),
              createdAtUtc: now,
              updatedAtUtc: now,
            ),
          );

      await db
          .into(db.journalEntries)
          .insert(
            JournalEntriesCompanion.insert(
              id: 'je-imm-1',
              profileId: 'prof-a',
              transactionId: 'tx-imm-1',
              status: 'draft',
              effectiveAtUtc: now,
              createdAtUtc: now,
            ),
          );
      await db
          .into(db.ledgerPostings)
          .insert(
            LedgerPostingsCompanion.insert(
              id: 'lp-imm-1',
              profileId: 'prof-a',
              journalEntryId: 'je-imm-1',
              ledgerAccountId: 'la-exp-prof-a',
              side: 'debit',
              baseAmountMinor: 50000,
              currencyCode: 'INR',
              originalAmountMinor: 50000,
            ),
          );
      await db
          .into(db.ledgerPostings)
          .insert(
            LedgerPostingsCompanion.insert(
              id: 'lp-imm-2',
              profileId: 'prof-a',
              journalEntryId: 'je-imm-1',
              ledgerAccountId: 'la-cash-prof-a',
              side: 'credit',
              baseAmountMinor: 50000,
              currencyCode: 'INR',
              originalAmountMinor: 50000,
            ),
          );

      // Balanced posting succeeds.
      await (db.update(db.journalEntries)
            ..where((j) => j.id.equals('je-imm-1')))
          .write(const JournalEntriesCompanion(status: Value('posted')));

      // Attempting to mutate posting amount MUST fail.
      await expectLater(
        () =>
            (db.update(
              db.ledgerPostings,
            )..where((p) => p.id.equals('lp-imm-1'))).write(
              const LedgerPostingsCompanion(baseAmountMinor: Value(10000)),
            ),
        throwsA(anything),
      );

      // Attempting to delete posted journal MUST fail.
      await expectLater(
        () => (db.delete(
          db.journalEntries,
        )..where((j) => j.id.equals('je-imm-1'))).go(),
        throwsA(anything),
      );

      // Attempting to delete posting of posted journal MUST fail.
      await expectLater(
        () => (db.delete(
          db.ledgerPostings,
        )..where((p) => p.id.equals('lp-imm-1'))).go(),
        throwsA(anything),
      );
    },
  );
}
