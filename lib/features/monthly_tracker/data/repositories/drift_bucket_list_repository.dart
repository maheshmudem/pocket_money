import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utilities/clock.dart';
import '../../../../core/utilities/id_generator.dart';
import '../../domain/entities/bucket_list_item_entity.dart';
import '../../domain/repositories/bucket_list_repository.dart';

/// Profile-isolated Drift/SQLite repository for Monthly Bucket List items.
final class DriftBucketListRepository implements BucketListRepository {
  DriftBucketListRepository({
    required AppDatabase db,
    required IdGenerator idGenerator,
    required UtcClock clock,
  }) : _db = db,
       _idGen = idGenerator,
       _clock = clock;

  final AppDatabase _db;
  final IdGenerator _idGen;
  final UtcClock _clock;

  static final RegExp _monthRegex = RegExp(r'^\d{4}-\d{2}$');

  @override
  Future<Result<List<BucketListItemEntity>>> listItems(
    ProfileId profileId,
  ) async {
    try {
      final rows =
          await (_db.select(_db.bucketListItems)
                ..where((b) => b.profileId.equals(profileId.value))
                ..orderBy([
                  (b) => OrderingTerm.asc(b.targetYearMonth),
                  (b) => OrderingTerm.asc(b.createdAtUtc),
                ]))
              .get();
      return Success(rows.map(_mapRow).toList());
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  @override
  Future<Result<BucketListItemEntity>> createItem({
    required ProfileId profileId,
    required String name,
    required int estimatedAmountMinor,
    required String currencyCode,
    required BucketPriority priority,
    required String targetYearMonth,
    int savedAmountMinor = 0,
    String? dueDateUtc,
    String? reminderAtUtc,
    String? categoryId,
    String? note,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty ||
        estimatedAmountMinor <= 0 ||
        !_monthRegex.hasMatch(targetYearMonth)) {
      return const FailureResult(
        ValidationFailure(
          message:
              'Valid item name, positive amount, and target month are required.',
        ),
      );
    }

    final id = _idGen.nextUuid();
    final now = _clock.nowIsoUtc();
    final clampedSaved = math.min<int>(
      estimatedAmountMinor,
      math.max<int>(0, savedAmountMinor),
    );
    final trimmedNote = note?.trim();

    try {
      await _db
          .into(_db.bucketListItems)
          .insert(
            BucketListItemsCompanion.insert(
              id: id,
              profileId: profileId.value,
              name: trimmedName,
              estimatedAmountMinor: estimatedAmountMinor,
              savedAmountMinor: Value(clampedSaved),
              reservedInBudgetMinor: const Value(0),
              currencyCode: currencyCode,
              priority: priority.wireValue,
              targetYearMonth: targetYearMonth,
              dueDateUtc: Value(dueDateUtc),
              reminderAtUtc: Value(reminderAtUtc),
              categoryId: Value(categoryId),
              note: Value(
                trimmedNote != null && trimmedNote.isNotEmpty
                    ? trimmedNote
                    : null,
              ),
              status: BucketItemStatus.planned.wireValue,
              createdAtUtc: now,
              updatedAtUtc: now,
            ),
          );

      final row =
          await (_db.select(_db.bucketListItems)..where(
                (b) => b.id.equals(id) & b.profileId.equals(profileId.value),
              ))
              .getSingle();
      return Success(_mapRow(row));
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  @override
  Future<Result<BucketListItemEntity>> updateItem(
    BucketListItemEntity item,
  ) async {
    final trimmedName = item.name.trim();
    if (trimmedName.isEmpty ||
        item.estimatedAmountMinor <= 0 ||
        !_monthRegex.hasMatch(item.targetYearMonth)) {
      return const FailureResult(
        ValidationFailure(
          message:
              'Valid item name, positive amount, and target month are required.',
        ),
      );
    }

    final now = _clock.nowIsoUtc();
    final nextVersion = item.version + 1;
    final clampedSaved = math.min<int>(
      item.estimatedAmountMinor,
      math.max<int>(0, item.savedAmountMinor),
    );
    final trimmedNote = item.note?.trim();

    try {
      final updatedCount =
          await (_db.update(_db.bucketListItems)..where(
                (b) =>
                    b.id.equals(item.id) &
                    b.profileId.equals(item.profileId.value),
              ))
              .write(
                BucketListItemsCompanion(
                  name: Value(trimmedName),
                  estimatedAmountMinor: Value(item.estimatedAmountMinor),
                  savedAmountMinor: Value(clampedSaved),
                  reservedInBudgetMinor: Value(
                    math.max<int>(0, item.reservedInBudgetMinor),
                  ),
                  actualAmountMinor: Value(item.actualAmountMinor),
                  currencyCode: Value(item.currencyCode),
                  priority: Value(item.priority.wireValue),
                  targetYearMonth: Value(item.targetYearMonth),
                  dueDateUtc: Value(item.dueDateUtc),
                  reminderAtUtc: Value(item.reminderAtUtc),
                  categoryId: Value(item.categoryId),
                  linkedGoalId: Value(item.linkedGoalId),
                  purchasedTransactionId: Value(item.purchasedTransactionId),
                  note: Value(
                    trimmedNote != null && trimmedNote.isNotEmpty
                        ? trimmedNote
                        : null,
                  ),
                  postponeCount: Value(math.max<int>(0, item.postponeCount)),
                  status: Value(item.status.wireValue),
                  updatedAtUtc: Value(now),
                  version: Value(nextVersion),
                ),
              );
      if (updatedCount == 0) {
        return const FailureResult(
          ValidationFailure(message: 'Bucket list item not found.'),
        );
      }
      final row =
          await (_db.select(_db.bucketListItems)..where(
                (b) =>
                    b.id.equals(item.id) &
                    b.profileId.equals(item.profileId.value),
              ))
              .getSingle();
      return Success(_mapRow(row));
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  @override
  Future<Result<void>> deleteItem(ProfileId profileId, String id) async {
    try {
      await (_db.delete(_db.bucketListItems)..where(
            (b) => b.id.equals(id) & b.profileId.equals(profileId.value),
          ))
          .go();
      return const Success(null);
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  @override
  Future<Result<BucketListItemEntity>> addSavedAmount(
    ProfileId profileId,
    String id,
    int deltaMinor,
  ) async {
    if (deltaMinor <= 0) {
      return const FailureResult(
        ValidationFailure(message: 'Amount must be greater than zero.'),
      );
    }
    try {
      final row =
          await (_db.select(_db.bucketListItems)..where(
                (b) => b.id.equals(id) & b.profileId.equals(profileId.value),
              ))
              .getSingleOrNull();
      if (row == null) {
        return const FailureResult(
          ValidationFailure(message: 'Bucket list item not found.'),
        );
      }
      final nextSaved = math.min<int>(
        row.estimatedAmountMinor,
        row.savedAmountMinor + deltaMinor,
      );
      final now = _clock.nowIsoUtc();
      await (_db.update(_db.bucketListItems)..where(
            (b) => b.id.equals(id) & b.profileId.equals(profileId.value),
          ))
          .write(
            BucketListItemsCompanion(
              savedAmountMinor: Value(nextSaved),
              updatedAtUtc: Value(now),
              version: Value(row.version + 1),
            ),
          );
      final updated =
          await (_db.select(_db.bucketListItems)..where(
                (b) => b.id.equals(id) & b.profileId.equals(profileId.value),
              ))
              .getSingle();
      return Success(_mapRow(updated));
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  BucketListItemEntity _mapRow(BucketListItem r) => BucketListItemEntity(
    id: r.id,
    profileId: ProfileId(r.profileId),
    name: r.name,
    estimatedAmountMinor: r.estimatedAmountMinor,
    savedAmountMinor: r.savedAmountMinor,
    reservedInBudgetMinor: r.reservedInBudgetMinor,
    actualAmountMinor: r.actualAmountMinor,
    currencyCode: r.currencyCode,
    priority: BucketPriority.fromWire(r.priority),
    targetYearMonth: r.targetYearMonth,
    dueDateUtc: r.dueDateUtc,
    reminderAtUtc: r.reminderAtUtc,
    categoryId: r.categoryId,
    linkedGoalId: r.linkedGoalId,
    purchasedTransactionId: r.purchasedTransactionId,
    note: r.note,
    postponeCount: r.postponeCount,
    status: BucketItemStatus.fromWire(r.status),
    createdAtUtc: r.createdAtUtc,
    updatedAtUtc: r.updatedAtUtc,
    version: r.version,
  );
}
