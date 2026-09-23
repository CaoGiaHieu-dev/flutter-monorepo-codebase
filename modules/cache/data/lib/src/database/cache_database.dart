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
/// ## Why this lives here and not in `core_database`
///
/// Drift resolves `@DriftDatabase(tables: ...)` at compile time and requires a
/// DAO to be a `part of` its database library. A single shared database would
/// therefore force the package declaring it to name every other package's
/// tables — the same "one object knows everything" coupling that was removed
/// from `core_storage` and `platform_kernel`.
///
/// So each package that owns persisted data declares its own database and
/// keeps its tables, DAO and data source together. `core_database` supplies
/// only the mechanism: [DriftDatabaseOpener], [driftMigrationStrategy],
/// [IDatabaseMigration] and [IDatabaseHandle].
///
/// The practical consequence is the property the app needs: deleting this
/// package deletes its database with it. No other package references
/// [CacheDatabase], so nothing else breaks — and no other package can reach
/// these rows in the first place.
///
/// The trade-off is that SQL cannot join across package boundaries. That is
/// intentional: crossing a bounded context belongs at the repository layer,
/// not inside a query.
@DriftDatabase(tables: [CacheEntries], daos: [CacheEntriesDao])
class CacheDatabase extends _$CacheDatabase {
  CacheDatabase._(super.e, Iterable<IDatabaseMigration> migrations)
    : _migrations = migrations;

  /// Schema steps contributed for this database.
  ///
  /// Passed in rather than looked up here so the database stays testable and
  /// free of service-locator calls; the DI module does the collection.
  final Iterable<IDatabaseMigration> _migrations;

  /// Opens the cache database on a background isolate.
  ///
  /// Corruption recovery and connection verification are handled by
  /// [DriftDatabaseOpener]; see its documentation for exactly when a damaged file
  /// is quarantined rather than deleted.
  static Future<CacheDatabase> open({
    String fileName = CacheConstants.DATABASE_FILE_NAME,
    int readPool = DatabaseConstants.DEFAULT_READ_POOL,
    Iterable<IDatabaseMigration> migrations = const <IDatabaseMigration>[],
  }) {
    return DriftDatabaseOpener.open(
      (executor) => CacheDatabase._(executor, migrations),
      fileName: fileName,
      readPool: readPool,
    );
  }

  /// In-memory database for unit tests (runs on the current isolate).
  @visibleForTesting
  factory CacheDatabase.forTesting([
    QueryExecutor? executor,
    Iterable<IDatabaseMigration> migrations = const <IDatabaseMigration>[],
  ]) {
    return CacheDatabase._(executor ?? NativeDatabase.memory(), migrations);
  }

  @override
  int get schemaVersion => 1;

  /// Migration behaviour is shared with every other database in the project.
  ///
  /// See [driftMigrationStrategy] for the `PRAGMA` settings it applies and
  /// how contributed [IDatabaseMigration]s are replayed.
  ///
  /// To change this schema: edit the table, bump [schemaVersion], then
  /// implement [IDatabaseMigration] with `version` set to the new number and
  /// register it with `@LazySingleton(as: IDatabaseMigration<CacheDatabase>)`.
  /// Nothing in
  /// this file changes — that is the point of the contract.
  @override
  MigrationStrategy get migration =>
      driftMigrationStrategy(database: this, migrations: _migrations);
}
