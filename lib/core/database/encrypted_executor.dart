import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../errors/failures.dart';
import '../security/key_manager.dart';

/// Factory creating encrypted Drift [QueryExecutor] instances backed by
/// `sqlite3` v3's SQLite3MultipleCiphers native hook (`ADR-005`, `SEC-001`).
abstract final class EncryptedDatabaseExecutor {
  static final RegExp _hexKeyRegex = RegExp(r'^[0-9a-fA-F]{64}$');

  /// Opens the primary application encrypted database stored in app-private storage.
  static LazyDatabase openAppDatabase({
    required KeyManager keyManager,
    required bool requireEncryption,
    String fileName = 'pocket_cfo_v1.db',
  }) {
    return LazyDatabase(() async {
      final dir = await getApplicationSupportDirectory();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final dbFile = File(p.join(dir.path, fileName));
      final keyHex = await keyManager.getOrCreateDatabaseKeyHex();
      return openEncryptedFile(
        file: dbFile,
        keyHex: keyHex,
        requireEncryption: requireEncryption,
      );
    });
  }

  /// Opens an encrypted SQLite database at [file] using a 256-bit hex DEK.
  /// Enforces fail-closed verification: if [requireEncryption] is true and
  /// SQLite3MultipleCiphers is not active, throws [SecurityFailure].
  static QueryExecutor openEncryptedFile({
    required File file,
    required String keyHex,
    bool requireEncryption = true,
  }) {
    if (!_hexKeyRegex.hasMatch(keyHex)) {
      throw const SecurityFailure(
        message: 'Invalid database encryption key format.',
      );
    }

    return NativeDatabase.createInBackground(
      file,
      setup: (Database rawDb) {
        _configureCipherAndPragmas(
          rawDb,
          keyHex: keyHex,
          requireEncryption: requireEncryption,
        );
      },
    );
  }

  /// Synchronous encrypted executor useful for staging restore validation and tests.
  static QueryExecutor openEncryptedFileSync({
    required File file,
    required String keyHex,
    bool requireEncryption = true,
  }) {
    if (!_hexKeyRegex.hasMatch(keyHex)) {
      throw const SecurityFailure(
        message: 'Invalid database encryption key format.',
      );
    }

    return NativeDatabase(
      file,
      setup: (Database rawDb) {
        _configureCipherAndPragmas(
          rawDb,
          keyHex: keyHex,
          requireEncryption: requireEncryption,
        );
      },
    );
  }

  /// Fast isolated in-memory database for unit, financial, and repository tests.
  static QueryExecutor openInMemory() {
    return NativeDatabase.memory(
      setup: (Database rawDb) {
        rawDb.execute('PRAGMA foreign_keys = ON;');
      },
    );
  }

  static void _configureCipherAndPragmas(
    Database rawDb, {
    required String keyHex,
    required bool requireEncryption,
  }) {
    // Configure SQLite3MultipleCiphers in SQLCipher v4 compatible AES-256 mode.
    rawDb.execute("PRAGMA cipher = 'sqlcipher';");
    rawDb.execute('PRAGMA legacy = 4;');
    rawDb.execute("PRAGMA key = \"x'$keyHex'\";");

    // Verify encryption engine is actually compiled in and active (fail-closed).
    final cipherCheck = rawDb.select('PRAGMA cipher;');
    final activeCipher = cipherCheck.isNotEmpty
        ? cipherCheck.first.values.first?.toString()
        : null;
    if (requireEncryption && (activeCipher == null || activeCipher.isEmpty)) {
      throw const SecurityFailure(
        message:
            'Encrypted SQLite runtime (SQLite3MultipleCiphers) is unavailable. Refusing plaintext database.',
      );
    }

    // Touch schema to validate key immediately on existing DBs (fails fast on wrong key).
    rawDb.select('SELECT count(*) FROM sqlite_master;');

    rawDb.execute('PRAGMA cipher_memory_security = ON;');
    rawDb.execute('PRAGMA foreign_keys = ON;');
    rawDb.execute('PRAGMA journal_mode = WAL;');
    rawDb.execute('PRAGMA synchronous = FULL;');
    rawDb.execute('PRAGMA temp_store = MEMORY;');
  }
}
