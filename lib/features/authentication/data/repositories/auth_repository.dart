import 'package:equatable/equatable.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/security/key_manager.dart';
import '../../../settings/data/settings_repository.dart';

final class AuthenticatedUser extends Equatable {
  const AuthenticatedUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.isLocalOnlyWorkspace,
  });

  static const localOwner = AuthenticatedUser(
    id: 'local-owner',
    email: 'local@device',
    displayName: 'Local Workspace',
    isLocalOnlyWorkspace: true,
  );

  final String id;
  final String email;
  final String displayName;
  final bool isLocalOnlyWorkspace;

  @override
  List<Object?> get props => [id, email, displayName, isLocalOnlyWorkspace];
}

final class RegisteredDevice extends Equatable {
  const RegisteredDevice({
    required this.deviceId,
    required this.platform,
    required this.appVersion,
    required this.lastSeenAtUtc,
    this.deviceLabel,
    this.revokedAtUtc,
  });

  final String deviceId;
  final String platform;
  final String appVersion;
  final String? deviceLabel;
  final String lastSeenAtUtc;
  final String? revokedAtUtc;

  bool get isRevoked => revokedAtUtc != null;

  @override
  List<Object?> get props => [
    deviceId,
    platform,
    appVersion,
    deviceLabel,
    lastSeenAtUtc,
    revokedAtUtc,
  ];
}

/// Manages cloud authentication (`FR-001`), registered devices (`FR-021`),
/// and immediate offline-first Local Workspace onboarding (Decision D-3).
final class AuthRepository {
  AuthRepository({
    required ApiClient apiClient,
    required KeyManager keyManager,
    required SettingsRepository settingsRepository,
    required String appVersion,
  }) : _api = apiClient,
       _keyManager = keyManager,
       _settings = settingsRepository,
       _appVersion = appVersion;

  final ApiClient _api;
  final KeyManager _keyManager;
  final SettingsRepository _settings;
  final String _appVersion;

  Future<AuthenticatedUser?> restoreSession() async {
    final mode = await _settings.getString('auth.mode');
    if (mode == 'local') {
      return AuthenticatedUser.localOwner;
    }
    if (mode == 'cloud') {
      final userId = await _settings.getString('auth.user_id');
      final email = await _settings.getString('auth.email');
      final name = await _settings.getString('auth.display_name');
      final refresh = await _keyManager.readRefreshToken();
      if (userId != null && email != null && refresh != null) {
        return AuthenticatedUser(
          id: userId,
          email: email,
          displayName: name ?? email,
          isLocalOnlyWorkspace: false,
        );
      }
    }
    return null;
  }

  Future<AuthenticatedUser> startLocalWorkspace() async {
    await _settings.setString('auth.mode', 'local');
    await _settings.setString('auth.user_id', AuthenticatedUser.localOwner.id);
    return AuthenticatedUser.localOwner;
  }

  Future<Result<AuthenticatedUser>> register({
    required String email,
    required String password,
    required String displayName,
    String platform = 'android',
  }) async {
    final deviceId = await _keyManager.getOrCreateDeviceId();
    final res = await _api.postJson(
      '/auth/register/',
      body: {
        'email': email.trim().toLowerCase(),
        'password': password,
        'display_name': displayName.trim(),
        'device_id': deviceId,
        'platform': platform,
        'app_version': _appVersion,
        'device_label': 'Pocket CFO Mobile',
      },
    );
    if (res.isFailure) return FailureResult(res.failureOrNull!);
    return _persistCloudSession(res.valueOrNull!);
  }

  Future<Result<AuthenticatedUser>> login({
    required String email,
    required String password,
    String platform = 'android',
  }) async {
    final deviceId = await _keyManager.getOrCreateDeviceId();
    final res = await _api.postJson(
      '/auth/login/',
      body: {
        'email': email.trim().toLowerCase(),
        'password': password,
        'device_id': deviceId,
        'platform': platform,
        'app_version': _appVersion,
        'device_label': 'Pocket CFO Mobile',
      },
    );
    if (res.isFailure) return FailureResult(res.failureOrNull!);
    return _persistCloudSession(res.valueOrNull!);
  }

  Future<Result<void>> requestPasswordReset(String email) async {
    final res = await _api.postJson(
      '/auth/password-reset/',
      body: {'email': email.trim().toLowerCase()},
    );
    if (res.isFailure) return FailureResult(res.failureOrNull!);
    return const Success(null);
  }

  Future<void> logout() async {
    final refresh = await _keyManager.readRefreshToken();
    if (refresh != null && _api.hasAccessToken) {
      await _api.postJson('/auth/logout/', body: {'refresh_token': refresh});
    }
    await _api.clearTokens();
    await _settings.setString('auth.mode', '');
  }

  Future<Result<List<RegisteredDevice>>> listDevices() async {
    final res = await _api.getJson('/devices/');
    if (res.isFailure) return FailureResult(res.failureOrNull!);
    final rows = (res.valueOrNull!['data'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    return Success(
      rows
          .map(
            (r) => RegisteredDevice(
              deviceId: r['device_id'] as String,
              platform: r['platform'] as String,
              appVersion: r['app_version'] as String,
              deviceLabel: r['device_label'] as String?,
              lastSeenAtUtc: r['last_seen_at_utc'] as String? ?? '',
              revokedAtUtc: r['revoked_at_utc'] as String?,
            ),
          )
          .toList(),
    );
  }

  Future<Result<void>> revokeDevice(String deviceId) =>
      _api.delete('/devices/$deviceId/');

  Future<Result<AuthenticatedUser>> _persistCloudSession(
    Map<String, dynamic> response,
  ) async {
    final data = response['data'] as Map<String, dynamic>?;
    if (data == null) {
      return const FailureResult(UnexpectedFailure());
    }
    final accessToken = data['access_token'] as String;
    final refreshToken = data['refresh_token'] as String;
    final userMap = data['user'] as Map<String, dynamic>;

    _api.setAccessToken(accessToken);
    await _keyManager.saveRefreshToken(refreshToken);

    final user = AuthenticatedUser(
      id: userMap['id'] as String,
      email: userMap['email'] as String,
      displayName: userMap['display_name'] as String,
      isLocalOnlyWorkspace: false,
    );

    await _settings.setString('auth.mode', 'cloud');
    await _settings.setString('auth.user_id', user.id);
    await _settings.setString('auth.email', user.email);
    await _settings.setString('auth.display_name', user.displayName);

    return Success(user);
  }
}
