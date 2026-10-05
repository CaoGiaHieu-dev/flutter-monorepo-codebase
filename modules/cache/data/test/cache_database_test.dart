import 'dart:io';

import 'package:core_database/core_database.dart';
import 'package:data_cache/data_cache.dart';
// Both drift imports are prefixed: drift's query builder exports `isNull` /
// `isNotNull`, which collide with the matchers from flutter_test.
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart' as drift_native;
import 'package:flutter_test/flutter_test.dart';

/// Adds a column with raw SQL, so a real file's schema actually changes.
class _AddColumn implements IDatabaseMigration {
  _AddColumn(this.version, this.sql);

  @override
  final int version;

  final String sql;

  @override
  Future<void> upgrade(drift.Migrator m) => m.database.customStatement(sql);

  @override
  Future<void> downgrade(drift.Migrator m) async {}
}

/// Inert migration used to prove dispatch without a real schema history.
class _RecordingMigration implements IDatabaseMigration {
  _RecordingMigration(this.version, this.log);

  @override
  final int version;

  final List<String> log;

  @override
  Future<void> upgrade(drift.Migrator m) async => log.add('up:$version');

  @override
  Future<void> downgrade(drift.Migrator m) async => log.add('down:$version');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Several tests intentionally open more than one CacheDatabase (a file is
  // reopened to prove data persisted). Each uses its own QueryExecutor, so
  // drift's shared-executor race warning does not apply here.
  drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late CacheDatabase database;

  setUp(() {
    database = CacheDatabase.forTesting();
  });

  tearDown(() async {
    await database.close();
  });

  group('CacheEntriesDao', () {
    test('upsert and getValue round-trip', () async {
      await database.cacheEntriesDao.upsert('greeting', 'hello');

      expect(await database.cacheEntriesDao.getValue('greeting'), 'hello');
    });

    test('upsert replaces an existing key', () async {
      await database.cacheEntriesDao.upsert('greeting', 'hello');
      await database.cacheEntriesDao.upsert('greeting', 'world');

      expect(await database.cacheEntriesDao.getValue('greeting'), 'world');
    });

    test('getEntry returns the full row', () async {
      await database.cacheEntriesDao.upsert('meta', 'payload');

      final row = await database.cacheEntriesDao.getEntry('meta');

      expect(row, isNotNull);
      expect(row!.key, 'meta');
      expect(row.value, 'payload');
    });
  });

  group('migration wiring', () {
    test('opens normally when no migration is registered', () async {
      // The removability case: a package contributing migrations can be
      // deleted from the app, leaving an empty registry. Opening must still
      // succeed — this is what keeps the app bootable without that package.
      final db = CacheDatabase.forTesting();
      addTearDown(db.close);

      await db.cacheEntriesDao.upsert('k', 'v');

      expect(await db.cacheEntriesDao.getValue('k'), 'v');
    });

    test('a fresh database runs onCreate, never onUpgrade', () async {
      final log = <String>[];
      final db = CacheDatabase.forTesting(null, [_RecordingMigration(2, log)]);
      addTearDown(db.close);

      await db.cacheEntriesDao.upsert('k', 'v');

      expect(log, isEmpty);
      expect(await db.cacheEntriesDao.getValue('k'), 'v');
    });
  });

  group('on a real file', () {
    // `CacheDatabase.open` cannot run here: it resolves the app documents
    // directory through the path_provider plugin, which is unavailable in a
    // unit test. Opening the same schema over a temp file still exercises
    // everything that differs from the in-memory case: real file I/O, and the
    // pragmas that only take effect on disk.
    late Directory tempDir;
    late CacheDatabase fileDatabase;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('data_cache_db_test');
      fileDatabase = CacheDatabase.forTesting(
        drift_native.NativeDatabase(
          File('${tempDir.path}${Platform.pathSeparator}probe.sqlite'),
        ),
      );
    });

    tearDown(() async {
      await fileDatabase.close();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('journal_mode is WAL on a real file', () async {
      final row = await fileDatabase
          .customSelect('PRAGMA journal_mode')
          .getSingle();

      expect(row.data.values.first.toString().toLowerCase(), 'wal');
    });

    test('foreign keys are enforced on a real file', () async {
      final row = await fileDatabase
          .customSelect('PRAGMA foreign_keys')
          .getSingle();

      expect(row.data.values.first.toString(), '1');
    });

    // The old schema is written by hand and stamped `user_version = 1`;
    // `setup` runs on the raw connection before Drift reads the version, so a
    // build with schema version 2 sees an old file and replays the step.
    CacheDatabase openOldFile(
      String path,
      List<IDatabaseMigration> steps,
      int schemaVersion,
    ) {
      return CacheDatabase.forTesting(
        drift_native.NativeDatabase(
          File(path),
          setup: (raw) {
            if (raw.select('PRAGMA user_version').first.values.first == 0) {
              raw.execute(
                'CREATE TABLE cache_entries (key TEXT NOT NULL PRIMARY KEY, '
                'value TEXT NOT NULL, updated_at INTEGER NOT NULL)',
              );
              raw.execute("INSERT INTO cache_entries VALUES ('k', 'v', 0)");
              raw.execute('PRAGMA user_version = 1');
            }
          },
        ),
        steps,
        schemaVersion,
      );
    }

    Future<List<Object?>> columnsOf(CacheDatabase db) async {
      final rows = await db
          .customSelect('PRAGMA table_info(cache_entries)')
          .get();
      return rows.map((row) => row.data['name']).toList();
    }

    test(
      'an old-version file upgrades through its step and keeps rows',
      () async {
        final path = '${tempDir.path}${Platform.pathSeparator}old.sqlite';
        final upgraded = openOldFile(path, [
          _AddColumn(
            2,
            'ALTER TABLE cache_entries ADD COLUMN expires_at INTEGER',
          ),
        ], 2);
        addTearDown(upgraded.close);

        expect(await columnsOf(upgraded), contains('expires_at'));
        expect(await upgraded.cacheEntriesDao.getValue('k'), 'v');
      },
    );

    test('a failing step leaves the old file as it was', () async {
      final path = '${tempDir.path}${Platform.pathSeparator}atomic.sqlite';
      final failing = openOldFile(path, [
        _AddColumn(
          2,
          'ALTER TABLE cache_entries ADD COLUMN expires_at INTEGER',
        ),
        _AddColumn(3, 'ALTER TABLE missing_table ADD COLUMN x INTEGER'),
      ], 3);
      await expectLater(
        failing.cacheEntriesDao.getValue('k'),
        throwsA(anything),
      );
      try {
        await failing.close();
      } catch (_) {}

      // Step 2 was rolled back with step 3, so the fixed build can replay it.
      final retried = openOldFile(path, [
        _AddColumn(
          2,
          'ALTER TABLE cache_entries ADD COLUMN expires_at INTEGER',
        ),
        _AddColumn(3, 'ALTER TABLE cache_entries ADD COLUMN note TEXT'),
      ], 3);
      addTearDown(retried.close);

      expect(await columnsOf(retried), containsAll(['expires_at', 'note']));
      expect(await retried.cacheEntriesDao.getValue('k'), 'v');
    });

    test('data survives a close and reopen of the same file', () async {
      final path = '${tempDir.path}${Platform.pathSeparator}persist.sqlite';

      final first = CacheDatabase.forTesting(
        drift_native.NativeDatabase(File(path)),
      );
      await first.cacheEntriesDao.upsert('persisted', 'value');
      await first.close();

      final second = CacheDatabase.forTesting(
        drift_native.NativeDatabase(File(path)),
      );
      addTearDown(second.close);

      expect(await second.cacheEntriesDao.getValue('persisted'), 'value');
    });
  });
}
