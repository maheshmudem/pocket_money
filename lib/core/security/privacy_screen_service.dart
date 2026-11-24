import 'package:flutter/services.dart';

/// Bridges Flutter privacy lock state to native Android `FLAG_SECURE` so
/// sensitive balances do not appear in recent-apps thumbnails (`SEC-001`).
final class PrivacyScreenService {
  const PrivacyScreenService();

  static const _channel = MethodChannel('com.pocketcfo.app/privacy_screen');

  Future<void> setSecureScreen({required bool enabled}) async {
    try {
      await _channel.invokeMethod<void>('setSecureScreen', {
        'enabled': enabled,
      });
    } on MissingPluginException {
      // Non-Android platforms / unit tests handle privacy overlay in Flutter UI.
    } on PlatformException {
      // Best-effort native flag; Flutter overlay still enforces privacy curtain.
    } catch (_) {
      // Headless pure-Dart unit tests without WidgetsBinding initialized.
    }
  }
}
