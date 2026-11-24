import 'package:drift/drift.dart';

import 'database_triggers.dart';
import 'tables/core_tables.dart';
import 'tables/ledger_tables.dart';
import 'tables/operations_tables.dart';
import 'tables/planning_tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    // Workspace & Monetary
    Profiles,
    ProfileMemberships,
    ProfileCurrencyHistory,
    AppSettings,
    Currencies,
    ExchangeRates,
    LedgerAccounts,
    FinancialAccounts,
    Categories,
    // Double-Entry Ledger & Transactions
    Transactions,
    TransactionSplits,
    JournalEntries,
    LedgerPostings,
    Attachments,
    // Planning, Goals, Recurring & Loans
    Budgets,
    BudgetCategories,
    SavingsGoals,
    GoalContributions,
    RecurringRules,
    Loans,
    LoanInstallments,
    // Import, Sync, Audit & Notifications
    ImportBatches,
    ImportedTransactions,
    SyncOutbox,
    SyncCursors,
    SyncConflicts,
    AuditLogs,
    LocalNotifications,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _installIntegrityObjects();
      await seedDefaultCurrencies();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      // Versioned incremental upgrades go here without ever mutating released versions.
      await _installIntegrityObjects();
    },
    beforeOpen: (OpeningDetails details) async {
      await customStatement('PRAGMA foreign_keys = ON;');
    },
  );

  Future<void> _installIntegrityObjects() async {
    for (final indexSql in DatabaseIntegritySql.indexStatements) {
      await customStatement(indexSql);
    }
    for (final triggerSql in DatabaseIntegritySql.triggerStatements) {
      await customStatement(triggerSql);
    }
  }

  Future<void> seedDefaultCurrencies() async {
    await batch((b) {
      b.insertAllOnConflictUpdate(
        currencies,
        DatabaseIntegritySql.defaultCurrencies
            .map(
              (c) => CurrenciesCompanion.insert(
                code: c.code,
                name: c.name,
                minorUnit: c.minorUnit,
                symbol: Value(c.symbol),
              ),
            )
            .toList(),
      );
    });
  }
}
