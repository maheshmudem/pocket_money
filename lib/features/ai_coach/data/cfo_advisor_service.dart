import '../../../core/errors/failures.dart';
import '../../../core/financial_engine/cfo_advisor_engine.dart';
import '../../../core/utilities/clock.dart';
import '../../../core/utilities/id_generator.dart';
import '../../accounts/domain/entities/financial_account_entity.dart';
import '../../accounts/domain/repositories/account_repository.dart';
import '../../budgets/domain/repositories/budget_repository.dart';
import '../../transactions/domain/entities/transaction_entity.dart';
import '../../transactions/domain/repositories/transaction_repository.dart';

/// Profile-scoped on-device service assembling 6 months of double-entry ledger
/// history, active budgets, and liquid reserves for [CfoAdvisorEngine].
final class CfoAdvisorService {
  CfoAdvisorService({
    required TransactionRepository transactionRepository,
    required BudgetRepository budgetRepository,
    required AccountRepository accountRepository,
    required UtcClock clock,
  }) : _txRepo = transactionRepository,
       _budgetRepo = budgetRepository,
       _accountRepo = accountRepository,
       _clock = clock;

  final TransactionRepository _txRepo;
  final BudgetRepository _budgetRepo;
  final AccountRepository _accountRepo;
  final UtcClock _clock;

  Future<Result<CfoAdvisorReport>> buildReport({
    required ProfileId profileId,
    required String baseCurrencyCode,
    String? selectedYearMonth,
  }) async {
    try {
      final nowUtc = _clock.nowUtc();
      // Pull 8 months of posted ledger history so even viewing 5 months back
      // still has trailing 3-month comparison history!
      final lookbackFrom = DateTime.utc(nowUtc.year, nowUtc.month - 8, 1);

      final txRes = await _txRepo.queryTransactions(
        profileId,
        filter: TransactionFilter(
          status: TransactionStatus.posted,
          fromUtc: lookbackFrom.toIso8601String(),
        ),
        limit: 2500,
      );
      if (txRes.isFailure) {
        return FailureResult(txRes.failureOrNull!);
      }

      final budgetsRes = await _budgetRepo.listBudgetsWithProgress(profileId);
      final accountsRes = await _accountRepo.listAccounts(profileId);

      final items = txRes.valueOrNull?.items ?? const <TransactionEntity>[];
      final rawExpenses = <AdvisorExpenseEntry>[];
      final incomes = <AdvisorIncomeEntry>[];
      final refundsByKey = <String, int>{}; // "YYYY-MM|catKey" -> minor

      for (final tx in items) {
        if (tx.isReversed || tx.status != TransactionStatus.posted) continue;
        final dt = DateTime.tryParse(tx.transactionDateUtc)?.toUtc();
        if (dt == null) continue;
        final ym = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';

        if (tx.type == TransactionType.income) {
          incomes.add(
            AdvisorIncomeEntry(
              dateUtc: dt,
              amountMinor: tx.baseAmount.amountMinor,
              categoryName: tx.categoryName ?? 'Income',
            ),
          );
          continue;
        }

        if (tx.type == TransactionType.refund) {
          final catKey = tx.categoryId ?? (tx.categoryName ?? 'Uncategorized');
          final key = '$ym|$catKey';
          refundsByKey[key] =
              (refundsByKey[key] ?? 0) + tx.baseAmount.amountMinor;
          continue;
        }

        if (tx.type != TransactionType.expense) continue;

        if (tx.splits.isNotEmpty) {
          for (final sp in tx.splits) {
            final label = sp.memo?.trim().isNotEmpty == true
                ? sp.memo!.trim()
                : (tx.description?.trim().isNotEmpty == true
                      ? tx.description!.trim()
                      : sp.categoryName);
            rawExpenses.add(
              AdvisorExpenseEntry(
                dateUtc: dt,
                amountMinor: sp.baseAmountMinor,
                categoryId: sp.categoryId,
                categoryName: sp.categoryName,
                merchantLabel: label,
              ),
            );
          }
        } else {
          final catName = tx.categoryName ?? 'Uncategorized';
          final label = tx.description?.trim().isNotEmpty == true
              ? tx.description!.trim()
              : catName;
          rawExpenses.add(
            AdvisorExpenseEntry(
              dateUtc: dt,
              amountMinor: tx.baseAmount.amountMinor,
              categoryId: tx.categoryId,
              categoryName: catName,
              merchantLabel: label,
            ),
          );
        }
      }

      // Net out posted refunds against expenses in the same (month, category).
      final expenses = <AdvisorExpenseEntry>[];
      for (final exp in rawExpenses) {
        final ym =
            '${exp.dateUtc.year}-${exp.dateUtc.month.toString().padLeft(2, '0')}';
        final catKey = exp.categoryId ?? exp.categoryName;
        final key = '$ym|$catKey';
        final pendingRefund = refundsByKey[key] ?? 0;
        if (pendingRefund > 0) {
          if (pendingRefund >= exp.amountMinor) {
            refundsByKey[key] = pendingRefund - exp.amountMinor;
            continue;
          } else {
            refundsByKey[key] = 0;
            expenses.add(
              AdvisorExpenseEntry(
                dateUtc: exp.dateUtc,
                amountMinor: exp.amountMinor - pendingRefund,
                categoryId: exp.categoryId,
                categoryName: exp.categoryName,
                merchantLabel: exp.merchantLabel,
              ),
            );
            continue;
          }
        }
        expenses.add(exp);
      }

      final activeBudgets = (budgetsRes.valueOrNull ?? const [])
          .map(
            (b) => AdvisorActiveBudget(
              id: b.id,
              name: b.name,
              overallLimitMinor: b.overallLimit.amountMinor,
              spentMinor: b.totalSpent.amountMinor,
              categoryIds: b.allocations.map((a) => a.categoryId).toList(),
            ),
          )
          .toList();

      final liquidAssetsMinor = (accountsRes.valueOrNull ?? const [])
          .where(
            (a) =>
                !a.isLiability &&
                (a.accountType == FinancialAccountType.bank ||
                    a.accountType == FinancialAccountType.cash ||
                    a.accountType == FinancialAccountType.wallet),
          )
          .fold<int>(0, (s, a) => s + a.baseBalance.amountMinor);

      final report = CfoAdvisorEngine.analyze(
        CfoAdvisorInput(
          currencyCode: baseCurrencyCode,
          nowUtc: nowUtc,
          selectedYearMonth: selectedYearMonth,
          expenses: expenses,
          incomes: incomes,
          activeBudgets: activeBudgets,
          totalLiquidAssetsMinor: liquidAssetsMinor,
        ),
      );
      return Success(report);
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }
}
