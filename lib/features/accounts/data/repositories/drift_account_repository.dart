import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/financial_engine/currency.dart';
import '../../../../core/financial_engine/double_entry_engine.dart';
import '../../../../core/financial_engine/fx_rate.dart';
import '../../../../core/financial_engine/money.dart';
import '../../../../core/utilities/clock.dart';
import '../../../../core/utilities/id_generator.dart';
import '../../../profiles/data/repositories/drift_profile_repository.dart';
import '../../domain/entities/financial_account_entity.dart';
import '../../domain/repositories/account_repository.dart';

final class DriftAccountRepository implements AccountRepository {
  DriftAccountRepository({
    required AppDatabase db,
    required IdGenerator idGenerator,
    required UtcClock clock,
  }) : _db = db,
       _idGen = idGenerator,
       _clock = clock;

  final AppDatabase _db;
  final IdGenerator _idGen;
  final UtcClock _clock;

  Selectable<QueryRow> _accountsSelect(
    ProfileId profileId, {
    bool includeArchived = false,
  }) {
    return _db.customSelect(
      '''
          SELECT
            fa.id,
            fa.profile_id,
            fa.ledger_account_id,
            fa.name,
            fa.account_type,
            fa.currency_code,
            fa.institution_label,
            fa.is_active,
            fa.created_at_utc,
            fa.updated_at_utc,
            fa.archived_at_utc,
            fa.version,
            fa.sync_status,
            p.base_currency_code,
            la.normal_balance,
            COALESCE(SUM(CASE WHEN je.status IN ('posted','reversed') AND lp.side = 'debit' THEN lp.original_amount_minor ELSE 0 END), 0) AS orig_debits,
            COALESCE(SUM(CASE WHEN je.status IN ('posted','reversed') AND lp.side = 'credit' THEN lp.original_amount_minor ELSE 0 END), 0) AS orig_credits,
            COALESCE(SUM(CASE WHEN je.status IN ('posted','reversed') AND lp.side = 'debit' THEN lp.base_amount_minor ELSE 0 END), 0) AS base_debits,
            COALESCE(SUM(CASE WHEN je.status IN ('posted','reversed') AND lp.side = 'credit' THEN lp.base_amount_minor ELSE 0 END), 0) AS base_credits
          FROM financial_accounts fa
          INNER JOIN profiles p ON p.id = fa.profile_id
          INNER JOIN ledger_accounts la ON la.id = fa.ledger_account_id AND la.profile_id = fa.profile_id
          LEFT JOIN ledger_postings lp ON lp.ledger_account_id = fa.ledger_account_id AND lp.profile_id = fa.profile_id
          LEFT JOIN journal_entries je ON je.id = lp.journal_entry_id AND je.profile_id = lp.profile_id
          WHERE fa.profile_id = ?
            AND fa.deleted_at_utc IS NULL
            ${includeArchived ? '' : 'AND fa.is_active = 1 AND fa.archived_at_utc IS NULL'}
          GROUP BY fa.id
          ORDER BY fa.created_at_utc ASC
          ''',
      variables: [Variable.withString(profileId.value)],
      readsFrom: {
        _db.financialAccounts,
        _db.profiles,
        _db.ledgerAccounts,
        _db.ledgerPostings,
        _db.journalEntries,
      },
    );
  }

  @override
  Stream<List<FinancialAccountEntity>> watchAccounts(
    ProfileId profileId, {
    bool includeArchived = false,
  }) {
    // Recompute derived ledger balances whenever accounts, journals, or postings change.
    return _accountsSelect(
      profileId,
      includeArchived: includeArchived,
    ).watch().map((rows) => rows.map(_mapRow).toList());
  }

