import 'package:equatable/equatable.dart';

import '../../../../core/financial_engine/double_entry_engine.dart';
import '../../../../core/financial_engine/fx_rate.dart';
import '../../../../core/financial_engine/money.dart';
import '../../../../core/utilities/id_generator.dart';

enum TransactionType {
  openingBalance('opening_balance', 'Opening Balance'),
  income('income', 'Income'),
  expense('expense', 'Expense'),
  transfer('transfer', 'Transfer'),
  adjustment('adjustment', 'Adjustment'),
  refund('refund', 'Refund');

  const TransactionType(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static TransactionType fromWire(String raw) => switch (raw) {
    'opening_balance' => TransactionType.openingBalance,
    'income' => TransactionType.income,
    'expense' => TransactionType.expense,
    'transfer' => TransactionType.transfer,
    'adjustment' => TransactionType.adjustment,
    'refund' => TransactionType.refund,
    _ => throw ArgumentError('Unknown transaction type: $raw'),
  };
}

enum TransactionStatus {
  draft('draft', 'Draft'),
  posted('posted', 'Posted'),
  voided('voided', 'Voided');

  const TransactionStatus(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static TransactionStatus fromWire(String raw) => switch (raw) {
    'draft' => TransactionStatus.draft,
    'posted' => TransactionStatus.posted,
    'voided' => TransactionStatus.voided,
    _ => TransactionStatus.draft,
  };
}

final class TransactionSplitEntity extends Equatable {
  const TransactionSplitEntity({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    required this.amountMinor,
    required this.baseAmountMinor,
    this.memo,
  });

  final String id;
  final String categoryId;
  final String categoryName;
  final int amountMinor;
  final int baseAmountMinor;
  final String? memo;

  @override
  List<Object?> get props => [
    id,
    categoryId,
    categoryName,
    amountMinor,
    baseAmountMinor,
    memo,
  ];
}

final class PostingDetail extends Equatable {
  const PostingDetail({
    required this.id,
    required this.ledgerAccountId,
    required this.ledgerAccountName,
    required this.side,
    required this.baseAmountMinor,
    required this.currencyCode,
    required this.originalAmountMinor,
  });

  final String id;
  final String ledgerAccountId;
  final String ledgerAccountName;
  final PostingSide side;
  final int baseAmountMinor;
  final String currencyCode;
  final int originalAmountMinor;

  @override
  List<Object?> get props => [
    id,
    ledgerAccountId,
    ledgerAccountName,
    side,
    baseAmountMinor,
    currencyCode,
    originalAmountMinor,
  ];
}

final class TransactionEntity extends Equatable {
  const TransactionEntity({
    required this.id,
    required this.profileId,
    required this.type,
    required this.status,
    required this.transactionDateUtc,
    required this.amount,
    required this.baseAmount,
    required this.fxRateScaled,
    required this.fxRateScale,
    required this.fxRateSource,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.version,
    required this.syncStatus,
    this.destinationAmount,
    this.sourceAccountId,
    this.sourceAccountName,
    this.destinationAccountId,
    this.destinationAccountName,
    this.categoryId,
    this.categoryName,
    this.relatedTransactionId,
    this.externalRef,
    this.description,
    this.splits = const [],
    this.postings = const [],
    this.journalStatus,
    this.runningBalanceBefore,
    this.runningBalanceAfter,
  });

  final String id;
  final ProfileId profileId;
  final TransactionType type;
  final TransactionStatus status;
  final String transactionDateUtc;
  final Money amount;
  final Money? destinationAmount;
  final Money baseAmount;
  final int fxRateScaled;
  final int fxRateScale;
  final String fxRateSource;
  final String? sourceAccountId;
  final String? sourceAccountName;
  final String? destinationAccountId;
  final String? destinationAccountName;
  final String? categoryId;
  final String? categoryName;
  final String? relatedTransactionId;
  final String? externalRef;
  final String? description;
  final String createdAtUtc;
  final String updatedAtUtc;
  final int version;
  final String syncStatus;
  final List<TransactionSplitEntity> splits;
  final List<PostingDetail> postings;
  final String? journalStatus;

  /// Chronological account balance immediately before this posted transaction.
  final Money? runningBalanceBefore;

  /// Chronological account balance immediately after this posted transaction.
  final Money? runningBalanceAfter;

  bool get isReversed => journalStatus == 'reversed';

