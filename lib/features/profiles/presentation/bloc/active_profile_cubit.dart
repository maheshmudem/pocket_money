import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/utilities/id_generator.dart';
import '../../../../core/utilities/profile_scope_controller.dart';
import '../../../settings/data/settings_repository.dart';
import '../../domain/entities/profile_entity.dart';
import '../../domain/repositories/profile_repository.dart';

enum ActiveProfileStatus { initial, loading, loaded, empty, failure }

final class ActiveProfileState extends Equatable {
  const ActiveProfileState({
    this.status = ActiveProfileStatus.initial,
    this.profiles = const [],
    this.activeProfile,
    this.scopeEpoch = 0,
    this.failure,
  });

  final ActiveProfileStatus status;
  final List<FinancialProfile> profiles;
  final FinancialProfile? activeProfile;
  final int scopeEpoch;
  final AppFailure? failure;

  ActiveProfileState copyWith({
    ActiveProfileStatus? status,
    List<FinancialProfile>? profiles,
    FinancialProfile? activeProfile,
    bool clearActive = false,
    int? scopeEpoch,
    AppFailure? failure,
    bool clearFailure = false,
  }) => ActiveProfileState(
    status: status ?? this.status,
    profiles: profiles ?? this.profiles,
    activeProfile: clearActive ? null : (activeProfile ?? this.activeProfile),
    scopeEpoch: scopeEpoch ?? this.scopeEpoch,
    failure: clearFailure ? null : (failure ?? this.failure),
  );

  @override
  List<Object?> get props => [
    status,
    profiles,
    activeProfile,
    scopeEpoch,
    failure,
  ];
}

class ActiveProfileCubit extends Cubit<ActiveProfileState> {
  ActiveProfileCubit({
    required ProfileRepository repository,
    required ProfileScopeController scopeController,
    required SettingsRepository settings,
  }) : _repo = repository,
       _scope = scopeController,
       _settings = settings,
       super(const ActiveProfileState());

  final ProfileRepository _repo;
  final ProfileScopeController _scope;
  final SettingsRepository _settings;
  String _currentUserId = 'local-owner';

  Future<void> loadProfiles({required String userId}) async {
    _currentUserId = userId;
    emit(
      state.copyWith(status: ActiveProfileStatus.loading, clearFailure: true),
    );
    final res = await _repo.listActiveProfiles(userId: userId);
    await res.fold(
      onSuccess: (profiles) async {
        if (profiles.isEmpty) {
          final snap = _scope.clearScope();
          emit(
            ActiveProfileState(
              status: ActiveProfileStatus.empty,
              profiles: const [],
              scopeEpoch: snap.epoch,
            ),
          );
          return;
        }
        final savedId = await _settings.getString(
          'workspace.active_profile_id',
        );
        final selected = profiles.firstWhere(
          (p) => p.id.value == savedId,
          orElse: () => profiles.first,
        );
        final snap = _scope.switchTo(
          profileId: selected.id,
          role: selected.role.wireValue,
          baseCurrencyCode: selected.baseCurrencyCode,
          timezone: selected.timezone,
        );
        emit(
          ActiveProfileState(
            status: ActiveProfileStatus.loaded,
            profiles: profiles,
            activeProfile: selected,
            scopeEpoch: snap.epoch,
          ),
        );
      },
      onFailure: (f) async {
        emit(state.copyWith(status: ActiveProfileStatus.failure, failure: f));
      },
    );
  }

  /// Validates active membership and atomically switches profile scope,
  /// incrementing epoch to reject stale data from previous profile (`AC-PROFILE-001`).
  Future<bool> switchProfile(ProfileId targetProfileId) async {
    if (state.status == ActiveProfileStatus.loaded &&
        state.activeProfile?.id == targetProfileId) {
      return true;
    }
    final res = await _repo.getProfile(
      profileId: targetProfileId,
      userId: _currentUserId,
    );
    return res.fold(
      onSuccess: (profile) async {
        final existing = state.profiles;
        final updatedProfiles = existing.any((p) => p.id == profile.id)
            ? [
                for (final p in existing)
                  if (p.id == profile.id) profile else p,
              ]
            : [...existing, profile];
        final snap = _scope.switchTo(
          profileId: profile.id,
          role: profile.role.wireValue,
          baseCurrencyCode: profile.baseCurrencyCode,
          timezone: profile.timezone,
        );
        emit(
          ActiveProfileState(
            status: ActiveProfileStatus.loaded,
            profiles: updatedProfiles,
            activeProfile: profile,
            scopeEpoch: snap.epoch,
          ),
        );
        await _settings.setString(
          'workspace.active_profile_id',
          profile.id.value,
        );
        final listRes = await _repo.listActiveProfiles(userId: _currentUserId);
        final latestList = listRes.valueOrNull;
        if (!isClosed &&
            latestList != null &&
            _scope.currentEpoch == snap.epoch &&
            latestList.length != updatedProfiles.length) {
          emit(state.copyWith(profiles: latestList));
        }
        return true;
      },
      onFailure: (f) async {
        emit(state.copyWith(failure: f));
        return false;
      },
    );
  }

