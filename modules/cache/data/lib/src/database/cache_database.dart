import 'package:core_database/core_database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../utils/cache_constants.dart';
import 'tables/cache_entries_table.dart';

part 'cache_database.g.dart';
part 'dao/cache_entries_dao.dart';

/// SAMPLE — the database owned by `data_cache`, holding only its own tables.
///
/// Drift binds tables at compile time and a DAO must be a `part of` its
/// database, so each package that persists data declares its own database
/// next to its tables, DAO and data source; deleting the package deletes the
/// database with it. `core_database` supplies only the mechanism
/// ([DriftDatabaseOpener], [driftMigrationStrategy], [IDatabaseMigration],
/// [IDatabaseHandle]).
@DriftDatabase(tables: [CacheEntries], daos: [CacheEntriesDao])
class CacheDatabase extends _$CacheDatabase {
  CacheDatabase._(super.e, this._migrations, [this.schemaVersion = 1]);

  /// Schema steps contributed for this database, collected by the DI module.
  final Iterable<IDatabaseMigration> _migrations;

  /// Bump it together with a new [IDatabaseMigration] whose `version` is the
  /// new number; nothing else in this file changes.
  @override
  final int schemaVersion;

  /// Opens the database on a background isolate, with corruption recovery
  /// ([DriftDatabaseOpener]).
  static Future<CacheDatabase> open({
    Iterable<IDatabaseMigration> migrations = const <IDatabaseMigration>[],
  }) {
    return DriftDatabaseOpener.open(
      (executor) => CacheDatabase._(executor, migrations),
      fileName: CacheConstants.DATABASE_FILE_NAME,
    );
  }

  /// In-memory database for tests. [executor] and [schemaVersion] let an
  /// upgrade test reopen a hand-written old file so the [migrations] run.
  @visibleForTesting
  factory CacheDatabase.forTesting([
    QueryExecutor? executor,
    Iterable<IDatabaseMigration> migrations = const <IDatabaseMigration>[],
    int schemaVersion = 1,
  ]) {
    return CacheDatabase._(
      executor ?? NativeDatabase.memory(),
      migrations,
      schemaVersion,
    );
  }

  @override
  MigrationStrategy get migration =>
      driftMigrationStrategy(database: this, migrations: _migrations);
}
