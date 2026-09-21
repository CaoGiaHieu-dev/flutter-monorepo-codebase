import 'package:drift/drift.dart';

import '../utils/database_constants.dart';
import 'database_migration_runner.dart';
import 'i_database_migration.dart';

/// Builds the [MigrationStrategy] every database in this project should use.
///
/// Centralised so the connection-level `PRAGMA` settings and the
/// [IDatabaseMigration] dispatch are written once instead of being copied
/// into each package's database — a package that forgot `foreign_keys = ON`
/// would silently lose referential integrity.
///
/// ```dart
/// @override
/// MigrationStrategy get migration => driftMigrationStrategy(
///   database: this,
///   migrations: _migrations,
/// );
/// ```
///
/// [migrations] may be empty: a database with no contributed steps opens
/// normally and only ever runs `onCreate`. That is what lets a package be
/// removed from the app without breaking the ones that remain.
MigrationStrategy driftMigrationStrategy({
  required GeneratedDatabase database,
  Iterable<IDatabaseMigration> migrations = const <IDatabaseMigration>[],
  int busyTimeoutMs = DatabaseConstants.BUSY_TIMEOUT_MS,
}) {
  final runner = DatabaseMigrationRunner(migrations);

  return MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },

    /// Runs when the stored schema version differs from `schemaVersion`.
    ///
    /// Drift has a single callback for both directions — its own docs note
    /// that "schema version upgrades and downgrades will both be run here" —
    /// so there is no separate `onDowngrade` to override. The runner compares
    /// [from] and [to] and dispatches to [IDatabaseMigration.upgrade] or
    /// [IDatabaseMigration.downgrade] accordingly.
    onUpgrade: (Migrator m, int from, int to) async {
      await runner.run(m, from, to);
    },

    /// Runs after migrations, before drift reports the database as open.
    ///
    /// `PRAGMA` settings are per-connection and are **not** persisted in the
    /// file, so they must be reapplied on every open — that is what makes
    /// this the correct place for them.
    beforeOpen: (OpeningDetails details) async {
      // SQLite ships with foreign key enforcement OFF. Without this any
      // `references()` declared on a table is silently ignored, so broken
      // relations are only discovered as corrupt data much later.
      await database.customStatement('PRAGMA foreign_keys = ON');

      // Write-Ahead Logging lets readers run concurrently with a writer,
      // which is required once readPool > 1 and avoids "database is locked"
      // under contention. It changes the on-disk layout by adding `-wal` and
      // `-shm` sidecar files; SQLite converts an existing database
      // automatically and reversibly. In-memory databases (tests) ignore
      // this and stay in `memory` journal mode.
      await database.customStatement('PRAGMA journal_mode = WAL');

      // Wait for a held lock instead of failing instantly with SQLITE_BUSY.
      await database.customStatement('PRAGMA busy_timeout = $busyTimeoutMs');
    },
  );
}
