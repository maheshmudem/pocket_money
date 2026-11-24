import 'package:equatable/equatable.dart';

import '../../../../core/utilities/id_generator.dart';

enum ProfileType {
  personal('personal', 'Personal'),
  family('family', 'Family'),
  business('business', 'Business');

  const ProfileType(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static ProfileType fromWire(String raw) => switch (raw) {
    'family' => ProfileType.family,
    'business' => ProfileType.business,
    _ => ProfileType.personal,
  };
}

enum ProfileRole {
  owner('owner', 'Owner'),
  admin('admin', 'Admin'),
  editor('editor', 'Editor'),
  viewer('viewer', 'Viewer');

  const ProfileRole(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static ProfileRole fromWire(String raw) => switch (raw) {
    'owner' => ProfileRole.owner,
    'admin' => ProfileRole.admin,
    'editor' => ProfileRole.editor,
    _ => ProfileRole.viewer,
  };
}

/// Domain enforcement of `ROLE_AND_PERMISSION_MATRIX.md` & Decision D-7.
final class ProfilePermissions extends Equatable {
  const ProfilePermissions({required this.role, required this.editorsCanPost});

  final ProfileRole role;
  final bool editorsCanPost;

  bool get canView => true;
  bool get canCreateDraft =>
      role == ProfileRole.owner ||
      role == ProfileRole.admin ||
      role == ProfileRole.editor;
  bool get canPostTransaction =>
      role == ProfileRole.owner ||
      role == ProfileRole.admin ||
      (role == ProfileRole.editor && editorsCanPost);
  bool get canReverseOrVoid =>
      role == ProfileRole.owner || role == ProfileRole.admin;
  bool get canManageCategoriesAndBudgets =>
      role == ProfileRole.owner ||
      role == ProfileRole.admin ||
      role == ProfileRole.editor;
  bool get canManageMembers =>
      role == ProfileRole.owner || role == ProfileRole.admin;
  bool get canChangeSettingsOrCurrency => role == ProfileRole.owner;
  bool get canTransferOwnershipOrArchive => role == ProfileRole.owner;

  @override
  List<Object?> get props => [role, editorsCanPost];
}

final class FinancialProfile extends Equatable {
  const FinancialProfile({
    required this.id,
    required this.name,
    required this.profileType,
    required this.baseCurrencyCode,
    required this.timezone,
    required this.role,
    required this.editorsCanPost,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.version,
    required this.syncStatus,
    this.archivedAtUtc,
  });

  final ProfileId id;
  final String name;
  final ProfileType profileType;
  final String baseCurrencyCode;
  final String timezone;
  final ProfileRole role;
  final bool editorsCanPost;
  final String createdAtUtc;
  final String updatedAtUtc;
  final String? archivedAtUtc;
  final int version;
  final String syncStatus;

  ProfilePermissions get permissions =>
      ProfilePermissions(role: role, editorsCanPost: editorsCanPost);

  @override
  List<Object?> get props => [
    id,
    name,
    profileType,
    baseCurrencyCode,
    timezone,
    role,
    editorsCanPost,
    createdAtUtc,
    updatedAtUtc,
    archivedAtUtc,
    version,
    syncStatus,
  ];
}

final class ProfileMember extends Equatable {
  const ProfileMember({
    required this.id,
    required this.profileId,
    required this.userId,
    required this.displayName,
    required this.role,
    required this.status,
    required this.createdAtUtc,
    this.email,
  });

  final String id;
  final ProfileId profileId;
  final String userId;
  final String displayName;
  final String? email;
  final ProfileRole role;
  final String status;
  final String createdAtUtc;

  @override
  List<Object?> get props => [
    id,
    profileId,
    userId,
    displayName,
    email,
    role,
    status,
    createdAtUtc,
  ];
}
