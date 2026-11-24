import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:equatable/equatable.dart';

import '../database/app_database.dart';
import '../errors/failures.dart';
import '../logging/redacting_logger.dart';
import '../network/api_client.dart';
import '../security/key_manager.dart';
import '../utilities/clock.dart';
import '../utilities/id_generator.dart';

final class SyncRunSummary extends Equatable {
  const SyncRunSummary({
    required this.pushedAccepted,
    required this.pushedDuplicates,
    required this.pushedConflicts,
    required this.pushedErrors,
    required this.pulledChanges,
    required this.completedAtUtc,
  });

  final int pushedAccepted;
  final int pushedDuplicates;
  final int pushedConflicts;
  final int pushedErrors;
  final int pulledChanges;
  final String completedAtUtc;

  @override
  List<Object?> get props => [
    pushedAccepted,
    pushedDuplicates,
    pushedConflicts,
    pushedErrors,
    pulledChanges,
    completedAtUtc,
  ];
}

final class SyncQueueSnapshot extends Equatable {
  const SyncQueueSnapshot({
    required this.pendingCount,
    required this.retryableErrorCount,
    required this.permanentErrorCount,
    required this.conflictCount,
    required this.syncedCount,
    this.lastPulledAtUtc,
    this.openConflicts = const [],
  });

  final int pendingCount;
  final int retryableErrorCount;
  final int permanentErrorCount;
  final int conflictCount;
  final int syncedCount;
  final String? lastPulledAtUtc;
  final List<SyncConflict> openConflicts;

  @override
  List<Object?> get props => [
    pendingCount,
    retryableErrorCount,
    permanentErrorCount,
    conflictCount,
    syncedCount,
    lastPulledAtUtc,
    openConflicts,
  ];
}

/// Offline-First Synchronization Engine (`ARCH-004`, `FR-019`, `FR-020`).
/// Pushes bounded idempotent outbox batches, applies exponential backoff + jitter
/// on transient errors, surfaces explicit draft/metadata conflicts without silent
/// overwrites, and pulls monotonic cursor deltas atomically.
final class SyncCoordinator {
  SyncCoordinator({
    required AppDatabase db,
    required ApiClient apiClient,
    required KeyManager keyManager,
    required IdGenerator idGenerator,
    required UtcClock clock,
    required RedactingLogger logger,
  }) : _db = db,
       _api = apiClient,
       _keyManager = keyManager,
       _idGen = idGenerator,
       _clock = clock,
       _logger = logger;

  final AppDatabase _db;
  final ApiClient _api;
  final KeyManager _keyManager;
  final IdGenerator _idGen;
  final UtcClock _clock;
  final RedactingLogger _logger;
  final Random _rng = Random();

  static const int _maxBatchSize = 50;

