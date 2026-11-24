import 'package:equatable/equatable.dart';

import '../../../../core/financial_engine/double_entry_engine.dart';
import '../../../../core/financial_engine/money.dart';
import '../../../../core/utilities/id_generator.dart';

enum FinancialAccountType {
  cash('cash', 'Cash', LedgerAccountType.asset),
  bank('bank', 'Bank Account', LedgerAccountType.asset),
  wallet('wallet', 'Digital Wallet', LedgerAccountType.asset),
  creditCard('credit_card', 'Credit Card', LedgerAccountType.liability),
  loan('loan', 'Loan', LedgerAccountType.liability),
  investment('investment', 'Investment', LedgerAccountType.asset),
  other('other', 'Other Asset', LedgerAccountType.asset);

  const FinancialAccountType(this.wireValue, this.label, this.ledgerType);

  final String wireValue;
  final String label;
  final LedgerAccountType ledgerType;

  bool get isLiability => ledgerType == LedgerAccountType.liability;

  static FinancialAccountType fromWire(String raw) => switch (raw) {
    'cash' => FinancialAccountType.cash,
    'bank' => FinancialAccountType.bank,
    'wallet' => FinancialAccountType.wallet,
    'credit_card' => FinancialAccountType.creditCard,
    'loan' => FinancialAccountType.loan,
    'investment' => FinancialAccountType.investment,
    _ => FinancialAccountType.other,
  };
}

/// Financial account whose [balance] and [baseBalance] are strictly derived
/// from posted double-entry ledger postings (zero shadow balances).
final class FinancialAccountEntity extends Equatable {
  const FinancialAccountEntity({
    required this.id,
    required this.profileId,
    required this.ledgerAccountId,
    required this.name,
    required this.accountType,
    required this.currencyCode,
    required this.balance,
    required this.baseBalance,
    required this.isActive,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.version,
    required this.syncStatus,
    this.institutionLabel,
    this.archivedAtUtc,
  });

  final String id;
  final ProfileId profileId;
  final String ledgerAccountId;
  final String name;
  final FinancialAccountType accountType;
  final String currencyCode;
  final Money balance;
  final Money baseBalance;
  final String? institutionLabel;
  final bool isActive;
  final String createdAtUtc;
  final String updatedAtUtc;
  final String? archivedAtUtc;
  final int version;
  final String syncStatus;

  bool get isLiability => accountType.isLiability;
  bool get isArchived => !isActive || archivedAtUtc != null;

  @override
  List<Object?> get props => [
    id,
    profileId,
    ledgerAccountId,
    name,
    accountType,
    currencyCode,
    balance,
    baseBalance,
    institutionLabel,
    isActive,
    createdAtUtc,
    updatedAtUtc,
    archivedAtUtc,
    version,
    syncStatus,
  ];
}
