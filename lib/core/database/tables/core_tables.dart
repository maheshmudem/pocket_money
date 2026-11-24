import 'package:drift/drift.dart';

class Profiles extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get profileType => text().check(
    profileType.isIn(const ['personal', 'family', 'business']),
  )();
  TextColumn get baseCurrencyCode => text().withLength(min: 3, max: 3)();
  TextColumn get timezone =>
      text().withDefault(const Constant('Asia/Kolkata'))();
  BoolColumn get editorsCanPost =>
      boolean().withDefault(const Constant(true))();
  TextColumn get createdAtUtc => text()();
  TextColumn get updatedAtUtc => text()();
  TextColumn get archivedAtUtc => text().nullable()();
  TextColumn get deletedAtUtc => text().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get syncStatus => text()
      .withDefault(const Constant('local_only'))
      .check(
        syncStatus.isIn(const [
          'local_only',
          'pending',
          'syncing',
          'synced',
          'retryable_error',
          'permanent_error',
          'conflict',
        ]),
      )();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'UNIQUE(id, base_currency_code)',
  ];
}

class ProfileMemberships extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get userId => text()();
  TextColumn get displayName => text().withDefault(const Constant('Owner'))();
  TextColumn get email => text().nullable()();
  TextColumn get role =>
      text().check(role.isIn(const ['owner', 'admin', 'editor', 'viewer']))();
  TextColumn get membershipStatus => text().check(
    membershipStatus.isIn(const ['active', 'invited', 'revoked']),
  )();
  TextColumn get createdAtUtc => text()();
  TextColumn get updatedAtUtc => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'UNIQUE(profile_id, user_id)',
    'UNIQUE(id, profile_id)',
  ];
}

class ProfileCurrencyHistory extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get previousCurrencyCode => text().references(Currencies, #code)();
  TextColumn get newCurrencyCode => text().references(Currencies, #code)();
  TextColumn get effectiveAtUtc => text()();
  TextColumn get changedByUserId => text()();
  TextColumn get note => text().nullable()();
  TextColumn get createdAtUtc => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AppSettings extends Table {
  TextColumn get settingKey => text()();
  TextColumn get settingValue => text()();
  TextColumn get updatedAtUtc => text()();

  @override
  Set<Column<Object>> get primaryKey => {settingKey};
}

class Currencies extends Table {
  TextColumn get code => text().withLength(min: 3, max: 3)();
  TextColumn get name => text()();
  IntColumn get minorUnit => integer().check(minorUnit.isBetweenValues(0, 4))();
  TextColumn get symbol => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {code};
}

class ExchangeRates extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().nullable().references(Profiles, #id)();
  TextColumn get baseCurrencyCode => text().references(Currencies, #code)();
  TextColumn get quoteCurrencyCode => text().references(Currencies, #code)();
  IntColumn get rateScaled =>
      integer().check(rateScaled.isBiggerThanValue(0))();
  IntColumn get rateScale => integer().check(rateScale.isBiggerThanValue(0))();
  TextColumn get source => text()();
  TextColumn get effectiveAtUtc => text()();
  TextColumn get retrievedAtUtc => text()();
  TextColumn get expiresAtUtc => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class LedgerAccounts extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get name => text()();
  TextColumn get accountType => text().check(
    accountType.isIn(const [
      'asset',
      'liability',
      'equity',
      'income',
      'expense',
    ]),
  )();
  TextColumn get normalBalance =>
      text().check(normalBalance.isIn(const ['debit', 'credit']))();
  TextColumn get systemCode => text().nullable()();
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
  TextColumn get createdAtUtc => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const ['UNIQUE(id, profile_id)'];
}

class FinancialAccounts extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get ledgerAccountId => text()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get accountType => text().check(
    accountType.isIn(const [
      'cash',
      'bank',
      'wallet',
      'credit_card',
      'loan',
      'investment',
      'other',
    ]),
  )();
  TextColumn get currencyCode => text().references(Currencies, #code)();
  TextColumn get institutionLabel => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get createdAtUtc => text()();
  TextColumn get updatedAtUtc => text()();
  TextColumn get archivedAtUtc => text().nullable()();
  TextColumn get deletedAtUtc => text().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('local_only'))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'UNIQUE(id, profile_id)',
    'UNIQUE(ledger_account_id, profile_id)',
    'FOREIGN KEY(ledger_account_id, profile_id) REFERENCES ledger_accounts(id, profile_id)',
  ];
}

class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get ledgerAccountId => text()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get categoryType => text().check(
    categoryType.isIn(const ['income', 'expense', 'transfer', 'other']),
  )();
  TextColumn get parentCategoryId => text().nullable()();
  TextColumn get iconKey => text().withDefault(const Constant('category'))();
  TextColumn get colorToken => text().withDefault(const Constant('primary'))();
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get createdAtUtc => text()();
  TextColumn get updatedAtUtc => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('local_only'))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'UNIQUE(id, profile_id)',
    'FOREIGN KEY(ledger_account_id, profile_id) REFERENCES ledger_accounts(id, profile_id)',
    'FOREIGN KEY(parent_category_id, profile_id) REFERENCES categories(id, profile_id)',
  ];
}
