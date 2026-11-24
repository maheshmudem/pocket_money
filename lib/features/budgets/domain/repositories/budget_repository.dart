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

  Future<Result<void>> deleteBudget(ProfileId profileId, String budgetId);
}