  /// Cycles to the next (or previous) active financial profile without interruption.
  /// Powers Play Store swipe-down and Instagram bottom-bar profile switching.
  Future<FinancialProfile?> cycleNextProfile({bool reverse = false}) async {
    final list = state.profiles;
    if (list.length < 2) return null;
    final currentId = state.activeProfile?.id;
    final currentIdx = list.indexWhere((p) => p.id == currentId);
    final baseIdx = currentIdx < 0 ? 0 : currentIdx;
    final nextIdx = (baseIdx + (reverse ? -1 : 1) + list.length) % list.length;
    final target = list[nextIdx];
    final ok = await switchProfile(target.id);
    return ok ? (state.activeProfile ?? target) : null;
  }

  Future<Result<FinancialProfile>> createProfile({
    required String ownerDisplayName,
    String? ownerEmail,
    required String name,
    required ProfileType profileType,
    required String baseCurrencyCode,
    String timezone = 'Asia/Kolkata',
    bool queueSync = false,
  }) async {
    final res = await _repo.createProfile(
      userId: _currentUserId,
      ownerDisplayName: ownerDisplayName,
      ownerEmail: ownerEmail,
      name: name,
      profileType: profileType,
      baseCurrencyCode: baseCurrencyCode,
      timezone: timezone,
      queueSync: queueSync,
    );
    if (res.isSuccess) {
      await switchProfile(res.valueOrNull!.id);
    }
    return res;
  }

  Future<Result<FinancialProfile>> renameActiveProfile(String newName) async {
    final active = state.activeProfile;
    if (active == null) return const FailureResult(NotFoundFailure());
    final res = await _repo.renameProfile(
      profileId: active.id,
      userId: _currentUserId,
      newName: newName,
    );
    if (res.isSuccess) {
      await loadProfiles(userId: _currentUserId);
    }
    return res;
  }

  Future<Result<FinancialProfile>> updateProfile({
    required ProfileId profileId,
    required String name,
    required ProfileType profileType,
    String? baseCurrencyCode,
    String? timezone,
    bool? editorsCanPost,
    bool queueSync = false,
  }) async {
    final res = await _repo.updateProfile(
      profileId: profileId,
      userId: _currentUserId,
      name: name,
      profileType: profileType,
      baseCurrencyCode: baseCurrencyCode,
      timezone: timezone,
      editorsCanPost: editorsCanPost,
      queueSync: queueSync,
    );
    if (res.isSuccess) {
      await loadProfiles(userId: _currentUserId);
    }
    return res;
  }

  Future<Result<void>> archiveProfile(
    ProfileId profileId, {
    bool queueSync = false,
  }) async {
    if (state.profiles.length <= 1) {
      return const FailureResult(
        ValidationFailure(
          message: 'Keep at least one active financial profile.',
        ),
      );
    }
    final res = await _repo.archiveProfile(
      profileId: profileId,
      userId: _currentUserId,
      queueSync: queueSync,
    );
    if (res.isSuccess) {
      await loadProfiles(userId: _currentUserId);
    }
    return res;
  }

  Future<Result<FinancialProfile>> changeActiveBaseCurrency(
    String newCurrencyCode, {
    String? note,
  }) async {
    final active = state.activeProfile;
    if (active == null) return const FailureResult(NotFoundFailure());
    return changeProfileBaseCurrency(
      profileId: active.id,
      newCurrencyCode: newCurrencyCode,
      note: note,
    );
  }

  Future<Result<FinancialProfile>> changeProfileBaseCurrency({
    required ProfileId profileId,
    required String newCurrencyCode,
    String? note,
  }) async {
    final res = await _repo.changeBaseCurrency(
      profileId: profileId,
      userId: _currentUserId,
      newBaseCurrencyCode: newCurrencyCode,
      note: note,
    );
    if (res.isSuccess) {
      await loadProfiles(userId: _currentUserId);
    }
    return res;
  }

  void clearOnLogout() {
    final snap = _scope.clearScope();
    emit(ActiveProfileState(scopeEpoch: snap.epoch));
  }
}
