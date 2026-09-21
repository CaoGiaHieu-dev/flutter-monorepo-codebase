import 'package:drift/drift.dart';

import 'i_database_migration.dart';

/// Replays the [IDatabaseMigration]s contributed by other packages.
///
/// Drift exposes a single `onUpgrade` callback for both directions (see
/// [MigrationStrategy.onUpgrade]); this runner turns that one entry point
/// into the ordered, per-step contract described by [IDatabaseMigration].
class DatabaseMigrationRunner {
  /// Sorts and validates [migrations] once, at construction.
  ///
  /// Validating here rather than mid-migration matters: a duplicate or
  /// out-of-range version is a wiring mistake, and discovering it halfway
  /// through would leave the schema in a partially migrated state.
  factory DatabaseMigrationRunner(Iterable<IDatabaseMigration> migrations) {
    final sorted = List<IDatabaseMigration>.of(migrations)
      ..sort((a, b) => a.version.compareTo(b.version));

    final seen = <int>{};
    for (final migration in sorted) {
      if (migration.version < _firstMigratableVersion) {
        throw ArgumentError.value(
          migration.version,
          'version',
          'Migration ${migration.runtimeType} must target version '
              '$_firstMigratableVersion or later; version 1 is the initial '
              'schema created by Migrator.createAll().',
        );
      }
      if (!seen.add(migration.version)) {
        throw ArgumentError.value(
          migration.version,
          'version',
          'Duplicate migration version: ${migration.runtimeType} collides '
              'with another migration targeting the same version.',
        );
      }
    }

    return DatabaseMigrationRunner._(sorted);
  }

  const DatabaseMigrationRunner._(this._migrations);

  /// Lowest version a migration may target; version 1 is created, not migrated.
  static const int _firstMigratableVersion = 2;

  /// Registered migrations, ascending by [IDatabaseMigration.version].
  final List<IDatabaseMigration> _migrations;

  /// Migrations known to this runner, ascending by version.
  List<IDatabaseMigration> get migrations => List.unmodifiable(_migrations);

  /// Applies every step needed to move the schema from [from] to [to].
  ///
  /// Upgrades run ascending, downgrades descending, so a device that skipped
  /// releases replays each intermediate step instead of jumping straight to
  /// the newest shape. When [from] equals [to] nothing runs.
  ///
  /// A gap in the registered versions is not treated as an error: a release
  /// may legitimately ship no schema change, leaving that version number
  /// unused.
  Future<void> run(Migrator m, int from, int to) async {
    if (from == to) return;

    if (to > from) {
      for (final migration in _migrations) {
        if (migration.version > from && migration.version <= to) {
          await migration.upgrade(m);
        }
      }
      return;
    }

    for (final migration in _migrations.reversed) {
      if (migration.version > to && migration.version <= from) {
        await migration.downgrade(m);
      }
    }
  }
}
