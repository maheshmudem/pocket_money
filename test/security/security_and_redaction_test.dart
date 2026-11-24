import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_money/core/errors/failures.dart';
import 'package:pocket_money/core/logging/redacting_logger.dart';
import 'package:pocket_money/core/security/backup_crypto.dart';
import 'package:pocket_money/core/security/key_manager.dart';

void main() {
  group('Security, Privacy & Cryptography Verification', () {
    test(
      'R-011 RedactingLogger strips secrets, amounts, notes, JWTs and emails',
      () {
        final emitted = <String>[];
        final logger = RedactingLogger(sink: emitted.add);

        logger.error(
          'transactions',
          'Failed for user@example.com with Bearer secret_abc_12345',
          requestId: 'req-001',
          errorCategory: 'validation',
          metadata: {
            'password': 'SuperSecretPassword!',
            'refresh_token':
                'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTYifQ.sig123456789',
            'amount_minor': 99900,
            'description': 'Rent payment to landlord',
            'safe_status': 'retryable_error',
          },
        );

        expect(emitted, hasLength(1));
        final line = emitted.single;
        expect(line, isNot(contains('SuperSecretPassword')));
        expect(line, isNot(contains('secret_abc_12345')));
        expect(line, isNot(contains('eyJhbGci')));
        expect(line, isNot(contains('user@example.com')));
        expect(line, isNot(contains('99900')));
        expect(line, isNot(contains('Rent payment')));
        expect(line, contains('retryable_error'));
        expect(line, contains('[REDACTED]'));
      },
    );

    test(
      'KeyManager generates 256-bit DEK and hashes fallback PIN with salted PBKDF2',
      () async {
        final store = InMemorySecureKeyValueStore();
        final km = KeyManager(store);

        final key1 = await km.getOrCreateDatabaseKeyHex();
        final key2 = await km.getOrCreateDatabaseKeyHex();
        expect(key1.length, 64);
        expect(key2, key1);

        expect(await km.hasAppPin(), isFalse);
        await km.setAppPin('482910');
        expect(await km.hasAppPin(), isTrue);
        expect(await km.verifyAppPin('482910'), isTrue);
        expect(await km.verifyAppPin('482911'), isFalse);

        // Ensure raw PIN is never stored anywhere in secure storage.
        final storedHash = await store.read('pocket_cfo.app_pin_hash.v1');
        expect(storedHash, isNot(contains('482910')));
      },
    );

    test(
      'FR-024 BackupCrypto AES-256-GCM encrypts, authenticates, and rejects wrong passphrase/tampering',
      () async {
        const crypto = BackupCrypto(kdfIterations: 10000);
        final payload = {
          'profiles': [
            {'id': 'p1', 'name': 'Personal', 'base_currency_code': 'INR'},
          ],
          'transactions': [
            {'id': 't1', 'amount_minor': 50000},
          ],
        };

        final archive = await crypto.encryptBackup(
          payloadJson: payload,
          passphrase: 'StrongPassphrase!2026',
          schemaVersion: 1,
          appVersion: '1.0.0+1',
          profileIds: ['p1'],
          createdAtUtc: '2026-11-19T07:00:00Z',
        );

        // Ciphertext archive MUST NOT leak plaintext contents.
        expect(archive, isNot(contains('Personal')));
        expect(archive, isNot(contains('50000')));

        // Correct passphrase decrypts and verifies SHA-256 integrity.
        final decrypted = await crypto.decryptBackup(
          rawArchive: archive,
          passphrase: 'StrongPassphrase!2026',
        );
        expect(decrypted.metadata.schemaVersion, 1);
        expect(decrypted.payloadJson['profiles'], hasLength(1));

        // Wrong passphrase fails with SecurityFailure.
        await expectLater(
          () => crypto.decryptBackup(
            rawArchive: archive,
            passphrase: 'WrongPassphrase!2026',
          ),
          throwsA(isA<SecurityFailure>()),
        );

        // Tampering with AAD metadata MUST fail GCM authentication.
        final tamperedMap = jsonDecode(archive) as Map<String, dynamic>;
        (tamperedMap['metadata'] as Map<String, dynamic>)['schema_version'] =
            99;
        await expectLater(
          () => crypto.decryptBackup(
            rawArchive: jsonEncode(tamperedMap),
            passphrase: 'StrongPassphrase!2026',
          ),
          throwsA(isA<SecurityFailure>()),
        );
      },
    );
  });
}
