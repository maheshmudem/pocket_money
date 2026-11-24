import 'package:equatable/equatable.dart';

import '../errors/failures.dart';
import '../utilities/id_generator.dart';
import 'currency.dart';
import 'fx_rate.dart';
import 'money.dart';

enum LedgerAccountType {
  asset('asset', PostingSide.debit),
  liability('liability', PostingSide.credit),
  equity('equity', PostingSide.credit),
  income('income', PostingSide.credit),
  expense('expense', PostingSide.debit);

  const LedgerAccountType(this.wireValue, this.normalBalance);
  final String wireValue;
  final PostingSide normalBalance;

  static LedgerAccountType fromWire(String raw) => switch (raw) {
    'asset' => LedgerAccountType.asset,
    'liability' => LedgerAccountType.liability,
    'equity' => LedgerAccountType.equity,
    'income' => LedgerAccountType.income,
    'expense' => LedgerAccountType.expense,
    _ => throw ArgumentError('Unknown ledger account type: $raw'),
  };
}

enum PostingSide {
  debit('debit'),
  credit('credit');

  const PostingSide(this.wireValue);
  final String wireValue;

  PostingSide get opposite =>
      this == PostingSide.debit ? PostingSide.credit : PostingSide.debit;

  static PostingSide fromWire(String raw) => switch (raw) {
    'debit' => PostingSide.debit,
    'credit' => PostingSide.credit,
    _ => throw ArgumentError('Unknown posting side: $raw'),
  };
}

final class LedgerPostingSpec extends Equatable {
  const LedgerPostingSpec({
    required this.ledgerAccountId,
    required this.side,
    required this.baseAmountMinor,
    required this.currencyCode,
    required this.originalAmountMinor,
  });

  final String ledgerAccountId;
  final PostingSide side;
  final int baseAmountMinor;
  final String currencyCode;
  final int originalAmountMinor;

  @override
  List<Object?> get props => [
    ledgerAccountId,
    side,
    baseAmountMinor,
    currencyCode,
    originalAmountMinor,
  ];
}

final class SplitLineInput extends Equatable {
  const SplitLineInput({
    required this.categoryId,
    required this.categoryLedgerAccountId,
    required this.amountMinor,
    this.memo,
  });

  final String categoryId;
  final String categoryLedgerAccountId;
  final int amountMinor;
  final String? memo;

  @override
  List<Object?> get props => [
    categoryId,
    categoryLedgerAccountId,
    amountMinor,
    memo,
  ];
}

final class ResolvedSplitLine extends Equatable {
  const ResolvedSplitLine({
    required this.categoryId,
    required this.categoryLedgerAccountId,
    required this.amountMinor,
    required this.baseAmountMinor,
    this.memo,
  });

  final String categoryId;
  final String categoryLedgerAccountId;
  final int amountMinor;
  final int baseAmountMinor;
  final String? memo;

  @override
  List<Object?> get props => [
    categoryId,
    categoryLedgerAccountId,
    amountMinor,
    baseAmountMinor,
    memo,
  ];
}

final class GeneratedJournal extends Equatable {
  const GeneratedJournal({
    required this.profileId,
    required this.baseCurrencyCode,
    required this.baseAmountMinor,
    required this.appliedFxRate,
    required this.postings,
    this.resolvedSplits = const [],
    this.reversesJournalEntryId,
  });

  final ProfileId profileId;
  final String baseCurrencyCode;
  final int baseAmountMinor;
  final FxRate appliedFxRate;
  final List<LedgerPostingSpec> postings;
  final List<ResolvedSplitLine> resolvedSplits;
  final String? reversesJournalEntryId;

  int get totalDebitsMinor => postings
      .where((p) => p.side == PostingSide.debit)
      .fold(0, (acc, p) => acc + p.baseAmountMinor);

  int get totalCreditsMinor => postings
      .where((p) => p.side == PostingSide.credit)
      .fold(0, (acc, p) => acc + p.baseAmountMinor);

