import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_money/core/financial_engine/currency.dart';
import 'package:pocket_money/core/financial_engine/double_entry_engine.dart';
import 'package:pocket_money/core/financial_engine/fx_rate.dart';
import 'package:pocket_money/core/financial_engine/loan_amortizer.dart';
import 'package:pocket_money/core/financial_engine/money.dart';
import 'package:pocket_money/core/utilities/id_generator.dart';

void main() {
  const profile = ProfileId('prof-1');
  const now = '2026-11-19T07:00:00Z';
  final inr = CurrencyCatalog.requireByCode('INR');
  final usd = CurrencyCatalog.requireByCode('USD');
  final jpy = CurrencyCatalog.requireByCode('JPY');
  final kwd = CurrencyCatalog.requireByCode('KWD');

  group('Financial Accuracy Test Catalogue (TC-FIN-001..TC-FIN-016)', () {
    test(
      'TC-FIN-001: 500 INR cash expense -> Debit Expense 50000, Credit Cash 50000',
      () {
        final res = DoubleEntryEngine.buildExpense(
          profileId: profile,
          sourceLedgerAccountId: 'la-cash',
          categoryLedgerAccountId: 'la-exp-food',
          amount: const Money(amountMinor: 50000, currencyCode: 'INR'),
          amountCurrency: inr,
          baseCurrency: inr,
          fxRate: null,
          effectiveAtUtc: now,
        );
        expect(res.isSuccess, isTrue);
        final je = res.valueOrNull!;
        expect(je.isBalanced, isTrue);
        expect(je.postings, hasLength(2));
        expect(je.postings[0].ledgerAccountId, 'la-exp-food');
        expect(je.postings[0].side, PostingSide.debit);
        expect(je.postings[0].baseAmountMinor, 50000);
        expect(je.postings[1].ledgerAccountId, 'la-cash');
        expect(je.postings[1].side, PostingSide.credit);
        expect(je.postings[1].baseAmountMinor, 50000);

        // Opening 1000 INR - 500 INR expense = 500 INR cash balance
        final cashBal = DoubleEntryEngine.computeBalanceMinor(
          accountType: LedgerAccountType.asset,
          postings: [
            (side: PostingSide.debit, amountMinor: 100000),
            (side: PostingSide.credit, amountMinor: 50000),
          ],
        );
        expect(cashBal, 50000);
      },
    );

    test(
      'TC-FIN-002: 10,000 INR salary into bank -> Debit Bank, Credit Income',
      () {
        final res = DoubleEntryEngine.buildIncome(
          profileId: profile,
          destinationLedgerAccountId: 'la-bank',
          incomeCategoryLedgerAccountId: 'la-inc-salary',
          amount: const Money(amountMinor: 1000000, currencyCode: 'INR'),
          amountCurrency: inr,
          baseCurrency: inr,
          fxRate: null,
          effectiveAtUtc: now,
        );
        expect(res.isSuccess, isTrue);
        final je = res.valueOrNull!;
        expect(je.isBalanced, isTrue);
        expect(je.postings[0].ledgerAccountId, 'la-bank');
        expect(je.postings[0].side, PostingSide.debit);
        expect(je.postings[1].ledgerAccountId, 'la-inc-salary');
        expect(je.postings[1].side, PostingSide.credit);
      },
    );

    test(
      'TC-FIN-003: 2,000 INR bank-to-cash transfer -> balanced assets, zero income/expense',
      () {
        final res = DoubleEntryEngine.buildTransfer(
          profileId: profile,
          sourceLedgerAccountId: 'la-bank',
          destinationLedgerAccountId: 'la-cash',
          sourceAmount: const Money(amountMinor: 200000, currencyCode: 'INR'),
          sourceCurrency: inr,
          destinationAmount: const Money(
            amountMinor: 200000,
            currencyCode: 'INR',
          ),
          destinationCurrency: inr,
          baseCurrency: inr,
          sourceToBaseRate: null,
          destinationToBaseRate: null,
          fxVarianceLedgerAccountId: null,
          effectiveAtUtc: now,
        );
        expect(res.isSuccess, isTrue);
        final je = res.valueOrNull!;
        expect(je.isBalanced, isTrue);
        expect(je.postings.map((p) => p.ledgerAccountId), [
          'la-cash',
          'la-bank',
        ]);
      },
    );

    test(
      'TC-FIN-004 & TC-FIN-005: 1,250 INR credit card purchase and repayment without duplicate expense',
      () {
        final purchase = DoubleEntryEngine.buildExpense(
          profileId: profile,
          sourceLedgerAccountId: 'la-card',
          categoryLedgerAccountId: 'la-exp-shop',
          amount: const Money(amountMinor: 125000, currencyCode: 'INR'),
          amountCurrency: inr,
          baseCurrency: inr,
          fxRate: null,
          effectiveAtUtc: now,
        ).valueOrNull!;

        final cardBalAfterPurchase = DoubleEntryEngine.computeBalanceMinor(
          accountType: LedgerAccountType.liability,
          postings: [
            for (final p in purchase.postings.where(
              (p) => p.ledgerAccountId == 'la-card',
            ))
              (side: p.side, amountMinor: p.baseAmountMinor),
          ],
        );
        expect(cardBalAfterPurchase, 125000);

        final repay = DoubleEntryEngine.buildTransfer(
          profileId: profile,
          sourceLedgerAccountId: 'la-bank',
          destinationLedgerAccountId: 'la-card',
          sourceAmount: const Money(amountMinor: 125000, currencyCode: 'INR'),
          sourceCurrency: inr,
          destinationAmount: const Money(
            amountMinor: 125000,
            currencyCode: 'INR',
          ),
          destinationCurrency: inr,
          baseCurrency: inr,
          sourceToBaseRate: null,
          destinationToBaseRate: null,
          fxVarianceLedgerAccountId: null,
          effectiveAtUtc: now,
        ).valueOrNull!;

        final cardBalAfterRepay = DoubleEntryEngine.computeBalanceMinor(
          accountType: LedgerAccountType.liability,
          postings: [
            for (final p in [
              ...purchase.postings,
              ...repay.postings,
            ].where((p) => p.ledgerAccountId == 'la-card'))
              (side: p.side, amountMinor: p.baseAmountMinor),
          ],
        );
        expect(cardBalAfterRepay, 0);
        // Expense touched only once (not during repayment).
        expect(
          repay.postings.where((p) => p.ledgerAccountId == 'la-exp-shop'),
          isEmpty,
        );
      },
    );

    test(
      'TC-FIN-006 & TC-FIN-007: split 1,000 into 600 + 400 succeeds; mismatch rejects atomically',
      () {
        final ok = DoubleEntryEngine.buildExpense(
          profileId: profile,
          sourceLedgerAccountId: 'la-cash',
          categoryLedgerAccountId: null,
          amount: const Money(amountMinor: 100000, currencyCode: 'INR'),
          amountCurrency: inr,
          baseCurrency: inr,
          fxRate: null,
          effectiveAtUtc: now,
          splits: const [
            SplitLineInput(
              categoryId: 'cat-1',
              categoryLedgerAccountId: 'la-exp-1',
              amountMinor: 60000,
            ),
            SplitLineInput(
              categoryId: 'cat-2',
              categoryLedgerAccountId: 'la-exp-2',
              amountMinor: 40000,
            ),
          ],
        );
        expect(ok.isSuccess, isTrue);
        expect(ok.valueOrNull!.isBalanced, isTrue);
        expect(ok.valueOrNull!.postings, hasLength(3));

        final bad = DoubleEntryEngine.buildExpense(
          profileId: profile,
          sourceLedgerAccountId: 'la-cash',
          categoryLedgerAccountId: null,
          amount: const Money(amountMinor: 100000, currencyCode: 'INR'),
          amountCurrency: inr,
          baseCurrency: inr,
          fxRate: null,
          effectiveAtUtc: now,
          splits: const [
            SplitLineInput(
              categoryId: 'cat-1',
              categoryLedgerAccountId: 'la-exp-1',
              amountMinor: 60000,
            ),
            SplitLineInput(
              categoryId: 'cat-2',
              categoryLedgerAccountId: 'la-exp-2',
              amountMinor: 39900,
            ),
          ],
        );
        expect(bad.isFailure, isTrue);
        expect(bad.failureOrNull!.code, 'SPLIT_MISMATCH');
      },
    );

    test('TC-FIN-008: unbalanced postings rejected by domain validator', () {
      final res = DoubleEntryEngine.validateBalancedPostings(const [
        LedgerPostingSpec(
          ledgerAccountId: 'a',
          side: PostingSide.debit,
          baseAmountMinor: 1000,
          currencyCode: 'INR',
          originalAmountMinor: 1000,
        ),
        LedgerPostingSpec(
          ledgerAccountId: 'b',
          side: PostingSide.credit,
          baseAmountMinor: 999,
          currencyCode: 'INR',
          originalAmountMinor: 999,
        ),
      ]);
      expect(res.isFailure, isTrue);
    });

    test(
      'TC-FIN-010 & TC-FIN-011: linked partial refund and compensating reversal balance cleanly',
      () {
        final orig = DoubleEntryEngine.buildExpense(
          profileId: profile,
          sourceLedgerAccountId: 'la-bank',
          categoryLedgerAccountId: 'la-exp-shop',
          amount: const Money(amountMinor: 100000, currencyCode: 'INR'),
          amountCurrency: inr,
          baseCurrency: inr,
          fxRate: null,
          effectiveAtUtc: now,
        ).valueOrNull!;

        final refund = DoubleEntryEngine.buildRefund(
          profileId: profile,
          destinationLedgerAccountId: 'la-bank',
          expenseCategoryLedgerAccountId: 'la-exp-shop',
          refundAmount: const Money(amountMinor: 40000, currencyCode: 'INR'),
          amountCurrency: inr,
          baseCurrency: inr,
          fxRate: null,
          effectiveAtUtc: now,
        ).valueOrNull!;

        final netExpense = DoubleEntryEngine.computeBalanceMinor(
          accountType: LedgerAccountType.expense,
          postings: [
            for (final p in [
              ...orig.postings,
              ...refund.postings,
            ].where((p) => p.ledgerAccountId == 'la-exp-shop'))
              (side: p.side, amountMinor: p.baseAmountMinor),
          ],
        );
        expect(netExpense, 60000);

        final reversal = DoubleEntryEngine.buildReversal(
          profileId: profile,
          originalJournalEntryId: 'je-orig',
          baseCurrencyCode: 'INR',
          originalPostings: orig.postings,
          effectiveAtUtc: now,
        ).valueOrNull!;
        expect(reversal.isBalanced, isTrue);
        expect(reversal.reversesJournalEntryId, 'je-orig');
        final afterReversal = DoubleEntryEngine.computeBalanceMinor(
          accountType: LedgerAccountType.expense,
          postings: [
            for (final p in [
              ...orig.postings,
              ...reversal.postings,
            ].where((p) => p.ledgerAccountId == 'la-exp-shop'))
              (side: p.side, amountMinor: p.baseAmountMinor),
          ],
        );
        expect(afterReversal, 0);
      },
    );

    test(
      'TC-FIN-012 & TC-FIN-013: 0 minor-unit JPY & 3 minor-unit KWD parsing and formatting',
      () {
        final jpyOk = Money.parseDecimal('1500', currency: jpy);
        expect(jpyOk.valueOrNull!.amountMinor, 1500);
        expect(jpyOk.valueOrNull!.format(spec: jpy), '¥ 1,500');

        final jpyBad = Money.parseDecimal('1500.5', currency: jpy);
        expect(jpyBad.isFailure, isTrue);

        final kwdOk = Money.parseDecimal('12.345', currency: kwd);
        expect(kwdOk.valueOrNull!.amountMinor, 12345);
        expect(kwdOk.valueOrNull!.format(spec: kwd), 'KD 12.345');

        final kwdBad = Money.parseDecimal('12.3456', currency: kwd);
        expect(kwdBad.isFailure, isTrue);

        // Indian grouping for INR
        expect(
          const Money(
            amountMinor: 123456789,
            currencyCode: 'INR',
          ).format(spec: inr),
          '₹ 12,34,567.89',
        );
      },
    );

    test(
      'TC-FIN-014 & TC-FIN-015: HALF_EVEN FX tie-breaking and missing-rate rejection (never silent 1:1)',
      () {
        // Missing FX rate MUST fail with FX_RATE_REQUIRED
        final missing = CurrencyConverter.convert(
          original: const Money(amountMinor: 1000, currencyCode: 'USD'),
          originalSpec: usd,
          targetSpec: inr,
          fxRate: null,
          fallbackEffectiveAtUtc: now,
        );
        expect(missing.isFailure, isTrue);
        expect(missing.failureOrNull!.code, 'FX_RATE_REQUIRED');

        // Exact half ties: 2.5 -> 2 (even), 3.5 -> 4 (even) under HALF_EVEN
        expect(
          CurrencyConverter.divideAndRound(
            numerator: BigInt.from(5),
            denominator: BigInt.from(2),
            mode: FxRoundingMode.halfEven,
          ),
          2,
        );
        expect(
          CurrencyConverter.divideAndRound(
            numerator: BigInt.from(7),
            denominator: BigInt.from(2),
            mode: FxRoundingMode.halfEven,
          ),
          4,
        );
      },
    );

    test(
      'TC-FIN-016: cross-currency transfer reconciles exact base postings with explicit FX variance',
      () {
        // Transfer 100.00 USD (rate 84.00 -> 8400.00 INR) arriving as 8350.00 INR -> 50.00 INR FX loss
        final res = DoubleEntryEngine.buildTransfer(
          profileId: profile,
          sourceLedgerAccountId: 'la-usd-bank',
          destinationLedgerAccountId: 'la-inr-bank',
          sourceAmount: const Money(amountMinor: 10000, currencyCode: 'USD'),
          sourceCurrency: usd,
          destinationAmount: const Money(
            amountMinor: 835000,
            currencyCode: 'INR',
          ),
          destinationCurrency: inr,
          baseCurrency: inr,
          sourceToBaseRate: const FxRate(
            fromCurrencyCode: 'USD',
            toCurrencyCode: 'INR',
            rateScaled: 8400000000, // 84.00
            rateScale: FxRate.defaultScale,
            source: 'manual',
            effectiveAtUtc: now,
          ),
          destinationToBaseRate: null,
          fxVarianceLedgerAccountId: 'la-fx-variance',
          effectiveAtUtc: now,
        );

        expect(res.isSuccess, isTrue);
        final je = res.valueOrNull!;
        expect(je.isBalanced, isTrue);
        expect(je.totalDebitsMinor, 840000);
        expect(je.totalCreditsMinor, 840000);
        expect(
          je.postings
              .singleWhere((p) => p.ledgerAccountId == 'la-fx-variance')
              .side,
          PostingSide.debit,
        );
        expect(
          je.postings
              .singleWhere((p) => p.ledgerAccountId == 'la-fx-variance')
              .baseAmountMinor,
          5000,
        );
      },
    );

    test(
      'FR-018: Reducing-balance loan amortization sums exactly to original principal',
      () {
        final schedule = LoanAmortizer.generateSchedule(
          principalMinor: 50000000, // ₹5,00,000.00
          annualInterestRateBps: 1050, // 10.50%
          termMonths: 24,
          startDateUtc: DateTime.utc(2026, 1, 1),
        );
        expect(schedule, hasLength(24));
        final principalSum = schedule.fold<int>(
          0,
          (s, p) => s + p.principalDueMinor,
        );
        expect(principalSum, 50000000);
        expect(schedule.last.remainingPrincipalMinor, 0);
        expect(
          schedule.first.interestDueMinor,
          greaterThan(schedule.last.interestDueMinor),
        );
      },
    );
  });
}
