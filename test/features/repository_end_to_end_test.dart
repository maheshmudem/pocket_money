import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_money/core/database/app_database.dart';
import 'package:pocket_money/core/database/encrypted_executor.dart';
import 'package:pocket_money/core/financial_engine/loan_amortizer.dart';
import 'package:pocket_money/core/logging/redacting_logger.dart';
import 'package:pocket_money/core/security/backup_crypto.dart';
import 'package:pocket_money/core/utilities/clock.dart';
import 'package:pocket_money/core/utilities/id_generator.dart';
import 'package:pocket_money/features/accounts/data/repositories/drift_account_repository.dart';
import 'package:pocket_money/features/accounts/domain/entities/financial_account_entity.dart';
import 'package:pocket_money/features/backup_restore/data/backup_restore_service.dart';
import 'package:pocket_money/features/budgets/data/repositories/drift_budget_repository.dart';
import 'package:pocket_money/features/budgets/domain/entities/budget_entity.dart';
import 'package:pocket_money/features/categories/data/repositories/drift_category_repository.dart';
import 'package:pocket_money/features/categories/domain/entities/category_entity.dart';
import 'package:pocket_money/features/dashboard/data/repositories/drift_analytics_repository.dart';
import 'package:pocket_money/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:pocket_money/features/import_export/data/repositories/drift_csv_import_repository.dart';
import 'package:pocket_money/features/import_export/domain/csv_import_engine.dart';
import 'package:pocket_money/features/loans/data/repositories/drift_loan_repository.dart';
import 'package:pocket_money/features/profiles/data/repositories/drift_profile_repository.dart';
import 'package:pocket_money/features/profiles/domain/entities/profile_entity.dart';
import 'package:pocket_money/features/recurring/data/repositories/drift_recurring_repository.dart';
import 'package:pocket_money/features/recurring/domain/entities/recurring_rule_entity.dart';
import 'package:pocket_money/features/reports/data/report_exporter.dart';
import 'package:pocket_money/features/savings_goals/data/repositories/drift_savings_goal_repository.dart';
import 'package:pocket_money/features/savings_goals/domain/entities/savings_goal_entity.dart';
import 'package:pocket_money/features/transactions/data/repositories/drift_transaction_repository.dart';
import 'package:pocket_money/features/transactions/domain/entities/transaction_entity.dart';