  bool get isBalanced =>
      postings.length >= 2 &&
      totalDebitsMinor > 0 &&
      totalDebitsMinor == totalCreditsMinor;

  @override
  List<Object?> get props => [
    profileId,
    baseCurrencyCode,
    baseAmountMinor,
    appliedFxRate,
    postings,
    resolvedSplits,
    reversesJournalEntryId,
  ];
}

/// Authoritative Pure-Dart Double-Entry Ledger Engine (`DATA-003`, `ADR-007`).
/// Every transaction effect, balance derivation, transfer, split, refund,
/// loan payment, and reversal flows through this deterministic domain service.
abstract final class DoubleEntryEngine {
  /// Validates any candidate list of postings before persistence (`TC-FIN-008`).
  static Result<void> validateBalancedPostings(
    List<LedgerPostingSpec> postings,
  ) {
    if (postings.length < 2) {
      return const FailureResult(
        LedgerInvariantFailure(
          message:
              'A posted journal entry requires at least two posting lines.',
        ),
      );
    }

    var debits = 0;
    var credits = 0;
    for (final p in postings) {
      if (p.baseAmountMinor <= 0 || p.originalAmountMinor <= 0) {
        return const FailureResult(
          LedgerInvariantFailure(
            message:
                'All posting amounts must be strictly positive minor units.',
          ),
        );
      }
      if (p.side == PostingSide.debit) {
        debits += p.baseAmountMinor;
      } else {
        credits += p.baseAmountMinor;
      }
    }

    if (debits != credits) {
      return FailureResult(
        LedgerInvariantFailure(
          message:
              'Unbalanced journal entry: debits ($debits) != credits ($credits).',
        ),
      );
    }
    return const Success(null);
  }

  /// Opening balance journal (`FR-005`).
  /// Positive Asset -> Debit Asset / Credit Opening Equity.
  /// Positive Liability (e.g., existing credit card balance) -> Debit Opening Equity / Credit Liability.
  static Result<GeneratedJournal> buildOpeningBalance({
    required ProfileId profileId,
    required LedgerAccountType accountLedgerType,
    required String accountLedgerId,
    required String openingEquityLedgerId,
    required Money openingAmount,
    required CurrencySpec accountCurrency,
    required CurrencySpec baseCurrency,
    required FxRate? fxRate,
    required String effectiveAtUtc,
  }) {
    if (!openingAmount.isPositive) {
      return const FailureResult(
        ValidationFailure(message: 'Opening balance amount must be positive.'),
      );
    }
    if (accountLedgerType != LedgerAccountType.asset &&
        accountLedgerType != LedgerAccountType.liability) {
      return const FailureResult(
        ValidationFailure(
          message:
              'Opening balances apply only to asset or liability accounts.',
        ),
      );
    }

    final fxRes = CurrencyConverter.convert(
      original: openingAmount,
      originalSpec: accountCurrency,
      targetSpec: baseCurrency,
      fxRate: fxRate,
      fallbackEffectiveAtUtc: effectiveAtUtc,
    );
    if (fxRes.isFailure) return FailureResult(fxRes.failureOrNull!);
    final conv = fxRes.valueOrNull!;

    final isAsset = accountLedgerType == LedgerAccountType.asset;
    final postings = [
      LedgerPostingSpec(
        ledgerAccountId: accountLedgerId,
        side: isAsset ? PostingSide.debit : PostingSide.credit,
        baseAmountMinor: conv.convertedAmount.amountMinor,
        currencyCode: openingAmount.currencyCode,
        originalAmountMinor: openingAmount.amountMinor,
      ),
      LedgerPostingSpec(
        ledgerAccountId: openingEquityLedgerId,
        side: isAsset ? PostingSide.credit : PostingSide.debit,
        baseAmountMinor: conv.convertedAmount.amountMinor,
        currencyCode: baseCurrency.code,
        originalAmountMinor: conv.convertedAmount.amountMinor,
      ),
    ];

    return _finalize(
      profileId: profileId,
      baseCurrencyCode: baseCurrency.code,
      baseAmountMinor: conv.convertedAmount.amountMinor,
      fxRate: conv.appliedRate,
      postings: postings,
    );
  }

