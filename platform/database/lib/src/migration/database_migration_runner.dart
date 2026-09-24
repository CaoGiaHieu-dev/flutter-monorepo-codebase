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
  ///
  /// ## Downgrades need explicit steps
  ///
  /// A downgrade ([from] > [to]) throws [UnsupportedError] unless this
  /// runner knows the schema it is leaving — a step registered for [from] or
  /// above. With no such step the runner used to do nothing, and drift then
  /// stamped the lower `user_version` over a schema that was still the newer
  /// one: every table kept its newer shape, and reinstalling the newer build
  /// later replayed its upgrades against tables that already had them, which
  /// fails (a duplicate column) on every launch from then on. Failing here
  /// leaves the file and its version untouched, and `DriftDatabaseOpener`
  /// surfaces the error instead of quarantining the database.
  ///
  /// In practice an older build only has such steps when they are shipped
  /// ahead of the change they reverse; otherwise installing an older build
  /// over a newer schema is simply unsupported.
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

    final newestKnown = _migrations.isEmpty ? null : _migrations.last.version;
    if (newestKnown == null || newestKnown < from) {
      throw UnsupportedError(
        'Cannot downgrade the schema from version $from to $to: this build '
        'registers no IDatabaseMigration for version $from '
        '(${newestKnown == null ? 'it registers none' : 'its newest is version $newestKnown'}), '
        'so it cannot reverse that schema. The database is left untouched. '
        'Downgrades need an explicit IDatabaseMigration.downgrade step for '
        'every version being left; otherwise reinstall a build with schema '
        'version $from or later.',
      );
    }

    for (final migration in _migrations.reversed) {
      if (migration.version > to && migration.version <= from) {
        await migration.downgrade(m);
      }
    }
  }
}
