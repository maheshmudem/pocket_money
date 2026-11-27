import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utilities/clock.dart';
import '../../../../core/utilities/id_generator.dart';
import '../../domain/entities/category_entity.dart';
import '../../domain/repositories/category_repository.dart';

final class DriftCategoryRepository implements CategoryRepository {
  DriftCategoryRepository({
    required AppDatabase db,
    required IdGenerator idGenerator,
    required UtcClock clock,
  }) : _db = db,
       _idGen = idGenerator,
       _clock = clock;

  final AppDatabase _db;
  final IdGenerator _idGen;
  final UtcClock _clock;

  SimpleSelectStatement<$CategoriesTable, Category> _categoriesSelect(
    ProfileId profileId, {
    CategoryType? type,
    bool includeInactive = false,
  }) {
    return _db.select(_db.categories)
      ..where((c) {
        Expression<bool> cond = c.profileId.equals(profileId.value);
        if (type != null) {
          cond = cond & c.categoryType.equals(type.wireValue);
        }
        if (!includeInactive) {
          cond = cond & c.isActive.equals(true);
        }
        return cond;
      })
      ..orderBy([
        (c) => OrderingTerm.asc(c.categoryType),
        (c) => OrderingTerm.asc(c.name),
      ]);
  }

  @override
  Stream<List<CategoryEntity>> watchCategories(
    ProfileId profileId, {
    CategoryType? type,
    bool includeInactive = false,
  }) {
    return _categoriesSelect(
      profileId,
      type: type,
      includeInactive: includeInactive,
    ).watch().map((rows) => rows.map(_map).toList());
  }

  @override
  Future<Result<List<CategoryEntity>>> listCategories(
    ProfileId profileId, {
    CategoryType? type,
    bool includeInactive = false,
  }) async {
    try {
      final rows = await _categoriesSelect(
        profileId,
        type: type,
        includeInactive: includeInactive,
      ).get();
      return Success(rows.map(_map).toList());
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  @override
  Future<Result<CategoryEntity>> createCategory({
    required ProfileId profileId,
    required String name,
    required CategoryType categoryType,
    String? parentCategoryId,
    String iconKey = 'category',
    String colorToken = 'primary',
    bool queueSync = false,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 80) {
      return const FailureResult(
        ValidationFailure(message: 'Category name must be 1–80 characters.'),
      );
    }

    final now = _clock.nowIsoUtc();
    final ledgerId = _idGen.nextUuid();
    final catId = _idGen.nextUuid();
    final isIncome = categoryType == CategoryType.income;

    try {
      await _db.transaction(() async {
        await _db
            .into(_db.ledgerAccounts)
            .insert(
              LedgerAccountsCompanion.insert(
                id: ledgerId,
                profileId: profileId.value,
                name: trimmed,
                accountType: isIncome ? 'income' : 'expense',
                normalBalance: isIncome ? 'credit' : 'debit',
                createdAtUtc: now,
              ),
            );
        await _db
            .into(_db.categories)
            .insert(
              CategoriesCompanion.insert(
                id: catId,
                profileId: profileId.value,
                ledgerAccountId: ledgerId,
                name: trimmed,
                categoryType: categoryType.wireValue,
                parentCategoryId: Value(parentCategoryId),
                iconKey: Value(iconKey),
                colorToken: Value(colorToken),
                createdAtUtc: now,
                updatedAtUtc: now,
                syncStatus: Value(queueSync ? 'pending' : 'local_only'),
              ),
            );
      });

      final row =
          await (_db.select(_db.categories)..where(
                (c) => c.id.equals(catId) & c.profileId.equals(profileId.value),
              ))
              .getSingle();
      return Success(_map(row));
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  @override
  Future<Result<CategoryEntity>> updateCategory({
    required ProfileId profileId,
    required String categoryId,
    required String name,
    String? iconKey,
    bool? isActive,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 80) {
      return const FailureResult(
        ValidationFailure(message: 'Category name must be 1–80 characters.'),
      );
    }

    final now = _clock.nowIsoUtc();
    try {
      final existing =
          await (_db.select(_db.categories)..where(
                (c) =>
                    c.id.equals(categoryId) &
                    c.profileId.equals(profileId.value),
              ))
              .getSingleOrNull();
      if (existing == null) return const FailureResult(NotFoundFailure());

      await (_db.update(_db.categories)..where(
            (c) =>
                c.id.equals(categoryId) & c.profileId.equals(profileId.value),
          ))
          .write(
            CategoriesCompanion(
              name: Value(trimmed),
              iconKey: iconKey != null ? Value(iconKey) : const Value.absent(),
              isActive: isActive != null
                  ? Value(isActive)
                  : const Value.absent(),
              updatedAtUtc: Value(now),
              version: Value(existing.version + 1),
            ),
          );
      final updated =
          await (_db.select(_db.categories)..where(
                (c) =>
                    c.id.equals(categoryId) &
                    c.profileId.equals(profileId.value),
              ))
              .getSingle();
      return Success(_map(updated));
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  CategoryEntity _map(Category row) => CategoryEntity(
    id: row.id,
    profileId: ProfileId(row.profileId),
    ledgerAccountId: row.ledgerAccountId,
    name: row.name,
    categoryType: CategoryType.fromWire(row.categoryType),
    parentCategoryId: row.parentCategoryId,
    iconKey: row.iconKey,
    colorToken: row.colorToken,
    isSystem: row.isSystem,
    isActive: row.isActive,
  );
}
