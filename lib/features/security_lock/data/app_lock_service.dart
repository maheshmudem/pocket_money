import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../../../core/security/key_manager.dart';
import '../../../core/security/privacy_screen_service.dart';
import '../../settings/data/settings_repository.dart';

/// Biometric + Salted-PIN fallback local access gate (`FR-023`, `AC-SEC-001`, `SEC-001`).
/// Biometrics never replace database encryption; they gate local UI access and
/// always degrade gracefully to PIN fallback when hardware is unavailable/fails.
class AppLockService {
  AppLockService({
    required KeyManager keyManager,
    required SettingsRepository settings,
    required PrivacyScreenService privacyScreen,
    LocalAuthentication? localAuth,
  }) : _keyManager = keyManager,
       _settings = settings,
       _privacyScreen = privacyScreen,
       _localAuth = localAuth ?? LocalAuthentication();

  final KeyManager _keyManager;
  final SettingsRepository _settings;
  final PrivacyScreenService _privacyScreen;
  final LocalAuthentication _localAuth;

  static const _lockEnabledKey = 'security.app_lock_enabled';
  static const _biometricEnabledKey = 'security.biometric_enabled';
  static const _timeoutSecKey = 'security.lock_timeout_seconds';
  static const _privacyCurtainKey = 'security.privacy_curtain_enabled';
  static const _blockScreenshotsKey = 'security.block_screenshots_enabled';

  Future<bool> isAppLockEnabled() => _settings.getBool(_lockEnabledKey);

  Future<bool> isBiometricEnabled() => _settings.getBool(_biometricEnabledKey);

  Future<int> getLockTimeoutSeconds() =>
      _settings.getInt(_timeoutSecKey, defaultValue: 30);

  Future<bool> isPrivacyCurtainEnabled() =>
      _settings.getBool(_privacyCurtainKey, defaultValue: true);

  Future<bool> isBlockScreenshotsEnabled() =>
      _settings.getBool(_blockScreenshotsKey, defaultValue: true);

  Future<bool> hasFallbackPin() => _keyManager.hasAppPin();

  Future<bool> canUseBiometrics() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      return supported && canCheck;
    } catch (_) {
      return false;
    }
  }

  Future<void> enableAppLock({
    required String fallbackPin,
    required bool useBiometrics,
    int timeoutSeconds = 30,
  }) async {
    await _keyManager.setAppPin(fallbackPin);
    await _settings.setBool(_lockEnabledKey, true);
    await _settings.setBool(_biometricEnabledKey, useBiometrics);
    await _settings.setInt(_timeoutSecKey, timeoutSeconds);
    final blockScreenshots = await isBlockScreenshotsEnabled();
    await _privacyScreen.setSecureScreen(enabled: blockScreenshots);
  }

  Future<void> disableAppLock() async {
    await _settings.setBool(_lockEnabledKey, false);
    await _settings.setBool(_biometricEnabledKey, false);
    await _keyManager.clearAppPin();
  }

  Future<void> setPrivacyCurtainEnabled(bool enabled) async {
    await _settings.setBool(_privacyCurtainKey, enabled);
  }

  Future<void> setBlockScreenshotsEnabled(bool enabled) async {
    await _settings.setBool(_blockScreenshotsKey, enabled);
    await _privacyScreen.setSecureScreen(enabled: enabled);
  }

  /// Attempts OS biometric auth; returns `false` on failure/unavailable so UI
  /// seamlessly displays the mandatory fallback PIN entry (`AC-SEC-001`).
  Future<bool> authenticateWithBiometrics() async {
    try {
      final available = await canUseBiometrics();
      if (!available) return false;
      return await _localAuth.authenticate(
        localizedReason: 'Unlock Pocket CFO to access your financial records',
        biometricOnly: true,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException {
      return false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> verifyPin(String pin) => _keyManager.verifyAppPin(pin);
}