  /// Income journal (`TC-FIN-002`): Debit Destination Account / Credit Income Ledger.
  static Result<GeneratedJournal> buildIncome({
    required ProfileId profileId,
    required String destinationLedgerAccountId,
    required String incomeCategoryLedgerAccountId,
    required Money amount,
    required CurrencySpec amountCurrency,
    required CurrencySpec baseCurrency,
    required FxRate? fxRate,
    required String effectiveAtUtc,
  }) {
    if (!amount.isPositive) {
      return const FailureResult(
        ValidationFailure(message: 'Income amount must be greater than zero.'),
      );
    }

    final fxRes = CurrencyConverter.convert(
      original: amount,
      originalSpec: amountCurrency,
      targetSpec: baseCurrency,
      fxRate: fxRate,
      fallbackEffectiveAtUtc: effectiveAtUtc,
    );
    if (fxRes.isFailure) return FailureResult(fxRes.failureOrNull!);
    final conv = fxRes.valueOrNull!;

    final postings = [
      LedgerPostingSpec(
        ledgerAccountId: destinationLedgerAccountId,
        side: PostingSide.debit,
        baseAmountMinor: conv.convertedAmount.amountMinor,
        currencyCode: amount.currencyCode,
        originalAmountMinor: amount.amountMinor,
      ),
      LedgerPostingSpec(
        ledgerAccountId: incomeCategoryLedgerAccountId,
        side: PostingSide.credit,
        baseAmountMinor: conv.convertedAmount.amountMinor,
        currencyCode: amount.currencyCode,
        originalAmountMinor: amount.amountMinor,
      ),
    ];

    return _finalize(
      profileId: profileId,
      baseCurrencyCode: baseCurrency.code,
      baseAmountMinor: conv.convertedAmount.amountMinor,
      fxRate: conv.appliedRate,
      postings: postings,
    );
  }

