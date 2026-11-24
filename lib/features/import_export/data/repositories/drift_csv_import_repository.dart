import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utilities/clock.dart';
import '../../../../core/utilities/id_generator.dart';
import '../../../transactions/domain/entities/transaction_entity.dart';
import '../../../transactions/domain/repositories/transaction_repository.dart';
import '../../domain/csv_import_engine.dart';

final class CsvImportSummary {
  const CsvImportSummary({
    required this.batchId,
    required this.totalRows,
    required this.importedCount,
    required this.skippedCount,
    required this.rejectedCount,
  });

  final String batchId;
  final int totalRows;
  final int importedCount;
  final int skippedCount;
  final int rejectedCount;
}

final class DriftCsvImportRepository {
  DriftCsvImportRepository({
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

  /// Analyzes parsed CSV rows against existing transactions in [profileId] & [accountId]
  /// to flag probable duplicates before user confirmation (`AC-CSV-001`, `TC-FIN-018`).
  Future<Result<List<StagedCsvRow>>> previewAndDetectDuplicates({
    required ProfileId profileId,
    required String accountId,
    required List<List<String>> rawRows,
    required CsvColumnMapping mapping,
  }) async {
    try {
      final existingTxs =
          await (_db.select(_db.transactions)..where(
                (t) =>
                    t.profileId.equals(profileId.value) &
                    t.deletedAtUtc.isNull() &
                    (t.sourceAccountId.equals(accountId) |
                        t.destinationAccountId.equals(accountId)),
              ))
              .get();

      final fingerprints = <String, String>{};
      final extRefs = <String, String>{};

      for (final tx in existingTxs) {
        if (tx.externalRef != null && tx.externalRef!.isNotEmpty) {
          extRefs[tx.externalRef!] = tx.id;
        }
        final dir = tx.transactionType == 'income' ? 'credit' : 'debit';
        final fp = CsvImportEngine.computeFingerprint(
          profileId: profileId,
          accountId: accountId,
          dateYyyyMmDd: tx.transactionDateUtc.substring(0, 10),
          amountMinor: tx.amountMinor,
          currencyCode: tx.currencyCode,
          direction: dir,
          description: tx.description ?? '',
        );
        fingerprints[fp] = tx.id;
      }

      final staged = CsvImportEngine.stageRows(
        profileId: profileId,
        accountId: accountId,
        rawRows: rawRows,
        mapping: mapping,
        existingFingerprints: fingerprints,
        existingExternalRefs: extRefs,
      );
      return Success(staged);
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  /// Persists the `import_batches` + `imported_transactions` audit rows and
  /// commits every confirmed row atomically into the double-entry ledger (`FR-015`).
  Future<Result<CsvImportSummary>> commitConfirmedBatch({
    required ProfileId profileId,
    required String accountId,
    required String fileName,
    required String rawCsvContent,
    required List<StagedCsvRow> reviewedRows,
    required String defaultExpenseCategoryId,
    required String defaultIncomeCategoryId,
  }) async {
    final batchId = _idGen.nextUuid();
    final now = _clock.nowIsoUtc();
    final fileHash = crypto.sha256
        .convert(utf8.encode(rawCsvContent))
        .toString();

    var imported = 0;
    var skipped = 0;
    var rejected = 0;

    try {
      await _db
          .into(_db.importBatches)
          .insert(
            ImportBatchesCompanion.insert(
              id: batchId,
              profileId: profileId.value,
              accountId: accountId,
              fileName: fileName,
              fileSha256: fileHash,
              totalRows: reviewedRows.length,
              status: 'committing',
              createdAtUtc: now,
            ),
          );

      for (final row in reviewedRows) {
        String? committedTxId;
        var finalDecision = row.decision;

        if (row.decision == StagedRowDecision.importRow &&
            row.amountMinor != null &&
            row.currencyCode != null &&
            row.transactionDateUtc != null &&
            row.direction != null) {
          final isIncome = row.direction == 'credit';
          final txRes = await _txRepo.createTransaction(
            profileId,
            CreateTransactionCommand(
              type: isIncome ? TransactionType.income : TransactionType.expense,
              amountMinor: row.amountMinor!,
              currencyCode: row.currencyCode!,
              transactionDateUtc: row.transactionDateUtc!,
              sourceAccountId: isIncome ? null : accountId,
              destinationAccountId: isIncome ? accountId : null,
              categoryId: isIncome
                  ? defaultIncomeCategoryId
                  : defaultExpenseCategoryId,
              importBatchId: batchId,
              externalRef: row.externalRef,
              description: row.description,
            ),
          );

          if (txRes.isSuccess) {
            committedTxId = txRes.valueOrNull!.id;
            imported++;
          } else {
            finalDecision = StagedRowDecision.rejected;
            rejected++;
          }
        } else if (row.decision == StagedRowDecision.skip) {
          skipped++;
        } else {
          rejected++;
        }

        await _db
            .into(_db.importedTransactions)
            .insert(
              ImportedTransactionsCompanion.insert(
                id: _idGen.nextUuid(),
                profileId: profileId.value,
                importBatchId: batchId,
                sourceRowNumber: row.sourceRowNumber,
                transactionDateUtc: Value(row.transactionDateUtc),
                description: Value(row.description),
                amountMinor: Value(row.amountMinor),
                currencyCode: Value(row.currencyCode),
                direction: Value(row.direction),
                externalRef: Value(row.externalRef),
                fingerprint: row.fingerprint,
                validationStatus: switch (row.validationStatus) {
                  StagedRowValidationStatus.valid => 'valid',
                  StagedRowValidationStatus.possibleDuplicate =>
                    'possible_duplicate',
                  StagedRowValidationStatus.invalid => 'invalid',
                },
                validationMessage: Value(row.validationMessage),
                duplicateCandidateTxId: Value(row.duplicateCandidateTxId),
                userDecision: switch (finalDecision) {
                  StagedRowDecision.importRow => 'import',
                  StagedRowDecision.skip => 'skip',
                  StagedRowDecision.rejected => 'rejected',
                  StagedRowDecision.pending => 'pending',
                },
                committedTransactionId: Value(committedTxId),
              ),
            );
      }

      await (_db.update(
        _db.importBatches,
      )..where((b) => b.id.equals(batchId))).write(
        ImportBatchesCompanion(
          importedRows: Value(imported),
          skippedRows: Value(skipped),
          rejectedRows: Value(rejected),
          status: const Value('completed'),
          completedAtUtc: Value(_clock.nowIsoUtc()),
        ),
      );

      return Success(
        CsvImportSummary(
          batchId: batchId,
          totalRows: reviewedRows.length,
          importedCount: imported,
          skippedCount: skipped,
          rejectedCount: rejected,
        ),
      );
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }
}
