# 14. Local Database System (Drift + Isolate)

Relational local persistence lives in **`packages/core/database`** (`core_database`). It uses [Drift](https://drift.simonbinder.eu/) on SQLite and runs I/O on a **background isolate** via `NativeDatabase.createInBackground`.

> **When to use what**
> | Need | Package |
> | :--- | :--- |
> | Tokens, flags, theme, locale (key-value) | `core_storage` |
> | Lists, relations, SQL queries, migrations | `core_database` |

The template ships a **full working sample** for cache rows:

| Layer | File |
| :--- | :--- |
| Table + DAO | `core_database` → `CacheEntries`, `CacheEntriesDao` |
| Local DataSource | `data_core` → `CacheEntryLocalDataSource` |
| Repository | `data_core` → `CacheEntryRepositoryImpl` |
| Domain | `domain_core` → `ICacheEntryRepository`, UseCases |

---

## 🚀 Quick Start

DI is already wired. After `configureDependencies()` you can resolve UseCases immediately:

```dart
import 'package:domain_core/domain_core.dart';
import 'package:core_di/core_di.dart';

final save = getIt<SaveCacheEntryUseCase>();
final get = getIt<GetCacheEntryUseCase>();

await save(CacheEntryParams(key: 'draft_note', value: 'Hello Drift'));

final result = await get('draft_note');
result.when(
  success: (entry) => print(entry?.value), // Hello Drift
  failure: (error) => print(error.message),
);
```

No manual `AppDatabase.open()` in `main.dart` — `@preResolve` handles it.

---

## 🏗️ Architecture Overview

```text
┌─────────────────────────────────────────────────────────────┐
│  Feature (Provider / Cubit)                                 │
│  injects UseCase from domain_core                           │
└───────────────────────────┬─────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────┐
│  Domain — ICacheEntryRepository, CacheEntryEntity, UseCases   │
│  (Pure Dart — no Drift imports)                             │
└───────────────────────────┬─────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────┐
│  Data — CacheEntryRepositoryImpl                            │
│         CacheEntryLocalDataSource                           │
│  maps Drift rows → Domain entities                          │
└───────────────────────────┬─────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────┐
│  Core — AppDatabase (background isolate)                    │
│         CacheEntriesDao                                     │
└─────────────────────────────────────────────────────────────┘
```

---

## 📘 Usage Level 1 — DAO Only (Core / debugging)

Use only inside `core_database` or early prototyping. **Do not** import `AppDatabase` from Feature packages.

```dart
import 'package:core_database/core_database.dart';

// Resolved by DI after configureDependencies()
final db = getIt<AppDatabase>();

await db.cacheEntriesDao.upsert('settings_json', '{"fontScale":1.2}');

final raw = await db.cacheEntriesDao.getValue('settings_json');
final row = await db.cacheEntriesDao.getEntry('settings_json');

await db.cacheEntriesDao.deleteByKey('settings_json');
await db.cacheEntriesDao.clearAll();
```

All calls are `async` and execute on the background isolate automatically.

---

## 📘 Usage Level 2 — Local DataSource (Data layer)

Wrap DAOs behind an interface so Repository code stays testable:

```dart
// packages/data/core/lib/src/data_sources/local/cache_entry_local_data_source.dart

@LazySingleton(as: ICacheEntryLocalDataSource)
class CacheEntryLocalDataSource implements ICacheEntryLocalDataSource {
  CacheEntryLocalDataSource(this._database);
  final AppDatabase _database;

  @override
  Future<void> save(String key, String value) {
    return _database.cacheEntriesDao.upsert(key, value);
  }

  @override
  Future<CacheEntry?> getEntry(String key) {
    return _database.cacheEntriesDao.getEntry(key);
  }
}
```

`CacheEntry` is a Drift-generated type — keep it inside the Data layer.

---

## 📘 Usage Level 3 — Full Clean Architecture (Recommended)

### Step A — Domain entity & contract

```dart
// domain_core — cache_entry_entity.dart
@freezed
abstract class CacheEntryEntity with _$CacheEntryEntity {
  const factory CacheEntryEntity({
    required String key,
    required String value,
    required DateTime updatedAt,
  }) = _CacheEntryEntity;
}

// domain_core — i_cache_entry_repository.dart
abstract class ICacheEntryRepository {
  Future<Result<CacheEntryEntity?>> getByKey(String key);
  Future<Result<void>> save(CacheEntryParams params);
  Future<Result<List<CacheEntryEntity>>> getAll();
}
```

### Step B — Repository implementation

```dart
// data_core — cache_entry_repository_impl.dart
@LazySingleton(as: ICacheEntryRepository)
class CacheEntryRepositoryImpl extends IBaseRepository
    implements ICacheEntryRepository {
  CacheEntryRepositoryImpl(this._local);
  final ICacheEntryLocalDataSource _local;

  @override
  Future<Result<CacheEntryEntity?>> getByKey(String key) {
    return execute<CacheEntry?, CacheEntryEntity?>(
      () => _local.getEntry(key),
      mapper: (row) => row == null
          ? null
          : CacheEntryEntity(
              key: row.key,
              value: row.value,
              updatedAt: row.updatedAt,
            ),
    );
  }

  @override
  Future<Result<void>> save(CacheEntryParams params) {
    return execute(() => _local.save(params.key, params.value));
  }
}
```

### Step C — UseCase

```dart
@injectable
class SaveCacheEntryUseCase extends BaseUseCase<void, CacheEntryParams> {
  SaveCacheEntryUseCase(this._repository);
  final ICacheEntryRepository _repository;

  @override
  Future<Result<void>> call(CacheEntryParams params) {
    return _repository.save(params);
  }
}
```

### Step D — Feature Provider (UI layer)

Place this in your **feature package** (e.g. `feature_home`), not in `data_core`:

```dart
import 'package:core_di/core_di.dart';
import 'package:domain_core/domain_core.dart';
import 'package:provider_state_management/provider_state_management.dart';

@injectable
class CacheDemoProvider extends BaseProvider {
  CacheDemoProvider(this._save, this._getAll);

  final SaveCacheEntryUseCase _save;
  final GetAllCacheEntriesUseCase _getAll;

  List<CacheEntryEntity> entries = [];

  Future<void> saveDraft(String text) async {
    await executeOperation(
      OperationConfig(
        operation: () => _save(
          CacheEntryParams(key: 'draft_note', value: text),
        ),
        onSuccess: (_) => refresh(),
      ),
    );
  }

  Future<void> refresh() async {
    await executeOperation(
      OperationConfig(
        operation: () => _getAll(const NoParams()),
        onSuccess: (data) => entries = data ?? [],
      ),
    );
  }
}
```

Bind at route level:

```dart
ChangeNotifierProvider(
  create: (_) => getIt<CacheDemoProvider>(),
  child: const CacheDemoPage(),
);
```

---

## 🛠️ Adding a New Table (Walkthrough)

Example: add a `Bookmarks` table for saved articles.

### 1. Create the table

```dart
// packages/core/database/lib/src/database/tables/bookmarks_table.dart
import 'package:drift/drift.dart';

class Bookmarks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  TextColumn get url => text()();
  DateTimeColumn get savedAt =>
      dateTime().withDefault(currentDateAndTime)();
}
```

### 2. Create the DAO (`part of '../app_database.dart'`)

```dart
part of '../app_database.dart';

@DriftAccessor(tables: [Bookmarks])
class BookmarksDao extends DatabaseAccessor<AppDatabase>
    with _$BookmarksDaoMixin {
  BookmarksDao(super.attachedDatabase);

  Future<int> insertBookmark(String title, String url) {
    return into(bookmarks).insert(
      BookmarksCompanion.insert(title: title, url: url),
    );
  }

  Stream<List<Bookmark>> watchAll() {
    return (select(bookmarks)
          ..orderBy([(t) => OrderingTerm.desc(t.savedAt)]))
        .watch();
  }
}
```

### 3. Register in `app_database.dart`

```dart
import 'tables/bookmarks_table.dart';

part 'dao/bookmarks_dao.dart';

@DriftDatabase(
  tables: [CacheEntries, Bookmarks],
  daos: [CacheEntriesDao, BookmarksDao],
)
class AppDatabase extends _$AppDatabase { ... }
```

### 4. Bump schema & add migration

```dart
@override
int get schemaVersion => 2;

@override
MigrationStrategy get migration => MigrationStrategy(
  onCreate: (m) => m.createAll(),
  onUpgrade: (m, from, to) async {
    if (from < 2) {
      await m.createTable(bookmarks);
    }
  },
);
```

### 5. Generate code & wire Data/Domain

```bash
fvm dart run build_runner build -d --workspace
```

Then add Local DataSource → Repository → UseCase following the cache sample.

---

## ⚙️ Background Isolate Details

```dart
// database_connection_factory.dart
static Future<QueryExecutor> createBackgroundExecutor({...}) async {
  final file = await resolveDatabaseFile(fileName: fileName);
  return NativeDatabase.createInBackground(file, readPool: readPool);
}
```

- **`readPool`**: optional extra read isolates for heavy read workloads (default `1`).
- **`AppDatabase.forTesting()`**: in-memory DB on the current isolate for unit tests.

---

## 🧪 Testing

### DAO test (core_database)

```dart
late AppDatabase database;

setUp(() => database = AppDatabase.forTesting());
tearDown(() => database.close());

test('upsert round-trip', () async {
  await database.cacheEntriesDao.upsert('k', 'v');
  expect(await database.cacheEntriesDao.getValue('k'), 'v');
});
```

### Repository test (mock Local DataSource)

```dart
class MockCacheLocal implements ICacheEntryLocalDataSource {
  final Map<String, String> store = {};
  @override
  Future<void> save(String key, String value) async => store[key] = value;
  @override
  Future<CacheEntry?> getEntry(String key) async => null; // return mock row
  // ...
}
```

Run:

```bash
fvm flutter test packages/core/database
```

---

## 📦 Dependencies

Managed in `pubspec_dependencies.yaml`:

| Package | Purpose |
| :--- | :--- |
| `drift` | ORM / query builder |
| `drift_dev` | Code generation (dev) |
| `sqlite3_flutter_libs` | SQLite on Android/iOS |
| `path_provider` | App documents directory |
| `path` | Path joining |

---

## 🔗 Related Docs

- [11. Storage System](./11_storage_system.md) — key-value secure storage
- [03. Data Layer](./03_data_layer.md) — Local DataSource conventions
- [05. Dependency Injection](./05_dependency_injection.md) — `@preResolve` lifecycle

---
*Copyright (c) 2026 CaoGiaHieu-dev. All rights reserved.*