  /// Expense journal (`TC-FIN-001`, `TC-FIN-004`, `TC-FIN-006`, `TC-FIN-007`).
  /// Supports both single-category expenses and multi-category splits with exact reconciliation.
  static Result<GeneratedJournal> buildExpense({
    required ProfileId profileId,
    required String sourceLedgerAccountId,
    required String? categoryLedgerAccountId,
    required Money amount,
    required CurrencySpec amountCurrency,
    required CurrencySpec baseCurrency,
    required FxRate? fxRate,
    required String effectiveAtUtc,
    List<SplitLineInput> splits = const [],
  }) {
    if (!amount.isPositive) {
      return const FailureResult(
        ValidationFailure(message: 'Expense amount must be greater than zero.'),
      );
    }

    final fxRes = CurrencyConverter.convert(
      original: amount,
      originalSpec: amountCurrency,
      targetSpec: baseCurrency,
      fxRate: fxRate,
      fallbackEffectiveAtUtc: effectiveAtUtc,
    );
    if (fxRes.isFailure) return FailureResult(fxRes.failureOrNull!);
    final conv = fxRes.valueOrNull!;

    final postings = <LedgerPostingSpec>[];
    final resolvedSplits = <ResolvedSplitLine>[];

    if (splits.isNotEmpty) {
      var splitOrigSum = 0;
      for (final split in splits) {
        if (split.amountMinor <= 0) {
          return const FailureResult(
            ValidationFailure(message: 'Every split line must be positive.'),
          );
        }
        splitOrigSum += split.amountMinor;
      }
      // TC-FIN-006 & TC-FIN-007: Split amounts must equal parent exactly.
      if (splitOrigSum != amount.amountMinor) {
        return FailureResult(
          ValidationFailure(
            code: 'SPLIT_MISMATCH',
            message:
                'Split total ($splitOrigSum) does not equal parent transaction amount (${amount.amountMinor}).',
          ),
        );
      }

      // Allocate converted base minor units proportionally with exact remainder reconciliation
      // on the largest split so SUM(split.baseAmountMinor) == parentBaseAmountMinor.
      var allocatedBase = 0;
      final splitBases = <int>[];
      var largestIdx = 0;
      for (var i = 0; i < splits.length; i++) {
        if (splits[i].amountMinor > splits[largestIdx].amountMinor) {
          largestIdx = i;
        }
        final converted = CurrencyConverter.divideAndRound(
          numerator:
              BigInt.from(splits[i].amountMinor) *
              BigInt.from(conv.convertedAmount.amountMinor),
          denominator: BigInt.from(amount.amountMinor),
          mode: conv.appliedRate.roundingMode,
        );
        final lineBase = converted > 0 ? converted : 1;
        splitBases.add(lineBase);
        allocatedBase += lineBase;
      }
      final drift = conv.convertedAmount.amountMinor - allocatedBase;
      if (drift != 0) {
        final adjusted = splitBases[largestIdx] + drift;
        if (adjusted <= 0) {
          return const FailureResult(
            LedgerInvariantFailure(
              message:
                  'Split base-currency allocation produced non-positive line.',
            ),
          );
        }
        splitBases[largestIdx] = adjusted;
      }

      for (var i = 0; i < splits.length; i++) {
        final split = splits[i];
        final lineBase = splitBases[i];
        resolvedSplits.add(
          ResolvedSplitLine(
            categoryId: split.categoryId,
            categoryLedgerAccountId: split.categoryLedgerAccountId,
            amountMinor: split.amountMinor,
            baseAmountMinor: lineBase,
            memo: split.memo,
          ),
        );
        postings.add(
          LedgerPostingSpec(
            ledgerAccountId: split.categoryLedgerAccountId,
            side: PostingSide.debit,
            baseAmountMinor: lineBase,
            currencyCode: amount.currencyCode,
            originalAmountMinor: split.amountMinor,
          ),
        );
      }
    } else {
      if (categoryLedgerAccountId == null || categoryLedgerAccountId.isEmpty) {
        return const FailureResult(
          ValidationFailure(message: 'Expense category is required.'),
        );
      }
      postings.add(
        LedgerPostingSpec(
          ledgerAccountId: categoryLedgerAccountId,
          side: PostingSide.debit,
          baseAmountMinor: conv.convertedAmount.amountMinor,
          currencyCode: amount.currencyCode,
          originalAmountMinor: amount.amountMinor,
        ),
      );
    }

    // Credit Source Account (Cash/Bank Asset decreases, or Credit Card Liability increases).
    postings.add(
      LedgerPostingSpec(
        ledgerAccountId: sourceLedgerAccountId,
        side: PostingSide.credit,
        baseAmountMinor: conv.convertedAmount.amountMinor,
        currencyCode: amount.currencyCode,
        originalAmountMinor: amount.amountMinor,
      ),
    );

    return _finalize(
      profileId: profileId,
      baseCurrencyCode: baseCurrency.code,
      baseAmountMinor: conv.convertedAmount.amountMinor,
      fxRate: conv.appliedRate,
      postings: postings,
      resolvedSplits: resolvedSplits,
    );
  }

