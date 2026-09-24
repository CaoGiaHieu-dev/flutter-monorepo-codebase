# Guide: Relational Database (Drift + SQLite)

**What this answers:** how to store relational data — rows, relations, queries, migrations — and how to do it so that deleting your package deletes its database with it, without breaking anyone else.

**After reading you can:** give a package its own database from scratch, contribute a schema migration without editing another package's file, and explain why there is no single `AppDatabase` in this project.

---

## 1. The rule: `core_database` owns no database

`core_database` provides the **mechanism** only. It declares no database, no table and no DAO — its DI module registers literally nothing:

```dart
// platform/database/lib/di/module.dart
/// `core_database` registers nothing on its own.
///
/// It provides the persistence MECHANISM — [DriftDatabaseOpener],
/// [driftMigrationStrategy], [IDatabaseMigration], [IDatabaseHandle] — and
/// deliberately owns no database, no table and no DAO. Registering a database
/// here would mean this package had to name the tables of whichever package
/// owns them.
@InjectableInit.microPackage()
void initMicroPackage() {}
```

**Each package that owns persisted data declares its own database**, next to its own tables, DAO and data source. The `cache` sample module's `CacheDatabase` (package `data_cache`, in `modules/cache/data`) is the reference wiring.

### Why — this is forced by Drift, not a preference

Two Drift facts drive the whole design:

1. `@DriftDatabase(tables: [...])` is resolved at **compile time**. There is no runtime table registration.
2. A DAO must be a **`part of`** its database library — Drift generates `_$XDaoMixin` and `$XTable` into that same library.

Put together: whichever package declares the database must name every table on it, and every DAO must live in that same library. A single shared `AppDatabase` would therefore force one package to know the tables of all the others — the same "one object knows everything" coupling the storage and constants ownership rules exist to prevent.

> [!NOTE]
> Moving a shared `AppDatabase` up into `apps/mobile/` does not solve this — it only relocates the god object, and the owning package still could not hold a usable DAO. Giving each package its own database is what actually removes the coupling.

### What you gain, and what you pay

| | |
|---|---|
| **Gain** | Deleting a package deletes its database with it. No other package references it, so nothing else breaks. |
| **Gain** | No package can reach another's rows — there is no shared object to reach through. |
| **Cost** | **SQL cannot join across package boundaries.** |

That cost is deliberate. Crossing a bounded context belongs at the repository layer — compose two repositories in a use case — not inside a single query.

---

## 2. What `core_database` actually gives you

| Export | Kind | What it does |
|---|---|---|
| `DriftDatabaseOpener` | `abstract final class` | Opens any `GeneratedDatabase` on a background isolate, **verifies** the connection, quarantines a corrupt file |
| `DatabaseConnectionFactory` | `abstract final class` | Resolves the file path in app documents, builds the background executor, quarantines files |
| `IDatabaseMigration` | abstract class | Contract a package implements to contribute **one** schema step |
| `DatabaseMigrationRunner` | class | Sorts, validates and replays those steps |
| `driftMigrationStrategy(...)` | function | The shared `MigrationStrategy`: migration dispatch + the per-connection `PRAGMA`s |
| `IDatabaseHandle<TDb>` / `DatabaseHandle<TDb>` | abstract class / class | How a data source reaches its database without holding every DAO |
| `DatabaseConstants` | class | Read-pool size, busy timeout, corruption/environment error markers, `.corrupt` suffix |

Notice every one of these is generic over `GeneratedDatabase`. `core_database` never names a concrete database class — that is the whole point.

---

## 3. How to: give your package its own database

Worked end-to-end from the real `data_cache` wiring. Substitute your package name throughout.

### Step 1 — Define the table

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

### Step 2 — Define the DAO as a `part of` your database

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

### Step 3 — Name the file in your own `utils/`

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

### Step 4 — Declare the database class

