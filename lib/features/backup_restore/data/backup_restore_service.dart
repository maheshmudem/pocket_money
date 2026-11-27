import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/encrypted_executor.dart';
import '../../../core/errors/failures.dart';
import '../../../core/security/backup_crypto.dart';
import '../../../core/utilities/clock.dart';
import '../../../core/utilities/id_generator.dart';

final class RestorePreview {
  const RestorePreview({
    required this.metadata,
    required this.profileCount,
    required this.accountCount,
    required this.transactionCount,
    required this.ledgerBalanced,
  });

  final BackupEnvelopeMetadata metadata;
  final int profileCount;
  final int accountCount;
  final int transactionCount;
  final bool ledgerBalanced;
}

/// Encrypted `.pcfo` Backup & Staging-DB Verified Restore (`FR-024`, `BACKUP_AND_RESTORE.md`).
/// Never activates a backup until it has been restored into an isolated in-memory staging
/// database and passed every foreign-key and double-entry balance trigger!
final class BackupRestoreService {
  BackupRestoreService({
    required AppDatabase db,
    required BackupCrypto crypto,
    required UtcClock clock,
    required String appVersion,
  }) : _db = db,
       _crypto = crypto,
       _clock = clock,
       _appVersion = appVersion;

  final AppDatabase _db;
  final BackupCrypto _crypto;
  final UtcClock _clock;
  final String _appVersion;

