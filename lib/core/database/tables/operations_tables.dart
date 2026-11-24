import 'package:drift/drift.dart';

import 'core_tables.dart';

class ImportBatches extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get accountId => text()();
  TextColumn get fileName => text()();
  TextColumn get fileSha256 => text()();
  IntColumn get totalRows => integer()();
  IntColumn get importedRows => integer().withDefault(const Constant(0))();
  IntColumn get skippedRows => integer().withDefault(const Constant(0))();
  IntColumn get rejectedRows => integer().withDefault(const Constant(0))();
  TextColumn get status => text().check(
    status.isIn(const ['staged', 'committing', 'completed', 'failed']),
  )();
  TextColumn get createdAtUtc => text()();
  TextColumn get completedAtUtc => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'UNIQUE(id, profile_id)',
    'FOREIGN KEY(account_id, profile_id) REFERENCES financial_accounts(id, profile_id)',
  ];
}

class ImportedTransactions extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get importBatchId => text()();
  IntColumn get sourceRowNumber => integer()();
  TextColumn get transactionDateUtc => text().nullable()();
  TextColumn get description => text().nullable()();
  IntColumn get amountMinor => integer().nullable()();
  TextColumn get currencyCode => text().nullable()();
  TextColumn get direction => text().nullable()();
  TextColumn get externalRef => text().nullable()();
  TextColumn get fingerprint => text()();
  TextColumn get validationStatus => text().check(
    validationStatus.isIn(const ['valid', 'possible_duplicate', 'invalid']),
  )();
  TextColumn get validationMessage => text().nullable()();
  TextColumn get duplicateCandidateTxId => text().nullable()();
  TextColumn get userDecision => text().check(
    userDecision.isIn(const ['pending', 'import', 'skip', 'rejected']),
  )();
  TextColumn get committedTransactionId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'FOREIGN KEY(import_batch_id, profile_id) REFERENCES import_batches(id, profile_id)',
  ];
}

class SyncOutbox extends Table {
  TextColumn get operationId => text()();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operationType => text().check(
    operationType.isIn(const ['create', 'update', 'archive', 'delete']),
  )();
  IntColumn get payloadVersion => integer().withDefault(const Constant(1))();
  IntColumn get baseVersion => integer().nullable()();
  TextColumn get payloadJson => text()();
  TextColumn get idempotencyKey => text()();
  TextColumn get createdAtUtc => text()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get nextAttemptAtUtc => text().nullable()();
  TextColumn get lastErrorCode => text().nullable()();
  TextColumn get errorCategory => text().nullable()();
  TextColumn get status => text().check(
    status.isIn(const [
      'pending',
      'syncing',
      'synced',
      'retryable_error',
      'permanent_error',
      'conflict',
    ]),
  )();

  @override
  Set<Column<Object>> get primaryKey => {operationId};
}

class SyncCursors extends Table {
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get cursorToken => text().withDefault(const Constant(''))();
  TextColumn get lastPulledAtUtc => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {profileId};
}

class SyncConflicts extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get operationId => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get localPayloadJson => text()();
  TextColumn get serverPayloadJson => text()();
  TextColumn get resolutionStatus => text().check(
    resolutionStatus.isIn(const [
      'open',
      'kept_local',
      'accepted_server',
      'merged',
    ]),
  )();
  TextColumn get createdAtUtc => text()();
  TextColumn get resolvedAtUtc => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AuditLogs extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().nullable()();
  TextColumn get actorUserId => text()();
  TextColumn get action => text()();
  TextColumn get targetType => text()();
  TextColumn get targetId => text()();
  TextColumn get outcome => text()();
  TextColumn get metadataRedactedJson =>
      text().withDefault(const Constant('{}'))();
  TextColumn get createdAtUtc => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class LocalNotifications extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Profiles, #id)();
  TextColumn get notificationType => text()();
  TextColumn get title => text()();
  TextColumn get body => text()();
  TextColumn get deepLinkRoute => text().nullable()();
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();
  TextColumn get scheduledAtUtc => text().nullable()();
  TextColumn get createdAtUtc => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
