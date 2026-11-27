import '../../../../core/errors/failures.dart';
import '../../../../core/utilities/id_generator.dart';
import '../entities/budget_entity.dart';

abstract interface class BudgetRepository {
  Future<Result<List<BudgetEntity>>> listBudgetsWithProgress(
    ProfileId profileId, {
    DateTime? referenceUtc,
  });

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
  });

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
  });

  /// Atomically shifts [amountMinor] from a source category envelope to a target
  /// category envelope (either within the same Master Budget or across two budgets).
  Future<Result<void>> reallocateCategoryLimit({
    required ProfileId profileId,
    required String fromBudgetId,
    required String fromCategoryId,
    required String toBudgetId,
    required String toCategoryId,
    required int amountMinor,
  });

  Future<Result<void>> deleteBudget(ProfileId profileId, String budgetId);
}