```dart
// modules/cache/data/lib/src/database/cache_database.dart
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

Two things to copy exactly:

- **Migrations are passed in, never looked up inside the class.** That keeps the database free of service-locator calls and directly constructible in tests.
- **`migration` delegates to `driftMigrationStrategy`.** Writing your own `MigrationStrategy` means re-deriving the `PRAGMA` settings — and a package that forgets `foreign_keys = ON` silently loses referential integrity.

### Step 5 — Register it in your DI module

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
> - **A step in the owning package** (here `data_cache`) is collected **as long as the open keeps `@Order(1)`**. Injectable registers a package's entries in ascending `@Order`, and a migration annotated `@LazySingleton(as: IDatabaseMigration<CacheDatabase>)` has the default order 0 — so it lands before the open. Remove `@Order(1)` and the open may be registered first; that is the bug `@Order(1)` was added to fix.
> - **A step from another package** must sit in an **earlier DI group** than the owning package in the app's `app_manifest.yaml`. `@Order` sorts only within one package's module; it cannot move a registration across modules. Nothing in the template does this yet, but it will bite the first feature that adds a migration for someone else's database.
>
> **Copying this pattern for your own database? Put `@Order(1)` on your `@preResolve` open as well** — without it, a step written exactly as §4 shows is never collected. See [`05_di.md`](05_di.md) for module ordering.

### Step 6 — Consume it through `IDatabaseHandle`, not the database

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

### Step 7 — Return a Model, never a Drift row

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

### Step 8 — Run codegen and barrels

```bash
dart run build_runner build --workspace
dart tools/barrel_generator/generate.dart modules/cache/data/lib
```

---

## 4. Decentralised migrations

You never edit another package's database file to change your schema. You implement one contract and register it.

```dart
// platform/database/lib/src/migration/i_database_migration.dart
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

Registered like a route module, typed to the database it belongs to — GetIt keys a registration by its exact type, so `CacheDatabase` collects only `IDatabaseMigration<CacheDatabase>` and another package's steps never reach it. Declared in the owning package, it is collected because the open carries `@Order(1)` ([Step 5](#step-5--register-it-in-your-di-module)):

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

### The contract

- **`version` is the version this step *produces*.** `version == 2` means "take a database at version 1 and make it version 2". So `upgrade` must run against `version - 1`, and `downgrade` must return it to that same shape.
- **Version 1 is not migratable** — it is what `Migrator.createAll()` creates. The runner rejects `version < 2` at construction.
- **Duplicate versions are rejected**, not silently resolved to one of them.

### How the runner replays

```dart
// platform/database/lib/src/migration/database_migration_runner.dart
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

  // A downgrade from a schema this build has no step for is refused.
  final newestKnown = _migrations.isEmpty ? null : _migrations.last.version;
  if (newestKnown == null || newestKnown < from) {
    throw UnsupportedError('Cannot downgrade the schema from version $from …');
  }

  for (final migration in _migrations.reversed) {
    if (migration.version > to && migration.version <= from) {
      await migration.downgrade(m);
    }
  }
}
```

Three properties worth naming:

1. **A plain `if`, not `else if`.** A device that skipped several releases replays *every* intermediate step instead of jumping straight to the newest shape.
2. **Upgrades ascend, downgrades descend.** Order matters in both directions.
3. **Gaps are legal.** A release may ship no schema change, leaving that version number unused.
4. **A downgrade needs explicit steps.** Going from `from` down to `to` throws `UnsupportedError` unless a step is registered for `from` or above — the runner must know the schema it is leaving. Without that check it did nothing, and drift stamped the lower `user_version` over tables that still had the newer shape; reinstalling the newer build then replayed its upgrades against them (a duplicate column) and failed on every launch. The throw leaves the file and its version untouched, and `DriftDatabaseOpener` surfaces it as a startup error rather than quarantining the file. In practice an older build only has such steps if they shipped ahead of the change they reverse — otherwise installing an older build over a newer schema is unsupported.

Validation happens once, at construction — not mid-migration. Discovering a wiring mistake halfway through would leave the schema partially migrated.