void main() {
  late AppDatabase db;
  late FixedUtcClock clock;
  late UuidV4Generator idGen;
  late RedactingLogger logger;
  late DriftProfileRepository profileRepo;
  late DriftAccountRepository accountRepo;
  late DriftCategoryRepository categoryRepo;
  late DriftTransactionRepository txRepo;
  late DriftAnalyticsRepository analyticsRepo;
  late DriftBudgetRepository budgetRepo;
  late DriftSavingsGoalRepository goalRepo;
  late DriftRecurringRepository recurringRepo;
  late DriftLoanRepository loanRepo;
  late DriftCsvImportRepository csvRepo;

  setUp(() {
    db = AppDatabase(EncryptedDatabaseExecutor.openInMemory());
    clock = FixedUtcClock(DateTime.utc(2026, 11, 15, 10, 0));
    idGen = const UuidV4Generator();
    logger = RedactingLogger();

    profileRepo = DriftProfileRepository(
      db: db,
      idGenerator: idGen,
      clock: clock,
      logger: logger,
    );
    accountRepo = DriftAccountRepository(
      db: db,
      idGenerator: idGen,
      clock: clock,
    );
    categoryRepo = DriftCategoryRepository(
      db: db,
      idGenerator: idGen,
      clock: clock,
    );
    txRepo = DriftTransactionRepository(
      db: db,
      idGenerator: idGen,
      clock: clock,
      logger: logger,
    );
    analyticsRepo = DriftAnalyticsRepository(
      db: db,
      accountRepository: accountRepo,
      transactionRepository: txRepo,
      clock: clock,
    );
    budgetRepo = DriftBudgetRepository(
      db: db,
      idGenerator: idGen,
      clock: clock,
    );
    goalRepo = DriftSavingsGoalRepository(
      db: db,
      transactionRepository: txRepo,
      idGenerator: idGen,
      clock: clock,
    );
    recurringRepo = DriftRecurringRepository(
      db: db,
      transactionRepository: txRepo,
      idGenerator: idGen,
      clock: clock,
    );
    loanRepo = DriftLoanRepository(
      db: db,
      accountRepository: accountRepo,
      idGenerator: idGen,
      clock: clock,
    );
    csvRepo = DriftCsvImportRepository(
      db: db,
      transactionRepository: txRepo,
      idGenerator: idGen,
      clock: clock,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'Full E2E financial workflow: isolation, double-entry, budgets, goals, recurring, loans, CSV dedup & .pcfo restore',
    () async {
      // 1. Create two isolated profiles (`AC-PROFILE-001`).
      final personal = (await profileRepo.createProfile(
        userId: 'user-1',
        ownerDisplayName: 'Asha',
        name: 'Personal',
        profileType: ProfileType.personal,
        baseCurrencyCode: 'INR',
      )).valueOrNull!;

      final business = (await profileRepo.createProfile(
        userId: 'user-1',
        ownerDisplayName: 'Asha',
        name: 'Studio Business',
        profileType: ProfileType.business,
        baseCurrencyCode: 'INR',
      )).valueOrNull!;

      // 2. Accounts with opening balances (`FR-004`, `FR-005`).
      final bank = (await accountRepo.createAccountWithOpeningBalance(
        profileId: personal.id,
        name: 'HDFC Bank',
        accountType: FinancialAccountType.bank,
        currencyCode: 'INR',
        openingBalanceMinor: 10000000, // ₹1,00,000.00
      )).valueOrNull!;
      expect(bank.balance.amountMinor, 10000000);

      final savingsAcc = (await accountRepo.createAccountWithOpeningBalance(
        profileId: personal.id,
        name: 'Emergency Savings',
        accountType: FinancialAccountType.bank,
        currencyCode: 'INR',
        openingBalanceMinor: 0,
      )).valueOrNull!;

      final card = (await accountRepo.createAccountWithOpeningBalance(
        profileId: personal.id,
        name: 'Visa Credit',
        accountType: FinancialAccountType.creditCard,
        currencyCode: 'INR',
        openingBalanceMinor: 0,
      )).valueOrNull!;

      // Business profile must see ZERO Personal accounts (`AC-PROFILE-001`).
      expect(
        (await accountRepo.listAccounts(business.id)).valueOrNull,
        isEmpty,
      );

      // Fetch Personal categories.
      final expCats = (await categoryRepo.listCategories(
        personal.id,
        type: CategoryType.expense,
      )).valueOrNull!;
      final incCats = (await categoryRepo.listCategories(
        personal.id,
        type: CategoryType.income,
      )).valueOrNull!;
      final groceries = expCats.firstWhere((c) => c.name == 'Groceries');
      final salary = incCats.firstWhere((c) => c.name == 'Salary');

      // 3. Income + Expense + Transfer + Credit Card Purchase + Linked Refund + Reversal.
      await txRepo.createTransaction(
        personal.id,
        CreateTransactionCommand(
          type: TransactionType.income,
          amountMinor: 5000000, // ₹50,000 salary
          currencyCode: 'INR',
          transactionDateUtc: clock.nowIsoUtc(),
          destinationAccountId: bank.id,
          categoryId: salary.id,
          description: 'November Salary',
        ),
      );

      final cardSpend = (await txRepo.createTransaction(
        personal.id,
        CreateTransactionCommand(
          type: TransactionType.expense,
          amountMinor: 200000, // ₹2,000 groceries on card
          currencyCode: 'INR',
          transactionDateUtc: clock.nowIsoUtc(),
          sourceAccountId: card.id,
          categoryId: groceries.id,
          description: 'Supermarket',
        ),
      )).valueOrNull!;

      // Linked partial refund of ₹500 on groceries (`TC-FIN-010`).
      await txRepo.createTransaction(
        personal.id,
        CreateTransactionCommand(
          type: TransactionType.refund,
          amountMinor: 50000,
          currencyCode: 'INR',
          transactionDateUtc: clock.nowIsoUtc(),
          destinationAccountId: card.id,
          categoryId: groceries.id,
          relatedTransactionId: cardSpend.id,
          description: 'Returned damaged item',
        ),
      );

      // Repay remaining ₹1,500 credit card via transfer (`TC-FIN-005`) -> NOT a second expense!
      await txRepo.createTransaction(
        personal.id,
        CreateTransactionCommand(
          type: TransactionType.transfer,
          amountMinor: 150000,
          currencyCode: 'INR',
          transactionDateUtc: clock.nowIsoUtc(),
          sourceAccountId: bank.id,
          destinationAccountId: card.id,
          description: 'Credit card bill repayment',
        ),
      );

      // Verify Dashboard reconciliation (`FR-012`).
      final dash = (await analyticsRepo.computeDashboardSummary(
        personal.id,
        period: DashboardPeriodPreset.thisMonth,
      )).valueOrNull!;
      expect(dash.periodIncome.amountMinor, 5000000);
      expect(dash.periodGrossExpense.amountMinor, 200000);
      expect(dash.periodNetExpense.amountMinor, 150000); // 2000 - 500 refund!
      expect(dash.totalLiabilities.amountMinor, 0); // Card fully repaid!
      expect(dash.netWorth.amountMinor, 14850000); // 1,00,000 + 50,000 - 1,500

      // 4. Budget progress nets out refunds and ignores transfers (`FR-013`).
      final budget = (await budgetRepo.createBudget(
        profileId: personal.id,
        name: 'Groceries Monthly',
        periodType: BudgetPeriodType.monthly,
        overallLimitMinor: 500000,
        currencyCode: 'INR',
        categoryLimitsMinor: {groceries.id: 500000},
      )).valueOrNull!;
      expect(budget.totalSpent.amountMinor, 150000);

      // 5. Savings Goal with real Account-Transfer contribution (`FR-014`).
      final goal = (await goalRepo.createGoal(
        profileId: personal.id,
        name: 'Emergency Reserve',
        targetAmountMinor: 1000000,
        currencyCode: 'INR',
        fundingMode: GoalFundingMode.accountTransfer,
        linkedAccountId: savingsAcc.id,
      )).valueOrNull!;
      final updatedGoal = (await goalRepo.recordContribution(
        profileId: personal.id,
        goalId: goal.id,
        amountMinor: 250000,
        sourceAccountId: bank.id,
      )).valueOrNull!;
      expect(updatedGoal.contributedAmount.amountMinor, 250000);
      expect(
        (await accountRepo.getAccount(
          personal.id,
          savingsAcc.id,
        )).valueOrNull!.balance.amountMinor,
        250000,
      );

      // 6. Recurring rule idempotency (`FR-017`): running twice generates exactly 1 occurrence.
      await recurringRepo.createRule(
        profileId: personal.id,
        name: 'Internet Fiber',
        transactionType: TransactionType.expense,
        amountMinor: 99900,
        currencyCode: 'INR',
        cadence: RecurringCadence.monthly,
        nextDueAtUtc: clock.nowIsoUtc(),
        sourceAccountId: bank.id,
        categoryId: groceries.id,
        autoCreateDraft: true,
      );
      expect((await recurringRepo.processDueRules(personal.id)).valueOrNull, 1);
      expect((await recurringRepo.processDueRules(personal.id)).valueOrNull, 0);

      // 7. Loan reducing-balance EMI & split Principal/Interest posting (`FR-018`).
      final loan = (await loanRepo.createLoan(
        profileId: personal.id,
        name: 'Equipment Loan',
        principalMinor: 1200000, // ₹12,000
        currencyCode: 'INR',
        annualInterestRateBps: 1200, // 12%
        termMonths: 12,
        startDateUtc: clock.nowUtc(),
        method: LoanInterestMethod.reducingBalance,
      )).valueOrNull!;
      expect(loan.installments, hasLength(12));
      final payRes = await loanRepo.payInstallment(
        profileId: personal.id,
        loanId: loan.id,
        installmentId: loan.installments.first.id,
        sourceBankAccountId: bank.id,
      );
      expect(payRes.isSuccess, isTrue);

      // 8. CSV Import duplicate detection (`AC-CSV-001`, `TC-FIN-018`) & export formula sanitization.
      const rawCsv =
          'Date,Description,Amount\n2026-11-10,Coffee Shop,-250.00\n2026-11-11,=EVIL_FORMULA(),+100.00\n';
      final rows = CsvImportEngine.parseRawCsv(rawCsv).valueOrNull!;
      const mapping = CsvColumnMapping(
        dateColumnIndex: 0,
        descriptionColumnIndex: 1,
        signedAmountColumnIndex: 2,
      );
      final preview1 = (await csvRepo.previewAndDetectDuplicates(
        profileId: personal.id,
        accountId: bank.id,
        rawRows: rows,
        mapping: mapping,
      )).valueOrNull!;
      expect(
        preview1.every(
          (r) => r.validationStatus == StagedRowValidationStatus.valid,
        ),
        isTrue,
      );

      final batch1 = (await csvRepo.commitConfirmedBatch(
        profileId: personal.id,
        accountId: bank.id,
        fileName: 'nov.csv',
        rawCsvContent: rawCsv,
        reviewedRows: preview1,
        defaultExpenseCategoryId: groceries.id,
        defaultIncomeCategoryId: salary.id,
      )).valueOrNull!;
      expect(batch1.importedCount, 2);

      // Re-importing the exact same CSV MUST detect both rows as possible duplicates!
      final preview2 = (await csvRepo.previewAndDetectDuplicates(
        profileId: personal.id,
        accountId: bank.id,
        rawRows: rows,
        mapping: mapping,
      )).valueOrNull!;
      expect(
        preview2.every(
          (r) =>
              r.validationStatus == StagedRowValidationStatus.possibleDuplicate,
        ),
        isTrue,
      );

      // Export CSV sanitizes leading '=' formula injection!
      final allTxs = (await txRepo.queryTransactions(
        personal.id,
      )).valueOrNull!.items;
      final exportedCsv = ReportExporter.generateTransactionsCsv(
        profile: personal,
        transactions: allTxs,
      );
      expect(exportedCsv, contains("'=EVIL_FORMULA()"));

      // 9. Automated Ledger Reconciliation Self-Check MUST be 100% healthy!
      final recon = (await txRepo.runReconciliationCheck(
        personal.id,
      )).valueOrNull!;
      expect(recon.isHealthy, isTrue);
      expect(recon.unbalancedJournalIds, isEmpty);
      expect(recon.orphanPostingCount, 0);
      expect(recon.totalDebitsMinor, recon.totalCreditsMinor);

      // 10. Encrypted `.pcfo` Backup & Staging-Validated Restore into a clean empty DB (`FR-024`)!
      final backupSvc = BackupRestoreService(
        db: db,
        crypto: const BackupCrypto(kdfIterations: 10000),
        clock: clock,
        appVersion: '1.0.0+1',
      );
      final archive = (await backupSvc.exportEncryptedBackup(
        passphrase: 'BackupVault#2026',
      )).valueOrNull!;

      final cleanDb = AppDatabase(EncryptedDatabaseExecutor.openInMemory());
      try {
        final restoreSvc = BackupRestoreService(
          db: cleanDb,
          crypto: const BackupCrypto(kdfIterations: 10000),
          clock: clock,
          appVersion: '1.0.0+1',
        );
        final restored = (await restoreSvc.restoreVerifiedBackup(
          rawArchive: archive,
          passphrase: 'BackupVault#2026',
        )).valueOrNull!;
        expect(restored.ledgerBalanced, isTrue);
        expect(restored.profileCount, 2);

        // Reconcile restored account balance against original!
        final restoredAccRepo = DriftAccountRepository(
          db: cleanDb,
          idGenerator: idGen,
          clock: clock,
        );
        final origBankBal = (await accountRepo.getAccount(
          personal.id,
          bank.id,
        )).valueOrNull!.balance.amountMinor;
        final restoredBankBal = (await restoredAccRepo.getAccount(
          personal.id,
          bank.id,
        )).valueOrNull!.balance.amountMinor;
        expect(restoredBankBal, origBankBal);
      } finally {
        await cleanDb.close();
      }
    },
  );
}
