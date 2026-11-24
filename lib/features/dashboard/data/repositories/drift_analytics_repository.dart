import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/financial_engine/money.dart';
import '../../../../core/utilities/clock.dart';
import '../../../../core/utilities/id_generator.dart';
import '../../../accounts/domain/repositories/account_repository.dart';
import '../../../transactions/domain/entities/transaction_entity.dart';
import '../../../transactions/domain/repositories/transaction_repository.dart';
import '../../domain/entities/dashboard_summary.dart';
import '../../domain/repositories/analytics_repository.dart';

/// Authoritative domain aggregation service computing Net Worth, Cash Flow,
/// and Category Spend strictly from posted double-entry ledger postings (`FR-012`, `DATA-003`).
final class DriftAnalyticsRepository implements AnalyticsRepository {
  DriftAnalyticsRepository({
    required AppDatabase db,
    required AccountRepository accountRepository,
    required TransactionRepository transactionRepository,
    required UtcClock clock,
  }) : _db = db,
       _accountRepo = accountRepository,
       _txRepo = transactionRepository,
       _clock = clock;

  final AppDatabase _db;
  final AccountRepository _accountRepo;
  final TransactionRepository _txRepo;
  final UtcClock _clock;

  @override
  Future<Result<DashboardSummary>> computeDashboardSummary(
    ProfileId profileId, {
    required DashboardPeriodPreset period,
  }) async {
    try {
      final profileRow = await (_db.select(
        _db.profiles,
      )..where((p) => p.id.equals(profileId.value))).getSingleOrNull();
      if (profileRow == null) {
        return const FailureResult(AuthorizationFailure());
      }
      final baseCurr = profileRow.baseCurrencyCode;
      final nowUtc = _clock.nowUtc();
      final bounds = period.resolveBoundsUtc(nowUtc);
      final fromIso = bounds.fromUtc?.toIso8601String();
      final toIso = bounds.toUtc?.toIso8601String();

      // 1. Account balances (derived strictly from posted ledger postings).
      final accountsRes = await _accountRepo.listAccounts(profileId);
      if (accountsRes.isFailure) {
        return FailureResult(accountsRes.failureOrNull!);
      }
      final accounts = accountsRes.valueOrNull!;

      var assetsMinor = 0;
      var liabilitiesMinor = 0;
      for (final a in accounts) {
        if (a.isLiability) {
          liabilitiesMinor += a.baseBalance.amountMinor;
        } else {
          assetsMinor += a.baseBalance.amountMinor;
        }
      }
      final netWorthMinor = assetsMinor - liabilitiesMinor;

      // 2. Period Income & Expense directly from posted ledger postings against
      //    income/expense ledger accounts (transfers never touch these accounts!).
      final dateFilterSql = StringBuffer();
      final vars = <Variable<Object>>[Variable.withString(profileId.value)];
      if (fromIso != null) {
        dateFilterSql.write(' AND je.effective_at_utc >= ?');
        vars.add(Variable.withString(fromIso));
      }
      if (toIso != null) {
        dateFilterSql.write(' AND je.effective_at_utc <= ?');
        vars.add(Variable.withString(toIso));
      }

      final totalsRow = await _db.customSelect('''
        SELECT
          COALESCE(SUM(CASE WHEN la.account_type = 'income' AND lp.side = 'credit' THEN lp.base_amount_minor
                            WHEN la.account_type = 'income' AND lp.side = 'debit' THEN -lp.base_amount_minor
                            ELSE 0 END), 0) AS net_income,
          COALESCE(SUM(CASE WHEN la.account_type = 'expense' AND lp.side = 'debit' AND t.transaction_type <> 'adjustment' THEN lp.base_amount_minor
                            ELSE 0 END), 0) AS gross_expense,
          COALESCE(SUM(CASE WHEN la.account_type = 'expense' AND lp.side = 'debit' THEN lp.base_amount_minor
                            WHEN la.account_type = 'expense' AND lp.side = 'credit' THEN -lp.base_amount_minor
                            ELSE 0 END), 0) AS net_expense
        FROM ledger_postings lp
        INNER JOIN journal_entries je ON je.id = lp.journal_entry_id AND je.profile_id = lp.profile_id
        INNER JOIN ledger_accounts la ON la.id = lp.ledger_account_id AND la.profile_id = lp.profile_id
        INNER JOIN transactions t ON t.id = je.transaction_id AND t.profile_id = je.profile_id
        WHERE lp.profile_id = ?
          AND je.status IN ('posted', 'reversed')
          ${dateFilterSql.toString()}
        ''', variables: vars).getSingle();

      final periodIncomeMinor = totalsRow.read<int>('net_income');
      final periodGrossExpenseMinor = totalsRow.read<int>('gross_expense');
      final periodNetExpenseMinor = totalsRow.read<int>('net_expense');

      // 3. Category Spend Breakdown (net of refunds & reversals, split-aware via ledger_accounts).
      final catRows = await _db.customSelect('''
        SELECT
          c.id AS category_id,
          c.name AS category_name,
          COALESCE(SUM(CASE WHEN lp.side = 'debit' THEN lp.base_amount_minor ELSE 0 END), 0) AS debits,
          COALESCE(SUM(CASE WHEN lp.side = 'credit' THEN lp.base_amount_minor ELSE 0 END), 0) AS credits
        FROM categories c
        INNER JOIN ledger_postings lp ON lp.ledger_account_id = c.ledger_account_id AND lp.profile_id = c.profile_id
        INNER JOIN journal_entries je ON je.id = lp.journal_entry_id AND je.profile_id = lp.profile_id
        WHERE c.profile_id = ?
          AND c.category_type = 'expense'
          AND je.status IN ('posted', 'reversed')
          ${dateFilterSql.toString()}
        GROUP BY c.id, c.name
        HAVING (debits - credits) > 0
        ORDER BY (debits - credits) DESC
        ''', variables: vars).get();

      final totalCatNet = catRows.fold<int>(
        0,
        (s, r) => s + (r.read<int>('debits') - r.read<int>('credits')),
      );
      final breakdown = catRows.map((r) {
        final d = r.read<int>('debits');
        final c = r.read<int>('credits');
        final net = d - c;
        return CategorySpendItem(
          categoryId: r.read<String>('category_id'),
          categoryName: r.read<String>('category_name'),
          grossSpendMinor: d,
          refundsMinor: c,
          netSpendMinor: net,
          currencyCode: baseCurr,
          sharePercent: totalCatNet > 0 ? (net * 100.0 / totalCatNet) : 0.0,
        );
      }).toList();

      // 4. Last 6 Months Cash Flow Series.
      final sixMonthsAgo = DateTime.utc(nowUtc.year, nowUtc.month - 5, 1);
      final seriesRows = await _db
          .customSelect(
            '''
        SELECT
          substr(je.effective_at_utc, 1, 7) AS ym,
          COALESCE(SUM(CASE WHEN la.account_type = 'income' AND lp.side = 'credit' THEN lp.base_amount_minor
                            WHEN la.account_type = 'income' AND lp.side = 'debit' THEN -lp.base_amount_minor
                            ELSE 0 END), 0) AS inc,
          COALESCE(SUM(CASE WHEN la.account_type = 'expense' AND lp.side = 'debit' THEN lp.base_amount_minor
                            WHEN la.account_type = 'expense' AND lp.side = 'credit' THEN -lp.base_amount_minor
                            ELSE 0 END), 0) AS exp
        FROM ledger_postings lp
        INNER JOIN journal_entries je ON je.id = lp.journal_entry_id AND je.profile_id = lp.profile_id
        INNER JOIN ledger_accounts la ON la.id = lp.ledger_account_id AND la.profile_id = lp.profile_id
        WHERE lp.profile_id = ?
          AND je.status IN ('posted', 'reversed')
          AND je.effective_at_utc >= ?
        GROUP BY ym
        ORDER BY ym ASC
        ''',
            variables: [
              Variable.withString(profileId.value),
              Variable.withString(sixMonthsAgo.toIso8601String()),
            ],
          )
          .get();

      final byYm = {
        for (final r in seriesRows)
          r.read<String>('ym'): (
            inc: r.read<int>('inc'),
            exp: r.read<int>('exp'),
          ),
      };
      final monthly = <MonthlyCashFlowPoint>[];
      for (var i = 5; i >= 0; i--) {
        final d = DateTime.utc(nowUtc.year, nowUtc.month - i, 1);
        final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
        final v = byYm[key];
        monthly.add(
          MonthlyCashFlowPoint(
            yearMonth: key,
            incomeMinor: v?.inc ?? 0,
            expenseMinor: v?.exp ?? 0,
            currencyCode: baseCurr,
          ),
        );
      }

      // 5. Recent transactions (limit 8).
      final recentRes = await _txRepo.queryTransactions(
        profileId,
        filter: TransactionFilter(fromUtc: fromIso, toUtc: toIso),
        limit: 8,
      );
      final recent =
          recentRes.valueOrNull?.items ?? const <TransactionEntity>[];

      // 6. Pending sync outbox count for honest sync banner.
      final pendingRow = await _db
          .customSelect(
            '''
        SELECT COUNT(*) AS cnt FROM sync_outbox
        WHERE profile_id = ? AND status IN ('pending', 'syncing', 'retryable_error', 'conflict')
        ''',
            variables: [Variable.withString(profileId.value)],
          )
          .getSingle();

      return Success(
        DashboardSummary(
          profileId: profileId,
          baseCurrencyCode: baseCurr,
          periodPreset: period,
          valuationTimestampUtc: nowUtc.toIso8601String(),
          totalAssets: Money(amountMinor: assetsMinor, currencyCode: baseCurr),
          totalLiabilities: Money(
            amountMinor: liabilitiesMinor,
            currencyCode: baseCurr,
          ),
          netWorth: Money(amountMinor: netWorthMinor, currencyCode: baseCurr),
          periodIncome: Money(
            amountMinor: periodIncomeMinor,
            currencyCode: baseCurr,
          ),
          periodGrossExpense: Money(
            amountMinor: periodGrossExpenseMinor,
            currencyCode: baseCurr,
          ),
          periodNetExpense: Money(
            amountMinor: periodNetExpenseMinor,
            currencyCode: baseCurr,
          ),
          periodNetCashFlow: Money(
            amountMinor: periodIncomeMinor - periodNetExpenseMinor,
            currencyCode: baseCurr,
          ),
          accounts: accounts,
          recentTransactions: recent,
          categoryBreakdown: breakdown,
          monthlyCashFlow: monthly,
          pendingSyncCount: pendingRow.read<int>('cnt'),
        ),
      );
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }
}
