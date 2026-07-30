# 14. Hệ Thống Database Cục Bộ (Drift + Isolate)

Lưu trữ quan hệ nằm trong **`packages/core/database`** (`core_database`). Dùng [Drift](https://drift.simonbinder.eu/) trên SQLite và chạy I/O trên **background isolate** qua `NativeDatabase.createInBackground`.

> **Khi nào dùng gì**
> | Nhu cầu | Package |
> | :--- | :--- |
> | Token, cờ, theme, locale (key-value) | `core_storage` |
> | Danh sách, quan hệ, SQL, migration | `core_database` |

Template có **sample hoàn chỉnh** cho cache rows:

| Layer | File |
| :--- | :--- |
| Table + DAO | `core_database` → `CacheEntries`, `CacheEntriesDao` |
| Local DataSource | `data_core` → `CacheEntryLocalDataSource` |
| Repository | `data_core` → `CacheEntryRepositoryImpl` |
| Domain | `domain_core` → `ICacheEntryRepository`, UseCases |

---

## 🚀 Bắt Đầu Nhanh

DI đã được cấu hình. Sau `configureDependencies()` có thể resolve UseCase ngay:

```dart
import 'package:domain_core/domain_core.dart';
import 'package:core_di/core_di.dart';

final save = getIt<SaveCacheEntryUseCase>();
final get = getIt<GetCacheEntryUseCase>();

await save(CacheEntryParams(key: 'draft_note', value: 'Xin chào Drift'));

final result = await get('draft_note');
result.when(
  success: (entry) => print(entry?.value), // Xin chào Drift
  failure: (error) => print(error.message),
);
```

Không cần gọi `AppDatabase.open()` trong `main.dart` — `@preResolve` lo việc này.

---

## 🏗️ Tổng Quan Kiến Trúc

```text
┌─────────────────────────────────────────────────────────────┐
│  Feature (Provider / Cubit)                                 │
│  inject UseCase từ domain_core                              │
└───────────────────────────┬─────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────┐
│  Domain — ICacheEntryRepository, CacheEntryEntity, UseCases │
│  (Pure Dart — không import Drift)                           │
└───────────────────────────┬─────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────┐
│  Data — CacheEntryRepositoryImpl                            │
│         CacheEntryLocalDataSource                           │
│  map Drift row → Domain entity                              │
└───────────────────────────┬─────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────┐
│  Core — AppDatabase (background isolate)                    │
│         CacheEntriesDao                                     │
└─────────────────────────────────────────────────────────────┘
```

---

## 📘 Cấp 1 — Chỉ Dùng DAO (Core / debug)

Chỉ dùng trong `core_database` hoặc prototype. **Không** import `AppDatabase` từ Feature.

```dart
import 'package:core_database/core_database.dart';

final db = getIt<AppDatabase>();

await db.cacheEntriesDao.upsert('settings_json', '{"fontScale":1.2}');

final raw = await db.cacheEntriesDao.getValue('settings_json');
final row = await db.cacheEntriesDao.getEntry('settings_json');

await db.cacheEntriesDao.deleteByKey('settings_json');
await db.cacheEntriesDao.clearAll();
```

Mọi lệnh đều `async` và chạy trên background isolate.

---

## 📘 Cấp 2 — Local DataSource (Data layer)

Bọc DAO sau interface để Repository dễ test:

```dart
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

`CacheEntry` là kiểu Drift sinh ra — giữ trong Data layer.

---

## 📘 Cấp 3 — Clean Architecture Đầy Đủ (Khuyến nghị)

### Bước A — Entity & contract (Domain)

```dart
@freezed
abstract class CacheEntryEntity with _$CacheEntryEntity {
  const factory CacheEntryEntity({
    required String key,
    required String value,
    required DateTime updatedAt,
  }) = _CacheEntryEntity;
}

abstract class ICacheEntryRepository {
  Future<Result<CacheEntryEntity?>> getByKey(String key);
  Future<Result<void>> save(CacheEntryParams params);
  Future<Result<List<CacheEntryEntity>>> getAll();
}
```

### Bước B — Repository implementation (Data)

```dart
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
}
```

### Bước C — UseCase

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

### Bước D — Feature Provider (UI layer)

Đặt trong **feature package** (vd. `feature_home`), không đặt trong `data_core`:

```dart
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

Gắn tại route:

```dart
ChangeNotifierProvider(
  create: (_) => getIt<CacheDemoProvider>(),
  child: const CacheDemoPage(),
);
```

---

## 🛠️ Thêm Bảng Mới (Hướng Dẫn Từng Bước)

Ví dụ: bảng `Bookmarks` lưu bài viết.

### 1. Tạo table

```dart
class Bookmarks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  TextColumn get url => text()();
  DateTimeColumn get savedAt =>
      dateTime().withDefault(currentDateAndTime)();
}
```

### 2. Tạo DAO (`part of '../app_database.dart'`)

```dart
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

### 3. Đăng ký trong `app_database.dart` + tăng `schemaVersion`

```dart
@DriftDatabase(
  tables: [CacheEntries, Bookmarks],
  daos: [CacheEntriesDao, BookmarksDao],
)
```

```dart
@override
int get schemaVersion => 2;

@override
MigrationStrategy get migration => MigrationStrategy(
  onCreate: (m) => m.createAll(),
  onUpgrade: (m, from, to) async {
    if (from < 2) await m.createTable(bookmarks);
  },
);
```

### 4. Generate & nối Data/Domain

```bash
fvm dart run build_runner build -d --workspace
```

Sau đó thêm Local DataSource → Repository → UseCase theo mẫu cache.

---

## ⚙️ Chi Tiết Background Isolate

```dart
return NativeDatabase.createInBackground(file, readPool: readPool);
```

- **`readPool`**: isolate đọc thêm cho workload nặng (mặc định `1`).
- **`AppDatabase.forTesting()`**: DB in-memory trên isolate hiện tại cho unit test.

---

## 🧪 Kiểm Thử

```dart
setUp(() => database = AppDatabase.forTesting());
tearDown(() => database.close());

test('upsert round-trip', () async {
  await database.cacheEntriesDao.upsert('k', 'v');
  expect(await database.cacheEntriesDao.getValue('k'), 'v');
});
```

```bash
fvm flutter test packages/core/database
```

---

## 📦 Dependencies

Quản lý tại `pubspec_dependencies.yaml`: `drift`, `drift_dev`, `path_provider`, `path`.

---

## 🔗 Tài Liệu Liên Quan

- [11. Hệ Thống Storage](./11_storage_system.md)
- [03. Data Layer](./03_data_layer.md)
- [05. Dependency Injection](./05_dependency_injection.md)

---
*Copyright (c) 2026 CaoGiaHieu-dev. All rights reserved.*
