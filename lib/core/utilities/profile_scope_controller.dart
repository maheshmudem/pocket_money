import 'dart:async';

import 'package:equatable/equatable.dart';

import 'id_generator.dart';

/// Immutable active profile scope snapshot tagged with a strictly monotonic
/// [epoch] so stale in-flight async work from a previous profile can never
/// overwrite UI state after a profile switch (`AC-PROFILE-001`, `TC-FIN-017`).
final class ProfileScopeSnapshot extends Equatable {
  const ProfileScopeSnapshot({
    required this.epoch,
    required this.profileId,
    required this.role,
    required this.baseCurrencyCode,
    required this.timezone,
  });

  final int epoch;
  final ProfileId? profileId;
  final String? role;
  final String baseCurrencyCode;
  final String timezone;

  bool get hasActiveProfile => profileId != null;

  @override
  List<Object?> get props => [
    epoch,
    profileId,
    role,
    baseCurrencyCode,
    timezone,
  ];
}

final class ProfileScopeController {
  ProfileScopeController()
    : _current = const ProfileScopeSnapshot(
        epoch: 0,
        profileId: null,
        role: null,
        baseCurrencyCode: 'INR',
        timezone: 'Asia/Kolkata',
      );

  final StreamController<ProfileScopeSnapshot> _controller =
      StreamController<ProfileScopeSnapshot>.broadcast();
  final List<void Function()> _invalidationHooks = [];

  ProfileScopeSnapshot _current;

  ProfileScopeSnapshot get current => _current;
  int get currentEpoch => _current.epoch;
  Stream<ProfileScopeSnapshot> get stream => _controller.stream;

  void registerCacheInvalidationHook(void Function() hook) {
    _invalidationHooks.add(hook);
  }

  /// Atomically advances epoch, clears all registered profile-scoped caches,
  /// and broadcasts the new authorized profile scope.
  ProfileScopeSnapshot switchTo({
    required ProfileId profileId,
    required String role,
    required String baseCurrencyCode,
    required String timezone,
  }) {
    for (final hook in _invalidationHooks) {
      hook();
    }
    _current = ProfileScopeSnapshot(
      epoch: _current.epoch + 1,
      profileId: profileId,
      role: role,
      baseCurrencyCode: baseCurrencyCode,
      timezone: timezone,
    );
    if (!_controller.isClosed) {
      _controller.add(_current);
    }
    return _current;
  }

  /// Clears active profile scope (e.g., on logout or membership revocation).
  ProfileScopeSnapshot clearScope() {
    for (final hook in _invalidationHooks) {
      hook();
    }
    _current = ProfileScopeSnapshot(
      epoch: _current.epoch + 1,
      profileId: null,
      role: null,
      baseCurrencyCode: 'INR',
      timezone: 'Asia/Kolkata',
    );
    if (!_controller.isClosed) {
      _controller.add(_current);
    }
    return _current;
  }

  bool isCurrentEpoch(int epoch, ProfileId? expectedProfileId) {
    return _current.epoch == epoch && _current.profileId == expectedProfileId;
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}
