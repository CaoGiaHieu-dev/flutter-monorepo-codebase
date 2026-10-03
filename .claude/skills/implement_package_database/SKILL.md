---
name: implement_package_database
description: Use when a package needs relational or offline storage — "add a table", "store a list of X locally", "add a Drift/SQLite database", "query rows or relations offline", "add a schema migration". Gives the package its own Drift database (tables, DAO as part of it, typed migration registration, @Order(1) @preResolve open, IDatabaseHandle, data source returning Models) and its upgrade test, modelled on modules/cache/data.
---

# Skill: Implement a package-owned database

Use this skill to add a table, store a list locally, query rows offline, or add a schema migration.

> **There is no `AppDatabase`.** Each package declares its own database (RULE-46) on top of `core_database`'s
> mechanism (`IDatabaseHandle<TDb>`, `IDatabaseMigration<TDb>`, `DatabaseMigrationRunner`,
> `DatabaseConnectionFactory`, `DriftDatabaseOpener`, `driftMigrationStrategy`). Migrations register typed to
> the database and the open carries `@Order(1)` (RULE-47); data sources return Models (RULE-41).

Reference implementation: `modules/cache/data` (`data_cache`) — sample code with no runtime consumer; copy its
shape. **Guide:** [`docs/en/guides/07_database.md`](../../../docs/en/guides/07_database.md).
**Rules** ([registry](../../../docs/en/reference/01_rules.md)): RULE-09, RULE-41, RULE-46, RULE-47, RULE-74.
Cite them; do not restate them.

## Database or key-value storage?

| Need | Use |
| :--- | :--- |
| A token, a flag, the theme, the locale (one value per key) | `core_storage` — [`implement_package_storage`](../implement_package_storage/SKILL.md) |
| Lists, relations, `WHERE` / `ORDER BY` / `JOIN`, schema migrations | **your own Drift database** (this skill) |

SQL cannot join across package boundaries: crossing a bounded context belongs at the repository layer (compose
two repositories in a use case), not in a query.

## Steps

Paths below use `modules/<module>/data`; substitute your package. Generate it first if it does not exist
(`dart tools/module_generator/generate.dart 3 <module>`, domain first —
[`implement_domain_data_flow`](../implement_domain_data_flow/SKILL.md)).

### Step 0: Declare the dependencies

Write the third-party entries **without a version**: versions live only in the catalog (RULE-74), and
`dart tools/dependency_sync.dart` fills an empty entry in and runs `pub get`. As `modules/cache/data/pubspec.yaml` does:

```yaml
dependencies:
  flutter:
    sdk: flutter              # `visibleForTesting` in the database class
  core_database:
    path: ../../../platform/infra/database
  platform_kernel:
    path: ../../../platform/foundation/kernel   # getAllOrEmpty, for the DI module
  drift:
  injectable:

dev_dependencies:
  build_runner:
  drift_dev:                  # generates `<name>_database.g.dart`
  injectable_generator:
  flutter_test:
    sdk: flutter              # the in-memory database tests
```

Add the rest of a data package as usual (`data_core`, `domain_core`, your `domain_*`, `freezed_annotation` /
`freezed` for models). `sqlite3` and `path_provider` are `core_database`'s own dependencies: do not repeat them.

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
      CacheEntriesCompanion.insert(key: key, value: value, updatedAt: Value(DateTime.now())),
    );
  }

  Future<CacheEntry?> getEntry(String key) {
    return (select(cacheEntries)..where((t) => t.key.equals(key))).getSingleOrNull();
  }
}
```

It must be `part of` **your** database library, never someone else's.

### Step 3: Name the file in your own `utils/`

```dart
// modules/cache/data/lib/src/utils/cache_constants.dart
class CacheConstants {
  CacheConstants._();

