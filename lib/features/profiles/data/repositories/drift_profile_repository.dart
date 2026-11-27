import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/financial_engine/currency.dart';
import '../../../../core/logging/redacting_logger.dart';
import '../../../../core/utilities/clock.dart';
import '../../../../core/utilities/id_generator.dart';
import '../../domain/entities/profile_entity.dart';
import '../../domain/repositories/profile_repository.dart';

/// System ledger account codes automatically seeded per isolated profile.
abstract final class SystemLedgerCodes {
  static const openingEquity = 'SYS_OPENING_EQUITY';
  static const fxVariance = 'SYS_FX_VARIANCE';
  static const loanInterest = 'SYS_LOAN_INTEREST_EXPENSE';
  static const loanFees = 'SYS_LOAN_FEES_EXPENSE';
}

final class DriftProfileRepository implements ProfileRepository {
  DriftProfileRepository({
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
  Stream<List<FinancialProfile>> watchActiveProfiles({required String userId}) {
    final query =
        _db.select(_db.profiles).join([
            innerJoin(
              _db.profileMemberships,
              _db.profileMemberships.profileId.equalsExp(_db.profiles.id),
            ),
          ])
          ..where(
            _db.profileMemberships.userId.equals(userId) &
                _db.profileMemberships.membershipStatus.equals('active') &
                _db.profiles.archivedAtUtc.isNull() &
                _db.profiles.deletedAtUtc.isNull(),
          )
          ..orderBy([OrderingTerm.asc(_db.profiles.createdAtUtc)]);

    return query.watch().map((rows) => rows.map(_mapJoinedRow).toList());
  }

  @override
  Future<Result<List<FinancialProfile>>> listActiveProfiles({
    required String userId,
  }) async {
    try {
      final query =
          _db.select(_db.profiles).join([
              innerJoin(
                _db.profileMemberships,
                _db.profileMemberships.profileId.equalsExp(_db.profiles.id),
              ),
            ])
            ..where(
              _db.profileMemberships.userId.equals(userId) &
                  _db.profileMemberships.membershipStatus.equals('active') &
                  _db.profiles.archivedAtUtc.isNull() &
                  _db.profiles.deletedAtUtc.isNull(),
            )
            ..orderBy([OrderingTerm.asc(_db.profiles.createdAtUtc)]);

      final rows = await query.get();
      return Success(rows.map(_mapJoinedRow).toList());
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  @override
  Future<Result<FinancialProfile>> getProfile({
    required ProfileId profileId,
    required String userId,
  }) async {
    try {
      final query =
          _db.select(_db.profiles).join([
            innerJoin(
              _db.profileMemberships,
              _db.profileMemberships.profileId.equalsExp(_db.profiles.id),
            ),
          ])..where(
            _db.profiles.id.equals(profileId.value) &
                _db.profileMemberships.userId.equals(userId) &
                _db.profileMemberships.membershipStatus.equals('active'),
          );

      final row = await query.getSingleOrNull();
      if (row == null) {
        return const FailureResult(AuthorizationFailure());
      }
      return Success(_mapJoinedRow(row));
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  @override
  Future<Result<FinancialProfile>> createProfile({
    required String userId,
    required String ownerDisplayName,
    String? ownerEmail,
    required String name,
    required ProfileType profileType,
    required String baseCurrencyCode,
    String timezone = 'Asia/Kolkata',
    bool editorsCanPost = true,
    bool queueSync = false,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 80) {
      return const FailureResult(
        ValidationFailure(
          message: 'Profile name must be between 1 and 80 characters.',
        ),
      );
    }
    final currency = baseCurrencyCode.toUpperCase();
    if (CurrencyCatalog.byCode(currency) == null) {
      return FailureResult(
        ValidationFailure(message: 'Unsupported base currency: $currency.'),
      );
    }

    final now = _clock.nowIsoUtc();
    final profileUuid = _idGen.nextUuid();
    final membershipUuid = _idGen.nextUuid();
    final syncStatus = queueSync ? 'pending' : 'local_only';

    try {
      await _db.transaction(() async {
        await _db
            .into(_db.profiles)
            .insert(
              ProfilesCompanion.insert(
                id: profileUuid,
                name: trimmed,
                profileType: profileType.wireValue,
                baseCurrencyCode: currency,
                timezone: Value(timezone),
                editorsCanPost: Value(editorsCanPost),
                createdAtUtc: now,
                updatedAtUtc: now,
                syncStatus: Value(syncStatus),
              ),
            );

        await _db
            .into(_db.profileMemberships)
            .insert(
              ProfileMembershipsCompanion.insert(
                id: membershipUuid,
                profileId: profileUuid,
                userId: userId,
                displayName: Value(ownerDisplayName),
                email: Value(ownerEmail),
                role: 'owner',
                membershipStatus: 'active',
                createdAtUtc: now,
                updatedAtUtc: now,
              ),
            );

        await _seedSystemLedgerAndCategories(
          profileId: profileUuid,
          profileType: profileType,
          nowUtc: now,
        );

        await _db
            .into(_db.auditLogs)
            .insert(
              AuditLogsCompanion.insert(
                id: _idGen.nextUuid(),
                profileId: Value(profileUuid),
                actorUserId: userId,
                action: 'profile.created',
                targetType: 'profile',
                targetId: profileUuid,
                outcome: 'success',
                metadataRedactedJson: Value(
                  jsonEncode({
                    'profile_type': profileType.wireValue,
                    'base_currency_code': currency,
                  }),
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
                  profileId: profileUuid,
                  entityType: 'profile',
                  entityId: profileUuid,
                  operationType: 'create',
                  payloadJson: jsonEncode({
                    'id': profileUuid,
                    'name': trimmed,
                    'profile_type': profileType.wireValue,
                    'base_currency_code': currency,
                    'timezone': timezone,
                    'editors_can_post': editorsCanPost,
                  }),
                  idempotencyKey: opId,
                  createdAtUtc: now,
                  status: 'pending',
                ),
              );
        }
      });

      _logger.info(
        'profiles',
        'profile_created',
        metadata: {'profile_type': profileType.wireValue},
      );

      return getProfile(profileId: ProfileId(profileUuid), userId: userId);
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  @override
  Future<Result<FinancialProfile>> renameProfile({
    required ProfileId profileId,
    required String userId,
    required String newName,
    bool queueSync = false,
  }) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed.length > 80) {
      return const FailureResult(
        ValidationFailure(
          message: 'Profile name must be between 1 and 80 characters.',
        ),
      );
    }

    final currentRes = await getProfile(profileId: profileId, userId: userId);
    if (currentRes.isFailure) return currentRes;
    final current = currentRes.valueOrNull!;
    if (!current.permissions.canChangeSettingsOrCurrency) {
      return const FailureResult(AuthorizationFailure());
    }

    final now = _clock.nowIsoUtc();
    final nextVersion = current.version + 1;
    try {
      await _db.transaction(() async {
        await (_db.update(
          _db.profiles,
        )..where((t) => t.id.equals(profileId.value))).write(
          ProfilesCompanion(
            name: Value(trimmed),
            updatedAtUtc: Value(now),
            version: Value(nextVersion),
            syncStatus: Value(queueSync ? 'pending' : current.syncStatus),
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
                  entityType: 'profile',
                  entityId: profileId.value,
                  operationType: 'update',
                  baseVersion: Value(current.version),
                  payloadJson: jsonEncode({'name': trimmed}),
                  idempotencyKey: opId,
                  createdAtUtc: now,
                  status: 'pending',
                ),
              );
        }
      });
      return getProfile(profileId: profileId, userId: userId);
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  @override
  Future<Result<FinancialProfile>> updateProfile({
    required ProfileId profileId,
    required String userId,
    required String name,
    required ProfileType profileType,
    String? baseCurrencyCode,
    String? timezone,
    bool? editorsCanPost,
    bool queueSync = false,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty || trimmedName.length > 80) {
      return const FailureResult(
        ValidationFailure(
          message: 'Profile name must be between 1 and 80 characters.',
        ),
      );
    }

    final currentRes = await getProfile(profileId: profileId, userId: userId);
    if (currentRes.isFailure) return currentRes;
    final current = currentRes.valueOrNull!;
    if (!current.permissions.canChangeSettingsOrCurrency) {
      return const FailureResult(AuthorizationFailure());
    }

    final nextCurrency = (baseCurrencyCode ?? current.baseCurrencyCode)
        .trim()
        .toUpperCase();
    if (CurrencyCatalog.byCode(nextCurrency) == null) {
      return FailureResult(
        ValidationFailure(message: 'Unsupported currency: $nextCurrency.'),
      );
    }

    final trimmedTz = timezone?.trim();
    final nextTimezone = (trimmedTz != null && trimmedTz.isNotEmpty)
        ? trimmedTz
        : current.timezone;
    final nextEditorsCanPost = editorsCanPost ?? current.editorsCanPost;

    final now = _clock.nowIsoUtc();
    final nextVersion = current.version + 1;

    try {
      await _db.transaction(() async {
        if (nextCurrency != current.baseCurrencyCode) {
          await _db
              .into(_db.profileCurrencyHistory)
              .insert(
                ProfileCurrencyHistoryCompanion.insert(
                  id: _idGen.nextUuid(),
                  profileId: profileId.value,
                  previousCurrencyCode: current.baseCurrencyCode,
                  newCurrencyCode: nextCurrency,
                  effectiveAtUtc: now,
                  changedByUserId: userId,
                  note: const Value('Updated via Edit Profile'),
                  createdAtUtc: now,
                ),
              );

          await _db
              .into(_db.auditLogs)
              .insert(
                AuditLogsCompanion.insert(
                  id: _idGen.nextUuid(),
                  profileId: Value(profileId.value),
                  actorUserId: userId,
                  action: 'profile.base_currency_changed',
                  targetType: 'profile',
                  targetId: profileId.value,
                  outcome: 'success',
                  metadataRedactedJson: Value(
                    jsonEncode({
                      'from': current.baseCurrencyCode,
                      'to': nextCurrency,
                    }),
                  ),
                  createdAtUtc: now,
                ),
              );
        }

        await (_db.update(
          _db.profiles,
        )..where((t) => t.id.equals(profileId.value))).write(
          ProfilesCompanion(
            name: Value(trimmedName),
            profileType: Value(profileType.wireValue),
            baseCurrencyCode: Value(nextCurrency),
            timezone: Value(nextTimezone),
            editorsCanPost: Value(nextEditorsCanPost),
            updatedAtUtc: Value(now),
            version: Value(nextVersion),
            syncStatus: Value(queueSync ? 'pending' : current.syncStatus),
          ),
        );

        await _db
            .into(_db.auditLogs)
            .insert(
              AuditLogsCompanion.insert(
                id: _idGen.nextUuid(),
                profileId: Value(profileId.value),
                actorUserId: userId,
                action: 'profile.updated',
                targetType: 'profile',
                targetId: profileId.value,
                outcome: 'success',
                metadataRedactedJson: Value(
                  jsonEncode({
                    'profile_type': profileType.wireValue,
                    'base_currency_code': nextCurrency,
                    'timezone': nextTimezone,
                    'editors_can_post': nextEditorsCanPost,
                  }),
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
                  entityType: 'profile',
                  entityId: profileId.value,
                  operationType: 'update',
                  baseVersion: Value(current.version),
                  payloadJson: jsonEncode({
                    'name': trimmedName,
                    'profile_type': profileType.wireValue,
                    'base_currency_code': nextCurrency,
                    'timezone': nextTimezone,
                    'editors_can_post': nextEditorsCanPost,
                  }),
                  idempotencyKey: opId,
                  createdAtUtc: now,
                  status: 'pending',
                ),
              );
        }
      });

      _logger.info(
        'profiles',
        'profile_updated',
        metadata: {'profile_type': profileType.wireValue},
      );
      return getProfile(profileId: profileId, userId: userId);
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  @override
  Future<Result<FinancialProfile>> changeBaseCurrency({
    required ProfileId profileId,
    required String userId,
    required String newBaseCurrencyCode,
    String? note,
    bool queueSync = false,
  }) async {
    final code = newBaseCurrencyCode.toUpperCase();
    if (CurrencyCatalog.byCode(code) == null) {
      return FailureResult(
        ValidationFailure(message: 'Unsupported currency: $code.'),
      );
    }

    final currentRes = await getProfile(profileId: profileId, userId: userId);
    if (currentRes.isFailure) return currentRes;
    final current = currentRes.valueOrNull!;
    if (!current.permissions.canChangeSettingsOrCurrency) {
      return const FailureResult(AuthorizationFailure());
    }
    if (current.baseCurrencyCode == code) {
      return Success(current);
    }

    final now = _clock.nowIsoUtc();
    final nextVersion = current.version + 1;
    try {
      await _db.transaction(() async {
        await _db
            .into(_db.profileCurrencyHistory)
            .insert(
              ProfileCurrencyHistoryCompanion.insert(
                id: _idGen.nextUuid(),
                profileId: profileId.value,
                previousCurrencyCode: current.baseCurrencyCode,
                newCurrencyCode: code,
                effectiveAtUtc: now,
                changedByUserId: userId,
                note: Value(note),
                createdAtUtc: now,
              ),
            );

        // Historical posted transactions are intentionally untouched (`FR-003`).
        await (_db.update(
          _db.profiles,
        )..where((t) => t.id.equals(profileId.value))).write(
          ProfilesCompanion(
            baseCurrencyCode: Value(code),
            updatedAtUtc: Value(now),
            version: Value(nextVersion),
            syncStatus: Value(queueSync ? 'pending' : current.syncStatus),
          ),
        );

        await _db
            .into(_db.auditLogs)
            .insert(
              AuditLogsCompanion.insert(
                id: _idGen.nextUuid(),
                profileId: Value(profileId.value),
                actorUserId: userId,
                action: 'profile.base_currency_changed',
                targetType: 'profile',
                targetId: profileId.value,
                outcome: 'success',
                metadataRedactedJson: Value(
                  jsonEncode({'from': current.baseCurrencyCode, 'to': code}),
                ),
                createdAtUtc: now,
              ),
            );
      });
      return getProfile(profileId: profileId, userId: userId);
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  @override
  Future<Result<void>> archiveProfile({
    required ProfileId profileId,
    required String userId,
    bool queueSync = false,
  }) async {
    final currentRes = await getProfile(profileId: profileId, userId: userId);
    if (currentRes.isFailure) return FailureResult(currentRes.failureOrNull!);
    final current = currentRes.valueOrNull!;
    if (!current.permissions.canTransferOwnershipOrArchive) {
      return const FailureResult(AuthorizationFailure());
    }

    final now = _clock.nowIsoUtc();
    try {
      await _db.transaction(() async {
        await (_db.update(
          _db.profiles,
        )..where((t) => t.id.equals(profileId.value))).write(
          ProfilesCompanion(
            archivedAtUtc: Value(now),
            updatedAtUtc: Value(now),
            version: Value(current.version + 1),
          ),
        );

        await _db
            .into(_db.auditLogs)
            .insert(
              AuditLogsCompanion.insert(
                id: _idGen.nextUuid(),
                profileId: Value(profileId.value),
                actorUserId: userId,
                action: 'profile.archived',
                targetType: 'profile',
                targetId: profileId.value,
                outcome: 'success',
                createdAtUtc: now,
              ),
            );
      });
      return const Success(null);
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  @override
  Future<Result<List<ProfileMember>>> listMembers({
    required ProfileId profileId,
    required String requestingUserId,
  }) async {
    final access = await getProfile(
      profileId: profileId,
      userId: requestingUserId,
    );
    if (access.isFailure) return FailureResult(access.failureOrNull!);

    try {
      final rows =
          await (_db.select(_db.profileMemberships)
                ..where((m) => m.profileId.equals(profileId.value))
                ..orderBy([(m) => OrderingTerm.asc(m.createdAtUtc)]))
              .get();

      return Success(
        rows
            .map(
              (r) => ProfileMember(
                id: r.id,
                profileId: ProfileId(r.profileId),
                userId: r.userId,
                displayName: r.displayName,
                email: r.email,
                role: ProfileRole.fromWire(r.role),
                status: r.membershipStatus,
                createdAtUtc: r.createdAtUtc,
              ),
            )
            .toList(),
      );
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  @override
  Future<Result<ProfileMember>> addOrUpdateMember({
    required ProfileId profileId,
    required String requestingUserId,
    required String memberUserId,
    required String displayName,
    String? email,
    required ProfileRole role,
    bool queueSync = false,
  }) async {
    final access = await getProfile(
      profileId: profileId,
      userId: requestingUserId,
    );
    if (access.isFailure) return FailureResult(access.failureOrNull!);
    final caller = access.valueOrNull!;
    if (!caller.permissions.canManageMembers) {
      return const FailureResult(AuthorizationFailure());
    }
    if (role == ProfileRole.owner && caller.role != ProfileRole.owner) {
      return const FailureResult(AuthorizationFailure());
    }

    final now = _clock.nowIsoUtc();
    try {
      final existing =
          await (_db.select(_db.profileMemberships)..where(
                (m) =>
                    m.profileId.equals(profileId.value) &
                    m.userId.equals(memberUserId),
              ))
              .getSingleOrNull();

      final memberId = existing?.id ?? _idGen.nextUuid();
      await _db.transaction(() async {
        if (existing == null) {
          await _db
              .into(_db.profileMemberships)
              .insert(
                ProfileMembershipsCompanion.insert(
                  id: memberId,
                  profileId: profileId.value,
                  userId: memberUserId,
                  displayName: Value(displayName),
                  email: Value(email),
                  role: role.wireValue,
                  membershipStatus: 'active',
                  createdAtUtc: now,
                  updatedAtUtc: now,
                ),
              );
        } else {
          await (_db.update(
            _db.profileMemberships,
          )..where((m) => m.id.equals(existing.id))).write(
            ProfileMembershipsCompanion(
              displayName: Value(displayName),
              email: Value(email),
              role: Value(role.wireValue),
              membershipStatus: const Value('active'),
              updatedAtUtc: Value(now),
              version: Value(existing.version + 1),
            ),
          );
        }
        await _db
            .into(_db.auditLogs)
            .insert(
              AuditLogsCompanion.insert(
                id: _idGen.nextUuid(),
                profileId: Value(profileId.value),
                actorUserId: requestingUserId,
                action: 'membership.upserted',
                targetType: 'membership',
                targetId: memberId,
                outcome: 'success',
                metadataRedactedJson: Value(
                  jsonEncode({'role': role.wireValue}),
                ),
                createdAtUtc: now,
              ),
            );
      });

      return Success(
        ProfileMember(
          id: memberId,
          profileId: profileId,
          userId: memberUserId,
          displayName: displayName,
          email: email,
          role: role,
          status: 'active',
          createdAtUtc: existing?.createdAtUtc ?? now,
        ),
      );
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  @override
  Future<Result<void>> revokeMember({
    required ProfileId profileId,
    required String requestingUserId,
    required String memberId,
    bool queueSync = false,
  }) async {
    final access = await getProfile(
      profileId: profileId,
      userId: requestingUserId,
    );
    if (access.isFailure) return FailureResult(access.failureOrNull!);
    if (!access.valueOrNull!.permissions.canManageMembers) {
      return const FailureResult(AuthorizationFailure());
    }

    final target =
        await (_db.select(_db.profileMemberships)..where(
              (m) =>
                  m.id.equals(memberId) & m.profileId.equals(profileId.value),
            ))
            .getSingleOrNull();
    if (target == null) return const FailureResult(NotFoundFailure());
    if (target.role == 'owner') {
      return const FailureResult(
        ValidationFailure(message: 'Cannot revoke the profile Owner.'),
      );
    }

    final now = _clock.nowIsoUtc();
    try {
      await (_db.update(
        _db.profileMemberships,
      )..where((m) => m.id.equals(memberId))).write(
        ProfileMembershipsCompanion(
          membershipStatus: const Value('revoked'),
          updatedAtUtc: Value(now),
          version: Value(target.version + 1),
        ),
      );
      return const Success(null);
    } catch (_) {
      return const FailureResult(DatabaseFailure());
    }
  }

  Future<void> _seedSystemLedgerAndCategories({
    required String profileId,
    required ProfileType profileType,
    required String nowUtc,
  }) async {
    // 1. Core System Ledger Accounts
    final systemLedgers = [
      (
        code: SystemLedgerCodes.openingEquity,
        name: 'Opening Balance Equity',
        type: 'equity',
        normal: 'credit',
      ),
      (
        code: SystemLedgerCodes.fxVariance,
        name: 'FX Gain / Loss',
        type: 'expense',
        normal: 'debit',
      ),
      (
        code: SystemLedgerCodes.loanInterest,
        name: 'Loan Interest Expense',
        type: 'expense',
        normal: 'debit',
      ),
      (
        code: SystemLedgerCodes.loanFees,
        name: 'Loan Fees Expense',
        type: 'expense',
        normal: 'debit',
      ),
    ];

    for (final sl in systemLedgers) {
      await _db
          .into(_db.ledgerAccounts)
          .insert(
            LedgerAccountsCompanion.insert(
              id: _idGen.nextUuid(),
              profileId: profileId,
              name: sl.name,
              accountType: sl.type,
              normalBalance: sl.normal,
              systemCode: Value(sl.code),
              isSystem: const Value(true),
              createdAtUtc: nowUtc,
            ),
          );
    }

    // 2. Profile-scoped default categories (each mapped to its own offsetting ledger account)
    final defaultCats = profileType == ProfileType.business
        ? const [
            (name: 'Client Revenue', type: 'income', icon: 'payments'),
            (name: 'Consulting Fees', type: 'income', icon: 'work'),
            (name: 'Other Income', type: 'income', icon: 'add_card'),
            (name: 'Software & Cloud', type: 'expense', icon: 'cloud'),
            (name: 'Office & Rent', type: 'expense', icon: 'business'),
            (name: 'Payroll & Contractors', type: 'expense', icon: 'groups'),
            (name: 'Travel & Meals', type: 'expense', icon: 'flight'),
            (name: 'Marketing', type: 'expense', icon: 'campaign'),
            (name: 'Taxes & Compliance', type: 'expense', icon: 'receipt_long'),
          ]
        : const [
            (name: 'Salary', type: 'income', icon: 'account_balance_wallet'),
            (name: 'Freelance & Bonus', type: 'income', icon: 'trending_up'),
            (name: 'Interest & Dividends', type: 'income', icon: 'savings'),
            (name: 'Groceries', type: 'expense', icon: 'shopping_cart'),
            (name: 'Dining & Food', type: 'expense', icon: 'restaurant'),
            (name: 'Housing & Rent', type: 'expense', icon: 'home'),
            (name: 'Utilities & Bills', type: 'expense', icon: 'bolt'),
            (name: 'Transport & Fuel', type: 'expense', icon: 'directions_car'),
            (name: 'Healthcare', type: 'expense', icon: 'medical_services'),
            (name: 'Shopping', type: 'expense', icon: 'shopping_bag'),
            (name: 'Education', type: 'expense', icon: 'school'),
            (name: 'Entertainment', type: 'expense', icon: 'movie'),
          ];

    for (final cat in defaultCats) {
      final ledgerId = _idGen.nextUuid();
      final isIncome = cat.type == 'income';
      await _db
          .into(_db.ledgerAccounts)
          .insert(
            LedgerAccountsCompanion.insert(
              id: ledgerId,
              profileId: profileId,
              name: cat.name,
              accountType: isIncome ? 'income' : 'expense',
              normalBalance: isIncome ? 'credit' : 'debit',
              isSystem: const Value(true),
              createdAtUtc: nowUtc,
            ),
          );
      await _db
          .into(_db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: _idGen.nextUuid(),
              profileId: profileId,
              ledgerAccountId: ledgerId,
              name: cat.name,
              categoryType: cat.type,
              iconKey: Value(cat.icon),
              colorToken: Value(isIncome ? 'income' : 'expense'),
              isSystem: const Value(true),
              createdAtUtc: nowUtc,
              updatedAtUtc: nowUtc,
            ),
          );
    }
  }

  FinancialProfile _mapJoinedRow(TypedResult row) {
    final p = row.readTable(_db.profiles);
    final m = row.readTable(_db.profileMemberships);
    return FinancialProfile(
      id: ProfileId(p.id),
      name: p.name,
      profileType: ProfileType.fromWire(p.profileType),
      baseCurrencyCode: p.baseCurrencyCode,
      timezone: p.timezone,
      role: ProfileRole.fromWire(m.role),
      editorsCanPost: p.editorsCanPost,
      createdAtUtc: p.createdAtUtc,
      updatedAtUtc: p.updatedAtUtc,
      archivedAtUtc: p.archivedAtUtc,
      version: p.version,
      syncStatus: p.syncStatus,
    );
  }
}
