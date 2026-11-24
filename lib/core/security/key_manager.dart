import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Abstraction over hardware-backed key storage (Android KeyStore / iOS Keychain)
/// so security flows are deterministically testable without platform channels.
abstract interface class SecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<void> deleteAll();
}

final class PlatformSecureKeyValueStore implements SecureKeyValueStore {
  PlatformSecureKeyValueStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}

final class InMemorySecureKeyValueStore implements SecureKeyValueStore {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<void> deleteAll() async => _data.clear();
}

/// Manages cryptographic keys, refresh token storage, device ID, and salted
/// PBKDF2-HMAC-SHA256 App PIN credentials (`SEC-001`, `ADR-005`).
final class KeyManager {
  KeyManager(this._store);

  final SecureKeyValueStore _store;

  static const _dbKeySlot = 'pocket_cfo.db_dek.v1';
  static const _refreshTokenSlot = 'pocket_cfo.refresh_token.v1';
  static const _deviceIdSlot = 'pocket_cfo.device_id.v1';
  static const _pinHashSlot = 'pocket_cfo.app_pin_hash.v1';
  static const _pinSaltSlot = 'pocket_cfo.app_pin_salt.v1';
  static const _pinIterations = 120000;

  /// Returns the existing 256-bit hex DB Encryption Key or generates a new CSPRNG one.
  Future<String> getOrCreateDatabaseKeyHex() async {
    final existing = await _store.read(_dbKeySlot);
    if (existing != null && existing.length == 64) {
      return existing;
    }
    final bytes = _randomBytes(32);
    final hex = _toHex(bytes);
    await _store.write(_dbKeySlot, hex);
    return hex;
  }

  /// Stable installation UUID registered with `/api/v1/devices/`.
  Future<String> getOrCreateDeviceId() async {
    final existing = await _store.read(_deviceIdSlot);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final created = const Uuid().v4();
    await _store.write(_deviceIdSlot, created);
    return created;
  }

  Future<String?> readRefreshToken() => _store.read(_refreshTokenSlot);

  Future<void> saveRefreshToken(String token) =>
      _store.write(_refreshTokenSlot, token);

  Future<void> clearRefreshToken() => _store.delete(_refreshTokenSlot);

  Future<bool> hasAppPin() async {
    final hash = await _store.read(_pinHashSlot);
    return hash != null && hash.isNotEmpty;
  }

  /// Stores a salted PBKDF2-HMAC-SHA256 hash of the user's fallback PIN.
  /// Never stores plaintext PINs in secure storage or SQLite.
  Future<void> setAppPin(String pin) async {
    final trimmed = pin.trim();
    if (trimmed.length < 4 || trimmed.length > 12) {
      throw ArgumentError('PIN must be between 4 and 12 characters.');
    }
    final salt = _randomBytes(16);
    final derived = await _derivePinHash(trimmed, salt);
    await _store.write(_pinSaltSlot, base64Encode(salt));
    await _store.write(_pinHashSlot, base64Encode(derived));
  }

  Future<bool> verifyAppPin(String candidatePin) async {
    final storedHashB64 = await _store.read(_pinHashSlot);
    final storedSaltB64 = await _store.read(_pinSaltSlot);
    if (storedHashB64 == null || storedSaltB64 == null) {
      return false;
    }
    final salt = base64Decode(storedSaltB64);
    final expected = base64Decode(storedHashB64);
    final actual = await _derivePinHash(candidatePin.trim(), salt);
    return _constantTimeEquals(expected, actual);
  }

  Future<void> clearAppPin() async {
    await _store.delete(_pinHashSlot);
    await _store.delete(_pinSaltSlot);
  }

  Future<List<int>> _derivePinHash(String pin, List<int> salt) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _pinIterations,
      bits: 256,
    );
    final key = await pbkdf2.deriveKeyFromPassword(password: pin, nonce: salt);
    return key.extractBytes();
  }

  static List<int> _randomBytes(int length) {
    final rng = Random.secure();
    return List<int>.generate(length, (_) => rng.nextInt(256));
  }

  static String _toHex(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
