import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/financial_engine/money.dart';
import '../../../../core/utilities/clock.dart';
import '../../../../core/utilities/id_generator.dart';
import '../../../transactions/domain/entities/transaction_entity.dart';
import '../../../transactions/domain/repositories/transaction_repository.dart';
import '../../domain/entities/savings_goal_entity.dart';
import '../../domain/repositories/savings_goal_repository.dart';

final class DriftSavingsGoalRepository implements SavingsGoalRepository {
  DriftSavingsGoalRepository({
    required AppDatabase db,
    required TransactionRepository transactionRepository,
    required IdGenerator idGenerator,
    required UtcClock clock,
  }) : _db = db,
       _txRepo = transactionRepository,
       _idGen = idGenerator,
       _clock = clock;

  final AppDatabase _db;
  final TransactionRepository _txRepo;
  final IdGenerator _idGen;
  final UtcClock _clock;

  @override
  Future<Result<List<SavingsGoalEntity>>> listGoals(ProfileId profileId) async {
    try {
      final rows = await _db
          .customSelect(
            '''
        SELECT
          g.id, g.profile_id, g.name, g.target_amount_minor, g.currency_code,
          g.target_date_utc, g.funding_mode, g.linked_account_id, g.status, g.created_at_utc,
          fa.name AS linked_account_name,
          COALESCE(SUM(CASE WHEN gc.contribution_type = 'deposit' THEN gc.amount_minor
                            WHEN gc.contribution_type = 'withdrawal' THEN -gc.amount_minor
                            ELSE 0 END), 0) AS contributed_minor
        FROM savings_goals g
        LEFT JOIN financial_accounts fa ON fa.id = g.linked_account_id AND fa.profile_id = g.profile_id
        LEFT JOIN goal_contributions gc ON gc.goal_id = g.id AND gc.profile_id = g.profile_id
        WHERE g.profile_id = ? AND g.status <> 'archived'
        GROUP BY g.id
        ORDER BY g.created_at_utc ASC
        ''',
            variables: [Variable.withString(profileId.value)],
          )
          .get();

      return Success(
        rows.map((r) {
          final curr = r.read<String>('currency_code');
          return SavingsGoalEntity(
            id: r.read<String>('id'),
            profileId: ProfileId(r.read<String>('profile_id')),
            name: r.read<String>('name'),
            targetAmount: Money(
              amountMinor: r.read<int>('target_amount_minor'),
              currencyCode: curr,
            ),
            contributedAmount: Money(
              amountMinor: r.read<int>('contributed_minor'),
              currencyCode: curr,
            ),
            fundingMode: GoalFundingMode.fromWire(
              r.read<String>('funding_mode'),
            ),
            status: r.read<String>('status'),
            createdAtUtc: r.read<String>('created_at_utc'),
            targetDateUtc: r.readNullable<String>('target_date_utc'),
            linkedAccountId: r.readNullable<String>('linked_account_id'),
            linkedAccountName: r.readNullable<String>('linked_account_name'),
          );
        }).toList(),
      );
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  @override
  Future<Result<SavingsGoalEntity>> createGoal({
    required ProfileId profileId,
    required String name,
    required int targetAmountMinor,
    required String currencyCode,
    required GoalFundingMode fundingMode,
    String? linkedAccountId,
    String? targetDateUtc,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || targetAmountMinor <= 0) {
      return const FailureResult(
        ValidationFailure(
          message: 'Goal name and positive target are required.',
        ),
      );
    }
    if (fundingMode == GoalFundingMode.accountTransfer &&
        linkedAccountId == null) {
      return const FailureResult(
        ValidationFailure(
          message:
              'Dedicated Account Transfer goals require a linked savings account.',
        ),
      );
    }

    final id = _idGen.nextUuid();
    final now = _clock.nowIsoUtc();
    try {
      await _db
          .into(_db.savingsGoals)
          .insert(
            SavingsGoalsCompanion.insert(
              id: id,
              profileId: profileId.value,
              name: trimmed,
              targetAmountMinor: targetAmountMinor,
              currencyCode: currencyCode.toUpperCase(),
              targetDateUtc: Value(targetDateUtc),
              fundingMode: fundingMode.wireValue,
              linkedAccountId: Value(linkedAccountId),
              status: 'active',
              createdAtUtc: now,
              updatedAtUtc: now,
            ),
          );
      final all = await listGoals(profileId);
      if (all.isFailure) return FailureResult(all.failureOrNull!);
      return Success(all.valueOrNull!.firstWhere((g) => g.id == id));
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  @override
  Future<Result<SavingsGoalEntity>> recordContribution({
    required ProfileId profileId,
    required String goalId,
    required int amountMinor,
    String? sourceAccountId,
    String? note,
    bool allowDirectDeposit = false,
  }) async {
    if (amountMinor <= 0) {
      return const FailureResult(
        ValidationFailure(message: 'Contribution amount must be positive.'),
      );
    }

    final goal =
        await (_db.select(_db.savingsGoals)..where(
              (g) => g.id.equals(goalId) & g.profileId.equals(profileId.value),
            ))
            .getSingleOrNull();
    if (goal == null) return const FailureResult(NotFoundFailure());

    final now = _clock.nowIsoUtc();
    String? linkedTxId;

    if (goal.fundingMode == 'account_transfer') {
      if (sourceAccountId == null || goal.linkedAccountId == null) {
        return const FailureResult(
          ValidationFailure(
            message:
                'Select a source account to transfer funds into the goal account.',
          ),
        );
      }
      final isDirectSameAccountDeposit =
          allowDirectDeposit && sourceAccountId == goal.linkedAccountId;
      if (!isDirectSameAccountDeposit) {
        final txRes = await _txRepo.createTransaction(
          profileId,
          CreateTransactionCommand(
            type: TransactionType.transfer,
            amountMinor: amountMinor,
            currencyCode: goal.currencyCode,
            transactionDateUtc: now,
            sourceAccountId: sourceAccountId,
            destinationAccountId: goal.linkedAccountId,
            description: note?.trim().isNotEmpty == true
                ? 'Goal (${goal.name}): ${note!.trim()}'
                : 'Savings goal contribution: ${goal.name}',
          ),
        );
        if (txRes.isFailure) return FailureResult(txRes.failureOrNull!);
        linkedTxId = txRes.valueOrNull!.id;
      }
    }

    try {
      await _db
          .into(_db.goalContributions)
          .insert(
            GoalContributionsCompanion.insert(
              id: _idGen.nextUuid(),
              profileId: profileId.value,
              goalId: goalId,
              transactionId: Value(linkedTxId),
              amountMinor: amountMinor,
              contributionType: 'deposit',
              contributedAtUtc: now,
              note: Value(note?.trim()),
            ),
          );

      final all = await listGoals(profileId);
      if (all.isFailure) return FailureResult(all.failureOrNull!);
      final updated = all.valueOrNull!.firstWhere((g) => g.id == goalId);
      if (updated.isCompleted && goal.status == 'active') {
        await (_db.update(
          _db.savingsGoals,
        )..where((g) => g.id.equals(goalId))).write(
          SavingsGoalsCompanion(
            status: const Value('completed'),
            updatedAtUtc: Value(now),
          ),
        );
      }
      return Success(updated);
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }
}