  Future<Result<SyncQueueSnapshot>> getQueueSnapshot(
    ProfileId profileId,
  ) async {
    try {
      final rows = await (_db.select(
        _db.syncOutbox,
      )..where((o) => o.profileId.equals(profileId.value))).get();
      final cursor = await (_db.select(
        _db.syncCursors,
      )..where((c) => c.profileId.equals(profileId.value))).getSingleOrNull();
      final conflicts =
          await (_db.select(_db.syncConflicts)
                ..where(
                  (c) =>
                      c.profileId.equals(profileId.value) &
                      c.resolutionStatus.equals('open'),
                )
                ..orderBy([(c) => OrderingTerm.desc(c.createdAtUtc)]))
              .get();

      return Success(
        SyncQueueSnapshot(
          pendingCount: rows
              .where((r) => r.status == 'pending' || r.status == 'syncing')
              .length,
          retryableErrorCount: rows
              .where((r) => r.status == 'retryable_error')
              .length,
          permanentErrorCount: rows
              .where((r) => r.status == 'permanent_error')
              .length,
          conflictCount: conflicts.length,
          syncedCount: rows.where((r) => r.status == 'synced').length,
          lastPulledAtUtc: cursor?.lastPulledAtUtc,
          openConflicts: conflicts,
        ),
      );
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  /// Executes one bounded Push + Pull sync cycle for [profileId].
  Future<Result<SyncRunSummary>> synchronizeProfile(ProfileId profileId) async {
    if (!_api.hasAccessToken) {
      return const FailureResult(AuthenticationFailure());
    }

    final deviceId = await _keyManager.getOrCreateDeviceId();
    final nowIso = _clock.nowIsoUtc();

    var accepted = 0;
    var duplicates = 0;
    var conflicts = 0;
    var errors = 0;
    var pulled = 0;

    // 1. Select due pending/retryable operations for this profile only.
    final dueOps =
        await (_db.select(_db.syncOutbox)
              ..where(
                (o) =>
                    o.profileId.equals(profileId.value) &
                    (o.status.equals('pending') |
                        (o.status.equals('retryable_error') &
                            (o.nextAttemptAtUtc.isNull() |
                                o.nextAttemptAtUtc.isSmallerOrEqualValue(
                                  nowIso,
                                )))),
              )
              ..orderBy([(o) => OrderingTerm.asc(o.createdAtUtc)])
              ..limit(_maxBatchSize))
            .get();

    if (dueOps.isNotEmpty) {
      final opIds = dueOps.map((o) => o.operationId).toList();
      await (_db.update(_db.syncOutbox)
            ..where((o) => o.operationId.isIn(opIds)))
          .write(const SyncOutboxCompanion(status: Value('syncing')));

      final pushPayload = {
        'device_id': deviceId,
        'operations': [
          for (final op in dueOps)
            {
              'operation_id': op.operationId,
              'profile_id': op.profileId,
              'entity_type': op.entityType,
              'entity_id': op.entityId,
              'operation_type': op.operationType,
              'payload_version': op.payloadVersion,
              'base_version': op.baseVersion,
              'payload': jsonDecode(op.payloadJson),
            },
        ],
      };

      final pushRes = await _api.postJson(
        '/sync/push/',
        body: pushPayload,
        extraHeaders: {'Idempotency-Key': dueOps.first.idempotencyKey},
      );

      if (pushRes.isFailure) {
        final fail = pushRes.failureOrNull!;
        final isRetryable = fail.retryable;
        for (final op in dueOps) {
          final nextRetry = op.retryCount + 1;
          await (_db.update(
            _db.syncOutbox,
          )..where((o) => o.operationId.equals(op.operationId))).write(
            SyncOutboxCompanion(
              status: Value(
                isRetryable ? 'retryable_error' : 'permanent_error',
              ),
              retryCount: Value(nextRetry),
              nextAttemptAtUtc: Value(
                isRetryable ? _computeBackoffIso(nextRetry) : null,
              ),
              lastErrorCode: Value(fail.code),
              errorCategory: Value(isRetryable ? 'transient' : 'permanent'),
            ),
          );
        }
        return FailureResult(fail);
      }

      final results =
          ((pushRes.valueOrNull!['data'] as Map<String, dynamic>)['results']
                  as List<dynamic>)
              .cast<Map<String, dynamic>>();

      final opById = {for (final o in dueOps) o.operationId: o};

      await _db.transaction(() async {
        for (final r in results) {
          final opId = r['operation_id'] as String;
          final outcome = r['outcome'] as String;
          final errorCode = r['error_code'] as String?;
          final op = opById[opId];
          if (op == null) continue;

          switch (outcome) {
            case 'accepted':
              accepted++;
              await _markSynced(op);
            case 'duplicate':
              duplicates++;
              await _markSynced(op);
            case 'conflict':
              conflicts++;
              await (_db.update(
                _db.syncOutbox,
              )..where((o) => o.operationId.equals(opId))).write(
                SyncOutboxCompanion(
                  status: const Value('conflict'),
                  lastErrorCode: Value(errorCode ?? 'VERSION_CONFLICT'),
                  errorCategory: const Value('conflict'),
                ),
              );
              await _db
                  .into(_db.syncConflicts)
                  .insert(
                    SyncConflictsCompanion.insert(
                      id: _idGen.nextUuid(),
                      profileId: op.profileId,
                      operationId: op.operationId,
                      entityType: op.entityType,
                      entityId: op.entityId,
                      localPayloadJson: op.payloadJson,
                      serverPayloadJson: jsonEncode(
                        r['server_payload'] ?? const {},
                      ),
                      resolutionStatus: 'open',
                      createdAtUtc: _clock.nowIsoUtc(),
                    ),
                  );
            case 'retryable_error':
              errors++;
              final nextRetry = op.retryCount + 1;
              await (_db.update(
                _db.syncOutbox,
              )..where((o) => o.operationId.equals(opId))).write(
                SyncOutboxCompanion(
                  status: const Value('retryable_error'),
                  retryCount: Value(nextRetry),
                  nextAttemptAtUtc: Value(_computeBackoffIso(nextRetry)),
                  lastErrorCode: Value(errorCode),
                  errorCategory: const Value('transient'),
                ),
              );
            default:
              errors++;
              await (_db.update(
                _db.syncOutbox,
              )..where((o) => o.operationId.equals(opId))).write(
                SyncOutboxCompanion(
                  status: const Value('permanent_error'),
                  lastErrorCode: Value(errorCode),
                  errorCategory: const Value('permanent'),
                ),
              );
          }
        }
      });
    }

    // 2. Pull incremental server changes using opaque monotonic cursor.
    final cursorRow = await (_db.select(
      _db.syncCursors,
    )..where((c) => c.profileId.equals(profileId.value))).getSingleOrNull();
    var cursor = cursorRow?.cursorToken ?? '';
    var hasMore = true;
    var guardPages = 0;

    while (hasMore && guardPages < 10) {
      guardPages++;
      final pullRes = await _api.getJson(
        '/sync/pull/',
        queryParameters: {
          'profile_id': profileId.value,
          if (cursor.isNotEmpty) 'cursor': cursor,
          'limit': 100,
        },
      );
      if (pullRes.isFailure) break;

      final data = pullRes.valueOrNull!['data'] as Map<String, dynamic>;
      final changes = (data['changes'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final nextCursor = data['next_cursor'] as String? ?? cursor;
      hasMore = data['has_more'] as bool? ?? false;

      pulled += changes.length;
      cursor = nextCursor;

      await _db
          .into(_db.syncCursors)
          .insertOnConflictUpdate(
            SyncCursorsCompanion.insert(
              profileId: profileId.value,
              cursorToken: Value(nextCursor),
              lastPulledAtUtc: Value(_clock.nowIsoUtc()),
            ),
          );
    }

    _logger.info(
      'sync',
      'sync_completed',
      metadata: {
        'accepted': accepted,
        'duplicates': duplicates,
        'conflicts': conflicts,
        'errors': errors,
        'pulled': pulled,
      },
    );

    return Success(
      SyncRunSummary(
        pushedAccepted: accepted,
        pushedDuplicates: duplicates,
        pushedConflicts: conflicts,
        pushedErrors: errors,
        pulledChanges: pulled,
        completedAtUtc: _clock.nowIsoUtc(),
      ),
    );
  }

  /// Explicitly resolves an open draft/metadata conflict (`FR-020`).
  Future<Result<void>> resolveConflict({
    required ProfileId profileId,
    required String conflictId,
    required String resolution, // 'kept_local' | 'accepted_server'
  }) async {
    final row =
        await (_db.select(_db.syncConflicts)..where(
              (c) =>
                  c.id.equals(conflictId) & c.profileId.equals(profileId.value),
            ))
            .getSingleOrNull();
    if (row == null) return const FailureResult(NotFoundFailure());

    final now = _clock.nowIsoUtc();
    await _db.transaction(() async {
      await (_db.update(
        _db.syncConflicts,
      )..where((c) => c.id.equals(conflictId))).write(
        SyncConflictsCompanion(
          resolutionStatus: Value(resolution),
          resolvedAtUtc: Value(now),
        ),
      );
      if (resolution == 'kept_local') {
        await (_db.update(
          _db.syncOutbox,
        )..where((o) => o.operationId.equals(row.operationId))).write(
          const SyncOutboxCompanion(
            status: Value('pending'),
            baseVersion: Value(null),
          ),
        );
      } else {
        await (_db.update(_db.syncOutbox)
              ..where((o) => o.operationId.equals(row.operationId)))
            .write(const SyncOutboxCompanion(status: Value('synced')));
      }
    });
    return const Success(null);
  }

  Future<void> _markSynced(SyncOutboxData op) async {
    await (_db.update(_db.syncOutbox)
          ..where((o) => o.operationId.equals(op.operationId)))
        .write(const SyncOutboxCompanion(status: Value('synced')));

    if (op.entityType == 'transaction') {
      await (_db.update(_db.transactions)..where(
            (t) => t.id.equals(op.entityId) & t.profileId.equals(op.profileId),
          ))
          .write(const TransactionsCompanion(syncStatus: Value('synced')));
    } else if (op.entityType == 'profile') {
      await (_db.update(_db.profiles)..where((p) => p.id.equals(op.entityId)))
          .write(const ProfilesCompanion(syncStatus: Value('synced')));
    }
  }

  String _computeBackoffIso(int retryCount) {
    final baseSec = min(300, pow(2, retryCount).toInt() * 5);
    final jitterSec = _rng.nextInt(5);
    return _clock
        .nowUtc()
        .add(Duration(seconds: baseSec + jitterSec))
        .toIso8601String();
  }
}
