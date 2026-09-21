import 'package:drift/drift.dart';

/// One schema step, contributed by the package that owns the affected tables.
///
/// `core_database` deliberately does not know which tables a feature needs.
/// A package that changes the schema implements this contract next to its own
/// tables and registers it in its DI module, mirroring how features contribute
/// routes through `IFeatureRouteModule`:
///
/// ```dart
/// @LazySingleton(as: IDatabaseMigration)
/// class AddExpiresAtToCacheEntries implements IDatabaseMigration {
///   @override
///   int get version => 2;
///
///   @override
///   Future<void> upgrade(Migrator m) =>
///       m.addColumn(cacheEntries, cacheEntries.expiresAt);
///
///   @override
///   Future<void> downgrade(Migrator m) =>
///       m.alterTable(TableMigration(cacheEntries));
/// }
/// ```
///
/// ## Contract
///
/// [version] is the schema version this migration *produces*. Implementing
/// `version == 2` means: "take a database at version 1 and make it version 2".
/// Consequently [upgrade] must be able to run against version `version - 1`,
/// and [downgrade] must return the database to that same shape.
///
/// Steps are replayed in order, so a device that skipped several releases
/// still arrives at the right schema — never assume the previous version was
/// the one immediately before the current release.
///
/// Registering two migrations with the same [version] is a programming error
/// and is rejected at startup rather than silently applying one of them.
abstract class IDatabaseMigration {
  /// Schema version produced by [upgrade]; must be `>= 2` and unique.
  ///
  /// Version 1 is the initial schema created by `Migrator.createAll()`, so
  /// there is nothing to migrate *to* it.
  int get version;

  /// Moves the schema from `version - 1` to [version].
  Future<void> upgrade(Migrator m);

  /// Reverses [upgrade], moving the schema from [version] back to
  /// `version - 1`.
  ///
  /// Drift has no dedicated downgrade callback — it routes both directions
  /// through `onUpgrade` — so this is invoked when a user installs an older
  /// build over a newer one. Implement it whenever the change is reversible;
  /// throw a descriptive error when it is not, so the failure is explicit
  /// instead of leaving a schema that no longer matches the running code.
  Future<void> downgrade(Migrator m);
}