> [!WARNING]
> **Drift 2.x has no `onDowngrade`** (the lockfile resolves 2.35.0). `MigrationStrategy` exposes only `onCreate`, `onUpgrade` and `beforeOpen`; Drift's own documentation notes that "schema version upgrades and downgrades will both be run here". `IDatabaseMigration.downgrade` is real and tested, but it rides on that single entry point via a `from`/`to` comparison. Implement it when the change is reversible; **throw a descriptive error when it is not**, so the failure is explicit instead of leaving a schema that no longer matches the running code.

---

## 5. The `PRAGMA` settings, and why they are centralised

`PRAGMA` settings are **per-connection and are not stored in the file**, so they must be reapplied on every open. That is why they live in `beforeOpen`:

```dart
// platform/database/lib/src/migration/drift_migration_strategy.dart
beforeOpen: (OpeningDetails details) async {
  // SQLite ships with foreign key enforcement OFF. Without this any
  // `references()` declared on a table is silently ignored, so broken
  // relations are only discovered as corrupt data much later.
  await database.customStatement('PRAGMA foreign_keys = ON');

  // Write-Ahead Logging lets readers run concurrently with a writer,
  // which a read pool (readPool > 0) requires, and avoids "database is locked"
  // under contention.
  await database.customStatement('PRAGMA journal_mode = WAL');

  // Wait for a held lock instead of failing instantly with SQLITE_BUSY.
  await database.customStatement('PRAGMA busy_timeout = $busyTimeoutMs');
},
```

| Pragma | Why it matters |
|---|---|
| `foreign_keys = ON` | **SQLite defaults this OFF.** Every `references()` you declare is silently ignored without it — a silent trap that surfaces much later as corrupt relations. |
| `journal_mode = WAL` | Readers run concurrently with a writer. Required by any read pool (`readPool > 0`; the default is `1`); avoids "database is locked" under contention. |
| `busy_timeout = 5000` | Waits for a held lock instead of failing instantly with `SQLITE_BUSY`. Default is `0`. |

`beforeOpen` runs on the **writer** connection only. The read pool — one more connection per reader, each on its own isolate — never sees it, so `DatabaseConnectionFactory` also passes drift a `setup` callback that applies `busy_timeout` to every connection it opens (`platform/database/test/database_connection_factory_test.dart` reads it back through a reader). `journal_mode` needs no such help: WAL is stored in the file. `foreign_keys` is only enforced on writes, which never reach a reader.

WAL adds `-wal` and `-shm` sidecar files next to the database. SQLite converts an existing file automatically and reversibly. In-memory databases (tests) ignore this and stay in `memory` journal mode — which is exactly why the WAL test in `data_cache` runs against a **real file**.

This is centralised for one reason: a package that wrote its own `MigrationStrategy` and forgot `foreign_keys = ON` would lose referential integrity without any error.

---

## 6. Corruption recovery: quarantine, never delete

Opening is registered with `@preResolve`, so anything thrown there aborts `configureDependencies()` and the app cannot start. A damaged file would mean a permanent crash loop.

`DriftDatabaseOpener.open` handles this — and the design leans hard towards *not* touching user data:

```dart
// platform/database/lib/src/opening/drift_database_opener.dart
static Future<T> open<T extends GeneratedDatabase>(
  DriftDatabaseBuilder<T> build, {
  required String fileName,
  int readPool = DatabaseConstants.DEFAULT_READ_POOL,
}) async {
  try {
    return await _openVerified(build, fileName: fileName, readPool: readPool);
  } catch (error, stackTrace) {
    if (!isCorruptionError(error)) rethrow;
    // ... quarantine, then reopen empty
  }
}
```

Three deliberate decisions:

**The connection is verified, not assumed.** `createBackgroundExecutor` is lazy — it does not touch the file until the first statement. `_openVerified` runs a `SELECT 1` probe so a broken database fails *here* rather than at some unrelated call site later.

**The file is renamed, never deleted.**

```dart
// platform/database/lib/src/connection/database_connection_factory.dart
/// The file is **renamed, never deleted** — if the corruption check ever
/// misfires the user's bytes are still recoverable from
/// `<fileName><CORRUPT_FILE_SUFFIX>`. Only one quarantined copy is kept;
/// an older one is replaced so repeated failures cannot fill the disk.
```

