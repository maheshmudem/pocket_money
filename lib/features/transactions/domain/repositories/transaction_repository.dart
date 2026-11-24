import '../../../../core/errors/failures.dart';
import '../../../../core/utilities/id_generator.dart';
import '../entities/transaction_entity.dart';

abstract interface class TransactionRepository {
  Future<Result<TransactionEntity>> createTransaction(
    ProfileId profileId,
    CreateTransactionCommand command,
  );

  Future<Result<TransactionEntity>> getTransactionDetail(
    ProfileId profileId,
    String transactionId,
  );

  Future<Result<PaginatedTransactions>> queryTransactions(
    ProfileId profileId, {
    TransactionFilter filter = const TransactionFilter(),
    int limit = 50,
    int offset = 0,
  });

  Future<Result<TransactionEntity>> updateDraftTransaction(
    ProfileId profileId,
    String transactionId,
    CreateTransactionCommand updated,
  );

  Future<Result<void>> deleteDraftTransaction(
    ProfileId profileId,
    String transactionId,
  );

  Future<Result<TransactionEntity>> postDraftTransaction(
    ProfileId profileId,
    String transactionId, {
    bool queueSync = false,
  });

  /// Reverses a posted transaction via an immutable compensating journal (`FR-010`, `TC-FIN-011`).
  Future<Result<TransactionEntity>> reversePostedTransaction(
    ProfileId profileId, {
    required String originalTransactionId,
    required String reason,
    String actorUserId = 'local-owner',
    bool queueSync = false,
  });

  /// Verifies all posted journals balance (`SUM(debit) == SUM(credit)`) with zero orphans.
  Future<Result<LedgerReconciliationReport>> runReconciliationCheck(
    ProfileId profileId,
  );
}