  static const String DATABASE_FILE_NAME = 'cache.sqlite';
}
```

Name the file after the owning package. Changing it later points the package at a different file and makes the
rows already on devices unreachable.

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

- Migrations are **passed in**, never looked up inside the database: it stays free of service-locator calls and
  constructible in tests.
- `migration` delegates to `driftMigrationStrategy` (per-connection `PRAGMA`s: `foreign_keys`, WAL,
  `busy_timeout`; replays contributed steps). Do not hand-roll a `MigrationStrategy`.
- `DriftDatabaseOpener.open` opens on a background isolate, verifies the connection and quarantines — never
  deletes — a corrupt file.

### Step 5: Register it in the package's DI module

Edit the generated `modules/<module>/data/lib/di/module.dart`: keep the `@InjectableInit.microPackage()` marker
and add the `@module` class beside it (`modules/cache/data/lib/di/module.dart`):

```dart
import 'package:core_database/core_database.dart';
import 'package:injectable/injectable.dart';
import 'package:platform_kernel/platform_kernel.dart';

import '../src/database/cache_database.dart';

@InjectableInit.microPackage()
void initMicroPackage() {}

@module
abstract class DataCacheDiModule {
  @Order(1)
  @preResolve
  @lazySingleton
  Future<CacheDatabase> cacheDatabase() => CacheDatabase.open(
    migrations: getAllOrEmpty<IDatabaseMigration<CacheDatabase>>(),
  );

  @lazySingleton
  IDatabaseHandle<CacheDatabase> cacheDatabaseHandle(CacheDatabase database) =>
      DatabaseHandle<CacheDatabase>(database);
}
```

- `@preResolve` opens the database, and runs its migrations, while the module initialises, so every step must
  already be registered.
- `@Order(1)` guarantees that inside the package: injectable registers a package's entries in ascending order and
  a migration has the default order `0`. A step from **another** package must sit in an earlier DI group.
- `getAllOrEmpty` (from `platform_kernel`) is mandatory: a bare `getAll` throws when no step is registered, and a
  database must open normally with none — that keeps the package removable.
- Collect exactly `IDatabaseMigration<YourDatabase>`, never the untyped interface.
- An app that composes the package also composes `core_database` (in `apps/mobile`'s `core` group; `apps/admin`
  has none), and its smoke test needs the `path_provider` double that `apps/mobile/test/di_smoke_test.dart`
  carries, because the open runs during DI.

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

The data source takes `IDatabaseHandle<TDb>` (only the accessor it asks for, plus `transaction`), not the
database, and converts the Drift row at the boundary with a model factory (`CacheEntryModel.fromRow(CacheEntry row)`
in `modules/cache/data/lib/src/models/cache_entry_model.dart`) — the generated row class never appears in a public
signature. The model is Freezed, `implements BaseModel<Entity>` with `toEntity()`, and is **not**
`json_serializable` (rows come from SQLite). Above it the RepositoryImpl wraps the data source in `execute()` as
any other repository: [`implement_domain_data_flow`](../implement_domain_data_flow/SKILL.md).

### Step 7: Codegen

```bash
dart run build_runner build --workspace
```

Barrels: [`run_repo_tooling`](../run_repo_tooling/SKILL.md#barrel-generator).

## Change the schema later

A schema change is **three edits made together**; miss one and the upgrade silently does nothing, or a fresh
install and an upgraded one differ:

1. Edit the table. A column added to an existing table must be `nullable()` or have `withDefault(...)`.
2. Bump `schemaVersion` to the new number (Drift runs `onUpgrade` only when the stored `user_version` is below it).
3. Contribute one `IDatabaseMigration<YourDatabase>` whose `version` is that number, registered **typed** to
   your database, then run `build_runner`:

```dart
import 'package:core_database/core_database.dart';
import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

import '../../database/cache_database.dart';