  @override
  List<Object?> get props => [
    id,
    profileId,
    type,
    status,
    transactionDateUtc,
    amount,
    destinationAmount,
    baseAmount,
    fxRateScaled,
    fxRateScale,
    fxRateSource,
    sourceAccountId,
    sourceAccountName,
    destinationAccountId,
    destinationAccountName,
    categoryId,
    categoryName,
    relatedTransactionId,
    externalRef,
    description,
    createdAtUtc,
    updatedAtUtc,
    version,
    syncStatus,
    splits,
    postings,
    journalStatus,
    runningBalanceBefore,
    runningBalanceAfter,
  ];
}

final class SplitCommandLine extends Equatable {
  const SplitCommandLine({
    required this.categoryId,
    required this.amountMinor,
    this.memo,
  });

  final String categoryId;
  final int amountMinor;
  final String? memo;

  @override
  List<Object?> get props => [categoryId, amountMinor, memo];
}

final class CreateTransactionCommand extends Equatable {
  const CreateTransactionCommand({
    required this.type,
    required this.amountMinor,
    required this.currencyCode,
    required this.transactionDateUtc,
    this.clientTransactionId,
    this.idempotencyKey,
    this.sourceAccountId,
    this.destinationAccountId,
    this.destinationAmountMinor,
    this.destinationCurrencyCode,
    this.categoryId,
    this.relatedTransactionId,
    this.importBatchId,
    this.externalRef,
    this.description,
    this.fxRate,
    this.destinationFxRate,
    this.splits = const [],
    this.saveAsDraft = false,
    this.createdByUserId = 'local-owner',
    this.queueSync = false,
  });

  final String? clientTransactionId;
  final String? idempotencyKey;
  final TransactionType type;
  final int amountMinor;
  final String currencyCode;
  final int? destinationAmountMinor;
  final String? destinationCurrencyCode;
  final String transactionDateUtc;
  final String? sourceAccountId;
  final String? destinationAccountId;
  final String? categoryId;
  final String? relatedTransactionId;
  final String? importBatchId;
  final String? externalRef;
  final String? description;
  final FxRate? fxRate;
  final FxRate? destinationFxRate;
  final List<SplitCommandLine> splits;
  final bool saveAsDraft;
  final String createdByUserId;
  final bool queueSync;

  @override
  List<Object?> get props => [
    clientTransactionId,
    idempotencyKey,
    type,
    amountMinor,
    currencyCode,
    destinationAmountMinor,
    destinationCurrencyCode,
    transactionDateUtc,
    sourceAccountId,
    destinationAccountId,
    categoryId,
    relatedTransactionId,
    importBatchId,
    externalRef,
    description,
    fxRate,
    destinationFxRate,
    splits,
    saveAsDraft,
    createdByUserId,
    queueSync,
  ];
}

final class TransactionFilter extends Equatable {
  const TransactionFilter({
    this.searchQuery,
    this.accountId,
    this.categoryId,
    this.type,
    this.status,
    this.fromUtc,
    this.toUtc,
  });

  final String? searchQuery;
  final String? accountId;
  final String? categoryId;
  final TransactionType? type;
  final TransactionStatus? status;
  final String? fromUtc;
  final String? toUtc;

  bool get hasActiveFilters =>
      (searchQuery != null && searchQuery!.trim().isNotEmpty) ||
      accountId != null ||
      categoryId != null ||
      type != null ||
      status != null ||
      fromUtc != null ||
      toUtc != null;

  @override
  List<Object?> get props => [
    searchQuery,
    accountId,
    categoryId,
    type,
    status,
    fromUtc,
    toUtc,
  ];
}

final class PaginatedTransactions extends Equatable {
  const PaginatedTransactions({
    required this.items,
    required this.totalCount,
    required this.hasMore,
  });

  final List<TransactionEntity> items;
  final int totalCount;
  final bool hasMore;

  @override
  List<Object?> get props => [items, totalCount, hasMore];
}

/// Output of the automated double-entry ledger reconciliation self-check.
final class LedgerReconciliationReport extends Equatable {
  const LedgerReconciliationReport({
    required this.profileId,
    required this.checkedAtUtc,
    required this.postedJournalCount,
    required this.unbalancedJournalIds,
    required this.orphanPostingCount,
    required this.totalDebitsMinor,
    required this.totalCreditsMinor,
  });

  final ProfileId profileId;
  final String checkedAtUtc;
  final int postedJournalCount;
  final List<String> unbalancedJournalIds;
  final int orphanPostingCount;
  final int totalDebitsMinor;
  final int totalCreditsMinor;

  bool get isHealthy =>
      unbalancedJournalIds.isEmpty &&
      orphanPostingCount == 0 &&
      totalDebitsMinor == totalCreditsMinor;

  @override
  List<Object?> get props => [
    profileId,
    checkedAtUtc,
    postedJournalCount,
    unbalancedJournalIds,
    orphanPostingCount,
    totalDebitsMinor,
    totalCreditsMinor,
  ];
}
