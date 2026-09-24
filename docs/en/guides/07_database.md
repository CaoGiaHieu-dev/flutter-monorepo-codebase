# Guide: Relational Database (Drift + SQLite)

## Goal

You give a package its own relational database: tables, a DAO, a data source that returns models, and versioned migrations. Deleting the package deletes its database with it, without breaking anyone else. The worked example is the real `data_cache` wiring; substitute your package name throughout.

## Prerequisites

- A data package — [`02_new_domain_data.md`](02_new_domain_data.md).
- **Why there is no shared `AppDatabase`**, what `core_database` exports, how the migration runner replays, the `PRAGMA`s it applies and how a corrupt file is quarantined — [`../architecture/02_core.md` § 8](../architecture/02_core.md#8-core_database--relational-storage-drift--sqlite). The rules: RULE-46, RULE-47.

> [!NOTE]
> The chain — `CacheEntries` → `CacheEntriesDao` → `CacheEntryLocalDataSource` → `CacheEntryRepositoryImpl` → `ICacheEntryRepository` → `GetCacheEntryUseCase` / `SaveCacheEntryUseCase` — is the `cache` module (`modules/cache/domain` + `modules/cache/data`), wired end to end, but **no feature in this template consumes it**. It exists as a working reference for the shape below, and as the fixture the database tests run against.
>
> It is an ordinary removable module: `apps/mobile` composes it, `apps/admin` does not — so only mobile opens the SQLite file at boot. Copy the shape for real tables, or remove it with `dart tools/sample_cleanup/remove_sample.dart cache --apply` (without `--apply` it only previews). The database tests go with it; they exercise `core_database`'s `DatabaseHandle` and `driftMigrationStrategy` through this fixture, so give them another before deleting if you want to keep that coverage.

---

## 1. Decide: key-value storage or a database

| You need | Use | Why |
|---|---|---|
| A token, a flag, a theme mode, a locale | [`core_storage`](06_storage.md) | One value per key; encrypted; reactive via `ChangeNotifier` / `Stream` |
| A list of rows you query, filter or sort | `core_database` | SQL, indexes, ordering |
| Relations between records | `core_database` | Foreign keys (enforced because every connection runs `PRAGMA foreign_keys = ON`) |
| Data whose shape will change over releases | `core_database` | Versioned migrations |
| Something small, read on every frame | `core_storage` | In-memory cache; no async round-trip |

Rule of thumb: if you would reach for `WHERE`, `ORDER BY` or `JOIN`, you want a database.

## 2. Declare the dependencies

The package's `pubspec.yaml` needs what the real `modules/cache/data/pubspec.yaml` declares for its database:

```yaml
dependencies:
  flutter:
    sdk: flutter              # `visibleForTesting` in the database class
  core_database:
    path: ../../../platform/infra/database
  drift: "^2.34.3"
  get_it: ^9.2.1              # the DI module collects migrations through GetIt
  injectable: ^3.0.0

dev_dependencies:
  build_runner: "^2.16.0"
  drift_dev: "^2.34.5"        # generates `<name>_database.g.dart`
  injectable_generator: "^3.1.3"
  flutter_test:
    sdk: flutter              # for the in-memory database tests (step 12)
```

Add the rest of a data package as usual (`domain_core`, `data_core`, your `domain_*`, `freezed_annotation` / `freezed` for models). `sqlite3` and `path_provider` are `core_database`'s own dependencies — do not repeat them. Versions come from the catalog `pubspec_dependencies.yaml`: a dependency written with no version (`drift:`) is filled in by `dart tools/dependency_sync.dart`, and a mismatched one rewritten. Then `flutter pub get`.

## 3. Define the table

A `Table` subclass is standalone: it references no database, so it lives in your package.

```dart
// modules/cache/data/lib/src/database/tables/cache_entries_table.dart
import 'package:drift/drift.dart';

/// Example table — stores arbitrary string payloads keyed by a unique id.
///
/// Use this as a template when adding feature-specific tables.
class CacheEntries extends Table {
  /// Unique cache key (e.g. `home_feed`, `user_profile_draft`).
  TextColumn get key => text()();

  /// Serialized payload (JSON string, plain text, etc.).
  TextColumn get value => text()();

  /// Last write timestamp for TTL / eviction policies.
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
```

## 4. Define the DAO as a `part of` your database

```dart
// modules/cache/data/lib/src/database/dao/cache_entries_dao.dart
part of '../cache_database.dart';

/// Data access object for [CacheEntries].
@DriftAccessor(tables: [CacheEntries])
class CacheEntriesDao extends DatabaseAccessor<CacheDatabase>
    with _$CacheEntriesDaoMixin {
  CacheEntriesDao(super.attachedDatabase);

  /// Inserts or replaces a cache row.
  Future<void> upsert(String key, String value) {
    return into(cacheEntries).insertOnConflictUpdate(
      CacheEntriesCompanion.insert(
        key: key,
        value: value,
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Reads the full row for [key], or `null` when missing.
  Future<CacheEntry?> getEntry(String key) {
    return (select(
      cacheEntries,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
  }
}
```

The `part of` is mandatory — that is Drift's requirement, and the reason the DAO cannot live in another package.

## 5. Name the database file in your own `utils/`

Per the repo-wide rule, constants live in the owning package's `utils/`:

```dart
// modules/cache/data/lib/src/utils/cache_constants.dart
class CacheConstants {
  CacheConstants._();

  /// On-disk SQLite file for this package's [CacheDatabase], resolved inside
  /// the app documents directory.
  ///
  /// Named after its owner rather than the app, because each package that
  /// persists data opens its own file. Changing this value points the package
  /// at a different database and makes existing on-device rows unreachable.
  static const String DATABASE_FILE_NAME = 'cache.sqlite';
}
```

> [!CAUTION]
> Name the file after its **owning package**, not after the app. Several databases coexist in the documents directory; a generic `app_database.sqlite` would collide. Changing this string after release makes existing rows unreachable.

## 6. Declare the database class

```dart
// modules/cache/data/lib/src/database/cache_database.dart
import 'package:core_database/core_database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../utils/cache_constants.dart';
import 'tables/cache_entries_table.dart';

part 'cache_database.g.dart';
part 'dao/cache_entries_dao.dart';

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

  @override
  MigrationStrategy get migration =>
      driftMigrationStrategy(database: this, migrations: _migrations);
}
```

The imports matter as much as the class: the **table** is an ordinary `import` (it is standalone), while the **DAO** is a `part` — Drift requires an accessor to live in its database's library — next to `part '<name>_database.g.dart';`, which `build_runner` writes.

Two things to copy exactly:

- **Migrations are passed in, never looked up inside the class.** That keeps the database free of service-locator calls and directly constructible in tests.
- **`migration` delegates to `driftMigrationStrategy`.** Writing your own `MigrationStrategy` means re-deriving the `PRAGMA` settings — and a package that forgets `foreign_keys = ON` silently loses referential integrity.

## 7. Register the database in your DI module

```dart
// modules/cache/data/lib/di/module.dart
@module
abstract class DataCacheDiModule {
  /// `@Order(1)`: injectable registers a module's entries in ascending order,
  /// so this package's own migrations (default order 0) exist before the open.
  @Order(1)
  @preResolve
  @lazySingleton
  Future<CacheDatabase> cacheDatabase() =>
      CacheDatabase.open(migrations: _registeredMigrations());

  /// Narrow accessor handle for this package's data sources.
  @lazySingleton
  IDatabaseHandle<CacheDatabase> cacheDatabaseHandle(CacheDatabase database) =>
      DatabaseHandle<CacheDatabase>(database);

  /// Reads contributed migrations without throwing when none are registered.
  static Iterable<IDatabaseMigration> _registeredMigrations() {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<IDatabaseMigration<CacheDatabase>>()) {
      return const <IDatabaseMigration>[];
    }
    return getIt.getAll<IDatabaseMigration<CacheDatabase>>();
  }
}
```

The `isRegistered` guard matters: `getAll<T>()` **throws** when nothing is registered for `T`. Without the guard, a build with no contributed migration would crash during `configureDependencies()`.

> [!WARNING]
> **Registration order.** `@preResolve` opens the database — and therefore runs migrations — at the moment injectable reaches that registration, so every step must already be registered by then. A step that is not is skipped without an error: `schemaVersion` moves and the schema does not.
>
> - **A step in the owning package** (here `data_cache`) is collected **as long as the open keeps `@Order(1)`**. Injectable registers a package's entries in ascending `@Order`, and a migration annotated `@LazySingleton(as: IDatabaseMigration<CacheDatabase>)` has the default order 0 — so it lands before the open.
> - Remove `@Order(1)` and the open may be registered first; that is the bug `@Order(1)` was added to fix.
> - **A step from another package** must sit in an **earlier DI group** than the owning package in the app's `app_manifest.yaml`. `@Order` sorts only within one package's module; it cannot move a registration across modules. Nothing in the template does this yet, but it will bite the first feature that adds a migration for someone else's database.
>
> **Copying this pattern for your own database? Put `@Order(1)` on your `@preResolve` open as well** — without it, a step written exactly as step 11 shows is never collected. See [`05_di.md`](05_di.md) for module ordering.

## 8. Consume it through `IDatabaseHandle`, not the database

```dart
// modules/cache/data/lib/src/data_sources/local/cache_entry_local_data_source.dart
@LazySingleton(as: ICacheEntryLocalDataSource)
class CacheEntryLocalDataSource implements ICacheEntryLocalDataSource {
  CacheEntryLocalDataSource(IDatabaseHandle<CacheDatabase> handle)
    : _dao = handle.accessor(CacheEntriesDao.new);

  final CacheEntriesDao _dao;

  @override
  Future<CacheEntryModel?> getEntry(String key) async {
    final row = await _dao.getEntry(key);
    return row == null ? null : CacheEntryModel.fromRow(row);
  }
  // ...
}
```

Taking `IDatabaseHandle` rather than `CacheDatabase` means the class receives only the accessor it asks for, and the boundary is visible in the constructor.

`IDatabaseHandle` also exposes `transaction`, so a package can make multi-statement writes atomic without being handed the database:

```dart
await _handle.transaction(() async {
  await _dao.upsert('a', '1');
  await _dao.upsert('b', '2');
});
```

> [!NOTE]
> This is **API-surface narrowing, not enforced isolation** — Drift's `DatabaseAccessor` requires the database, so the factory callback still receives it and a determined caller could capture it. The real isolation comes from the layer above: separate databases per package. The doc comment in `i_database_handle.dart` states this rather than overclaiming.

## 9. Return a model, never a Drift row

```dart
// modules/cache/data/lib/src/data_sources/local/cache_entry_local_data_source.dart
abstract class ICacheEntryLocalDataSource {
  Future<void> save(String key, String value);

  Future<CacheEntryModel?> getEntry(String key);
}
```

`CacheEntry` — the class Drift generates for a row — never appears in a signature. The conversion happens at the boundary:

```dart
// modules/cache/data/lib/src/models/cache_entry_model.dart
@freezed
abstract class CacheEntryModel
    with _$CacheEntryModel
    implements BaseModel<CacheEntryEntity> {
  const CacheEntryModel._();

  const factory CacheEntryModel({
    required String key,
    required String value,
    required DateTime updatedAt,
  }) = _CacheEntryModel;

  /// Maps a Drift row into the data-layer model.
  factory CacheEntryModel.fromRow(CacheEntry row) {
    return CacheEntryModel(
      key: row.key,
      value: row.value,
      updatedAt: row.updatedAt,
    );
  }

  @override
  CacheEntryEntity toEntity() {
    return CacheEntryEntity(key: key, value: value, updatedAt: updatedAt);
  }
}
```

It is deliberately **not** `json_serializable`: rows come from SQLite, not from an API payload, so there is no JSON contract to honour.

## 10. Generate the code and the barrels

```bash
dart run build_runner build --workspace
dart tools/barrel_generator/generate.dart modules/cache/data/lib
```

## 11. Add a schema migration

You never edit another package's database file to change your schema. You implement one contract and register it.

```dart
// platform/infra/database/lib/src/migration/i_database_migration.dart
abstract class IDatabaseMigration<TDb extends GeneratedDatabase> {
  /// Schema version produced by [upgrade]; must be `>= 2` and unique.
  int get version;

  /// Moves the schema from `version - 1` to [version].
  Future<void> upgrade(Migrator m);

  /// Reverses [upgrade], moving the schema from [version] back to
  /// `version - 1`.
  Future<void> downgrade(Migrator m);
}
```

A schema change is **three edits made together** — miss one and the upgrade silently does nothing, or a fresh install and an upgraded one end up with different schemas:

1. **Add the column to the table class** — Drift generates the schema from it, and `Migrator.createAll()` builds fresh installs from it. A column added to an existing table must be `nullable()` or have a `withDefault(...)`: SQLite cannot add a `NOT NULL` column without a default to rows that already exist.

   ```dart
   // tables/cache_entries_table.dart — inside `CacheEntries`
   DateTimeColumn get expiresAt => dateTime().nullable()();
   ```

2. **Bump `schemaVersion`** in your database class (`1` → `2`). It must equal the highest `version` among your steps: Drift calls `onUpgrade` only when the stored `user_version` is below `schemaVersion`, so without the bump no step ever runs on an existing install, and its queries fail with *"no such column"*.

   ```dart
   @override
   int get schemaVersion => 2;
   ```

3. **Register the step** — below. Then `dart run build_runner build --workspace` (the generated table class gains the column).

Registered like a route module, typed to the database it belongs to — GetIt keys a registration by its exact type, so `CacheDatabase` collects only `IDatabaseMigration<CacheDatabase>` and another package's steps never reach it. Declared in the owning package, it is collected because the open carries `@Order(1)` ([step 7](#7-register-the-database-in-your-di-module)):

```dart
@LazySingleton(as: IDatabaseMigration<CacheDatabase>)
class AddExpiresAtToCacheEntries
    implements IDatabaseMigration<CacheDatabase> {
  @override
  int get version => 2;

  @override
  Future<void> upgrade(Migrator m) {
    // `Migrator.database` is the database being migrated; the cast reaches
    // its generated table getters. `expiresAt` is the column this step adds.
    final db = m.database as CacheDatabase;
    return m.addColumn(db.cacheEntries, db.cacheEntries.expiresAt);
  }

  @override
  Future<void> downgrade(Migrator m) {
    final db = m.database as CacheDatabase;
    return m.alterTable(TableMigration(db.cacheEntries));
  }
}
```

### Honour the contract

- **`version` is the version this step *produces*.** `version == 2` means "take a database at version 1 and make it version 2". So `upgrade` must run against `version - 1`, and `downgrade` must return it to that same shape.
- **Version 1 is not migratable** — it is what `Migrator.createAll()` creates. The runner rejects `version < 2` at construction.
- **Duplicate versions are rejected**, not silently resolved to one of them.

## 12. Test the database

`CacheDatabase.forTesting()` gives an in-memory database on the current isolate — no `path_provider`, no isolate, no file:

```dart
final database = CacheDatabase.forTesting();
```

The existing tests are split to follow the code:

| Package | File | Covers |
|---|---|---|
| `core_database` | `migration_test.dart` | Runner validation (version < 2, duplicates, sorting), replay of skipped versions, descending downgrade, gaps, irreversible downgrade, downgrade with no covering step refused (and the stored version left untouched, against a real file), empty registry |
| `core_database` | `drift_database_opener_test.dart` | The corruption predicate directly — including the case where an environment marker vetoes a corruption match |
| `data_cache` | `cache_database_test.dart` | DAO round-trips, migration wiring, and **real-file** behaviour (WAL, foreign keys, survival across close/reopen) |
| `data_cache` | `database_handle_test.dart` | Accessor reads/writes, shared connection, transaction commit / rollback / return value |

Two habits worth copying:

- **Test the corruption predicate directly.** It decides whether a user's database may be moved aside — verifying it only through a real corrupt file is not enough.
- **Test pragmas on a real file.** An in-memory database reports `journal_mode = memory`, so it cannot prove WAL is on.

---

## Verify

```bash
dart run build_runner build --workspace   # <name>_database.g.dart, the DAO mixin, module.module.dart
flutter analyze                           # No issues found!
cd modules/cache/data && flutter test     # the reference tests: DAO, migrations, WAL on a real file
cd platform/infra/database && flutter test
cd apps/mobile && flutter test test/di_smoke_test.dart   # the @preResolve open succeeds in the real graph
```

Run your own package's tests the same way. A new migration needs a test that opens the old schema, runs the step and reads the new column back.

Review checklist:

- [ ] Tables, DAO, database class and data source all live in the **owning package**
- [ ] Database file name is a constant in that package's `utils/`, named after the package
- [ ] `migration` delegates to `driftMigrationStrategy` (do not hand-roll `MigrationStrategy`)
- [ ] Migrations are **passed into** the database, never looked up inside it
- [ ] `_registeredMigrations()` guards with `isRegistered` before `getAll`
- [ ] The `@preResolve` open carries `@Order(1)`, so the package's own migrations register before it; a step from another package sits in an earlier DI group
- [ ] Data sources take `IDatabaseHandle<TDb>`, not the database
- [ ] Signatures return a **Model**; no Drift row class in the public API
- [ ] New schema step = new `IDatabaseMigration` with `version >= 2`, registered via `@LazySingleton(as: IDatabaseMigration<YourDatabase>)`; `schemaVersion` bumped to match
- [ ] `downgrade` implemented, or throws a descriptive error when irreversible
- [ ] Barrels regenerated and `build_runner` run

## Troubleshooting

| Symptom | Cause | Fix |
|:--|:--|:--|
| `no such column` after an upgrade | `schemaVersion` was not bumped, or the step was never collected | Bump `schemaVersion` and register the step typed to your database (step 11) |
| The step exists but never runs | The open lacks `@Order(1)`, the step is registered as untyped `IDatabaseMigration`, or it sits in a later DI group | Add `@Order(1)` (step 7); register `as: IDatabaseMigration<YourDatabase>` (step 11) |
| Boot crashes in `configureDependencies()` with no migration registered | `getAll<T>()` throws when nothing is registered | Keep the `isRegistered` guard (step 7) |
| `UnsupportedError: Cannot downgrade the schema…` at startup | An older build was installed over a newer schema | Ship the downgrade step first, or reinstall the newer build |
| Relations are not enforced | A hand-written `MigrationStrategy` skipped `foreign_keys = ON` | Delegate to `driftMigrationStrategy` (step 6) |
| The file was moved to `<name>.corrupt` | The opener detected a corrupt database and quarantined it | The bytes are kept for recovery; see [`../architecture/02_core.md` § 8](../architecture/02_core.md#corruption-recovery-quarantine-never-delete) |
| A test cannot prove WAL is on | In-memory databases report `journal_mode = memory` | Test pragmas on a real file (step 12) |

## Related

- Rules: RULE-41 (return models, never rows), RULE-46 (each package owns its database), RULE-47 (migrations typed to their database) — [`../reference/01_rules.md`](../reference/01_rules.md)
- [`../architecture/02_core.md` § 8](../architecture/02_core.md#8-core_database--relational-storage-drift--sqlite) — the design behind the mechanism
- [`06_storage.md`](06_storage.md) — key-value storage, and when to prefer it
- [`02_new_domain_data.md`](02_new_domain_data.md) — the repository and model layers above the DAO
- [`05_di.md`](05_di.md) — `@preResolve`, module ordering, `getAll` vs `getAllOrEmpty`
