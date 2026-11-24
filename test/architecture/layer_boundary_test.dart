import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'ADR-003 / NFR-013 Domain and Financial Engine remain 100% Pure Dart',
    () {
      final forbiddenPatterns = [
        "import 'package:flutter/",
        "import 'package:drift/",
        "import 'package:dio/",
        "import 'package:sqlite3/",
      ];

      final violations = <String>[];

      void scanDirectory(Directory dir) {
        if (!dir.existsSync()) return;
        for (final entity in dir.listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          final normalized = entity.path.replaceAll('\\', '/');
          final isPureLayer =
              normalized.contains('lib/core/financial_engine/') ||
              normalized.contains('/domain/');
          if (!isPureLayer) continue;

          final content = entity.readAsStringSync();
          for (final forbidden in forbiddenPatterns) {
            if (content.contains(forbidden)) {
              violations.add('$normalized imports forbidden $forbidden');
            }
          }
        }
      }

      scanDirectory(Directory('lib'));
      expect(violations, isEmpty, reason: violations.join('\n'));
    },
  );
}
