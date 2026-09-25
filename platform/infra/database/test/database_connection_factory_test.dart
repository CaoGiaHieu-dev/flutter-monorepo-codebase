import 'dart:io';

import 'package:core_database/core_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/test_database.dart';

void main() {
  group('DatabaseConnectionFactory.backgroundExecutorFor', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('core_database_pool');
    });

    tearDown(() async {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    // `MigrationStrategy.beforeOpen` runs on the writer only. A `SELECT`
    // outside a transaction is served by the read pool, so this reads the
    // reader's own setting — `0` before the factory configured every
    // connection, which made a reader fail at once on any lock.
    test('gives read-pool connections a busy timeout', () async {
      final database = TestDatabase(
        DatabaseConnectionFactory.backgroundExecutorFor(
          File(p.join(tempDir.path, 'pool.sqlite')),
          readPool: 1,
        ),
      );
      addTearDown(database.close);

      final row = await database
          .customSelect('PRAGMA busy_timeout')
          .getSingle();

      expect(row.data.values.first, DatabaseConstants.BUSY_TIMEOUT_MS);
    });
  });
}
