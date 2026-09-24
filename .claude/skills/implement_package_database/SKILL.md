---
name: implement_package_database
description: Use when a package needs relational or offline storage — "add a table", "store a list of X locally", "add a Drift/SQLite database", "query rows or relations offline", "add a schema migration". Gives the package its own Drift database (tables, DAO as part of it, typed migration registration, @Order(1) @preResolve open, IDatabaseHandle, data source returning Models), modelled on modules/cache/data.
---

# 🗄️ Skill: Implement a Package-Owned Database

Use this skill when requested to: "add a table", "store a list of X locally", "add a Drift/SQLite database", "query rows / relations offline", "add a schema migration", etc.

> [!IMPORTANT]
> **There is no `AppDatabase`** — each package declares its own database (RULE-46) on top of
> `core_database`'s mechanism (`IDatabaseHandle<TDb>`, `IDatabaseMigration<TDb>`,
> `DatabaseMigrationRunner`, `DatabaseConnectionFactory`, `DriftDatabaseOpener`,
> `driftMigrationStrategy`). Migrations register typed to the database, and the open carries
> `@Order(1)` (RULE-47); data sources return Models (RULE-41).
>
> Reference implementation: `modules/cache/data` (`data_cache`). It is sample code with no
> runtime consumer — copy its shape. **Guide:** [`docs/en/guides/07_database.md`](../../../docs/en/guides/07_database.md).
> **Rules** ([registry](../../../docs/en/reference/01_rules.md)): RULE-09, RULE-41, RULE-46, RULE-47, RULE-74, RULE-75.

---

## 🧭 Database or key-value storage?

| Need | Use |
| :--- | :--- |
| A token, a flag, the theme, the locale (one value per key) | `core_storage` — see `implement_package_storage` |
| Lists, relations, `WHERE` / `ORDER BY` / `JOIN`, schema migrations | **Your own Drift database** (this skill) |

Accepted trade-off: SQL cannot join across package boundaries. Crossing a bounded context belongs
at the repository layer (compose two repositories in a use case), not in a query.

---

## 📋 Detailed Steps

Paths below use `modules/<module>/data`; substitute your package. Dependencies the package needs
(versions come from `pubspec_dependencies.yaml` via `dart tools/dependency_sync.dart`, never
hand-written): `core_database`, `drift`, and `flutter` (for `visibleForTesting`) in
`dependencies`; `drift_dev` and `build_runner` in `dev_dependencies` — as
`modules/cache/data/pubspec.yaml` declares them.

### Step 1: Define the table

A `Table` references no database, so it is a standalone file:

```dart
// modules/cache/data/lib/src/database/tables/cache_entries_table.dart
import 'package:drift/drift.dart';

class CacheEntries extends Table {
  TextColumn get key => text()();

  TextColumn get value => text()();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
```

### Step 2: Define the DAO as a `part of` your database

```dart
// modules/cache/data/lib/src/database/dao/cache_entries_dao.dart
part of '../cache_database.dart';

@DriftAccessor(tables: [CacheEntries])
class CacheEntriesDao extends DatabaseAccessor<CacheDatabase>
    with _$CacheEntriesDaoMixin {
  CacheEntriesDao(super.attachedDatabase);

  Future<void> upsert(String key, String value) {
    return into(cacheEntries).insertOnConflictUpdate(
      CacheEntriesCompanion.insert(
        key: key,
        value: value,
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<CacheEntry?> getEntry(String key) {
    return (select(
      cacheEntries,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
  }
}
```

It must be `part of` **your** database library — never someone else's.

### Step 3: Name the file in your own `utils/`

```dart
// modules/cache/data/lib/src/utils/cache_constants.dart
class CacheConstants {
  CacheConstants._();

  static const String DATABASE_FILE_NAME = 'cache.sqlite';
}
```

Name the file after the owning package. Changing it later points the package at a different file
and makes existing on-device rows unreachable.

### Step 4: Declare the database

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

  final Iterable<IDatabaseMigration> _migrations;

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

- Migrations are **passed in**, never looked up inside the database — it stays free of
  service-locator calls and constructible in tests.
- `migration` **delegates to `driftMigrationStrategy`** — it applies the per-connection `PRAGMA`s
  (`foreign_keys`, WAL, `busy_timeout`) and replays contributed steps. Do not hand-roll a
  `MigrationStrategy`.
- `DriftDatabaseOpener.open` opens on a background isolate, verifies the connection and
  quarantines (never deletes) a corrupt file.

### Step 5: Register it in your DI module

```dart
// modules/cache/data/lib/di/module.dart
import 'package:core_database/core_database.dart';
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

import '../src/database/cache_database.dart';

@InjectableInit.microPackage()
void initMicroPackage() {}

@module
abstract class DataCacheDiModule {
  @Order(1)
  @preResolve
  @lazySingleton
  Future<CacheDatabase> cacheDatabase() =>
      CacheDatabase.open(migrations: _registeredMigrations());

  @lazySingleton
  IDatabaseHandle<CacheDatabase> cacheDatabaseHandle(CacheDatabase database) =>
      DatabaseHandle<CacheDatabase>(database);

  static Iterable<IDatabaseMigration> _registeredMigrations() {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<IDatabaseMigration<CacheDatabase>>()) {
      return const <IDatabaseMigration>[];
    }
    return getIt.getAll<IDatabaseMigration<CacheDatabase>>();
  }
}
```

