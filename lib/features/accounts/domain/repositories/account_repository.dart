import '../../../../core/errors/failures.dart';
import '../../../../core/financial_engine/fx_rate.dart';
import '../../../../core/utilities/id_generator.dart';
import '../entities/financial_account_entity.dart';

abstract interface class AccountRepository {
  Stream<List<FinancialAccountEntity>> watchAccounts(
    ProfileId profileId, {
    bool includeArchived = false,
  });

  Future<Result<List<FinancialAccountEntity>>> listAccounts(
    ProfileId profileId, {
    bool includeArchived = false,
  });

  Future<Result<FinancialAccountEntity>> getAccount(
    ProfileId profileId,
    String accountId,
  );

  /// Creates the financial account, its 1:1 ledger account, and (when [openingBalanceMinor] > 0)
  /// a balanced Opening Balance Equity journal entry atomically (`FR-004`, `FR-005`).
  Future<Result<FinancialAccountEntity>> createAccountWithOpeningBalance({
    required ProfileId profileId,
    required String name,
    required FinancialAccountType accountType,
    required String currencyCode,
    int openingBalanceMinor = 0,
    FxRate? openingFxRate,
    String? institutionLabel,
    String? openingDateUtc,
    String createdByUserId = 'local-owner',
    bool queueSync = false,
  });

  Future<Result<FinancialAccountEntity>> updateAccount({
    required ProfileId profileId,
    required String accountId,
    required String name,
    String? institutionLabel,
    bool queueSync = false,
  });

  Future<Result<void>> archiveAccount({
    required ProfileId profileId,
    required String accountId,
    bool queueSync = false,
  });

  Future<Result<void>> unarchiveAccount({
    required ProfileId profileId,
    required String accountId,
    bool queueSync = false,
  });
}
