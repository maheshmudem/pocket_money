import '../../../../core/errors/failures.dart';
import '../../../../core/utilities/id_generator.dart';
import '../entities/profile_entity.dart';

abstract interface class ProfileRepository {
  Stream<List<FinancialProfile>> watchActiveProfiles({required String userId});

  Future<Result<List<FinancialProfile>>> listActiveProfiles({
    required String userId,
  });

  Future<Result<FinancialProfile>> getProfile({
    required ProfileId profileId,
    required String userId,
  });

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
  });

  Future<Result<FinancialProfile>> renameProfile({
    required ProfileId profileId,
    required String userId,
    required String newName,
    bool queueSync = false,
  });

  /// Updates mutable profile metadata (`name`, `profileType`, `baseCurrencyCode`,
  /// `timezone`, `editorsCanPost`). Base currency changes record a versioned
  /// [profileCurrencyHistory] entry without rewriting posted history (`FR-003`).
  Future<Result<FinancialProfile>> updateProfile({
    required ProfileId profileId,
    required String userId,
    required String name,
    required ProfileType profileType,
    String? baseCurrencyCode,
    String? timezone,
    bool? editorsCanPost,
    bool queueSync = false,
  });

  /// Records a versioned currency change without rewriting posted history (`FR-003`).
  Future<Result<FinancialProfile>> changeBaseCurrency({
    required ProfileId profileId,
    required String userId,
    required String newBaseCurrencyCode,
    String? note,
    bool queueSync = false,
  });

  Future<Result<void>> archiveProfile({
    required ProfileId profileId,
    required String userId,
    bool queueSync = false,
  });

  Future<Result<List<ProfileMember>>> listMembers({
    required ProfileId profileId,
    required String requestingUserId,
  });

  Future<Result<ProfileMember>> addOrUpdateMember({
    required ProfileId profileId,
    required String requestingUserId,
    required String memberUserId,
    required String displayName,
    String? email,
    required ProfileRole role,
    bool queueSync = false,
  });

  Future<Result<void>> revokeMember({
    required ProfileId profileId,
    required String requestingUserId,
    required String memberId,
    bool queueSync = false,
  });
}
