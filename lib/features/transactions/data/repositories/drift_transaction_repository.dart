import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/financial_engine/currency.dart';
import '../../../../core/financial_engine/double_entry_engine.dart';
import '../../../../core/financial_engine/fx_rate.dart';
import '../../../../core/financial_engine/money.dart';
import '../../../../core/logging/redacting_logger.dart';
import '../../../../core/utilities/clock.dart';
import '../../../../core/utilities/id_generator.dart';
import '../../../profiles/data/repositories/drift_profile_repository.dart';
import '../../domain/entities/transaction_entity.dart';
import '../../domain/repositories/transaction_repository.dart';

final class DriftTransactionRepository implements TransactionRepository {
  DriftTransactionRepository({
    required AppDatabase db,
    required IdGenerator idGenerator,
    required UtcClock clock,
    required RedactingLogger logger,
  }) : _db = db,
       _idGen = idGenerator,
       _clock = clock,
       _logger = logger;

  final AppDatabase _db;
  final IdGenerator _idGen;
  final UtcClock _clock;
  final RedactingLogger _logger;

  @override
  Future<Result<TransactionEntity>> createTransaction(
    ProfileId profileId,
    CreateTransactionCommand command,
  ) async {
    if (command.amountMinor <= 0) {
      return const FailureResult(
        ValidationFailure(message: 'Amount must be greater than zero.'),
      );
    }

    // Data-layer idempotency: if a clientTransactionId already exists in this profile, return it!
    if (command.clientTransactionId != null) {
      final existing =
          await (_db.select(_db.transactions)..where(
                (t) =>
                    t.id.equals(command.clientTransactionId!) &
                    t.profileId.equals(profileId.value),
              ))
              .getSingleOrNull();
      if (existing != null) {
        return getTransactionDetail(profileId, existing.id);
      }
    }

    final profileRow = await (_db.select(
      _db.profiles,
    )..where((p) => p.id.equals(profileId.value))).getSingleOrNull();
    if (profileRow == null) {
      return const FailureResult(AuthorizationFailure());
    }

    final currCode = command.currencyCode.toUpperCase();
    final origCurr = CurrencyCatalog.byCode(currCode);
    if (origCurr == null) {
      return FailureResult(
        ValidationFailure(message: 'Unsupported currency: $currCode.'),
      );
    }
    final baseCurr = CurrencyCatalog.requireByCode(profileRow.baseCurrencyCode);

    final txId = command.clientTransactionId ?? _idGen.nextUuid();
    final now = _clock.nowIsoUtc();
    final syncStatus = command.queueSync ? 'pending' : 'local_only';

    // Handle Draft saves (allowed even when FX rate is pending per `TC-FIN-015`).
    if (command.saveAsDraft) {
      final draftFx =
          command.fxRate ??
          FxRate.identity(currCode, command.transactionDateUtc);
      var draftBaseMinor = 0;
      if (currCode == baseCurr.code) {
        draftBaseMinor = command.amountMinor;
      } else if (command.fxRate != null) {
        final conv = CurrencyConverter.convert(
          original: Money(
            amountMinor: command.amountMinor,
            currencyCode: currCode,
          ),
          originalSpec: origCurr,
          targetSpec: baseCurr,
          fxRate: command.fxRate,
          fallbackEffectiveAtUtc: command.transactionDateUtc,
          requirePositiveResult: false,
        );
        if (conv.isSuccess) {
          draftBaseMinor = conv.valueOrNull!.convertedAmount.amountMinor;
        }
      }

      try {
        await _db.transaction(() async {
          await _db
              .into(_db.transactions)
              .insert(
                TransactionsCompanion.insert(
                  id: txId,
                  profileId: profileId.value,
                  transactionType: command.type.wireValue,
                  status: 'draft',
                  transactionDateUtc: command.transactionDateUtc,
                  amountMinor: command.amountMinor,
                  currencyCode: currCode,
                  destinationAmountMinor: Value(command.destinationAmountMinor),
                  destinationCurrencyCode: Value(
                    command.destinationCurrencyCode?.toUpperCase(),
                  ),
                  baseCurrencyCode: baseCurr.code,
                  baseAmountMinor: draftBaseMinor,
                  fxRateScaled: draftFx.rateScaled,
                  fxRateScale: draftFx.rateScale,
                  fxRateSource: Value(draftFx.source),
                  fxEffectiveAtUtc: Value(draftFx.effectiveAtUtc),
                  fxRoundingMode: Value(draftFx.roundingMode.wireValue),
                  sourceAccountId: Value(command.sourceAccountId),
                  destinationAccountId: Value(command.destinationAccountId),
                  categoryId: Value(command.categoryId),
                  relatedTransactionId: Value(command.relatedTransactionId),
                  importBatchId: Value(command.importBatchId),
                  externalRef: Value(command.externalRef),
                  description: Value(command.description?.trim()),
                  createdByUserId: Value(command.createdByUserId),
                  createdAtUtc: now,
                  updatedAtUtc: now,
                  syncStatus: Value(syncStatus),
                ),
              );

          for (final split in command.splits) {
            await _db
                .into(_db.transactionSplits)
                .insert(
                  TransactionSplitsCompanion.insert(
                    id: _idGen.nextUuid(),
                    profileId: profileId.value,
                    transactionId: txId,
                    categoryId: split.categoryId,
                    amountMinor: split.amountMinor,
                    baseAmountMinor: split.amountMinor,
                    memo: Value(split.memo),
                  ),
                );
          }
        });
        return getTransactionDetail(profileId, txId);
      } catch (_) {
        return const FailureResult(DatabaseFailure());
      }
    }

    // Build and validate authoritative double-entry journal in Pure Dart domain BEFORE DB write.
    final journalRes = await _buildDomainJournal(
      profileId: profileId,
      baseCurr: baseCurr,
      origCurr: origCurr,
      command: command,
    );
    if (journalRes.isFailure) return FailureResult(journalRes.failureOrNull!);
    final journal = journalRes.valueOrNull!;

    try {
      await _db.transaction(() async {
        await _db
            .into(_db.transactions)
            .insert(
              TransactionsCompanion.insert(
                id: txId,
                profileId: profileId.value,
                transactionType: command.type.wireValue,
                status: 'posted',
                transactionDateUtc: command.transactionDateUtc,
                amountMinor: command.amountMinor,
                currencyCode: currCode,
                destinationAmountMinor: Value(command.destinationAmountMinor),
                destinationCurrencyCode: Value(
                  command.destinationCurrencyCode?.toUpperCase(),
                ),
                baseCurrencyCode: baseCurr.code,
                baseAmountMinor: journal.baseAmountMinor,
                fxRateScaled: journal.appliedFxRate.rateScaled,
                fxRateScale: journal.appliedFxRate.rateScale,
                fxRateSource: Value(journal.appliedFxRate.source),
                fxEffectiveAtUtc: Value(journal.appliedFxRate.effectiveAtUtc),
                fxRoundingMode: Value(
                  journal.appliedFxRate.roundingMode.wireValue,
                ),
                sourceAccountId: Value(command.sourceAccountId),
                destinationAccountId: Value(command.destinationAccountId),
                categoryId: Value(
                  journal.resolvedSplits.isEmpty ? command.categoryId : null,
                ),
                relatedTransactionId: Value(command.relatedTransactionId),
                importBatchId: Value(command.importBatchId),
                externalRef: Value(command.externalRef),
                description: Value(command.description?.trim()),
                createdByUserId: Value(command.createdByUserId),
                createdAtUtc: now,
                updatedAtUtc: now,
                syncStatus: Value(syncStatus),
              ),
            );

        for (final split in journal.resolvedSplits) {
          await _db
              .into(_db.transactionSplits)
              .insert(
                TransactionSplitsCompanion.insert(
                  id: _idGen.nextUuid(),
                  profileId: profileId.value,
                  transactionId: txId,
                  categoryId: split.categoryId,
                  amountMinor: split.amountMinor,
                  baseAmountMinor: split.baseAmountMinor,
                  memo: Value(split.memo),
                ),
              );
        }

        final jeId = _idGen.nextUuid();
        await _db
            .into(_db.journalEntries)
            .insert(
              JournalEntriesCompanion.insert(
                id: jeId,
                profileId: profileId.value,
                transactionId: txId,
                status: 'draft',
                effectiveAtUtc: command.transactionDateUtc,
                createdAtUtc: now,
              ),
            );

        for (final posting in journal.postings) {
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

        // Transition draft -> posted (triggers SQLite balance & >=2 postings check).
        await (_db.update(_db.journalEntries)..where((j) => j.id.equals(jeId)))
            .write(const JournalEntriesCompanion(status: Value('posted')));

        if (command.queueSync) {
          final opId = command.idempotencyKey ?? _idGen.nextUuid();
          await _db
              .into(_db.syncOutbox)
              .insert(
                SyncOutboxCompanion.insert(
                  operationId: opId,
                  profileId: profileId.value,
                  entityType: 'transaction',
                  entityId: txId,
                  operationType: 'create',
                  payloadJson: jsonEncode({
                    'id': txId,
                    'transaction_type': command.type.wireValue,
                    'status': 'posted',
                    'transaction_date_utc': command.transactionDateUtc,
                    'amount_minor': command.amountMinor,
                    'currency_code': currCode,
                    'base_currency_code': baseCurr.code,
                    'base_amount_minor': journal.baseAmountMinor,
                    'fx_rate_scaled': journal.appliedFxRate.rateScaled,
                    'fx_rate_scale': journal.appliedFxRate.rateScale,
                    'source_account_id': command.sourceAccountId,
                    'destination_account_id': command.destinationAccountId,
                    'category_id': command.categoryId,
                    'related_transaction_id': command.relatedTransactionId,
                    'description': command.description?.trim(),
                    'journal_entry_id': jeId,
                    'postings': journal.postings
                        .map(
                          (p) => {
                            'ledger_account_id': p.ledgerAccountId,
                            'side': p.side.wireValue,
                            'base_amount_minor': p.baseAmountMinor,
                            'currency_code': p.currencyCode,
                            'original_amount_minor': p.originalAmountMinor,
                          },
                        )
                        .toList(),
                  }),
                  idempotencyKey: opId,
                  createdAtUtc: now,
                  status: 'pending',
                ),
              );
        }
      });

      _logger.info(
        'transactions',
        'transaction_posted',
        metadata: {
          'transaction_type': command.type.wireValue,
          'currency_code': currCode,
          'split_count': journal.resolvedSplits.length,
        },
      );

      return getTransactionDetail(profileId, txId);
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  Future<Result<GeneratedJournal>> _buildDomainJournal({
    required ProfileId profileId,
    required CurrencySpec baseCurr,
    required CurrencySpec origCurr,
    required CreateTransactionCommand command,
  }) async {
    final money = Money(
      amountMinor: command.amountMinor,
      currencyCode: origCurr.code,
    );

    switch (command.type) {
      case TransactionType.income:
        if (command.destinationAccountId == null) {
          return const FailureResult(
            ValidationFailure(
              message: 'Select a destination account for income.',
            ),
          );
        }
        if (command.categoryId == null) {
          return const FailureResult(
            ValidationFailure(message: 'Select an income category.'),
          );
        }
        final destAcc = await _requireActiveAccount(
          profileId,
          command.destinationAccountId!,
        );
        if (destAcc.isFailure) return FailureResult(destAcc.failureOrNull!);
        final cat = await _requireCategory(profileId, command.categoryId!);
        if (cat.isFailure) return FailureResult(cat.failureOrNull!);
        if (cat.valueOrNull!.categoryType != 'income') {
          return const FailureResult(
            ValidationFailure(
              message: 'Selected category must be an income category.',
            ),
          );
        }

        return DoubleEntryEngine.buildIncome(
          profileId: profileId,
          destinationLedgerAccountId: destAcc.valueOrNull!.ledgerAccountId,
          incomeCategoryLedgerAccountId: cat.valueOrNull!.ledgerAccountId,
          amount: money,
          amountCurrency: origCurr,
          baseCurrency: baseCurr,
          fxRate: command.fxRate,
          effectiveAtUtc: command.transactionDateUtc,
        );

      case TransactionType.expense:
        if (command.sourceAccountId == null) {
          return const FailureResult(
            ValidationFailure(message: 'Select a source account for expense.'),
          );
        }
        final srcAcc = await _requireActiveAccount(
          profileId,
          command.sourceAccountId!,
        );
        if (srcAcc.isFailure) return FailureResult(srcAcc.failureOrNull!);

        if (command.splits.isNotEmpty) {
          final splitInputs = <SplitLineInput>[];
          for (final s in command.splits) {
            final catRes = await _requireCategory(profileId, s.categoryId);
            if (catRes.isFailure) return FailureResult(catRes.failureOrNull!);
            if (catRes.valueOrNull!.categoryType != 'expense') {
              return const FailureResult(
                ValidationFailure(
                  message:
                      'All split categories on an expense must be expense categories.',
                ),
              );
            }
            splitInputs.add(
              SplitLineInput(
                categoryId: s.categoryId,
                categoryLedgerAccountId: catRes.valueOrNull!.ledgerAccountId,
                amountMinor: s.amountMinor,
                memo: s.memo,
              ),
            );
          }
          return DoubleEntryEngine.buildExpense(
            profileId: profileId,
            sourceLedgerAccountId: srcAcc.valueOrNull!.ledgerAccountId,
            categoryLedgerAccountId: null,
            amount: money,
            amountCurrency: origCurr,
            baseCurrency: baseCurr,
            fxRate: command.fxRate,
            effectiveAtUtc: command.transactionDateUtc,
            splits: splitInputs,
          );
        } else {
          if (command.categoryId == null) {
            return const FailureResult(
              ValidationFailure(message: 'Select an expense category.'),
            );
          }
          final cat = await _requireCategory(profileId, command.categoryId!);
          if (cat.isFailure) return FailureResult(cat.failureOrNull!);
          if (cat.valueOrNull!.categoryType != 'expense') {
            return const FailureResult(
              ValidationFailure(
                message: 'Selected category must be an expense category.',
              ),
            );
          }
          return DoubleEntryEngine.buildExpense(
            profileId: profileId,
            sourceLedgerAccountId: srcAcc.valueOrNull!.ledgerAccountId,
            categoryLedgerAccountId: cat.valueOrNull!.ledgerAccountId,
            amount: money,
            amountCurrency: origCurr,
            baseCurrency: baseCurr,
            fxRate: command.fxRate,
            effectiveAtUtc: command.transactionDateUtc,
          );
        }

      case TransactionType.transfer:
        if (command.sourceAccountId == null ||
            command.destinationAccountId == null) {
          return const FailureResult(
            ValidationFailure(
              message:
                  'Select both source and destination accounts for a transfer.',
            ),
          );
        }
        if (command.sourceAccountId == command.destinationAccountId) {
          return const FailureResult(
            ValidationFailure(
              message: 'Source and destination accounts must be different.',
            ),
          );
        }
        final srcAcc = await _requireActiveAccount(
          profileId,
          command.sourceAccountId!,
        );
        if (srcAcc.isFailure) return FailureResult(srcAcc.failureOrNull!);
        final dstAcc = await _requireActiveAccount(
          profileId,
          command.destinationAccountId!,
        );
        if (dstAcc.isFailure) return FailureResult(dstAcc.failureOrNull!);

        final dstCurrCode =
            (command.destinationCurrencyCode ??
                    dstAcc.valueOrNull!.currencyCode)
                .toUpperCase();
        final dstCurr = CurrencyCatalog.byCode(dstCurrCode);
        if (dstCurr == null) {
          return FailureResult(
            ValidationFailure(
              message: 'Unsupported destination currency: $dstCurrCode.',
            ),
          );
        }
        final dstAmountMinor =
            command.destinationAmountMinor ?? command.amountMinor;
        final fxVarLedger =
            await (_db.select(_db.ledgerAccounts)..where(
                  (l) =>
                      l.profileId.equals(profileId.value) &
                      l.systemCode.equals(SystemLedgerCodes.fxVariance),
                ))
                .getSingleOrNull();

        return DoubleEntryEngine.buildTransfer(
          profileId: profileId,
          sourceLedgerAccountId: srcAcc.valueOrNull!.ledgerAccountId,
          destinationLedgerAccountId: dstAcc.valueOrNull!.ledgerAccountId,
          sourceAmount: money,
          sourceCurrency: origCurr,
          destinationAmount: Money(
            amountMinor: dstAmountMinor,
            currencyCode: dstCurrCode,
          ),
          destinationCurrency: dstCurr,
          baseCurrency: baseCurr,
          sourceToBaseRate: command.fxRate,
          destinationToBaseRate: command.destinationFxRate ?? command.fxRate,
          fxVarianceLedgerAccountId: fxVarLedger?.id,
          effectiveAtUtc: command.transactionDateUtc,
        );

      case TransactionType.refund:
        if (command.destinationAccountId == null ||
            command.categoryId == null) {
          return const FailureResult(
            ValidationFailure(
              message:
                  'Refund requires a destination account and original expense category.',
            ),
          );
        }
        final destAcc = await _requireActiveAccount(
          profileId,
          command.destinationAccountId!,
        );
        if (destAcc.isFailure) return FailureResult(destAcc.failureOrNull!);
        final cat = await _requireCategory(profileId, command.categoryId!);
        if (cat.isFailure) return FailureResult(cat.failureOrNull!);

        return DoubleEntryEngine.buildRefund(
          profileId: profileId,
          destinationLedgerAccountId: destAcc.valueOrNull!.ledgerAccountId,
          expenseCategoryLedgerAccountId: cat.valueOrNull!.ledgerAccountId,
          refundAmount: money,
          amountCurrency: origCurr,
          baseCurrency: baseCurr,
          fxRate: command.fxRate,
          effectiveAtUtc: command.transactionDateUtc,
        );

      case TransactionType.openingBalance:
      case TransactionType.adjustment:
        return const FailureResult(
          ValidationFailure(
            message:
                'Use account opening balance or reversal flows for opening/adjustment entries.',
          ),
        );
    }
  }

  @override
  Future<Result<TransactionEntity>> getTransactionDetail(
    ProfileId profileId,
    String transactionId,
  ) async {
    try {
      final row =
          await (_db.select(_db.transactions)..where(
                (t) =>
                    t.id.equals(transactionId) &
                    t.profileId.equals(profileId.value) &
                    t.deletedAtUtc.isNull(),
              ))
              .getSingleOrNull();
      if (row == null) return const FailureResult(NotFoundFailure());

      final accountsMap = await _accountNamesMap(profileId);
      final categoriesMap = await _categoryNamesMap(profileId);
      final ledgerNamesMap = await _ledgerNamesMap(profileId);

      final splitRows =
          await (_db.select(_db.transactionSplits)..where(
                (s) =>
                    s.transactionId.equals(transactionId) &
                    s.profileId.equals(profileId.value),
              ))
              .get();

      final jeRow =
          await (_db.select(_db.journalEntries)
                ..where(
                  (j) =>
                      j.transactionId.equals(transactionId) &
                      j.profileId.equals(profileId.value),
                )
                ..orderBy([(j) => OrderingTerm.desc(j.createdAtUtc)])
                ..limit(1))
              .getSingleOrNull();

      final postings = <PostingDetail>[];
      if (jeRow != null) {
        final pRows =
            await (_db.select(_db.ledgerPostings)..where(
                  (p) =>
                      p.journalEntryId.equals(jeRow.id) &
                      p.profileId.equals(profileId.value),
                ))
                .get();
        for (final p in pRows) {
          postings.add(
            PostingDetail(
              id: p.id,
              ledgerAccountId: p.ledgerAccountId,
              ledgerAccountName:
                  ledgerNamesMap[p.ledgerAccountId] ?? 'Ledger Account',
              side: PostingSide.fromWire(p.side),
              baseAmountMinor: p.baseAmountMinor,
              currencyCode: p.currencyCode,
              originalAmountMinor: p.originalAmountMinor,
            ),
          );
        }
      }

      return Success(
        _mapTransaction(
          row,
          accountsMap: accountsMap,
          categoriesMap: categoriesMap,
          splits: splitRows
              .map(
                (s) => TransactionSplitEntity(
                  id: s.id,
                  categoryId: s.categoryId,
                  categoryName: categoriesMap[s.categoryId] ?? 'Category',
                  amountMinor: s.amountMinor,
                  baseAmountMinor: s.baseAmountMinor,
                  memo: s.memo,
                ),
              )
              .toList(),
          postings: postings,
          journalStatus: jeRow?.status,
        ),
      );
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  @override
  Future<Result<PaginatedTransactions>> queryTransactions(
    ProfileId profileId, {
    TransactionFilter filter = const TransactionFilter(),
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      Expression<bool> buildWhere($TransactionsTable t) {
        Expression<bool> cond =
            t.profileId.equals(profileId.value) & t.deletedAtUtc.isNull();
        if (filter.accountId != null) {
          cond =
              cond &
              (t.sourceAccountId.equals(filter.accountId!) |
                  t.destinationAccountId.equals(filter.accountId!));
        }
        if (filter.categoryId != null) {
          cond = cond & t.categoryId.equals(filter.categoryId!);
        }
        if (filter.type != null) {
          cond = cond & t.transactionType.equals(filter.type!.wireValue);
        }
        if (filter.status != null) {
          cond = cond & t.status.equals(filter.status!.wireValue);
        }
        if (filter.fromUtc != null) {
          cond =
              cond & t.transactionDateUtc.isBiggerOrEqualValue(filter.fromUtc!);
        }
        if (filter.toUtc != null) {
          cond =
              cond & t.transactionDateUtc.isSmallerOrEqualValue(filter.toUtc!);
        }
        final q = filter.searchQuery?.trim();
        if (q != null && q.isNotEmpty) {
          cond =
              cond &
              (t.description.contains(q) |
                  t.externalRef.contains(q) |
                  t.transactionType.contains(q));
        }
        return cond;
      }

      final countExpr = _db.transactions.id.count();
      final countQuery = _db.selectOnly(_db.transactions)
        ..addColumns([countExpr])
        ..where(buildWhere(_db.transactions));
      final totalCount = (await countQuery.getSingle()).read(countExpr) ?? 0;

      final rows =
          await (_db.select(_db.transactions)
                ..where(buildWhere)
                ..orderBy([
                  (t) => OrderingTerm.desc(t.transactionDateUtc),
                  (t) => OrderingTerm.desc(t.createdAtUtc),
                ])
                ..limit(limit, offset: offset))
              .get();

      final accountsMap = await _accountNamesMap(profileId);
      final categoriesMap = await _categoryNamesMap(profileId);

      // Load journal statuses & split lines for the page in two batch queries.
      final txIds = rows.map((r) => r.id).toList();
      final jeStatusMap = <String, String>{};
      final splitsMap = <String, List<TransactionSplitEntity>>{};
      if (txIds.isNotEmpty) {
        final jes =
            await (_db.select(_db.journalEntries)..where(
                  (j) =>
                      j.profileId.equals(profileId.value) &
                      j.transactionId.isIn(txIds),
                ))
                .get();
        for (final j in jes) {
          jeStatusMap[j.transactionId] = j.status;
        }
        final splitRows =
            await (_db.select(_db.transactionSplits)..where(
                  (s) =>
                      s.profileId.equals(profileId.value) &
                      s.transactionId.isIn(txIds),
                ))
                .get();
        for (final s in splitRows) {
          splitsMap
              .putIfAbsent(s.transactionId, () => <TransactionSplitEntity>[])
              .add(
                TransactionSplitEntity(
                  id: s.id,
                  categoryId: s.categoryId,
                  categoryName: categoriesMap[s.categoryId] ?? 'Category',
                  amountMinor: s.amountMinor,
                  baseAmountMinor: s.baseAmountMinor,
                  memo: s.memo,
                ),
              );
        }
      }

      final items = rows
          .map(
            (r) => _mapTransaction(
              r,
              accountsMap: accountsMap,
              categoriesMap: categoriesMap,
              splits: splitsMap[r.id] ?? const [],
              journalStatus: jeStatusMap[r.id],
            ),
          )
          .toList();

      return Success(
        PaginatedTransactions(
          items: items,
          totalCount: totalCount,
          hasMore: offset + items.length < totalCount,
        ),
      );
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  @override
  Future<Result<TransactionEntity>> updateDraftTransaction(
    ProfileId profileId,
    String transactionId,
    CreateTransactionCommand updated,
  ) async {
    final existing =
        await (_db.select(_db.transactions)..where(
              (t) =>
                  t.id.equals(transactionId) &
                  t.profileId.equals(profileId.value),
            ))
            .getSingleOrNull();
    if (existing == null) return const FailureResult(NotFoundFailure());
    if (existing.status != 'draft') {
      return const FailureResult(
        ValidationFailure(
          message:
              'Posted transactions are immutable. Create a reversal or refund instead.',
        ),
      );
    }

    final now = _clock.nowIsoUtc();
    try {
      await _db.transaction(() async {
        await (_db.update(_db.transactions)..where(
              (t) =>
                  t.id.equals(transactionId) &
                  t.profileId.equals(profileId.value),
            ))
            .write(
              TransactionsCompanion(
                transactionType: Value(updated.type.wireValue),
                transactionDateUtc: Value(updated.transactionDateUtc),
                amountMinor: Value(updated.amountMinor),
                currencyCode: Value(updated.currencyCode.toUpperCase()),
                sourceAccountId: Value(updated.sourceAccountId),
                destinationAccountId: Value(updated.destinationAccountId),
                categoryId: Value(updated.categoryId),
                description: Value(updated.description?.trim()),
                updatedAtUtc: Value(now),
                version: Value(existing.version + 1),
              ),
            );
      });
      return getTransactionDetail(profileId, transactionId);
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  @override
  Future<Result<void>> deleteDraftTransaction(
    ProfileId profileId,
    String transactionId,
  ) async {
    final existing =
        await (_db.select(_db.transactions)..where(
              (t) =>
                  t.id.equals(transactionId) &
                  t.profileId.equals(profileId.value),
            ))
            .getSingleOrNull();
    if (existing == null) return const FailureResult(NotFoundFailure());
    if (existing.status != 'draft') {
      return const FailureResult(
        ValidationFailure(
          message:
              'Posted transactions cannot be deleted. Use Reversal to maintain ledger integrity.',
        ),
      );
    }

    try {
      await _db.transaction(() async {
        await (_db.delete(_db.transactionSplits)..where(
              (s) =>
                  s.transactionId.equals(transactionId) &
                  s.profileId.equals(profileId.value),
            ))
            .go();
        await (_db.delete(_db.transactions)..where(
              (t) =>
                  t.id.equals(transactionId) &
                  t.profileId.equals(profileId.value),
            ))
            .go();
      });
      return const Success(null);
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  @override
  Future<Result<TransactionEntity>> postDraftTransaction(
    ProfileId profileId,
    String transactionId, {
    bool queueSync = false,
  }) async {
    final draftRes = await getTransactionDetail(profileId, transactionId);
    if (draftRes.isFailure) return draftRes;
    final draft = draftRes.valueOrNull!;
    if (draft.status != TransactionStatus.draft) {
      return const FailureResult(
        ValidationFailure(message: 'Only draft transactions can be posted.'),
      );
    }

    final fxRate = draft.amount.currencyCode == draft.baseAmount.currencyCode
        ? null
        : FxRate(
            fromCurrencyCode: draft.amount.currencyCode,
            toCurrencyCode: draft.baseAmount.currencyCode,
            rateScaled: draft.fxRateScaled,
            rateScale: draft.fxRateScale,
            source: draft.fxRateSource,
            effectiveAtUtc: draft.transactionDateUtc,
          );

    // Replace draft safely with posted record via atomic DB transaction.
    final del = await deleteDraftTransaction(profileId, transactionId);
    if (del.isFailure) return FailureResult(del.failureOrNull!);

    return createTransaction(
      profileId,
      CreateTransactionCommand(
        clientTransactionId: transactionId,
        type: draft.type,
        amountMinor: draft.amount.amountMinor,
        currencyCode: draft.amount.currencyCode,
        destinationAmountMinor: draft.destinationAmount?.amountMinor,
        destinationCurrencyCode: draft.destinationAmount?.currencyCode,
        transactionDateUtc: draft.transactionDateUtc,
        sourceAccountId: draft.sourceAccountId,
        destinationAccountId: draft.destinationAccountId,
        categoryId: draft.categoryId,
        relatedTransactionId: draft.relatedTransactionId,
        description: draft.description,
        fxRate: fxRate,
        splits: draft.splits
            .map(
              (s) => SplitCommandLine(
                categoryId: s.categoryId,
                amountMinor: s.amountMinor,
                memo: s.memo,
              ),
            )
            .toList(),
        saveAsDraft: false,
        queueSync: queueSync,
      ),
    );
  }

  @override
  Future<Result<TransactionEntity>> reversePostedTransaction(
    ProfileId profileId, {
    required String originalTransactionId,
    required String reason,
    String actorUserId = 'local-owner',
    bool queueSync = false,
  }) async {
    final origTx =
        await (_db.select(_db.transactions)..where(
              (t) =>
                  t.id.equals(originalTransactionId) &
                  t.profileId.equals(profileId.value),
            ))
            .getSingleOrNull();
    if (origTx == null) return const FailureResult(NotFoundFailure());
    if (origTx.status != 'posted') {
      return const FailureResult(
        ValidationFailure(message: 'Only posted transactions can be reversed.'),
      );
    }

    final origJe =
        await (_db.select(_db.journalEntries)..where(
              (j) =>
                  j.transactionId.equals(originalTransactionId) &
                  j.profileId.equals(profileId.value),
            ))
            .getSingleOrNull();
    if (origJe == null) {
      return const FailureResult(
        LedgerInvariantFailure(message: 'Original journal entry not found.'),
      );
    }
    if (origJe.status == 'reversed') {
      return const FailureResult(
        ValidationFailure(
          message: 'This transaction has already been reversed.',
        ),
      );
    }

    final origPostings =
        await (_db.select(_db.ledgerPostings)..where(
              (p) =>
                  p.journalEntryId.equals(origJe.id) &
                  p.profileId.equals(profileId.value),
            ))
            .get();

    final now = _clock.nowIsoUtc();
    final reversalDomain = DoubleEntryEngine.buildReversal(
      profileId: profileId,
      originalJournalEntryId: origJe.id,
      baseCurrencyCode: origTx.baseCurrencyCode,
      originalPostings: origPostings
          .map(
            (p) => LedgerPostingSpec(
              ledgerAccountId: p.ledgerAccountId,
              side: PostingSide.fromWire(p.side),
              baseAmountMinor: p.baseAmountMinor,
              currencyCode: p.currencyCode,
              originalAmountMinor: p.originalAmountMinor,
            ),
          )
          .toList(),
      effectiveAtUtc: now,
    );
    if (reversalDomain.isFailure) {
      return FailureResult(reversalDomain.failureOrNull!);
    }
    final revJournal = reversalDomain.valueOrNull!;
    final revTxId = _idGen.nextUuid();
    final revJeId = _idGen.nextUuid();
    final syncStatus = queueSync ? 'pending' : 'local_only';

    try {
      await _db.transaction(() async {
        // 1. Mark original journal as reversed (allowed by immutability trigger).
        await (_db.update(_db.journalEntries)
              ..where((j) => j.id.equals(origJe.id)))
            .write(const JournalEntriesCompanion(status: Value('reversed')));

        // 2. Insert compensating adjustment transaction linked to original.
        await _db
            .into(_db.transactions)
            .insert(
              TransactionsCompanion.insert(
                id: revTxId,
                profileId: profileId.value,
                transactionType: 'adjustment',
                status: 'posted',
                transactionDateUtc: now,
                amountMinor: origTx.amountMinor,
                currencyCode: origTx.currencyCode,
                baseCurrencyCode: origTx.baseCurrencyCode,
                baseAmountMinor: revJournal.baseAmountMinor,
                fxRateScaled: origTx.fxRateScaled,
                fxRateScale: origTx.fxRateScale,
                fxRateSource: Value(origTx.fxRateSource),
                sourceAccountId: Value(origTx.destinationAccountId),
                destinationAccountId: Value(origTx.sourceAccountId),
                categoryId: Value(origTx.categoryId),
                relatedTransactionId: Value(origTx.id),
                description: Value(
                  'Reversal: ${reason.trim().isEmpty ? 'Correction' : reason.trim()}',
                ),
                createdByUserId: Value(actorUserId),
                createdAtUtc: now,
                updatedAtUtc: now,
                syncStatus: Value(syncStatus),
              ),
            );

        // 3. Insert compensating journal + mirror postings, then post.
        await _db
            .into(_db.journalEntries)
            .insert(
              JournalEntriesCompanion.insert(
                id: revJeId,
                profileId: profileId.value,
                transactionId: revTxId,
                status: 'draft',
                effectiveAtUtc: now,
                createdAtUtc: now,
                reversesJournalEntryId: Value(origJe.id),
              ),
            );

        for (final p in revJournal.postings) {
          await _db
              .into(_db.ledgerPostings)
              .insert(
                LedgerPostingsCompanion.insert(
                  id: _idGen.nextUuid(),
                  profileId: profileId.value,
                  journalEntryId: revJeId,
                  ledgerAccountId: p.ledgerAccountId,
                  side: p.side.wireValue,
                  baseAmountMinor: p.baseAmountMinor,
                  currencyCode: p.currencyCode,
                  originalAmountMinor: p.originalAmountMinor,
                ),
              );
        }

        await (_db.update(_db.journalEntries)
              ..where((j) => j.id.equals(revJeId)))
            .write(const JournalEntriesCompanion(status: Value('posted')));

        await _db
            .into(_db.auditLogs)
            .insert(
              AuditLogsCompanion.insert(
                id: _idGen.nextUuid(),
                profileId: Value(profileId.value),
                actorUserId: actorUserId,
                action: 'ledger.journal_reversed',
                targetType: 'transaction',
                targetId: origTx.id,
                outcome: 'success',
                metadataRedactedJson: Value(
                  jsonEncode({'reversal_tx_id': revTxId}),
                ),
                createdAtUtc: now,
              ),
            );

        if (queueSync) {
          final opId = _idGen.nextUuid();
          await _db
              .into(_db.syncOutbox)
              .insert(
                SyncOutboxCompanion.insert(
                  operationId: opId,
                  profileId: profileId.value,
                  entityType: 'transaction_reversal',
                  entityId: revTxId,
                  operationType: 'create',
                  payloadJson: jsonEncode({
                    'reversal_transaction_id': revTxId,
                    'original_transaction_id': origTx.id,
                    'reversal_journal_entry_id': revJeId,
                    'original_journal_entry_id': origJe.id,
                  }),
                  idempotencyKey: opId,
                  createdAtUtc: now,
                  status: 'pending',
                ),
              );
        }
      });

      return getTransactionDetail(profileId, revTxId);
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  @override
  Future<Result<LedgerReconciliationReport>> runReconciliationCheck(
    ProfileId profileId,
  ) async {
    try {
      final rows = await _db
          .customSelect(
            '''
        SELECT
          je.id AS journal_id,
          COALESCE(SUM(CASE WHEN lp.side = 'debit' THEN lp.base_amount_minor ELSE 0 END), 0) AS debits,
          COALESCE(SUM(CASE WHEN lp.side = 'credit' THEN lp.base_amount_minor ELSE 0 END), 0) AS credits,
          COUNT(lp.id) AS posting_count
        FROM journal_entries je
        LEFT JOIN ledger_postings lp ON lp.journal_entry_id = je.id AND lp.profile_id = je.profile_id
        WHERE je.profile_id = ? AND je.status IN ('posted', 'reversed')
        GROUP BY je.id
        ''',
            variables: [Variable.withString(profileId.value)],
          )
          .get();

      final unbalanced = <String>[];
      var totalDebits = 0;
      var totalCredits = 0;
      for (final r in rows) {
        final d = r.read<int>('debits');
        final c = r.read<int>('credits');
        final cnt = r.read<int>('posting_count');
        totalDebits += d;
        totalCredits += c;
        if (cnt < 2 || d != c || d <= 0) {
          unbalanced.add(r.read<String>('journal_id'));
        }
      }

      final orphanRow = await _db
          .customSelect(
            '''
        SELECT COUNT(*) AS cnt
        FROM ledger_postings lp
        LEFT JOIN journal_entries je ON je.id = lp.journal_entry_id AND je.profile_id = lp.profile_id
        WHERE lp.profile_id = ? AND je.id IS NULL
        ''',
            variables: [Variable.withString(profileId.value)],
          )
          .getSingle();

      return Success(
        LedgerReconciliationReport(
          profileId: profileId,
          checkedAtUtc: _clock.nowIsoUtc(),
          postedJournalCount: rows.length,
          unbalancedJournalIds: unbalanced,
          orphanPostingCount: orphanRow.read<int>('cnt'),
          totalDebitsMinor: totalDebits,
          totalCreditsMinor: totalCredits,
        ),
      );
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  Future<Result<FinancialAccount>> _requireActiveAccount(
    ProfileId profileId,
    String accountId,
  ) async {
    final acc =
        await (_db.select(_db.financialAccounts)..where(
              (a) =>
                  a.id.equals(accountId) &
                  a.profileId.equals(profileId.value) &
                  a.isActive.equals(true) &
                  a.archivedAtUtc.isNull(),
            ))
            .getSingleOrNull();
    if (acc == null) {
      return const FailureResult(
        ValidationFailure(
          message:
              'Selected account is missing, archived, or outside the active profile.',
        ),
      );
    }
    return Success(acc);
  }

  Future<Result<Category>> _requireCategory(
    ProfileId profileId,
    String categoryId,
  ) async {
    final cat =
        await (_db.select(_db.categories)..where(
              (c) =>
                  c.id.equals(categoryId) & c.profileId.equals(profileId.value),
            ))
            .getSingleOrNull();
    if (cat == null) {
      return const FailureResult(
        ValidationFailure(
          message: 'Selected category does not belong to the active profile.',
        ),
      );
    }
    return Success(cat);
  }

  Future<Map<String, String>> _accountNamesMap(ProfileId profileId) async {
    final rows = await (_db.select(
      _db.financialAccounts,
    )..where((a) => a.profileId.equals(profileId.value))).get();
    return {for (final r in rows) r.id: r.name};
  }

  Future<Map<String, String>> _categoryNamesMap(ProfileId profileId) async {
    final rows = await (_db.select(
      _db.categories,
    )..where((c) => c.profileId.equals(profileId.value))).get();
    return {for (final r in rows) r.id: r.name};
  }

  Future<Map<String, String>> _ledgerNamesMap(ProfileId profileId) async {
    final rows = await (_db.select(
      _db.ledgerAccounts,
    )..where((l) => l.profileId.equals(profileId.value))).get();
    return {for (final r in rows) r.id: r.name};
  }

  TransactionEntity _mapTransaction(
    Transaction row, {
    required Map<String, String> accountsMap,
    required Map<String, String> categoriesMap,
    List<TransactionSplitEntity> splits = const [],
    List<PostingDetail> postings = const [],
    String? journalStatus,
  }) {
    return TransactionEntity(
      id: row.id,
      profileId: ProfileId(row.profileId),
      type: TransactionType.fromWire(row.transactionType),
      status: TransactionStatus.fromWire(row.status),
      transactionDateUtc: row.transactionDateUtc,
      amount: Money(
        amountMinor: row.amountMinor,
        currencyCode: row.currencyCode,
      ),
      destinationAmount:
          row.destinationAmountMinor != null &&
              row.destinationCurrencyCode != null
          ? Money(
              amountMinor: row.destinationAmountMinor!,
              currencyCode: row.destinationCurrencyCode!,
            )
          : null,
      baseAmount: Money(
        amountMinor: row.baseAmountMinor,
        currencyCode: row.baseCurrencyCode,
      ),
      fxRateScaled: row.fxRateScaled,
      fxRateScale: row.fxRateScale,
      fxRateSource: row.fxRateSource,
      sourceAccountId: row.sourceAccountId,
      sourceAccountName: row.sourceAccountId != null
          ? accountsMap[row.sourceAccountId!]
          : null,
      destinationAccountId: row.destinationAccountId,
      destinationAccountName: row.destinationAccountId != null
          ? accountsMap[row.destinationAccountId!]
          : null,
      categoryId: row.categoryId,
      categoryName: row.categoryId != null
          ? categoriesMap[row.categoryId!]
          : null,
      relatedTransactionId: row.relatedTransactionId,
      externalRef: row.externalRef,
      description: row.description,
      createdAtUtc: row.createdAtUtc,
      updatedAtUtc: row.updatedAtUtc,
      version: row.version,
      syncStatus: row.syncStatus,
      splits: splits,
      postings: postings,
      journalStatus: journalStatus,
    );
  }
}
