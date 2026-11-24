import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/financial_engine/currency.dart';
import '../../../../core/financial_engine/double_entry_engine.dart';
import '../../../../core/financial_engine/loan_amortizer.dart';
import '../../../../core/financial_engine/money.dart';
import '../../../../core/utilities/clock.dart';
import '../../../../core/utilities/id_generator.dart';
import '../../../accounts/domain/entities/financial_account_entity.dart';
import '../../../accounts/domain/repositories/account_repository.dart';
import '../../../profiles/data/repositories/drift_profile_repository.dart';
import '../../domain/entities/loan_entity.dart';

final class DriftLoanRepository {
  DriftLoanRepository({
    required AppDatabase db,
    required AccountRepository accountRepository,
    required IdGenerator idGenerator,
    required UtcClock clock,
  }) : _db = db,
       _accountRepo = accountRepository,
       _idGen = idGenerator,
       _clock = clock;

  final AppDatabase _db;
  final AccountRepository _accountRepo;
  final IdGenerator _idGen;
  final UtcClock _clock;

  Future<Result<List<LoanEntity>>> listLoans(ProfileId profileId) async {
    try {
      final loanRows =
          await (_db.select(_db.loans)
                ..where((l) => l.profileId.equals(profileId.value))
                ..orderBy([(l) => OrderingTerm.desc(l.createdAtUtc)]))
              .get();

      final list = <LoanEntity>[];
      for (final l in loanRows) {
        final instRows =
            await (_db.select(_db.loanInstallments)
                  ..where(
                    (i) =>
                        i.loanId.equals(l.id) &
                        i.profileId.equals(profileId.value),
                  )
                  ..orderBy([(i) => OrderingTerm.asc(i.installmentNumber)]))
                .get();

        list.add(
          LoanEntity(
            id: l.id,
            profileId: ProfileId(l.profileId),
            name: l.name,
            loanAccountId: l.loanAccountId,
            fundingAccountId: l.fundingAccountId,
            principal: Money(
              amountMinor: l.principalMinor,
              currencyCode: l.currencyCode,
            ),
            annualInterestRateBps: l.annualInterestRateBps,
            termMonths: l.termMonths,
            interestMethod: l.interestMethod,
            startDateUtc: l.startDateUtc,
            status: l.status,
            installments: instRows
                .map(
                  (i) => LoanInstallmentEntity(
                    id: i.id,
                    loanId: i.loanId,
                    installmentNumber: i.installmentNumber,
                    dueDateUtc: i.dueDateUtc,
                    principalDueMinor: i.principalDueMinor,
                    interestDueMinor: i.interestDueMinor,
                    feeDueMinor: i.feeDueMinor,
                    status: i.status,
                    paymentTransactionId: i.paymentTransactionId,
                    paidAtUtc: i.paidAtUtc,
                  ),
                )
                .toList(),
          ),
        );
      }
      return Success(list);
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  /// Creates a Loan liability account with opening principal journal and full
  /// Reducing-Balance (or Flat) EMI installment schedule (`FR-018`).
  Future<Result<LoanEntity>> createLoan({
    required ProfileId profileId,
    required String name,
    required int principalMinor,
    required String currencyCode,
    required int annualInterestRateBps,
    required int termMonths,
    required DateTime startDateUtc,
    LoanInterestMethod method = LoanInterestMethod.reducingBalance,
    String? fundingAccountId,
  }) async {
    if (name.trim().isEmpty || principalMinor <= 0 || termMonths <= 0) {
      return const FailureResult(
        ValidationFailure(
          message: 'Loan requires a name, positive principal, and valid term.',
        ),
      );
    }

    // Provision dedicated Liability financial account with opening principal balance.
    final accRes = await _accountRepo.createAccountWithOpeningBalance(
      profileId: profileId,
      name: '${name.trim()} (Loan)',
      accountType: FinancialAccountType.loan,
      currencyCode: currencyCode,
      openingBalanceMinor: principalMinor,
      openingDateUtc: startDateUtc.toUtc().toIso8601String(),
    );
    if (accRes.isFailure) return FailureResult(accRes.failureOrNull!);
    final loanAcc = accRes.valueOrNull!;

    final schedule = LoanAmortizer.generateSchedule(
      principalMinor: principalMinor,
      annualInterestRateBps: annualInterestRateBps,
      termMonths: termMonths,
      startDateUtc: startDateUtc.toUtc(),
      method: method,
    );

    final loanId = _idGen.nextUuid();
    final now = _clock.nowIsoUtc();

    try {
      await _db.transaction(() async {
        await _db
            .into(_db.loans)
            .insert(
              LoansCompanion.insert(
                id: loanId,
                profileId: profileId.value,
                name: name.trim(),
                loanAccountId: loanAcc.id,
                fundingAccountId: Value(fundingAccountId),
                principalMinor: principalMinor,
                currencyCode: currencyCode.toUpperCase(),
                annualInterestRateBps: annualInterestRateBps,
                termMonths: termMonths,
                interestMethod: Value(method.wireValue),
                startDateUtc: startDateUtc.toUtc().toIso8601String(),
                createdAtUtc: now,
                updatedAtUtc: now,
              ),
            );

        for (final item in schedule) {
          await _db
              .into(_db.loanInstallments)
              .insert(
                LoanInstallmentsCompanion.insert(
                  id: _idGen.nextUuid(),
                  profileId: profileId.value,
                  loanId: loanId,
                  installmentNumber: item.installmentNumber,
                  dueDateUtc: item.dueDateUtc.toIso8601String(),
                  principalDueMinor: item.principalDueMinor,
                  interestDueMinor: item.interestDueMinor,
                ),
              );
        }
      });

      final all = await listLoans(profileId);
      if (all.isFailure) return FailureResult(all.failureOrNull!);
      return Success(all.valueOrNull!.firstWhere((l) => l.id == loanId));
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  /// Pays an installment splitting Principal (Liability), Interest (Expense),
  /// and optional Fee (Expense) in one atomic double-entry journal (`FR-018`).
  Future<Result<void>> payInstallment({
    required ProfileId profileId,
    required String loanId,
    required String installmentId,
    required String sourceBankAccountId,
    int feeMinor = 0,
  }) async {
    final loan =
        await (_db.select(_db.loans)..where(
              (l) => l.id.equals(loanId) & l.profileId.equals(profileId.value),
            ))
            .getSingleOrNull();
    if (loan == null) return const FailureResult(NotFoundFailure());

    final inst =
        await (_db.select(_db.loanInstallments)..where(
              (i) =>
                  i.id.equals(installmentId) &
                  i.loanId.equals(loanId) &
                  i.profileId.equals(profileId.value),
            ))
            .getSingleOrNull();
    if (inst == null) return const FailureResult(NotFoundFailure());
    if (inst.status == 'paid') {
      return const FailureResult(
        ValidationFailure(message: 'This installment is already paid.'),
      );
    }

    final bankAcc =
        await (_db.select(_db.financialAccounts)..where(
              (a) =>
                  a.id.equals(sourceBankAccountId) &
                  a.profileId.equals(profileId.value),
            ))
            .getSingleOrNull();
    final loanAcc =
        await (_db.select(_db.financialAccounts)..where(
              (a) =>
                  a.id.equals(loan.loanAccountId) &
                  a.profileId.equals(profileId.value),
            ))
            .getSingleOrNull();
    final interestLedger =
        await (_db.select(_db.ledgerAccounts)..where(
              (l) =>
                  l.profileId.equals(profileId.value) &
                  l.systemCode.equals(SystemLedgerCodes.loanInterest),
            ))
            .getSingleOrNull();
    final feeLedger =
        await (_db.select(_db.ledgerAccounts)..where(
              (l) =>
                  l.profileId.equals(profileId.value) &
                  l.systemCode.equals(SystemLedgerCodes.loanFees),
            ))
            .getSingleOrNull();
    final profileRow = await (_db.select(
      _db.profiles,
    )..where((p) => p.id.equals(profileId.value))).getSingleOrNull();

    if (bankAcc == null ||
        loanAcc == null ||
        interestLedger == null ||
        profileRow == null) {
      return const FailureResult(
        LedgerInvariantFailure(
          message: 'Required bank, loan, or interest ledger account missing.',
        ),
      );
    }

    final now = _clock.nowIsoUtc();
    final currSpec = CurrencyCatalog.requireByCode(loan.currencyCode);
    final baseSpec = CurrencyCatalog.requireByCode(profileRow.baseCurrencyCode);

    final journalRes = DoubleEntryEngine.buildLoanPayment(
      profileId: profileId,
      sourceBankLedgerAccountId: bankAcc.ledgerAccountId,
      loanLiabilityLedgerAccountId: loanAcc.ledgerAccountId,
      interestExpenseLedgerAccountId: interestLedger.id,
      feeExpenseLedgerAccountId: feeLedger?.id,
      principalMinor: inst.principalDueMinor,
      interestMinor: inst.interestDueMinor,
      feeMinor: feeMinor,
      currency: currSpec,
      baseCurrency: baseSpec,
      fxRate: null,
      effectiveAtUtc: now,
    );
    if (journalRes.isFailure) return FailureResult(journalRes.failureOrNull!);
    final journal = journalRes.valueOrNull!;

    final txId = _idGen.nextUuid();
    final jeId = _idGen.nextUuid();
    final totalMinor =
        inst.principalDueMinor + inst.interestDueMinor + feeMinor;

    try {
      await _db.transaction(() async {
        await _db
            .into(_db.transactions)
            .insert(
              TransactionsCompanion.insert(
                id: txId,
                profileId: profileId.value,
                transactionType: 'adjustment',
                status: 'posted',
                transactionDateUtc: now,
                amountMinor: totalMinor,
                currencyCode: loan.currencyCode,
                baseCurrencyCode: baseSpec.code,
                baseAmountMinor: journal.baseAmountMinor,
                fxRateScaled: journal.appliedFxRate.rateScaled,
                fxRateScale: journal.appliedFxRate.rateScale,
                sourceAccountId: Value(sourceBankAccountId),
                destinationAccountId: Value(loan.loanAccountId),
                description: Value(
                  '${loan.name} — Installment #${inst.installmentNumber} (Principal/Interest)',
                ),
                createdAtUtc: now,
                updatedAtUtc: now,
              ),
            );

        await _db
            .into(_db.journalEntries)
            .insert(
              JournalEntriesCompanion.insert(
                id: jeId,
                profileId: profileId.value,
                transactionId: txId,
                status: 'draft',
                effectiveAtUtc: now,
                createdAtUtc: now,
              ),
            );

        for (final p in journal.postings) {
          await _db
              .into(_db.ledgerPostings)
              .insert(
                LedgerPostingsCompanion.insert(
                  id: _idGen.nextUuid(),
                  profileId: profileId.value,
                  journalEntryId: jeId,
                  ledgerAccountId: p.ledgerAccountId,
                  side: p.side.wireValue,
                  baseAmountMinor: p.baseAmountMinor,
                  currencyCode: p.currencyCode,
                  originalAmountMinor: p.originalAmountMinor,
                ),
              );
        }

        await (_db.update(_db.journalEntries)..where((j) => j.id.equals(jeId)))
            .write(const JournalEntriesCompanion(status: Value('posted')));

        await (_db.update(
          _db.loanInstallments,
        )..where((i) => i.id.equals(installmentId))).write(
          LoanInstallmentsCompanion(
            feeDueMinor: Value(feeMinor),
            status: const Value('paid'),
            paymentTransactionId: Value(txId),
            paidAtUtc: Value(now),
          ),
        );

        final remainingUnpaid =
            await (_db.select(_db.loanInstallments)..where(
                  (i) =>
                      i.loanId.equals(loanId) &
                      i.profileId.equals(profileId.value) &
                      i.status.equals('paid').not(),
                ))
                .get();
        if (remainingUnpaid.isEmpty) {
          await (_db.update(_db.loans)..where(
                (l) =>
                    l.id.equals(loanId) & l.profileId.equals(profileId.value),
              ))
              .write(
                LoansCompanion(
                  status: const Value('paid_off'),
                  updatedAtUtc: Value(now),
                ),
              );
        }
      });
      return const Success(null);
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }
}