@LazySingleton(as: IDatabaseMigration<CacheDatabase>)
class AddExpiresAtToCacheEntries implements IDatabaseMigration<CacheDatabase> {
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

(`expiresAt` is the `DateTimeColumn get expiresAt => dateTime().nullable()();` that edit 1 added.)

- An untyped `@LazySingleton(as: IDatabaseMigration)` is **never collected** (GetIt keys a registration by its
  exact type): the version moves and the schema does not.
- `version` is the version the step *produces* and must be `>= 2`; duplicates are rejected at startup.
  Upgrades replay ascending, downgrades descending; gaps are legal.
- Drift has no `onDowngrade`: a downgrade with no registered step for the version being left **throws**
  `UnsupportedError` rather than stamping a lower `user_version` over a newer schema. Implement `downgrade` when
  the change is reversible; throw a descriptive error when it is not.

## Tests

`CacheDatabase.forTesting()` is an in-memory database on the current isolate (no file, no isolate). Put the
tests in the owning package's `test/`, following `modules/cache/data/test/` (`cache_database_test.dart`: DAO
round-trips, migration wiring, real-file WAL / foreign keys; `database_handle_test.dart`). Test pragmas on a real
file: an in-memory database reports `journal_mode = memory`.

**Test an upgrade.** Write the **old** schema by hand — never derive it from the current table class, which
already has the new column — stamp `PRAGMA user_version = 1`, and reopen with the step. `NativeDatabase`'s `setup`
runs on the raw SQLite connection before Drift reads `user_version`, so Drift sees a version-1 file and runs the step:

```dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
// plus data_cache's barrel for CacheDatabase and your step

test('v1 -> v2 adds expires_at and keeps the rows', () async {
  final dir = await Directory.systemTemp.createTemp('cache_upgrade');
  addTearDown(() => dir.delete(recursive: true));

  final database = CacheDatabase.forTesting(
    NativeDatabase(
      File('${dir.path}/cache.sqlite'),
      setup: (raw) {
        raw.execute(
          'CREATE TABLE cache_entries '
          '(key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL, updated_at INTEGER NOT NULL)',
        );
        raw.execute("INSERT INTO cache_entries VALUES ('k', 'v', 0)");
        raw.execute('PRAGMA user_version = 1');
      },
    ),
    [AddExpiresAtToCacheEntries()],
  );
  addTearDown(database.close);

  final columns = await database.customSelect('PRAGMA table_info(cache_entries)').get();
  expect(columns.map((row) => row.data['name']), contains('expires_at'));
  expect(await database.cacheEntriesDao.getValue('k'), 'v');
});
```

## Checklist

- [ ] Tables, DAO, database class and data source all live in the **owning package**
- [ ] DAO is `part of` **your** database library
- [ ] The file name is a constant in the package's `utils/`, named after the package
- [ ] `migration` delegates to `driftMigrationStrategy`; migrations are passed into the database
- [ ] The open is `@Order(1) @preResolve @lazySingleton` and collects with `getAllOrEmpty<IDatabaseMigration<YourDatabase>>()`
- [ ] Data sources take `IDatabaseHandle<TDb>` and return a **Model** (`fromRow`), never a Drift row
- [ ] Schema change = column + `schemaVersion` bump + `@LazySingleton(as: IDatabaseMigration<YourDatabase>)` step + an upgrade test
- [ ] `downgrade` implemented, or throws a descriptive error when irreversible

## Related

- [`docs/en/guides/07_database.md`](../../../docs/en/guides/07_database.md) — corruption recovery, `PRAGMA`s, runner internals
- [`implement_package_storage`](../implement_package_storage/SKILL.md) — key-value persistence instead of tables
- [`implement_dependency_injection`](../implement_dependency_injection/SKILL.md) — `@preResolve`, module order, `getAll` vs `getAllOrEmpty`

## Verify

```bash
dart run build_runner build --workspace                  # <name>_database.g.dart, the DAO mixin, module.module.dart
flutter analyze                                          # 0 issues (RULE-70)
dart tools/arch_check/check.dart
dart tools/composer/composer.dart verify
cd modules/<module>/data && flutter test
cd apps/mobile && flutter test test/di_smoke_test.dart   # the @preResolve open succeeds in the real graph
cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev   # RULE-77
```