The `-wal` / `-shm` sidecars move with it, to `<fileName>.corrupt-wal` / `.corrupt-shm`: they belong to the quarantined database and must not be applied to the new one, and the WAL holds committed transactions not yet checkpointed — deleting it would lose the newest data.

**An environment marker vetoes a corruption match.**

```dart
@visibleForTesting
static bool isCorruptionError(Object error) {
  final message = error.toString().toLowerCase();

  final looksLikeEnvironment = DatabaseConstants.ENVIRONMENT_ERROR_MARKERS
      .any(message.contains);
  if (looksLikeEnvironment) return false;

  return DatabaseConstants.CORRUPTION_ERROR_MARKERS.any(message.contains);
}
```

| Treated as corruption → quarantine | Treated as environment → rethrow untouched |
|---|---|
| `database disk image is malformed` | `unable to open database file` |
| `file is not a database` | `disk i/o error` |
| `file is encrypted or is not a database` | `database or disk is full` |
| `malformed database schema` | `attempt to write a readonly database` |
| | `access denied` / `permission denied` / `operation not permitted` |

The predicate matches on message strings rather than a typed `SqliteException`. `sqlite3` *is* a declared dependency of `core_database` (the connection factory imports it), so the type is available — but it is not what reaches the opener. The connection runs on a background isolate (`NativeDatabase.createInBackground`), and drift hands an error raised there back as a `DriftRemoteException` whose `remoteCause` holds the original; `on SqliteException` would never match it. `DriftRemoteException.toString()` returns the cause's message, so matching the message covers an error from either side of the isolate boundary. A typed check is possible — unwrap `remoteCause` and test for `SqliteException` and its `extendedResultCode` — but it would still need the message fallback for anything else. Because string matching is fragile, the predicate is **biased towards not recovering**: if an environment marker appears, the database is left alone even when a corruption marker also matched.

Losing user data is worse than surfacing a startup error.

---

## 7. `core_storage` or `core_database`?

| You need | Use | Why |
|---|---|---|
| A token, a flag, a theme mode, a locale | [`core_storage`](06_storage.md) | One value per key; encrypted; reactive via `ChangeNotifier` / `Stream` |
| A list of rows you query, filter or sort | `core_database` | SQL, indexes, ordering |
| Relations between records | `core_database` | Foreign keys (remember: enabled by the `PRAGMA` above) |
| Data whose shape will change over releases | `core_database` | Versioned migrations |
| Something small, read on every frame | `core_storage` | In-memory cache; no async round-trip |

Rule of thumb: if you would reach for `WHERE`, `ORDER BY` or `JOIN`, you want a database.

---

## 8. Testing

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

## 9. The cache module is sample code

> [!NOTE]
> The chain — `CacheEntries` → `CacheEntriesDao` → `CacheEntryLocalDataSource` → `CacheEntryRepositoryImpl` → `ICacheEntryRepository` → `GetCacheEntryUseCase` / `SaveCacheEntryUseCase` — is the `cache` module (`modules/cache/domain` + `modules/cache/data`), wired end to end, but **no feature in this template consumes it**. It exists as a working reference for the shape above, and as the fixture the database tests run against.
>
> It is an ordinary removable module: `apps/mobile` composes it, `apps/admin` does not — so only mobile opens the SQLite file at boot. Copy the shape for real tables, or remove it with `dart tools/sample_cleanup/remove_sample.dart cache --apply` (without `--apply` it only previews). The database tests go with it; they exercise `core_database`'s `DatabaseHandle` and `driftMigrationStrategy` through this fixture, so give them another before deleting if you want to keep that coverage.

---

## 10. Checklist

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

## See also

- [`06_storage.md`](06_storage.md) — key-value storage, and when to prefer it
- [`02_new_domain_data.md`](02_new_domain_data.md) — the repository and model layers above the DAO
- [`05_di.md`](05_di.md) — `@preResolve`, module ordering, `getAll` vs `getAllOrEmpty`
- [`../architecture/02_core.md`](../architecture/02_core.md) — where `core_database` sits
- [`../reference/01_rules.md`](../reference/01_rules.md) — the ownership rules in full