  /// Own-account transfer & credit card repayment (`TC-FIN-003`, `TC-FIN-005`, `TC-FIN-016`).
  /// Never touches income or expense categories; handles cross-currency FX variance explicitly.
  static Result<GeneratedJournal> buildTransfer({
    required ProfileId profileId,
    required String sourceLedgerAccountId,
    required String destinationLedgerAccountId,
    required Money sourceAmount,
    required CurrencySpec sourceCurrency,
    required Money destinationAmount,
    required CurrencySpec destinationCurrency,
    required CurrencySpec baseCurrency,
    required FxRate? sourceToBaseRate,
    required FxRate? destinationToBaseRate,
    required String? fxVarianceLedgerAccountId,
    required String effectiveAtUtc,
  }) {
    if (sourceLedgerAccountId == destinationLedgerAccountId) {
      return const FailureResult(
        ValidationFailure(
          message: 'Source and destination accounts must be different.',
        ),
      );
    }
    if (!sourceAmount.isPositive || !destinationAmount.isPositive) {
      return const FailureResult(
        ValidationFailure(message: 'Transfer amounts must be positive.'),
      );
    }

    final srcConvRes = CurrencyConverter.convert(
      original: sourceAmount,
      originalSpec: sourceCurrency,
      targetSpec: baseCurrency,
      fxRate: sourceToBaseRate,
      fallbackEffectiveAtUtc: effectiveAtUtc,
    );
    if (srcConvRes.isFailure) return FailureResult(srcConvRes.failureOrNull!);
    final srcConv = srcConvRes.valueOrNull!;

    final dstConvRes = CurrencyConverter.convert(
      original: destinationAmount,
      originalSpec: destinationCurrency,
      targetSpec: baseCurrency,
      fxRate: destinationToBaseRate,
      fallbackEffectiveAtUtc: effectiveAtUtc,
    );
    if (dstConvRes.isFailure) return FailureResult(dstConvRes.failureOrNull!);
    final dstConv = dstConvRes.valueOrNull!;

    final srcBase = srcConv.convertedAmount.amountMinor;
    final dstBase = dstConv.convertedAmount.amountMinor;

    final postings = <LedgerPostingSpec>[
      LedgerPostingSpec(
        ledgerAccountId: destinationLedgerAccountId,
        side: PostingSide.debit,
        baseAmountMinor: dstBase,
        currencyCode: destinationAmount.currencyCode,
        originalAmountMinor: destinationAmount.amountMinor,
      ),
      LedgerPostingSpec(
        ledgerAccountId: sourceLedgerAccountId,
        side: PostingSide.credit,
        baseAmountMinor: srcBase,
        currencyCode: sourceAmount.currencyCode,
        originalAmountMinor: sourceAmount.amountMinor,
      ),
    ];

    final fxDiff = dstBase - srcBase;
    if (fxDiff != 0) {
      if (fxVarianceLedgerAccountId == null ||
          fxVarianceLedgerAccountId.isEmpty) {
        return const FailureResult(
          LedgerInvariantFailure(
            message:
                'Cross-currency transfer FX variance requires an FX Gain/Loss ledger account.',
          ),
        );
      }
      // If dstBase > srcBase: FX gain (Credit FX Variance). If dstBase < srcBase: FX loss (Debit FX Variance).
      postings.add(
        LedgerPostingSpec(
          ledgerAccountId: fxVarianceLedgerAccountId,
          side: fxDiff > 0 ? PostingSide.credit : PostingSide.debit,
          baseAmountMinor: fxDiff.abs(),
          currencyCode: baseCurrency.code,
          originalAmountMinor: fxDiff.abs(),
        ),
      );
    }

    return _finalize(
      profileId: profileId,
      baseCurrencyCode: baseCurrency.code,
      baseAmountMinor: srcBase,
      fxRate: srcConv.appliedRate,
      postings: postings,
    );
  }

