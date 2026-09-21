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
/// pieces below. `data_core`'s `CacheDatabase` is the reference wiring.
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
///   `@LazySingleton(as: IDatabaseMigration)`
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
export 'di/di.dart';
export 'src/src.dart';
