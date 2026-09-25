/// Core Database — the MECHANISM for relational local persistence with Drift.
///
/// This package owns no database, no table and no DAO. Drift resolves
/// `@DriftDatabase(tables: ...)` at compile time and requires a DAO to be a
/// `part of` its database library, so a database declared here would have to
/// name the tables of whichever package owns them — the same "one object
/// knows everything" coupling that was removed from `core_storage` and
/// `core_common`.
///
/// Instead, **each package that owns persisted data declares its own
/// database** next to its tables, DAO and data source, and opens it with the
/// pieces below. `data_cache`'s `CacheDatabase` is the reference wiring.
///
/// The property this buys: deleting a package deletes its database with it.
/// Nothing else refers to it, and no other package can reach its rows.
/// The trade-off: SQL cannot join across package boundaries — crossing a
/// bounded context belongs at the repository layer, not inside a query.
///
/// Opening:
/// - [DriftDatabaseOpener] — opens any [GeneratedDatabase] on a background
///   isolate, verifies the connection, and quarantines (never deletes) a
///   corrupt file
/// - [DatabaseConnectionFactory] — resolves the file and builds the executor
///
/// Schema evolution:
/// - [IDatabaseMigration] — contract a package implements, next to its own
///   tables, to contribute one upgrade/downgrade step; register it with
///   `@LazySingleton(as: IDatabaseMigration<YourDatabase>)` — typed, so each
///   database collects only its own steps
/// - [DatabaseMigrationRunner] — orders, validates and replays those steps
/// - [driftMigrationStrategy] — the shared `MigrationStrategy`, including the
///   per-connection `PRAGMA` settings every database needs
///
/// Access:
/// - [IDatabaseHandle] / [DatabaseHandle] — how a data source reaches its
///   database. It receives only the accessor it asks for rather than every
///   DAO on the database.
library core_database;

// Auto-generated exports, do not edit manually.
export 'di/module.dart';
export 'di/module.module.dart';
export 'src/access/database_handle.dart';
export 'src/access/i_database_handle.dart';
export 'src/connection/database_connection_factory.dart';
export 'src/migration/database_migration_runner.dart';
export 'src/migration/drift_migration_strategy.dart';
export 'src/migration/i_database_migration.dart';
export 'src/opening/drift_database_opener.dart';
export 'src/utils/database_constants.dart';