  /// Linked Refund (`TC-FIN-010`): Debit Destination Account / Credit Expense Category Ledger.
  /// Reduces net category spend while keeping the original expense immutable.
  static Result<GeneratedJournal> buildRefund({
    required ProfileId profileId,
    required String destinationLedgerAccountId,
    required String expenseCategoryLedgerAccountId,
    required Money refundAmount,
    required CurrencySpec amountCurrency,
    required CurrencySpec baseCurrency,
    required FxRate? fxRate,
    required String effectiveAtUtc,
  }) {
    if (!refundAmount.isPositive) {
      return const FailureResult(
        ValidationFailure(message: 'Refund amount must be positive.'),
      );
    }

    final fxRes = CurrencyConverter.convert(
      original: refundAmount,
      originalSpec: amountCurrency,
      targetSpec: baseCurrency,
      fxRate: fxRate,
      fallbackEffectiveAtUtc: effectiveAtUtc,
    );
    if (fxRes.isFailure) return FailureResult(fxRes.failureOrNull!);
    final conv = fxRes.valueOrNull!;

    final postings = [
      LedgerPostingSpec(
        ledgerAccountId: destinationLedgerAccountId,
        side: PostingSide.debit,
        baseAmountMinor: conv.convertedAmount.amountMinor,
        currencyCode: refundAmount.currencyCode,
        originalAmountMinor: refundAmount.amountMinor,
      ),
      LedgerPostingSpec(
        ledgerAccountId: expenseCategoryLedgerAccountId,
        side: PostingSide.credit,
        baseAmountMinor: conv.convertedAmount.amountMinor,
        currencyCode: refundAmount.currencyCode,
        originalAmountMinor: refundAmount.amountMinor,
      ),
    ];

    return _finalize(
      profileId: profileId,
      baseCurrencyCode: baseCurrency.code,
      baseAmountMinor: conv.convertedAmount.amountMinor,
      fxRate: conv.appliedRate,
      postings: postings,
    );
  }

  /// Compensating Reversal Journal (`TC-FIN-011`): strictly mirrors every posting
  /// on the opposite side without mutating the original posted journal.
  static Result<GeneratedJournal> buildReversal({
    required ProfileId profileId,
    required String originalJournalEntryId,
    required String baseCurrencyCode,
    required List<LedgerPostingSpec> originalPostings,
    required String effectiveAtUtc,
  }) {
    final reversed = originalPostings
        .map(
          (p) => LedgerPostingSpec(
            ledgerAccountId: p.ledgerAccountId,
            side: p.side.opposite,
            baseAmountMinor: p.baseAmountMinor,
            currencyCode: p.currencyCode,
            originalAmountMinor: p.originalAmountMinor,
          ),
        )
        .toList();

    final baseTotal = reversed
        .where((p) => p.side == PostingSide.debit)
        .fold(0, (acc, p) => acc + p.baseAmountMinor);

    return _finalize(
      profileId: profileId,
      baseCurrencyCode: baseCurrencyCode,
      baseAmountMinor: baseTotal,
      fxRate: FxRate.identity(baseCurrencyCode, effectiveAtUtc),
      postings: reversed,
      reversesJournalEntryId: originalJournalEntryId,
    );
  }