  @override
  Future<Result<List<FinancialAccountEntity>>> listAccounts(
    ProfileId profileId, {
    bool includeArchived = false,
  }) async {
    try {
      final rows = await _accountsSelect(
        profileId,
        includeArchived: includeArchived,
      ).get();
      return Success(rows.map(_mapRow).toList());
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  @override
  Future<Result<FinancialAccountEntity>> getAccount(
    ProfileId profileId,
    String accountId,
  ) async {
    try {
      final rows = await _accountsSelect(
        profileId,
        includeArchived: true,
      ).get();
      for (final row in rows) {
        final a = _mapRow(row);
        if (a.id == accountId) return Success(a);
      }
      return const FailureResult(NotFoundFailure());
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  @override
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
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 80) {
      return const FailureResult(
        ValidationFailure(
          message: 'Account name must be between 1 and 80 characters.',
        ),
      );
    }
    if (openingBalanceMinor < 0) {
      return const FailureResult(
        ValidationFailure(message: 'Opening balance cannot be negative.'),
      );
    }

    final currCode = currencyCode.toUpperCase();
    final accCurr = CurrencyCatalog.byCode(currCode);
    if (accCurr == null) {
      return FailureResult(
        ValidationFailure(message: 'Unsupported currency: $currCode.'),
      );
    }

    final profileRow = await (_db.select(
      _db.profiles,
    )..where((p) => p.id.equals(profileId.value))).getSingleOrNull();
    if (profileRow == null) {
      return const FailureResult(AuthorizationFailure());
    }
    final baseCurr = CurrencyCatalog.requireByCode(profileRow.baseCurrencyCode);

    final now = _clock.nowIsoUtc();
    final effectiveUtc = openingDateUtc ?? now;
    final ledgerId = _idGen.nextUuid();
    final accountId = _idGen.nextUuid();

    // Pre-validate opening journal in pure domain BEFORE opening DB transaction.
    GeneratedJournal? openingJournal;
    if (openingBalanceMinor > 0) {
      final openingEquityRow =
          await (_db.select(_db.ledgerAccounts)..where(
                (l) =>
                    l.profileId.equals(profileId.value) &
                    l.systemCode.equals(SystemLedgerCodes.openingEquity),
              ))
              .getSingleOrNull();
      if (openingEquityRow == null) {
        return const FailureResult(
          LedgerInvariantFailure(
            message:
                'Opening Balance Equity system account missing for profile.',
          ),
        );
      }

      final journalRes = DoubleEntryEngine.buildOpeningBalance(
        profileId: profileId,
        accountLedgerType: accountType.ledgerType,
        accountLedgerId: ledgerId,
        openingEquityLedgerId: openingEquityRow.id,
        openingAmount: Money(
          amountMinor: openingBalanceMinor,
          currencyCode: currCode,
        ),
        accountCurrency: accCurr,
        baseCurrency: baseCurr,
        fxRate: openingFxRate,
        effectiveAtUtc: effectiveUtc,
      );
      if (journalRes.isFailure) return FailureResult(journalRes.failureOrNull!);
      openingJournal = journalRes.valueOrNull!;
    }

    final syncStatus = queueSync ? 'pending' : 'local_only';

    try {
      await _db.transaction(() async {
        await _db
            .into(_db.ledgerAccounts)
            .insert(
              LedgerAccountsCompanion.insert(
                id: ledgerId,
                profileId: profileId.value,
                name: trimmed,
                accountType: accountType.ledgerType.wireValue,
                normalBalance: accountType.ledgerType.normalBalance.wireValue,
                createdAtUtc: now,
              ),
            );

        await _db
            .into(_db.financialAccounts)
            .insert(
              FinancialAccountsCompanion.insert(
                id: accountId,
                profileId: profileId.value,
                ledgerAccountId: ledgerId,
                name: trimmed,
                accountType: accountType.wireValue,
                currencyCode: currCode,
                institutionLabel: Value(institutionLabel?.trim()),
                createdAtUtc: now,
                updatedAtUtc: now,
                syncStatus: Value(syncStatus),
              ),
            );

        if (openingJournal != null) {
          final txId = _idGen.nextUuid();
          final jeId = _idGen.nextUuid();

          await _db
              .into(_db.transactions)
              .insert(
                TransactionsCompanion.insert(
                  id: txId,
                  profileId: profileId.value,
                  transactionType: 'opening_balance',
                  status: 'posted',
                  transactionDateUtc: effectiveUtc,
                  amountMinor: openingBalanceMinor,
                  currencyCode: currCode,
                  baseCurrencyCode: baseCurr.code,
                  baseAmountMinor: openingJournal.baseAmountMinor,
                  fxRateScaled: openingJournal.appliedFxRate.rateScaled,
                  fxRateScale: openingJournal.appliedFxRate.rateScale,
                  fxRateSource: Value(openingJournal.appliedFxRate.source),
                  fxEffectiveAtUtc: Value(
                    openingJournal.appliedFxRate.effectiveAtUtc,
                  ),
                  fxRoundingMode: Value(
                    openingJournal.appliedFxRate.roundingMode.wireValue,
                  ),
                  destinationAccountId: accountType.isLiability
                      ? const Value.absent()
                      : Value(accountId),
                  sourceAccountId: accountType.isLiability
                      ? Value(accountId)
                      : const Value.absent(),
                  description: Value('Opening balance for $trimmed'),
                  createdByUserId: Value(createdByUserId),
                  createdAtUtc: now,
                  updatedAtUtc: now,
                  syncStatus: Value(syncStatus),
                ),
              );

          await _db
              .into(_db.journalEntries)
              .insert(
                JournalEntriesCompanion.insert(
                  id: jeId,
                  profileId: profileId.value,
                  transactionId: txId,
                  status: 'draft',
                  effectiveAtUtc: effectiveUtc,
                  createdAtUtc: now,
                ),
              );

          for (final posting in openingJournal.postings) {
            await _db
                .into(_db.ledgerPostings)
                .insert(
                  LedgerPostingsCompanion.insert(
                    id: _idGen.nextUuid(),
                    profileId: profileId.value,
                    journalEntryId: jeId,
                    ledgerAccountId: posting.ledgerAccountId,
                    side: posting.side.wireValue,
                    baseAmountMinor: posting.baseAmountMinor,
                    currencyCode: posting.currencyCode,
                    originalAmountMinor: posting.originalAmountMinor,
                  ),
                );
          }

          await (_db.update(_db.journalEntries)
                ..where((j) => j.id.equals(jeId)))
              .write(const JournalEntriesCompanion(status: Value('posted')));
        }

        if (queueSync) {
          final opId = _idGen.nextUuid();
          await _db
              .into(_db.syncOutbox)
              .insert(
                SyncOutboxCompanion.insert(
                  operationId: opId,
                  profileId: profileId.value,
                  entityType: 'financial_account',
                  entityId: accountId,
                  operationType: 'create',
                  payloadJson: jsonEncode({
                    'id': accountId,
                    'ledger_account_id': ledgerId,
                    'name': trimmed,
                    'account_type': accountType.wireValue,
                    'currency_code': currCode,
                    'opening_balance_minor': openingBalanceMinor,
                  }),
                  idempotencyKey: opId,
                  createdAtUtc: now,
                  status: 'pending',
                ),
              );
        }
      });

      return getAccount(profileId, accountId);
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  @override
  Future<Result<FinancialAccountEntity>> updateAccount({
    required ProfileId profileId,
    required String accountId,
    required String name,
    String? institutionLabel,
    bool queueSync = false,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 80) {
      return const FailureResult(
        ValidationFailure(message: 'Account name must be 1–80 characters.'),
      );
    }
    final existing = await getAccount(profileId, accountId);
    if (existing.isFailure) return existing;
    final acc = existing.valueOrNull!;
    final now = _clock.nowIsoUtc();

    try {
      await _db.transaction(() async {
        await (_db.update(_db.financialAccounts)..where(
              (t) =>
                  t.id.equals(accountId) & t.profileId.equals(profileId.value),
            ))
            .write(
              FinancialAccountsCompanion(
                name: Value(trimmed),
                institutionLabel: Value(institutionLabel?.trim()),
                updatedAtUtc: Value(now),
                version: Value(acc.version + 1),
                syncStatus: Value(queueSync ? 'pending' : acc.syncStatus),
              ),
            );
        await (_db.update(_db.ledgerAccounts)..where(
              (l) =>
                  l.id.equals(acc.ledgerAccountId) &
                  l.profileId.equals(profileId.value),
            ))
            .write(LedgerAccountsCompanion(name: Value(trimmed)));
      });
      return getAccount(profileId, accountId);
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  @override
  Future<Result<void>> archiveAccount({
    required ProfileId profileId,
    required String accountId,
    bool queueSync = false,
  }) async {
    final existing = await getAccount(profileId, accountId);
    if (existing.isFailure) return FailureResult(existing.failureOrNull!);
    final now = _clock.nowIsoUtc();
    try {
      await (_db.update(_db.financialAccounts)..where(
            (t) => t.id.equals(accountId) & t.profileId.equals(profileId.value),
          ))
          .write(
            FinancialAccountsCompanion(
              isActive: const Value(false),
              archivedAtUtc: Value(now),
              updatedAtUtc: Value(now),
              version: Value(existing.valueOrNull!.version + 1),
            ),
          );
      return const Success(null);
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  @override
  Future<Result<void>> unarchiveAccount({
    required ProfileId profileId,
    required String accountId,
    bool queueSync = false,
  }) async {
    final existing = await getAccount(profileId, accountId);
    if (existing.isFailure) return FailureResult(existing.failureOrNull!);
    final now = _clock.nowIsoUtc();
    try {
      await (_db.update(_db.financialAccounts)..where(
            (t) => t.id.equals(accountId) & t.profileId.equals(profileId.value),
          ))
          .write(
            FinancialAccountsCompanion(
              isActive: const Value(true),
              archivedAtUtc: const Value(null),
              updatedAtUtc: Value(now),
              version: Value(existing.valueOrNull!.version + 1),
            ),
          );
      return const Success(null);
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  FinancialAccountEntity _mapRow(QueryRow row) {
    final normalBalance = row.read<String>('normal_balance');
    final origDebits = row.read<int>('orig_debits');
    final origCredits = row.read<int>('orig_credits');
    final baseDebits = row.read<int>('base_debits');
    final baseCredits = row.read<int>('base_credits');

    final origBal = normalBalance == 'debit'
        ? origDebits - origCredits
        : origCredits - origDebits;
    final baseBal = normalBalance == 'debit'
        ? baseDebits - baseCredits
        : baseCredits - baseDebits;
    final curr = row.read<String>('currency_code');
    final baseCurr = row.read<String>('base_currency_code');

    return FinancialAccountEntity(
      id: row.read<String>('id'),
      profileId: ProfileId(row.read<String>('profile_id')),
      ledgerAccountId: row.read<String>('ledger_account_id'),
      name: row.read<String>('name'),
      accountType: FinancialAccountType.fromWire(
        row.read<String>('account_type'),
      ),
      currencyCode: curr,
      balance: Money(amountMinor: origBal, currencyCode: curr),
      baseBalance: Money(amountMinor: baseBal, currencyCode: baseCurr),
      institutionLabel: row.readNullable<String>('institution_label'),
      isActive: row.read<int>('is_active') == 1,
      createdAtUtc: row.read<String>('created_at_utc'),
      updatedAtUtc: row.read<String>('updated_at_utc'),
      archivedAtUtc: row.readNullable<String>('archived_at_utc'),
      version: row.read<int>('version'),
      syncStatus: row.read<String>('sync_status'),
    );
  }
}
