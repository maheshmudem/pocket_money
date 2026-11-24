import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import '../errors/failures.dart';

/// Metadata header stored alongside an encrypted `.pcfo` backup payload.
final class BackupEnvelopeMetadata {
  const BackupEnvelopeMetadata({
    required this.formatVersion,
    required this.schemaVersion,
    required this.appVersion,
    required this.createdAtUtc,
    required this.profileIds,
    required this.payloadSha256,
  });

  final int formatVersion;
  final int schemaVersion;
  final String appVersion;
  final String createdAtUtc;
  final List<String> profileIds;
  final String payloadSha256;

  Map<String, Object?> toJson() => {
    'format_version': formatVersion,
    'schema_version': schemaVersion,
    'app_version': appVersion,
    'created_at_utc': createdAtUtc,
    'profile_ids': profileIds,
    'payload_sha256': payloadSha256,
  };

  factory BackupEnvelopeMetadata.fromJson(Map<String, dynamic> json) {
    return BackupEnvelopeMetadata(
      formatVersion: json['format_version'] as int,
      schemaVersion: json['schema_version'] as int,
      appVersion: json['app_version'] as String,
      createdAtUtc: json['created_at_utc'] as String,
      profileIds: (json['profile_ids'] as List<dynamic>).cast<String>(),
      payloadSha256: json['payload_sha256'] as String,
    );
  }
}

final class DecryptedBackup {
  const DecryptedBackup({required this.metadata, required this.payloadJson});

  final BackupEnvelopeMetadata metadata;
  final Map<String, dynamic> payloadJson;
}

/// Authenticated passphrase encryption for `.pcfo` local backups (`FR-024`, `BACKUP_AND_RESTORE.md`).
/// Uses PBKDF2-HMAC-SHA256 + AES-256-GCM + SHA-256 payload digest verification.
final class BackupCrypto {
  const BackupCrypto({this.kdfIterations = 210000});

  static const int currentFormatVersion = 1;
  final int kdfIterations;

  Future<String> encryptBackup({
    required Map<String, dynamic> payloadJson,
    required String passphrase,
    required int schemaVersion,
    required String appVersion,
    required List<String> profileIds,
    required String createdAtUtc,
  }) async {
    if (passphrase.length < 8) {
      throw const SecurityFailure(
        message: 'Backup passphrase must be at least 8 characters.',
      );
    }

    final plaintextBytes = utf8.encode(jsonEncode(payloadJson));
    final payloadSha256 = crypto.sha256.convert(plaintextBytes).toString();
    final salt = _randomBytes(16);
    final nonce = _randomBytes(12);

    final metadata = BackupEnvelopeMetadata(
      formatVersion: currentFormatVersion,
      schemaVersion: schemaVersion,
      appVersion: appVersion,
      createdAtUtc: createdAtUtc,
      profileIds: profileIds,
      payloadSha256: payloadSha256,
    );
    final aadBytes = utf8.encode(jsonEncode(metadata.toJson()));

    final secretKey = await _deriveKey(
      passphrase: passphrase,
      salt: salt,
      iterations: kdfIterations,
    );
    final cipher = AesGcm.with256bits();
    final box = await cipher.encrypt(
      plaintextBytes,
      secretKey: secretKey,
      nonce: nonce,
      aad: aadBytes,
    );

    return jsonEncode({
      'magic': 'POCKET_CFO_BACKUP',
      'metadata': metadata.toJson(),
      'kdf': {
        'algorithm': 'PBKDF2-HMAC-SHA256',
        'iterations': kdfIterations,
        'salt_b64': base64Encode(salt),
      },
      'cipher': {
        'algorithm': 'AES-256-GCM',
        'nonce_b64': base64Encode(nonce),
        'ciphertext_b64': base64Encode(box.cipherText),
        'mac_b64': base64Encode(box.mac.bytes),
      },
    });
  }

  Future<DecryptedBackup> decryptBackup({
    required String rawArchive,
    required String passphrase,
  }) async {
    try {
      final decoded = jsonDecode(rawArchive);
      if (decoded is! Map<String, dynamic> ||
          decoded['magic'] != 'POCKET_CFO_BACKUP') {
        throw const SecurityFailure(
          message: 'Selected file is not a valid Pocket CFO backup archive.',
        );
      }

      final metadataMap = decoded['metadata'] as Map<String, dynamic>;
      final metadata = BackupEnvelopeMetadata.fromJson(metadataMap);
      if (metadata.formatVersion > currentFormatVersion) {
        throw const SecurityFailure(
          message:
              'Backup format version is newer than this app version supports.',
        );
      }

      final kdfMap = decoded['kdf'] as Map<String, dynamic>;
      final cipherMap = decoded['cipher'] as Map<String, dynamic>;
      final iterations = kdfMap['iterations'] as int;
      final salt = base64Decode(kdfMap['salt_b64'] as String);
      final nonce = base64Decode(cipherMap['nonce_b64'] as String);
      final cipherText = base64Decode(cipherMap['ciphertext_b64'] as String);
      final macBytes = base64Decode(cipherMap['mac_b64'] as String);

      final secretKey = await _deriveKey(
        passphrase: passphrase,
        salt: salt,
        iterations: iterations,
      );
      final aadBytes = utf8.encode(jsonEncode(metadata.toJson()));

      final cipher = AesGcm.with256bits();
      final plaintext = await cipher.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
        secretKey: secretKey,
        aad: aadBytes,
      );

      final actualSha = crypto.sha256.convert(plaintext).toString();
      if (actualSha != metadata.payloadSha256) {
        throw const SecurityFailure(
          message:
              'Backup integrity verification failed. File may be corrupted.',
        );
      }

      final payload =
          jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
      return DecryptedBackup(metadata: metadata, payloadJson: payload);
    } on SecurityFailure {
      rethrow;
    } on SecretBoxAuthenticationError {
      throw const SecurityFailure(
        message: 'Incorrect backup passphrase or tampered backup file.',
      );
    } catch (_) {
      throw const SecurityFailure(
        message:
            'Could not read backup file. Ensure the archive is valid and unmodified.',
      );
    }
  }

  Future<SecretKey> _deriveKey({
    required String passphrase,
    required List<int> salt,
    required int iterations,
  }) {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    return pbkdf2.deriveKeyFromPassword(password: passphrase, nonce: salt);
  }

  static List<int> _randomBytes(int length) {
    final rng = Random.secure();
    return List<int>.generate(length, (_) => rng.nextInt(256));
  }
}
