import 'package:drift/drift.dart';

import 'core_tables.dart';
// ignore: unused_import
import 'ledger_tables.dart';

class Budgets extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get periodType => text().check(
    periodType.isIn(const [
      'weekly',
      'monthly',
      'quarterly',
      'yearly',
      'custom',
    ]),
  )();
  TextColumn get startDateUtc => text()();
  TextColumn get endDateUtc => text().nullable()();
  IntColumn get overallLimitMinor =>
      integer().check(overallLimitMinor.isBiggerThanValue(0))();
  TextColumn get currencyCode => text().references(Currencies, #code)();
  BoolColumn get rolloverEnabled =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get createdAtUtc => text()();
  TextColumn get updatedAtUtc => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('local_only'))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const ['UNIQUE(id, profile_id)'];
}

class BudgetCategories extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get budgetId => text()();
  TextColumn get categoryId => text()();
  IntColumn get limitMinor =>
      integer().check(limitMinor.isBiggerThanValue(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'UNIQUE(budget_id, category_id)',
    'FOREIGN KEY(budget_id, profile_id) REFERENCES budgets(id, profile_id)',
    'FOREIGN KEY(category_id, profile_id) REFERENCES categories(id, profile_id)',
  ];
}

class SavingsGoals extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  IntColumn get targetAmountMinor =>
      integer().check(targetAmountMinor.isBiggerThanValue(0))();
  TextColumn get currencyCode => text().references(Currencies, #code)();
  TextColumn get targetDateUtc => text().nullable()();
  TextColumn get fundingMode =>
      text().check(fundingMode.isIn(const ['allocated', 'account_transfer']))();
  TextColumn get linkedAccountId => text().nullable()();
  TextColumn get status =>
      text().check(status.isIn(const ['active', 'completed', 'archived']))();
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
    'FOREIGN KEY(linked_account_id, profile_id) REFERENCES financial_accounts(id, profile_id)',
  ];
}

class GoalContributions extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get goalId => text()();
  TextColumn get transactionId => text().nullable()();
  IntColumn get amountMinor =>
      integer().check(amountMinor.isBiggerThanValue(0))();
  TextColumn get contributionType =>
      text().check(contributionType.isIn(const ['deposit', 'withdrawal']))();
  TextColumn get contributedAtUtc => text()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'UNIQUE(id, profile_id)',
    'FOREIGN KEY(goal_id, profile_id) REFERENCES savings_goals(id, profile_id)',
    'FOREIGN KEY(transaction_id, profile_id) REFERENCES transactions(id, profile_id)',
  ];
}

class RecurringRules extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get transactionType => text().check(
    transactionType.isIn(const ['income', 'expense', 'transfer']),
  )();
  IntColumn get amountMinor =>
      integer().check(amountMinor.isBiggerThanValue(0))();
  TextColumn get currencyCode => text().references(Currencies, #code)();
  TextColumn get sourceAccountId => text().nullable()();
  TextColumn get destinationAccountId => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get cadence => text().check(
    cadence.isIn(const ['daily', 'weekly', 'monthly', 'yearly']),
  )();
  IntColumn get intervalCount => integer().withDefault(const Constant(1))();
  TextColumn get nextDueAtUtc => text()();
  TextColumn get endAtUtc => text().nullable()();
  BoolColumn get autoCreateDraft =>
      boolean().withDefault(const Constant(true))();
  TextColumn get status =>
      text().check(status.isIn(const ['active', 'paused', 'completed']))();
  TextColumn get lastGeneratedOccurrenceKey => text().nullable()();
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
    'FOREIGN KEY(source_account_id, profile_id) REFERENCES financial_accounts(id, profile_id)',
    'FOREIGN KEY(destination_account_id, profile_id) REFERENCES financial_accounts(id, profile_id)',
    'FOREIGN KEY(category_id, profile_id) REFERENCES categories(id, profile_id)',
  ];
}

class Loans extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get loanAccountId => text()();
  TextColumn get fundingAccountId => text().nullable()();
  IntColumn get principalMinor =>
      integer().check(principalMinor.isBiggerThanValue(0))();
  TextColumn get currencyCode => text().references(Currencies, #code)();
  IntColumn get annualInterestRateBps =>
      integer().check(annualInterestRateBps.isBiggerOrEqualValue(0))();
  IntColumn get termMonths =>
      integer().check(termMonths.isBiggerThanValue(0))();
  TextColumn get interestMethod => text()
      .withDefault(const Constant('reducing_balance'))
      .check(interestMethod.isIn(const ['reducing_balance', 'flat']))();
  TextColumn get startDateUtc => text()();
  TextColumn get status => text()
      .withDefault(const Constant('active'))
      .check(status.isIn(const ['active', 'paid_off', 'archived']))();
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
    'FOREIGN KEY(loan_account_id, profile_id) REFERENCES financial_accounts(id, profile_id)',
    'FOREIGN KEY(funding_account_id, profile_id) REFERENCES financial_accounts(id, profile_id)',
  ];
}

class LoanInstallments extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get loanId => text()();
  IntColumn get installmentNumber =>
      integer().check(installmentNumber.isBiggerThanValue(0))();
  TextColumn get dueDateUtc => text()();
  IntColumn get principalDueMinor =>
      integer().check(principalDueMinor.isBiggerOrEqualValue(0))();
  IntColumn get interestDueMinor =>
      integer().check(interestDueMinor.isBiggerOrEqualValue(0))();
  IntColumn get feeDueMinor => integer().withDefault(const Constant(0))();
  TextColumn get status => text()
      .withDefault(const Constant('scheduled'))
      .check(status.isIn(const ['scheduled', 'paid', 'overdue', 'skipped']))();
  TextColumn get paymentTransactionId => text().nullable()();
  TextColumn get paidAtUtc => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'UNIQUE(loan_id, installment_number)',
    'FOREIGN KEY(loan_id, profile_id) REFERENCES loans(id, profile_id)',
    'FOREIGN KEY(payment_transaction_id, profile_id) REFERENCES transactions(id, profile_id)',
  ];
}
