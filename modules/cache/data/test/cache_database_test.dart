import 'dart:io';

import 'package:core_database/core_database.dart';
import 'package:data_cache/data_cache.dart';
// Prefixed: drift's query builder exports `isNull` / `isNotNull`, which
// collide with the flutter_test matchers.
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart' as drift_native;
import 'package:flutter_test/flutter_test.dart';

/// Adds a column with raw SQL, so a real file's schema actually changes.
class _AddExpiresAt implements IDatabaseMigration {
  @override
  int get version => 2;

  @override
  Future<void> upgrade(drift.Migrator m) => m.database.customStatement(
    'ALTER TABLE cache_entries ADD COLUMN expires_at INTEGER',
  );

  @override
  Future<void> downgrade(drift.Migrator m) async {}
}

void main() {
  test('an old-version file upgrades through its step and keeps rows', () async {
    final dir = await Directory.systemTemp.createTemp('data_cache_upgrade');
    addTearDown(() => dir.delete(recursive: true));

    // The old schema is written by hand and stamped `user_version = 1`;
    // `setup` runs before Drift reads the version, so a build shipping schema
    // version 2 sees an old file and replays the step.
    final database = CacheDatabase.forTesting(
      drift_native.NativeDatabase(
        File('${dir.path}${Platform.pathSeparator}cache.sqlite'),
        setup: (raw) {
          raw.execute(
            'CREATE TABLE cache_entries (key TEXT NOT NULL PRIMARY KEY, '
            'value TEXT NOT NULL, updated_at INTEGER NOT NULL)',
          );
          raw.execute("INSERT INTO cache_entries VALUES ('k', 'v', 0)");
          raw.execute('PRAGMA user_version = 1');
        },
      ),
      [_AddExpiresAt()],
      2,
    );
    addTearDown(database.close);

    final columns = await database
        .customSelect('PRAGMA table_info(cache_entries)')
        .get();
    expect(columns.map((row) => row.data['name']), contains('expires_at'));
    expect((await database.cacheEntriesDao.getEntry('k'))?.value, 'v');
  });
}
