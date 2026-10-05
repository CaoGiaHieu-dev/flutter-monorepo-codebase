import 'dart:io';

import 'package:core_database/core_database.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/test_database.dart';

/// Records the order in which the runner invoked each direction.
///
/// The migrations here do not touch the schema: what is under test is the
/// dispatch logic (which steps run, in which order, in which direction), and
/// keeping them inert lets that be asserted without a real schema history.
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

/// Runs raw SQL, so a real file's schema actually changes.
class _SqlMigration implements IDatabaseMigration {
  const _SqlMigration(this.version, this.sql);

  @override
  final int version;

  final String sql;

  @override
  Future<void> upgrade(drift.Migrator m) => m.database.customStatement(sql);

  @override
  Future<void> downgrade(drift.Migrator m) async {}
}

class _ThrowingDowngrade implements IDatabaseMigration {
  const _ThrowingDowngrade(this.version);

  @override
  final int version;

  @override
  Future<void> upgrade(drift.Migrator m) async {}

  @override
  Future<void> downgrade(drift.Migrator m) async {
    throw UnsupportedError('v$version cannot be reversed');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  // The runner only ever passes the Migrator through to the registered
  // migrations, so a Migrator over a throwaway database is enough here.
  late TestDatabase database;
  late drift.Migrator migrator;

  setUp(() {
    database = TestDatabase();
    migrator = drift.Migrator(database);
  });

  tearDown(() async {
    await database.close();
  });

  group('DatabaseMigrationRunner validation', () {
    test('rejects a migration targeting version 1', () {
      expect(
        () => DatabaseMigrationRunner([_RecordingMigration(1, [])]),
        throwsArgumentError,
      );
    });

    test('rejects duplicate versions', () {
      expect(
        () => DatabaseMigrationRunner([
          _RecordingMigration(2, []),
          _RecordingMigration(2, []),
        ]),
        throwsArgumentError,
      );
    });

    test('sorts registrations by version regardless of input order', () {
      final runner = DatabaseMigrationRunner([
        _RecordingMigration(4, []),
        _RecordingMigration(2, []),
        _RecordingMigration(3, []),
      ]);

      expect(runner.migrations.map((m) => m.version), orderedEquals([2, 3, 4]));
    });
  });

  group('DatabaseMigrationRunner.run', () {
    test('replays every intermediate step when versions are skipped', () async {
      final log = <String>[];
      final runner = DatabaseMigrationRunner([
        _RecordingMigration(3, log),
        _RecordingMigration(2, log),
        _RecordingMigration(4, log),
      ]);

      await runner.run(migrator, 1, 4);

      expect(log, orderedEquals(['up:2', 'up:3', 'up:4']));
    });

    test('runs only the steps above the stored version', () async {
      final log = <String>[];
      final runner = DatabaseMigrationRunner([
        _RecordingMigration(2, log),
        _RecordingMigration(3, log),
        _RecordingMigration(4, log),
      ]);

      await runner.run(migrator, 2, 3);

      expect(log, orderedEquals(['up:3']));
    });

    test('downgrades in descending order', () async {
      final log = <String>[];
      final runner = DatabaseMigrationRunner([
        _RecordingMigration(2, log),
        _RecordingMigration(3, log),
        _RecordingMigration(4, log),
      ]);

      await runner.run(migrator, 4, 1);

      expect(log, orderedEquals(['down:4', 'down:3', 'down:2']));
    });

    test('does nothing when the version is unchanged', () async {
      final log = <String>[];
      final runner = DatabaseMigrationRunner([_RecordingMigration(2, log)]);

      await runner.run(migrator, 2, 2);

      expect(log, isEmpty);
    });

    test('tolerates gaps left by releases without schema changes', () async {
      final log = <String>[];
      final runner = DatabaseMigrationRunner([
        _RecordingMigration(2, log),
        // no migration for version 3
        _RecordingMigration(4, log),
      ]);

      await runner.run(migrator, 1, 4);

      expect(log, orderedEquals(['up:2', 'up:4']));
    });

    test('an irreversible downgrade surfaces its error', () async {
      final runner = DatabaseMigrationRunner([const _ThrowingDowngrade(2)]);

      expect(
        () => runner.run(migrator, 2, 1),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('a downgrade with no registered steps throws', () async {
      final runner = DatabaseMigrationRunner(const []);

      await expectLater(
        runner.run(migrator, 2, 1),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('a downgrade from a version newer than any step throws', () async {
      final log = <String>[];
      final runner = DatabaseMigrationRunner([
        _RecordingMigration(2, log),
        _RecordingMigration(3, log),
      ]);

      await expectLater(
        runner.run(migrator, 5, 1),
        throwsA(isA<UnsupportedError>()),
      );
      // Nothing ran: a partial downgrade would be worse than none.
      expect(log, isEmpty);
    });

    test('the downgrade error is never mistaken for corruption', () async {
      final runner = DatabaseMigrationRunner(const []);
      Object? error;
      try {
        await runner.run(migrator, 3, 1);
      } catch (e) {
        error = e;
      }
      expect(error, isNotNull);
      expect(DriftDatabaseOpener.isCorruptionError(error!), isFalse);
    });

    test('a downgrade tolerates gaps below the newest step', () async {
      final log = <String>[];
      final runner = DatabaseMigrationRunner([
        _RecordingMigration(2, log),
        // no migration for version 3
        _RecordingMigration(4, log),
      ]);

      await runner.run(migrator, 4, 1);

      expect(log, orderedEquals(['down:4', 'down:2']));
    });

    test('runs nothing when no migration is registered', () async {
      final runner = DatabaseMigrationRunner(const []);

      // Must not throw: a database with no contributed migrations is the
      // normal case for a template that has not changed its schema yet.
      await runner.run(migrator, 1, 5);

      expect(runner.migrations, isEmpty);
    });
  });

  group('downgrade against a real file', () {
    late Directory tempDir;
    late File file;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('core_database_down');
      file = File(p.join(tempDir.path, 'down.sqlite'));
    });

    tearDown(() async {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    Future<void> open(
      int schemaVersion, [
      List<IDatabaseMigration> migrations = const [],
    ]) async {
      final database = _VersionedDatabase(
        drift.NativeDatabase(file),
        schemaVersion,
        migrations,
      );
      try {
        await database.customSelect('SELECT 1').get();
      } finally {
        await database.close();
      }
    }

    test('an unsupported downgrade leaves the stored version alone', () async {
      await open(3);

      // An older build with no downgrade steps refuses to open…
      await expectLater(open(1), throwsA(anything));

      // …and the newer build still finds its own version: no upgrade runs.
      final log = <String>[];
      await open(3, [_RecordingMigration(2, log), _RecordingMigration(3, log)]);
      expect(log, isEmpty);
    });
  });

  group('upgrade against a real file', () {
    late Directory tempDir;
    late File file;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('core_database_up');
      file = File(p.join(tempDir.path, 'up.sqlite'));
      // A file as an older build left it: one table, `user_version = 1`.
      final old = TestDatabase(
        drift.NativeDatabase(
          file,
          setup: (raw) {
            raw.execute('CREATE TABLE t (k TEXT PRIMARY KEY)');
            raw.execute("INSERT INTO t VALUES ('row')");
            raw.execute('PRAGMA user_version = 1');
          },
        ),
      );
      await old.customSelect('SELECT 1').get();
      await old.close();
    });

    tearDown(() async {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    Future<({Object? error, List<String> columns, int version})> open(
      int schemaVersion,
      List<IDatabaseMigration> migrations,
    ) async {
      final database = _VersionedDatabase(
        drift.NativeDatabase(file),
        schemaVersion,
        migrations,
      );
      Object? error;
      var columns = <String>[];
      var version = -1;
      try {
        columns = (await database.customSelect('PRAGMA table_info(t)').get())
            .map((r) => r.data['name']! as String)
            .toList();
        version =
            (await database.customSelect('PRAGMA user_version').getSingle())
                    .data
                    .values
                    .first!
                as int;
      } catch (e) {
        error = e;
      }
      try {
        await database.close();
      } catch (_) {}
      return (error: error, columns: columns, version: version);
    }

    test('replays every step and keeps the rows', () async {
      final result = await open(3, const [
        _SqlMigration(2, 'ALTER TABLE t ADD COLUMN a INTEGER'),
        _SqlMigration(3, 'ALTER TABLE t ADD COLUMN b INTEGER'),
      ]);

      expect(result.error, isNull);
      expect(result.version, 3);
      expect(result.columns, ['k', 'a', 'b']);
    });

    test(
      'a failing step rolls back the earlier ones, so a retry works',
      () async {
        final failed = await open(3, const [
          _SqlMigration(2, 'ALTER TABLE t ADD COLUMN a INTEGER'),
          _SqlMigration(3, 'ALTER TABLE missing ADD COLUMN b INTEGER'),
        ]);
        expect(failed.error, isNotNull);

        // Reading the file with the old build's version shows what stayed.
        final after = await open(1, const []);
        expect(after.version, 1);
        expect(after.columns, ['k'], reason: 'step 2 must not stay applied');

        // The fixed build upgrades cleanly: no duplicate column on step 2.
        final retried = await open(3, const [
          _SqlMigration(2, 'ALTER TABLE t ADD COLUMN a INTEGER'),
          _SqlMigration(3, 'ALTER TABLE t ADD COLUMN b INTEGER'),
        ]);
        expect(retried.error, isNull);
        expect(retried.version, 3);
        expect(retried.columns, ['k', 'a', 'b']);
      },
    );
  });
}

/// A table-less database whose schema version and steps a test chooses.
class _VersionedDatabase extends TestDatabase {
  _VersionedDatabase(super.executor, this.schemaVersion, this._migrations);

  @override
  final int schemaVersion;

  final List<IDatabaseMigration> _migrations;

  @override
  drift.MigrationStrategy get migration =>
      driftMigrationStrategy(database: this, migrations: _migrations);
}
