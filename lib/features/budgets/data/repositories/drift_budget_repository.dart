import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/financial_engine/money.dart';
import '../../../../core/utilities/clock.dart';
import '../../../../core/utilities/id_generator.dart';
import '../../domain/entities/budget_entity.dart';
import '../../domain/repositories/budget_repository.dart';

final class DriftBudgetRepository implements BudgetRepository {
  DriftBudgetRepository({
    required AppDatabase db,
    required IdGenerator idGenerator,
    required UtcClock clock,
  }) : _db = db,
       _idGen = idGenerator,
       _clock = clock;

  final AppDatabase _db;
  final IdGenerator _idGen;
  final UtcClock _clock;

  @override
  Future<Result<List<BudgetEntity>>> listBudgetsWithProgress(
    ProfileId profileId, {
    DateTime? referenceUtc,
  }) async {
    try {
      final ref = (referenceUtc ?? _clock.nowUtc()).toUtc();
      final budgetRows =
          await (_db.select(_db.budgets)
                ..where(
                  (b) =>
                      b.profileId.equals(profileId.value) &
                      b.isActive.equals(true),
                )
                ..orderBy([(b) => OrderingTerm.asc(b.createdAtUtc)]))
              .get();

      final catRows = await (_db.select(
        _db.categories,
      )..where((c) => c.profileId.equals(profileId.value))).get();
      final catById = {for (final c in catRows) c.id: c};

      final results = <BudgetEntity>[];
      for (final b in budgetRows) {
        final periodType = BudgetPeriodType.fromWire(b.periodType);
        final (:fromUtc, :toUtc) = _resolveActiveWindow(b, periodType, ref);

        final allocRows =
            await (_db.select(_db.budgetCategories)..where(
                  (bc) =>
                      bc.budgetId.equals(b.id) &
                      bc.profileId.equals(profileId.value),
                ))
                .get();

        final spendByLedger = await _queryNetExpenseByLedger(
          profileId,
          fromUtc: fromUtc,
          toUtc: toUtc,
        );

        // Compute deterministic prior-period unspent rollover when enabled.
        Map<String, int>? prevSpendByLedger;
        if (b.rolloverEnabled && periodType != BudgetPeriodType.custom) {
          final createdAt = DateTime.parse(b.startDateUtc).toUtc();
          if (createdAt.isBefore(fromUtc)) {
            final prev = _resolvePreviousWindow(periodType, fromUtc);
            prevSpendByLedger = await _queryNetExpenseByLedger(
              profileId,
              fromUtc: prev.fromUtc,
              toUtc: prev.toUtc,
            );
          }
        }

        final allocations = <BudgetCategoryAllocation>[];
        var totalSpent = 0;
        var rolloverCarryMinor = 0;

        if (allocRows.isEmpty) {
          // Overall profile expense budget across all expense categories.
          for (final v in spendByLedger.values) {
            if (v > 0) totalSpent += v;
          }
          if (prevSpendByLedger != null) {
            var prevTotal = 0;
            for (final v in prevSpendByLedger.values) {
              if (v > 0) prevTotal += v;
            }
            if (b.overallLimitMinor > prevTotal) {
              rolloverCarryMinor = b.overallLimitMinor - prevTotal;
            }
          }
        } else {
          for (final alloc in allocRows) {
            final cat = catById[alloc.categoryId];
            final spent = cat != null
                ? (spendByLedger[cat.ledgerAccountId] ?? 0)
                : 0;
            final clampedSpent = spent > 0 ? spent : 0;
            totalSpent += clampedSpent;

            var allocCarry = 0;
            if (prevSpendByLedger != null && cat != null) {
              final prevSpent = prevSpendByLedger[cat.ledgerAccountId] ?? 0;
              final clampedPrev = prevSpent > 0 ? prevSpent : 0;
              if (alloc.limitMinor > clampedPrev) {
                allocCarry = alloc.limitMinor - clampedPrev;
              }
            }
            rolloverCarryMinor += allocCarry;

            allocations.add(
              BudgetCategoryAllocation(
                categoryId: alloc.categoryId,
                categoryName: cat?.name ?? 'Category',
                limitMinor: alloc.limitMinor + allocCarry,
                spentMinor: clampedSpent,
                currencyCode: b.currencyCode,
              ),
            );
          }
        }

        results.add(
          BudgetEntity(
            id: b.id,
            profileId: ProfileId(b.profileId),
            name: b.name,
            periodType: periodType,
            startDateUtc: fromUtc.toIso8601String(),
            endDateUtc: toUtc.toIso8601String(),
            overallLimit: Money(
              amountMinor: b.overallLimitMinor + rolloverCarryMinor,
              currencyCode: b.currencyCode,
            ),
            totalSpent: Money(
              amountMinor: totalSpent,
              currencyCode: b.currencyCode,
            ),
            rolloverEnabled: b.rolloverEnabled,
            isActive: b.isActive,
            allocations: allocations,
          ),
        );
      }

      return Success(results);
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  @override
  Future<Result<BudgetEntity>> createBudget({
    required ProfileId profileId,
    required String name,
    required BudgetPeriodType periodType,
    required int overallLimitMinor,
    required String currencyCode,
    required Map<String, int> categoryLimitsMinor,
    bool rolloverEnabled = false,
    String? startDateUtc,
    String? endDateUtc,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || overallLimitMinor <= 0) {
      return const FailureResult(
        ValidationFailure(
          message: 'Budget requires a name and a positive overall limit.',
        ),
      );
    }

    final now = _clock.nowIsoUtc();
    final budgetId = _idGen.nextUuid();

    try {
      await _db.transaction(() async {
        await _db
            .into(_db.budgets)
            .insert(
              BudgetsCompanion.insert(
                id: budgetId,
                profileId: profileId.value,
                name: trimmed,
                periodType: periodType.wireValue,
                startDateUtc: startDateUtc ?? now,
                endDateUtc: Value(endDateUtc),
                overallLimitMinor: overallLimitMinor,
                currencyCode: currencyCode.toUpperCase(),
                rolloverEnabled: Value(rolloverEnabled),
                createdAtUtc: now,
                updatedAtUtc: now,
              ),
            );

        for (final entry in categoryLimitsMinor.entries) {
          if (entry.value <= 0) continue;
          await _db
              .into(_db.budgetCategories)
              .insert(
                BudgetCategoriesCompanion.insert(
                  id: _idGen.nextUuid(),
                  profileId: profileId.value,
                  budgetId: budgetId,
                  categoryId: entry.key,
                  limitMinor: entry.value,
                ),
              );
        }
      });

      final all = await listBudgetsWithProgress(profileId);
      if (all.isFailure) return FailureResult(all.failureOrNull!);
      return Success(all.valueOrNull!.firstWhere((b) => b.id == budgetId));
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  @override
  Future<Result<BudgetEntity>> updateBudget({
    required ProfileId profileId,
    required String budgetId,
    required String name,
    required BudgetPeriodType periodType,
    required int overallLimitMinor,
    required Map<String, int> categoryLimitsMinor,
    required bool rolloverEnabled,
    String? startDateUtc,
    String? endDateUtc,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || overallLimitMinor <= 0) {
      return const FailureResult(
        ValidationFailure(
          message: 'Budget requires a name and a positive overall limit.',
        ),
      );
    }

    final existing =
        await (_db.select(_db.budgets)..where(
              (b) =>
                  b.id.equals(budgetId) & b.profileId.equals(profileId.value),
            ))
            .getSingleOrNull();
    if (existing == null) {
      return const FailureResult(NotFoundFailure());
    }

    final now = _clock.nowIsoUtc();
    try {
      await _db.transaction(() async {
        await (_db.update(_db.budgets)..where(
              (b) =>
                  b.id.equals(budgetId) & b.profileId.equals(profileId.value),
            ))
            .write(
              BudgetsCompanion(
                name: Value(trimmed),
                periodType: Value(periodType.wireValue),
                overallLimitMinor: Value(overallLimitMinor),
                rolloverEnabled: Value(rolloverEnabled),
                startDateUtc: startDateUtc != null
                    ? Value(startDateUtc)
                    : const Value.absent(),
                endDateUtc: endDateUtc != null
                    ? Value(endDateUtc)
                    : const Value.absent(),
                updatedAtUtc: Value(now),
                version: Value(existing.version + 1),
              ),
            );

        await (_db.delete(_db.budgetCategories)..where(
              (bc) =>
                  bc.budgetId.equals(budgetId) &
                  bc.profileId.equals(profileId.value),
            ))
            .go();

        for (final entry in categoryLimitsMinor.entries) {
          if (entry.value <= 0) continue;
          await _db
              .into(_db.budgetCategories)
              .insert(
                BudgetCategoriesCompanion.insert(
                  id: _idGen.nextUuid(),
                  profileId: profileId.value,
                  budgetId: budgetId,
                  categoryId: entry.key,
                  limitMinor: entry.value,
                ),
              );
        }
      });

      final all = await listBudgetsWithProgress(profileId);
      if (all.isFailure) return FailureResult(all.failureOrNull!);
      return Success(all.valueOrNull!.firstWhere((b) => b.id == budgetId));
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  @override
  Future<Result<void>> reallocateCategoryLimit({
    required ProfileId profileId,
    required String fromBudgetId,
    required String fromCategoryId,
    required String toBudgetId,
    required String toCategoryId,
    required int amountMinor,
  }) async {
    if (amountMinor <= 0) {
      return const FailureResult(
        ValidationFailure(message: 'Transfer amount must be positive.'),
      );
    }
    if (fromBudgetId == toBudgetId && fromCategoryId == toCategoryId) {
      return const FailureResult(
        ValidationFailure(
          message: 'Source and target category envelopes must be different.',
        ),
      );
    }

    final now = _clock.nowIsoUtc();
    try {
      final failure = await _db.transaction<AppFailure?>(() async {
        final fromCat =
            await (_db.select(_db.budgetCategories)..where(
                  (bc) =>
                      bc.budgetId.equals(fromBudgetId) &
                      bc.categoryId.equals(fromCategoryId) &
                      bc.profileId.equals(profileId.value),
                ))
                .getSingleOrNull();
        final toCat =
            await (_db.select(_db.budgetCategories)..where(
                  (bc) =>
                      bc.budgetId.equals(toBudgetId) &
                      bc.categoryId.equals(toCategoryId) &
                      bc.profileId.equals(profileId.value),
                ))
                .getSingleOrNull();

        if (fromCat == null || toCat == null) {
          return const NotFoundFailure(
            message: 'Category budget envelope not found.',
          );
        }
        if (fromCat.limitMinor - amountMinor <= 0) {
          return const ValidationFailure(
            message:
                'Transfer must leave a positive remaining limit in the source envelope.',
          );
        }

        final fromBudget =
            await (_db.select(_db.budgets)..where(
                  (b) =>
                      b.id.equals(fromBudgetId) &
                      b.profileId.equals(profileId.value),
                ))
                .getSingleOrNull();
        final toBudget =
            await (_db.select(_db.budgets)..where(
                  (b) =>
                      b.id.equals(toBudgetId) &
                      b.profileId.equals(profileId.value),
                ))
                .getSingleOrNull();
        if (fromBudget == null || toBudget == null) {
          return const NotFoundFailure();
        }
        if (fromBudgetId != toBudgetId &&
            fromBudget.overallLimitMinor - amountMinor <= 0) {
          return const ValidationFailure(
            message: 'Transfer exceeds the available cap of the source budget.',
          );
        }

        await (_db.update(
          _db.budgetCategories,
        )..where((bc) => bc.id.equals(fromCat.id))).write(
          BudgetCategoriesCompanion(
            limitMinor: Value(fromCat.limitMinor - amountMinor),
          ),
        );
        await (_db.update(
          _db.budgetCategories,
        )..where((bc) => bc.id.equals(toCat.id))).write(
          BudgetCategoriesCompanion(
            limitMinor: Value(toCat.limitMinor + amountMinor),
          ),
        );

        if (fromBudgetId == toBudgetId) {
          await (_db.update(
            _db.budgets,
          )..where((b) => b.id.equals(fromBudgetId))).write(
            BudgetsCompanion(
              updatedAtUtc: Value(now),
              version: Value(fromBudget.version + 1),
            ),
          );
        } else {
          await (_db.update(
            _db.budgets,
          )..where((b) => b.id.equals(fromBudgetId))).write(
            BudgetsCompanion(
              overallLimitMinor: Value(
                fromBudget.overallLimitMinor - amountMinor,
              ),
              updatedAtUtc: Value(now),
              version: Value(fromBudget.version + 1),
            ),
          );
          await (_db.update(
            _db.budgets,
          )..where((b) => b.id.equals(toBudgetId))).write(
            BudgetsCompanion(
              overallLimitMinor: Value(
                toBudget.overallLimitMinor + amountMinor,
              ),
              updatedAtUtc: Value(now),
              version: Value(toBudget.version + 1),
            ),
          );
        }
        return null;
      });

      if (failure != null) return FailureResult(failure);
      return const Success(null);
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  @override
  Future<Result<void>> deleteBudget(
    ProfileId profileId,
    String budgetId,
  ) async {
    try {
      await _db.transaction(() async {
        await (_db.delete(_db.budgetCategories)..where(
              (bc) =>
                  bc.budgetId.equals(budgetId) &
                  bc.profileId.equals(profileId.value),
            ))
            .go();
        await (_db.delete(_db.budgets)..where(
              (b) =>
                  b.id.equals(budgetId) & b.profileId.equals(profileId.value),
            ))
            .go();
      });
      return const Success(null);
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  Future<Map<String, int>> _queryNetExpenseByLedger(
    ProfileId profileId, {
    required DateTime fromUtc,
    required DateTime toUtc,
  }) async {
    final spendRows = await _db
        .customSelect(
          '''
      SELECT
        lp.ledger_account_id,
        COALESCE(SUM(CASE WHEN lp.side = 'debit' THEN lp.base_amount_minor
                          WHEN lp.side = 'credit' THEN -lp.base_amount_minor
                          ELSE 0 END), 0) AS net_spent
      FROM ledger_postings lp
      INNER JOIN journal_entries je ON je.id = lp.journal_entry_id AND je.profile_id = lp.profile_id
      INNER JOIN ledger_accounts la ON la.id = lp.ledger_account_id AND la.profile_id = lp.profile_id
      WHERE lp.profile_id = ?
        AND la.account_type = 'expense'
        AND je.status IN ('posted', 'reversed')
        AND je.effective_at_utc >= ?
        AND je.effective_at_utc <= ?
      GROUP BY lp.ledger_account_id
      ''',
          variables: [
            Variable.withString(profileId.value),
            Variable.withString(fromUtc.toIso8601String()),
            Variable.withString(toUtc.toIso8601String()),
          ],
        )
        .get();
    return {
      for (final r in spendRows)
        r.read<String>('ledger_account_id'): r.read<int>('net_spent'),
    };
  }

  ({DateTime fromUtc, DateTime toUtc}) _resolvePreviousWindow(
    BudgetPeriodType periodType,
    DateTime currentFromUtc,
  ) {
    final prevAnchor = currentFromUtc.subtract(const Duration(seconds: 1));
    return switch (periodType) {
      BudgetPeriodType.weekly => (
        fromUtc: currentFromUtc.subtract(const Duration(days: 7)),
        toUtc: prevAnchor,
      ),
      BudgetPeriodType.monthly => (
        fromUtc: DateTime.utc(prevAnchor.year, prevAnchor.month, 1),
        toUtc: DateTime.utc(
          prevAnchor.year,
          prevAnchor.month + 1,
          0,
          23,
          59,
          59,
        ),
      ),
      BudgetPeriodType.quarterly => () {
        final qStartMonth = ((prevAnchor.month - 1) ~/ 3) * 3 + 1;
        return (
          fromUtc: DateTime.utc(prevAnchor.year, qStartMonth, 1),
          toUtc: DateTime.utc(prevAnchor.year, qStartMonth + 3, 0, 23, 59, 59),
        );
      }(),
      BudgetPeriodType.yearly => (
        fromUtc: DateTime.utc(prevAnchor.year, 1, 1),
        toUtc: DateTime.utc(prevAnchor.year, 12, 31, 23, 59, 59),
      ),
      BudgetPeriodType.custom => (
        fromUtc: currentFromUtc,
        toUtc: currentFromUtc,
      ),
    };
  }

  ({DateTime fromUtc, DateTime toUtc}) _resolveActiveWindow(
    Budget row,
    BudgetPeriodType periodType,
    DateTime refUtc,
  ) {
    return switch (periodType) {
      BudgetPeriodType.weekly => (
        fromUtc: DateTime.utc(
          refUtc.year,
          refUtc.month,
          refUtc.day - (refUtc.weekday - 1),
        ),
        toUtc: DateTime.utc(
          refUtc.year,
          refUtc.month,
          refUtc.day + (7 - refUtc.weekday),
          23,
          59,
          59,
        ),
      ),
      BudgetPeriodType.monthly => (
        fromUtc: DateTime.utc(refUtc.year, refUtc.month, 1),
        toUtc: DateTime.utc(refUtc.year, refUtc.month + 1, 0, 23, 59, 59),
      ),
      BudgetPeriodType.quarterly => () {
        final qStartMonth = ((refUtc.month - 1) ~/ 3) * 3 + 1;
        return (
          fromUtc: DateTime.utc(refUtc.year, qStartMonth, 1),
          toUtc: DateTime.utc(refUtc.year, qStartMonth + 3, 0, 23, 59, 59),
        );
      }(),
      BudgetPeriodType.yearly => (
        fromUtc: DateTime.utc(refUtc.year, 1, 1),
        toUtc: DateTime.utc(refUtc.year, 12, 31, 23, 59, 59),
      ),
      BudgetPeriodType.custom => (
        fromUtc: DateTime.parse(row.startDateUtc).toUtc(),
        toUtc: row.endDateUtc != null
            ? DateTime.parse(row.endDateUtc!).toUtc()
            : refUtc,
      ),
    };
  }
}