  /// Loan Installment Repayment (`FR-018`): splits Principal, Interest, and Fees cleanly.
  static Result<GeneratedJournal> buildLoanPayment({
    required ProfileId profileId,
    required String sourceBankLedgerAccountId,
    required String loanLiabilityLedgerAccountId,
    required String interestExpenseLedgerAccountId,
    required String? feeExpenseLedgerAccountId,
    required int principalMinor,
    required int interestMinor,
    required int feeMinor,
    required CurrencySpec currency,
    required CurrencySpec baseCurrency,
    required FxRate? fxRate,
    required String effectiveAtUtc,
  }) {
    final totalMinor = principalMinor + interestMinor + feeMinor;
    if (totalMinor <= 0 ||
        principalMinor < 0 ||
        interestMinor < 0 ||
        feeMinor < 0) {
      return const FailureResult(
        ValidationFailure(
          message:
              'Loan payment components must be non-negative with a positive total.',
        ),
      );
    }

    final totalMoney = Money(
      amountMinor: totalMinor,
      currencyCode: currency.code,
    );
    final fxRes = CurrencyConverter.convert(
      original: totalMoney,
      originalSpec: currency,
      targetSpec: baseCurrency,
      fxRate: fxRate,
      fallbackEffectiveAtUtc: effectiveAtUtc,
    );
    if (fxRes.isFailure) return FailureResult(fxRes.failureOrNull!);
    final conv = fxRes.valueOrNull!;
    final totalBase = conv.convertedAmount.amountMinor;

    int convertPart(int partMinor) => CurrencyConverter.divideAndRound(
      numerator: BigInt.from(partMinor) * BigInt.from(totalBase),
      denominator: BigInt.from(totalMinor),
      mode: conv.appliedRate.roundingMode,
    );

    final interestBase = interestMinor > 0 ? convertPart(interestMinor) : 0;
    final feeBase = feeMinor > 0 ? convertPart(feeMinor) : 0;
    final principalBase = totalBase - interestBase - feeBase;

    final postings = <LedgerPostingSpec>[];
    if (principalMinor > 0 && principalBase > 0) {
      postings.add(
        LedgerPostingSpec(
          ledgerAccountId: loanLiabilityLedgerAccountId,
          side: PostingSide.debit,
          baseAmountMinor: principalBase,
          currencyCode: currency.code,
          originalAmountMinor: principalMinor,
        ),
      );
    }
    if (interestMinor > 0 && interestBase > 0) {
      postings.add(
        LedgerPostingSpec(
          ledgerAccountId: interestExpenseLedgerAccountId,
          side: PostingSide.debit,
          baseAmountMinor: interestBase,
          currencyCode: currency.code,
          originalAmountMinor: interestMinor,
        ),
      );
    }
    if (feeMinor > 0 && feeBase > 0) {
      if (feeExpenseLedgerAccountId == null) {
        return const FailureResult(
          ValidationFailure(
            message: 'Fee ledger account is required for loan fees.',
          ),
        );
      }
      postings.add(
        LedgerPostingSpec(
          ledgerAccountId: feeExpenseLedgerAccountId,
          side: PostingSide.debit,
          baseAmountMinor: feeBase,
          currencyCode: currency.code,
          originalAmountMinor: feeMinor,
        ),
      );
    }

    postings.add(
      LedgerPostingSpec(
        ledgerAccountId: sourceBankLedgerAccountId,
        side: PostingSide.credit,
        baseAmountMinor: totalBase,
        currencyCode: currency.code,
        originalAmountMinor: totalMinor,
      ),
    );

    return _finalize(
      profileId: profileId,
      baseCurrencyCode: baseCurrency.code,
      baseAmountMinor: totalBase,
      fxRate: conv.appliedRate,
      postings: postings,
    );
  }

  /// Derives authoritative ledger balance using normal-balance convention.
  static int computeBalanceMinor({
    required LedgerAccountType accountType,
    required Iterable<({PostingSide side, int amountMinor})> postings,
  }) {
    var debits = 0;
    var credits = 0;
    for (final p in postings) {
      if (p.side == PostingSide.debit) {
        debits += p.amountMinor;
      } else {
        credits += p.amountMinor;
      }
    }
    return accountType.normalBalance == PostingSide.debit
        ? debits - credits
        : credits - debits;
  }

  static Result<GeneratedJournal> _finalize({
    required ProfileId profileId,
    required String baseCurrencyCode,
    required int baseAmountMinor,
    required FxRate fxRate,
    required List<LedgerPostingSpec> postings,
    List<ResolvedSplitLine> resolvedSplits = const [],
    String? reversesJournalEntryId,
  }) {
    final check = validateBalancedPostings(postings);
    if (check.isFailure) return FailureResult(check.failureOrNull!);

    return Success(
      GeneratedJournal(
        profileId: profileId,
        baseCurrencyCode: baseCurrencyCode,
        baseAmountMinor: baseAmountMinor,
        appliedFxRate: fxRate,
        postings: List.unmodifiable(postings),
        resolvedSplits: List.unmodifiable(resolvedSplits),
        reversesJournalEntryId: reversesJournalEntryId,
      ),
    );
  }
}
