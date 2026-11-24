import '../../../../core/errors/failures.dart';
import '../../../../core/utilities/id_generator.dart';
import '../entities/savings_goal_entity.dart';

abstract interface class SavingsGoalRepository {
  Future<Result<List<SavingsGoalEntity>>> listGoals(ProfileId profileId);

  Future<Result<SavingsGoalEntity>> createGoal({
    required ProfileId profileId,
    required String name,
    required int targetAmountMinor,
    required String currencyCode,
    required GoalFundingMode fundingMode,
    String? linkedAccountId,
    String? targetDateUtc,
  });

  /// Records a contribution. For `accountTransfer` mode, creates an atomic
  /// ledger transfer from [sourceAccountId] into the goal's linked account (`FR-014`).
  Future<Result<SavingsGoalEntity>> recordContribution({
    required ProfileId profileId,
    required String goalId,
    required int amountMinor,
    String? sourceAccountId,
    String? note,
  });
}