  Future<Result<String>> exportEncryptedBackup({
    required String passphrase,
    ProfileId? scopeProfileId,
  }) async {
    try {
      final profileRows = scopeProfileId != null
          ? await (_db.select(
              _db.profiles,
            )..where((p) => p.id.equals(scopeProfileId.value))).get()
          : await _db.select(_db.profiles).get();
      final pIds = profileRows.map((p) => p.id).toList();
      if (pIds.isEmpty) {
        return const FailureResult(
          ValidationFailure(message: 'No profiles available to back up.'),
        );
      }

      Future<List<Map<String, dynamic>>> dumpTable(
        String tableName, {
        bool filterByProfile = true,
      }) async {
        final sql = filterByProfile
            ? 'SELECT * FROM $tableName WHERE profile_id IN (${List.filled(pIds.length, '?').join(',')})'
            : 'SELECT * FROM $tableName';
        final rows = await _db
            .customSelect(
              sql,
              variables: filterByProfile
                  ? pIds.map(Variable.withString).toList()
                  : const [],
            )
            .get();
        return rows.map((r) => Map<String, dynamic>.from(r.data)).toList();
      }

      final payload = <String, dynamic>{
        'profiles': profileRows.map((p) => p.toJson()).toList(),
        'profile_memberships': await dumpTable('profile_memberships'),
        'profile_currency_history': await dumpTable('profile_currency_history'),
        'ledger_accounts': await dumpTable('ledger_accounts'),
        'financial_accounts': await dumpTable('financial_accounts'),
        'categories': await dumpTable('categories'),
        'transactions': await dumpTable('transactions'),
        'transaction_splits': await dumpTable('transaction_splits'),
        'journal_entries': await dumpTable('journal_entries'),
        'ledger_postings': await dumpTable('ledger_postings'),
        'budgets': await dumpTable('budgets'),
        'budget_categories': await dumpTable('budget_categories'),
        'savings_goals': await dumpTable('savings_goals'),
        'goal_contributions': await dumpTable('goal_contributions'),
        'recurring_rules': await dumpTable('recurring_rules'),
        'loans': await dumpTable('loans'),
        'loan_installments': await dumpTable('loan_installments'),
        'bucket_list_items': await dumpTable('bucket_list_items'),
      };

      final archive = await _crypto.encryptBackup(
        payloadJson: payload,
        passphrase: passphrase,
        schemaVersion: _db.schemaVersion,
        appVersion: _appVersion,
        profileIds: pIds,
        createdAtUtc: _clock.nowIsoUtc(),
      );
      return Success(archive);
    } on SecurityFailure catch (e) {
      return FailureResult(e);
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  /// Decrypts and validates the archive inside an isolated staging database BEFORE
  /// touching active user data (`BACKUP_AND_RESTORE.md`).
  Future<Result<RestorePreview>> validateBackupInStaging({
    required String rawArchive,
    required String passphrase,
  }) async {
    try {
      final decrypted = await _crypto.decryptBackup(
        rawArchive: rawArchive,
        passphrase: passphrase,
      );

      if (decrypted.metadata.schemaVersion > _db.schemaVersion) {
        return const FailureResult(
          SecurityFailure(
            message:
                'Backup was created by a newer database schema version. Update Pocket CFO before restoring.',
          ),
        );
      }

      final stagingDb = AppDatabase(EncryptedDatabaseExecutor.openInMemory());
      try {
        await _applyPayloadIntoDatabase(stagingDb, decrypted.payloadJson);

        // Verify double-entry invariant in staging DB.
        final badJournals = await stagingDb.customSelect('''
          SELECT je.id
          FROM journal_entries je
          LEFT JOIN ledger_postings lp ON lp.journal_entry_id = je.id AND lp.profile_id = je.profile_id
          WHERE je.status IN ('posted', 'reversed')
          GROUP BY je.id
          HAVING COUNT(lp.id) < 2
            OR COALESCE(SUM(CASE WHEN lp.side = 'debit' THEN lp.base_amount_minor ELSE 0 END), 0)
            <> COALESCE(SUM(CASE WHEN lp.side = 'credit' THEN lp.base_amount_minor ELSE 0 END), 0)
          ''').get();

        final profiles = (decrypted.payloadJson['profiles'] as List).length;
        final accounts =
            (decrypted.payloadJson['financial_accounts'] as List).length;
        final txs = (decrypted.payloadJson['transactions'] as List).length;

        return Success(
          RestorePreview(
            metadata: decrypted.metadata,
            profileCount: profiles,
            accountCount: accounts,
            transactionCount: txs,
            ledgerBalanced: badJournals.isEmpty,
          ),
        );
      } finally {
        await stagingDb.close();
      }
    } on SecurityFailure catch (e) {
      return FailureResult(e);
    } catch (_) {
      return const FailureResult(
        SecurityFailure(
          message:
              'Staging restore validation failed: backup contains invalid foreign keys or unbalanced ledger data.',
        ),
      );
    }
  }

  /// Restores a previously validated archive into the active database inside a single ACID transaction.
  Future<Result<RestorePreview>> restoreVerifiedBackup({
    required String rawArchive,
    required String passphrase,
  }) async {
    final stagingCheck = await validateBackupInStaging(
      rawArchive: rawArchive,
      passphrase: passphrase,
    );
    if (stagingCheck.isFailure) return stagingCheck;
    if (!stagingCheck.valueOrNull!.ledgerBalanced) {
      return const FailureResult(
        LedgerInvariantFailure(
          message: 'Restore aborted: staging ledger reconciliation failed.',
        ),
      );
    }

    try {
      final decrypted = await _crypto.decryptBackup(
        rawArchive: rawArchive,
        passphrase: passphrase,
      );
      await _applyPayloadIntoDatabase(_db, decrypted.payloadJson);
      return stagingCheck;
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  Future<void> _applyPayloadIntoDatabase(
    AppDatabase targetDb,
    Map<String, dynamic> payload,
  ) async {
    await targetDb.transaction(() async {
      // Insert in strict foreign-key dependency order using INSERT OR IGNORE so duplicate restores are idempotent.
      final orderedTables = [
        'profiles',
        'profile_memberships',
        'profile_currency_history',
        'ledger_accounts',
        'financial_accounts',
        'categories',
        'transactions',
        'transaction_splits',
      ];

      for (final table in orderedTables) {
        final rows = (payload[table] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>();
        for (final row in rows) {
          await _insertRow(targetDb, table, row);
        }
      }

      // Journals must respect immutability trigger: insert as 'draft', insert postings, then mark target status.
      final journals =
          (payload['journal_entries'] as List<dynamic>? ?? const [])
              .cast<Map<String, dynamic>>();
      final postings =
          (payload['ledger_postings'] as List<dynamic>? ?? const [])
              .cast<Map<String, dynamic>>();

      final finalStatuses = <String, String>{};
      for (final je in journals) {
        final id = je['id'] as String;
        final targetStatus = je['status'] as String;
        finalStatuses[id] = targetStatus;
        final draftJe = Map<String, dynamic>.from(je)..['status'] = 'draft';
        await _insertRow(targetDb, 'journal_entries', draftJe);
      }

      for (final p in postings) {
        await _insertRow(targetDb, 'ledger_postings', p);
      }

      for (final entry in finalStatuses.entries) {
        if (entry.value == 'posted' || entry.value == 'reversed') {
          await targetDb.customStatement(
            "UPDATE journal_entries SET status = 'posted' WHERE id = ? AND status = 'draft'",
            [entry.key],
          );
          if (entry.value == 'reversed') {
            await targetDb.customStatement(
              "UPDATE journal_entries SET status = 'reversed' WHERE id = ? AND status = 'posted'",
              [entry.key],
            );
          }
        }
      }

      final secondaryTables = [
        'budgets',
        'budget_categories',
        'savings_goals',
        'goal_contributions',
        'recurring_rules',
        'loans',
        'loan_installments',
        'bucket_list_items',
      ];
      for (final table in secondaryTables) {
        final rows = (payload[table] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>();
        for (final row in rows) {
          await _insertRow(targetDb, table, row);
        }
      }
    });
  }

  Future<void> _insertRow(
    AppDatabase targetDb,
    String table,
    Map<String, dynamic> row,
  ) async {
    if (row.isEmpty) return;
    // Normalize camelCase keys from Drift `.toJson()` (for `profiles`) to snake_case SQL columns.
    final normalized = <String, Object?>{};
    for (final entry in row.entries) {
      final snake = entry.key.replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (m) => '${m.group(1)}_${m.group(2)!.toLowerCase()}',
      );
      final val = entry.value;
      normalized[snake] = val is bool ? (val ? 1 : 0) : val;
    }

    final cols = normalized.keys.toList();
    final placeholders = List.filled(cols.length, '?').join(', ');
    final sql =
        'INSERT OR IGNORE INTO $table (${cols.join(', ')}) VALUES ($placeholders)';
    await targetDb.customStatement(sql, normalized.values.toList());
  }
}