- **`@preResolve`** opens the database — and runs its migrations — while the module initialises,
  so every step must already be registered.
- **`@Order(1)`** guarantees that inside the package: injectable registers a package's entries in
  ascending order and a migration has the default order `0`. Without it the open runs first and a
  step in the same package is never collected. A step from **another** package must sit in an
  earlier DI group.
- **The `isRegistered` guard** is mandatory: a bare `getAll` throws when no step is registered,
  and a database must open normally with none (that is what keeps the package removable).
- Collect exactly `IDatabaseMigration<YourDatabase>` — never the untyped interface.

### Step 6: Consume it through `IDatabaseHandle` and return a Model

```dart
// modules/cache/data/lib/src/data_sources/local/cache_entry_local_data_source.dart
abstract class ICacheEntryLocalDataSource {
  Future<void> save(String key, String value);

  Future<CacheEntryModel?> getEntry(String key);
}

@LazySingleton(as: ICacheEntryLocalDataSource)
class CacheEntryLocalDataSource implements ICacheEntryLocalDataSource {
  CacheEntryLocalDataSource(IDatabaseHandle<CacheDatabase> handle)
    : _dao = handle.accessor(CacheEntriesDao.new);

  final CacheEntriesDao _dao;

  @override
  Future<void> save(String key, String value) => _dao.upsert(key, value);

  @override
  Future<CacheEntryModel?> getEntry(String key) async {
    final row = await _dao.getEntry(key);
    return row == null ? null : CacheEntryModel.fromRow(row);
  }
}
```

The data source takes `IDatabaseHandle<TDb>` (only the accessor it asks for, plus `transaction`),
not the database. It converts the Drift row class at the boundary with a model factory — the
generated `CacheEntry` never appears in a public signature:

```dart
// modules/cache/data/lib/src/models/cache_entry_model.dart
  factory CacheEntryModel.fromRow(CacheEntry row) {
    return CacheEntryModel(
      key: row.key,
      value: row.value,
      updatedAt: row.updatedAt,
    );
  }
```

The model is Freezed, implements `BaseModel<Entity>` with a `toEntity()` mapper, and is **not**
`json_serializable` (rows come from SQLite, not an API). Above it, the RepositoryImpl wraps the
data source in `execute()` exactly as any other repository — see `implement_domain_data_flow`.

### Step 7: Run codegen, then the barrels

```bash
dart run build_runner build --workspace
dart tools/barrel_generator/generate.dart modules/<module>/data/lib   # after build_runner
```

---

## 🔁 Changing the schema later

1. Edit the table.
2. Bump `schemaVersion` to the new number.
3. Contribute one `IDatabaseMigration<YourDatabase>` whose `version` is that number, registered
   **typed** to your database (the example from `core_database`'s own contract, where `expiresAt`
   is the column step 1 added to the table):

```dart
@LazySingleton(as: IDatabaseMigration<CacheDatabase>)
class AddExpiresAtToCacheEntries
    implements IDatabaseMigration<CacheDatabase> {
  @override
  int get version => 2;

  @override
  Future<void> upgrade(Migrator m) {
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

- An untyped `@LazySingleton(as: IDatabaseMigration)` is **never collected** — GetIt keys a
  registration by its exact type — so the version moves and the schema does not.
- `version` is the version the step *produces* and must be `>= 2` (version 1 is `createAll()`);
  duplicate versions are rejected at startup.
- Upgrades replay ascending, downgrades descending; gaps are legal.
- **Drift has no `onDowngrade`** — the downgrade rides `onUpgrade` via `from`/`to`. A downgrade
  with no registered step for the version being left **throws** `UnsupportedError` rather than
  stamping a lower `user_version` over a newer schema. Implement `downgrade` when the change is
  reversible; throw a descriptive error when it is not.

---

## 🧪 Tests

Use the in-memory database — no file, no isolate:

```dart
final database = CacheDatabase.forTesting();
```

Put tests in the owning package's `test/` directory, following `modules/cache/data/test/`
(`cache_database_test.dart`: DAO round-trips, migration wiring, real-file WAL / foreign keys;
`database_handle_test.dart`: accessor, shared connection, transactions). Test pragmas on a real
file — an in-memory database reports `journal_mode = memory`.

```bash
cd modules/<module>/data && flutter test
```

---

## ✅ Checklist

- [ ] Tables, DAO, database class and data source all live in the **owning package**
- [ ] DAO is `part of` **your** database library
- [ ] Database file name is a constant in the package's own `utils/`, named after the package
- [ ] `migration` delegates to `driftMigrationStrategy`; migrations are passed into the database
- [ ] Open is `@Order(1) @preResolve @lazySingleton`; `_registeredMigrations()` guards with `isRegistered`
- [ ] Data sources take `IDatabaseHandle<TDb>` and return a **Model** (`fromRow`), never a Drift row
- [ ] Schema change = `schemaVersion` bumped + `@LazySingleton(as: IDatabaseMigration<YourDatabase>)` step
- [ ] `downgrade` implemented, or throws a descriptive error when irreversible
- [ ] `build_runner` run, then the barrel generator

---

## 🔗 Related

- `docs/{en,vi}/guides/07_database.md` — the long-form guide (corruption recovery, `PRAGMA`s, runner internals)
- `implement_package_storage` — key-value persistence instead of tables
- `implement_domain_data_flow` — the Repository / UseCase layers above the data source
- `implement_dependency_injection` — `@preResolve`, module order, `getAll` vs `getAllOrEmpty`
