import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pocket_money/core/database/app_database.dart';
import 'package:pocket_money/core/database/encrypted_executor.dart';
import 'package:pocket_money/core/security/key_manager.dart';

void main() {
  group('ADR-005 Encrypted SQLite (SQLite3MultipleCiphers) Proof', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pocket_cfo_enc_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'encrypts database bytes on disk, rejects wrong key, and decrypts cleanly with correct key',
      () async {
        final dbFile = File(p.join(tempDir.path, 'encrypted_poc.db'));
        final keyManager = KeyManager(InMemorySecureKeyValueStore());
        final keyHex = await keyManager.getOrCreateDatabaseKeyHex();
        const secretMarker = 'CONFIDENTIAL_SALARY_999888777';

        // 1. Create encrypted DB and persist sensitive record.
        final db = AppDatabase(
          EncryptedDatabaseExecutor.openEncryptedFileSync(
            file: dbFile,
            keyHex: keyHex,
            requireEncryption: true,
          ),
        );

        await db
            .into(db.profiles)
            .insert(
              ProfilesCompanion.insert(
                id: 'prof-enc-1',
                name: secretMarker,
                profileType: 'personal',
                baseCurrencyCode: 'INR',
                createdAtUtc: '2026-11-19T00:00:00Z',
                updatedAtUtc: '2026-11-19T00:00:00Z',
              ),
            );
        await db.close();

        // 2. Inspect raw bytes on disk: MUST NOT be plaintext SQLite!
        final rawBytes = await dbFile.readAsBytes();
        expect(rawBytes.length, greaterThan(1024));
        final headerText = latin1.decode(rawBytes.take(16).toList());
        expect(headerText, isNot(startsWith('SQLite format 3')));
        final rawLatin1 = latin1.decode(rawBytes);
        expect(rawLatin1, isNot(contains(secretMarker)));

        // 3. Reopening with a wrong 256-bit key MUST fail.
        const wrongKeyHex =
            '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
        final wrongDb = AppDatabase(
          EncryptedDatabaseExecutor.openEncryptedFileSync(
            file: dbFile,
            keyHex: wrongKeyHex,
            requireEncryption: true,
          ),
        );
        await expectLater(
          () => wrongDb.select(wrongDb.profiles).get(),
          throwsA(anything),
        );
        await wrongDb.close();

        // 4. Reopening with the correct DEK MUST decrypt the exact record.
        final reopenedDb = AppDatabase(
          EncryptedDatabaseExecutor.openEncryptedFileSync(
            file: dbFile,
            keyHex: keyHex,
            requireEncryption: true,
          ),
        );
        final rows = await reopenedDb.select(reopenedDb.profiles).get();
        expect(rows, hasLength(1));
        expect(rows.single.name, secretMarker);
        await reopenedDb.close();
      },
    );
  });
}
