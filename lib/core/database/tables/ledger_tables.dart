import 'package:drift/drift.dart';

import 'core_tables.dart';

class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get transactionType => text().check(
    transactionType.isIn(const [
      'opening_balance',
      'income',
      'expense',
      'transfer',
      'adjustment',
      'refund',
    ]),
  )();
  TextColumn get status =>
      text().check(status.isIn(const ['draft', 'posted', 'voided']))();
  TextColumn get transactionDateUtc => text()();
  IntColumn get amountMinor =>
      integer().check(amountMinor.isBiggerThanValue(0))();
  TextColumn get currencyCode => text().references(Currencies, #code)();
  IntColumn get destinationAmountMinor => integer().nullable()();
  TextColumn get destinationCurrencyCode =>
      text().nullable().references(Currencies, #code)();
  TextColumn get baseCurrencyCode => text().references(Currencies, #code)();
  IntColumn get baseAmountMinor =>
      integer().check(baseAmountMinor.isBiggerOrEqualValue(0))();
  IntColumn get fxRateScaled =>
      integer().check(fxRateScaled.isBiggerThanValue(0))();
  IntColumn get fxRateScale =>
      integer().check(fxRateScale.isBiggerThanValue(0))();
  TextColumn get fxRateSource =>
      text().withDefault(const Constant('identity'))();
  TextColumn get fxEffectiveAtUtc => text().nullable()();
  TextColumn get fxRoundingMode =>
      text().withDefault(const Constant('HALF_EVEN'))();
  TextColumn get sourceAccountId => text().nullable()();
  TextColumn get destinationAccountId => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get relatedTransactionId => text().nullable()();
  TextColumn get importBatchId => text().nullable()();
  TextColumn get externalRef => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get createdByUserId =>
      text().withDefault(const Constant('local-owner'))();
  TextColumn get createdAtUtc => text()();
  TextColumn get updatedAtUtc => text()();
  TextColumn get deletedAtUtc => text().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('local_only'))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'UNIQUE(id, profile_id)',
    'FOREIGN KEY(source_account_id, profile_id) REFERENCES financial_accounts(id, profile_id)',
    'FOREIGN KEY(destination_account_id, profile_id) REFERENCES financial_accounts(id, profile_id)',
    'FOREIGN KEY(category_id, profile_id) REFERENCES categories(id, profile_id)',
    'FOREIGN KEY(related_transaction_id, profile_id) REFERENCES transactions(id, profile_id)',
    'CHECK(source_account_id IS NULL OR destination_account_id IS NULL OR source_account_id <> destination_account_id)',
    'CHECK(destination_amount_minor IS NULL OR destination_amount_minor > 0)',
  ];
}

class TransactionSplits extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get transactionId => text()();
  TextColumn get categoryId => text()();
  IntColumn get amountMinor =>
      integer().check(amountMinor.isBiggerThanValue(0))();
  IntColumn get baseAmountMinor =>
      integer().check(baseAmountMinor.isBiggerThanValue(0))();
  TextColumn get memo => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'UNIQUE(id, profile_id)',
    'FOREIGN KEY(transaction_id, profile_id) REFERENCES transactions(id, profile_id)',
    'FOREIGN KEY(category_id, profile_id) REFERENCES categories(id, profile_id)',
  ];
}

class JournalEntries extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get transactionId => text()();
  TextColumn get status =>
      text().check(status.isIn(const ['draft', 'posted', 'reversed']))();
  TextColumn get effectiveAtUtc => text()();
  TextColumn get createdAtUtc => text()();
  TextColumn get reversesJournalEntryId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'UNIQUE(id, profile_id)',
    'FOREIGN KEY(transaction_id, profile_id) REFERENCES transactions(id, profile_id)',
    'FOREIGN KEY(reverses_journal_entry_id, profile_id) REFERENCES journal_entries(id, profile_id)',
  ];
}

class LedgerPostings extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get journalEntryId => text()();
  TextColumn get ledgerAccountId => text()();
  TextColumn get side => text().check(side.isIn(const ['debit', 'credit']))();
  IntColumn get baseAmountMinor =>
      integer().check(baseAmountMinor.isBiggerThanValue(0))();
  TextColumn get currencyCode => text().references(Currencies, #code)();
  IntColumn get originalAmountMinor =>
      integer().check(originalAmountMinor.isBiggerThanValue(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'FOREIGN KEY(journal_entry_id, profile_id) REFERENCES journal_entries(id, profile_id)',
    'FOREIGN KEY(ledger_account_id, profile_id) REFERENCES ledger_accounts(id, profile_id)',
  ];
}

class Attachments extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get transactionId => text()();
  TextColumn get fileName => text()();
  TextColumn get mimeType => text()();
  IntColumn get byteSize => integer().check(byteSize.isBiggerThanValue(0))();
  TextColumn get sha256Hex => text()();
  TextColumn get localRelPath => text()();
  TextColumn get createdAtUtc => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'UNIQUE(id, profile_id)',
    'FOREIGN KEY(transaction_id, profile_id) REFERENCES transactions(id, profile_id)',
  ];
}
