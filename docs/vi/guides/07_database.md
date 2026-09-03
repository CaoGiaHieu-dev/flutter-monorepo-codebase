# Hướng dẫn: Cơ sở dữ liệu quan hệ (Drift + SQLite)

**File này trả lời:** làm sao lưu dữ liệu quan hệ — bản ghi, quan hệ, truy vấn, migration — và làm sao để xoá package của bạn là xoá luôn database của nó, mà không làm vỡ package nào khác.

**Đọc xong bạn làm được:** tạo database riêng cho một package từ đầu, đóng góp một bước migration mà không phải sửa file của package khác, và giải thích được vì sao dự án này không có một `AppDatabase` dùng chung.

---

## 1. Luật: `core_database` không sở hữu database nào

`core_database` chỉ cấp **cơ chế**. Nó không khai database, không khai bảng, không khai DAO — module DI của nó đăng ký đúng nghĩa là rỗng:

```dart
// packages/core/database/lib/di/module.dart
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

**Mỗi package sở hữu dữ liệu lưu trữ sẽ tự khai database của riêng nó**, đặt cạnh bảng, DAO và data source của chính nó. `CacheDatabase` trong `data_core` là bản wiring tham chiếu.

### Vì sao — đây là ràng buộc của Drift, không phải sở thích

Hai sự thật về Drift quyết định toàn bộ thiết kế:

1. `@DriftDatabase(tables: [...])` được phân giải ở **compile time**. Không có đăng ký bảng lúc runtime.
2. DAO buộc phải là **`part of`** thư viện database của nó — Drift sinh `_$XDaoMixin` và `$XTable` vào đúng thư viện đó.

Ghép lại: package nào khai database thì package đó buộc phải gọi tên mọi bảng trên database ấy, và mọi DAO phải nằm cùng thư viện. Một `AppDatabase` dùng chung vì thế sẽ buộc một package phải biết bảng của tất cả package còn lại — đúng kiểu "một object biết mọi thứ" mà các luật sở hữu về storage và constants sinh ra để ngăn chặn.

> [!NOTE]
> Dời `AppDatabase` dùng chung lên `app/` cũng **không** giải quyết được — nó chỉ di chuyển god object, và package sở hữu dữ liệu vẫn không thể giữ một DAO dùng được. Cho mỗi package một database riêng mới thực sự cắt được sự phụ thuộc này.

### Được gì, trả giá gì

| | |
|---|---|
| **Được** | Xoá package là xoá luôn database của nó. Không package nào tham chiếu tới, nên không gì khác vỡ. |
| **Được** | Không package nào chạm được bản ghi của package khác — không có object dùng chung để mà chạm. |
| **Trả giá** | **SQL không JOIN xuyên ranh giới package.** |

Cái giá đó là có chủ đích. Vượt bounded context là việc của tầng repository — ghép hai repository trong một use case — chứ không phải nhét vào một truy vấn.

---

## 2. `core_database` thực sự cho bạn những gì

| Export | Loại | Làm gì |
|---|---|---|
| `DriftDatabaseOpener` | `abstract final class` | Mở bất kỳ `GeneratedDatabase` nào trên isolate nền, **verify** kết nối, cách ly file hỏng |
| `DatabaseConnectionFactory` | `abstract final class` | Phân giải đường dẫn file trong app documents, dựng executor nền, cách ly file |
| `IDatabaseMigration` | abstract class | Hợp đồng để một package đóng góp **một** bước schema |
| `DatabaseMigrationRunner` | class | Sắp xếp, kiểm tra và replay các bước đó |
| `driftMigrationStrategy(...)` | function | `MigrationStrategy` dùng chung: dispatch migration + các `PRAGMA` theo kết nối |
| `IDatabaseHandle<TDb>` / `DatabaseHandle<TDb>` | abstract class / class | Cách một data source chạm tới database mà không cầm toàn bộ DAO |
| `DatabaseConstants` | class | Kích thước read pool, busy timeout, marker lỗi hỏng/môi trường, hậu tố `.corrupt` |

Để ý: mọi thứ ở trên đều generic theo `GeneratedDatabase`. `core_database` không bao giờ gọi tên một class database cụ thể — đó chính là điểm mấu chốt.

---

## 3. Cách làm: tạo database riêng cho package của bạn

Làm trọn vẹn theo đúng wiring thật của `data_core`. Thay tên package của bạn vào.

### Bước 1 — Định nghĩa bảng

Class kế thừa `Table` là độc lập: nó không tham chiếu database nào, nên nằm ở package của bạn được.

```dart
// packages/data/core/lib/src/database/tables/cache_entries_table.dart
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

### Bước 2 — Định nghĩa DAO dưới dạng `part of` database

```dart
// packages/data/core/lib/src/database/dao/cache_entries_dao.dart
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

  /// Clears the entire cache table.
  Future<int> clearAll() => delete(cacheEntries).go();
}
```

Dòng `part of` là bắt buộc — đó là yêu cầu của Drift, và là lý do DAO không thể nằm ở package khác.

### Bước 3 — Đặt tên file trong `utils/` của chính package

Theo luật chung của repo, constants nằm ở `utils/` của package sở hữu:

```dart
// packages/data/core/lib/src/utils/data_core_constants.dart
class DataCoreConstants {
  DataCoreConstants._();

  /// On-disk SQLite file for this package's [CacheDatabase], resolved inside
  /// the app documents directory.
  ///
  /// Named after its owner rather than the app, because each package that
  /// persists data opens its own file. Changing this value points the package
  /// at a different database and makes existing on-device rows unreachable.
  static const String CACHE_DATABASE_FILE_NAME = 'data_core_cache.sqlite';
}
```

> [!CAUTION]
> Đặt tên file theo **package sở hữu**, không theo tên app. Nhiều database cùng tồn tại trong thư mục documents; một cái tên chung chung kiểu `app_database.sqlite` sẽ đụng nhau. Đổi chuỗi này sau khi đã phát hành sẽ khiến dữ liệu cũ trên máy người dùng không còn truy cập được.

### Bước 4 — Khai class database

```dart
// packages/data/core/lib/src/database/cache_database.dart
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
    String fileName = DataCoreConstants.CACHE_DATABASE_FILE_NAME,
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

Hai điểm cần copy nguyên xi:

- **Migration được truyền vào, không bao giờ tra cứu bên trong class.** Nhờ vậy database không dính service-locator và dựng trực tiếp được trong test.
- **`migration` uỷ quyền cho `driftMigrationStrategy`.** Tự viết `MigrationStrategy` riêng nghĩa là phải tự suy ra lại các `PRAGMA` — và một package quên `foreign_keys = ON` sẽ âm thầm mất toàn vẹn tham chiếu.

### Bước 5 — Đăng ký trong module DI của bạn

```dart
// packages/data/core/lib/di/module.dart
@module
abstract class DataCoreDiModule {
  @preResolve
  @lazySingleton
  Future<CacheDatabase> cacheDatabase() =>
      CacheDatabase.open(migrations: _registeredMigrations());

  /// Narrow accessor handle for this package's data sources.
  @lazySingleton
  IDatabaseHandle<CacheDatabase> cacheDatabaseHandle(CacheDatabase database) =>
      DatabaseHandle<CacheDatabase>(database);

  /// Reads contributed migrations without throwing when none are registered,
  /// matching the `getAllOrEmpty` behaviour the app shell uses for routes.
  static Iterable<IDatabaseMigration> _registeredMigrations() {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<IDatabaseMigration>()) {
      return const <IDatabaseMigration>[];
    }
    return getIt.getAll<IDatabaseMigration>();
  }
}
```

Cái guard `isRegistered` rất quan trọng: `getAll<T>()` **ném lỗi** khi chưa có gì đăng ký cho `T`. Không có guard này, một bản build không có migration nào sẽ crash ngay trong `configureDependencies()`.

> [!WARNING]
> **Thứ tự đăng ký.** `@preResolve` mở database — tức là chạy migration — ngay trong lúc module này khởi tạo. Một `IDatabaseMigration` được đăng ký bởi module khởi tạo *sau đó* sẽ vô hình tại thời điểm ấy. Package nào đóng góp bước migration cho database này phải được wire **trước** `DataCorePackageModule` trong `configureDependencies()` của host. Hiện template chưa chạm phải tình huống này, nhưng nó sẽ cắn ngay khi feature đầu tiên thêm migration cho database của package khác. Xem [`05_di.md`](05_di.md) về thứ tự module.

### Bước 6 — Dùng qua `IDatabaseHandle`, không dùng thẳng database

```dart
// packages/data/core/lib/src/data_sources/local/cache_entry_local_data_source.dart
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

Nhận `IDatabaseHandle` thay vì `CacheDatabase` nghĩa là class chỉ nhận đúng accessor nó xin, và ranh giới hiện rõ ngay trên constructor.

`IDatabaseHandle` cũng expose `transaction`, để một package gộp nhiều lệnh ghi thành nguyên tử mà không cần cầm database:

```dart
await _handle.transaction(() async {
  await _dao.upsert('a', '1');
  await _dao.upsert('b', '2');
});
```

> [!NOTE]
> Đây là **thu hẹp bề mặt API, không phải cô lập cưỡng chế** — `DatabaseAccessor` của Drift cần database, nên callback factory vẫn nhận được nó và một người cố tình vẫn có thể giữ lại. Cô lập thật đến từ tầng trên: mỗi package một database riêng. Doc comment trong `i_database_handle.dart` nói thẳng điều này thay vì hứa quá lời.

### Bước 7 — Trả về Model, không bao giờ trả row của Drift

```dart
// packages/data/core/lib/src/data_sources/local/cache_entry_local_data_source.dart
abstract class ICacheEntryLocalDataSource {
  Future<void> save(String key, String value);
  Future<String?> get(String key);
  Future<CacheEntryModel?> getEntry(String key);
  Future<void> delete(String key);
  Future<List<CacheEntryModel>> getAll();
}
```

`CacheEntry` — class Drift sinh cho một row — không xuất hiện trong bất kỳ chữ ký nào. Việc chuyển đổi diễn ra ngay tại biên:

```dart
// packages/data/core/lib/src/models/cache_entry_model.dart
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

Nó cố ý **không** dùng `json_serializable`: dữ liệu đến từ SQLite chứ không phải payload API, nên không có hợp đồng JSON nào để tuân theo.

### Bước 8 — Chạy codegen và barrel

```bash
dart tools/barrel_generator/generate.dart packages/data/core/lib
dart run build_runner build -d --workspace
```

---

## 4. Migration phi tập trung

Bạn không bao giờ sửa file database của package khác để đổi schema của mình. Bạn implement một hợp đồng và đăng ký nó.

```dart
// packages/core/database/lib/src/migration/i_database_migration.dart
abstract class IDatabaseMigration {
  /// Schema version produced by [upgrade]; must be `>= 2` and unique.
  int get version;

  /// Moves the schema from `version - 1` to [version].
  Future<void> upgrade(Migrator m);

  /// Reverses [upgrade], moving the schema from [version] back to
  /// `version - 1`.
  Future<void> downgrade(Migrator m);
}
```

Đăng ký y hệt một route module:

```dart
@LazySingleton(as: IDatabaseMigration)
class AddExpiresAtToCacheEntries implements IDatabaseMigration {
  @override
  int get version => 2;

  @override
  Future<void> upgrade(Migrator m) =>
      m.addColumn(cacheEntries, cacheEntries.expiresAt);

  @override
  Future<void> downgrade(Migrator m) =>
      m.alterTable(TableMigration(cacheEntries));
}
```

### Hợp đồng

- **`version` là version mà bước này *tạo ra*.** `version == 2` nghĩa là "lấy database ở version 1 và đưa nó lên version 2". Do đó `upgrade` phải chạy được trên `version - 1`, và `downgrade` phải đưa nó về đúng hình dạng đó.
- **Version 1 không migrate được** — đó là thứ `Migrator.createAll()` tạo ra. Runner từ chối `version < 2` ngay lúc khởi tạo.
- **Trùng version bị từ chối**, không âm thầm chọn đại một cái.

### Runner replay thế nào

```dart
// packages/core/database/lib/src/migration/database_migration_runner.dart
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
```

Ba tính chất đáng gọi tên:

1. **Dùng `if` thuần, không phải `else if`.** Thiết bị bỏ lỡ vài bản phát hành sẽ replay *mọi* bước trung gian thay vì nhảy thẳng tới hình dạng mới nhất.
2. **Upgrade chạy tăng dần, downgrade chạy giảm dần.** Thứ tự quan trọng ở cả hai chiều.
3. **Khoảng trống version là hợp lệ.** Một bản phát hành có thể không đổi schema, để trống số version đó.

Việc kiểm tra diễn ra một lần, lúc khởi tạo — không phải giữa chừng migration. Phát hiện lỗi wiring khi đã chạy được nửa đường sẽ để lại schema migrate dở.

> [!WARNING]
> **Drift 2.34.3 KHÔNG có `onDowngrade`.** `MigrationStrategy` chỉ expose `onCreate`, `onUpgrade` và `beforeOpen`; chính tài liệu Drift ghi rằng "schema version upgrades and downgrades will both be run here". `IDatabaseMigration.downgrade` là thật và có test, nhưng nó đi nhờ trên đúng một entry point đó thông qua so sánh `from`/`to`. Hãy implement khi thay đổi có thể đảo ngược; **ném lỗi có mô tả rõ ràng khi không thể**, để thất bại là tường minh thay vì để lại một schema không còn khớp với code đang chạy.

---

## 5. Các `PRAGMA`, và vì sao chúng được tập trung hoá

`PRAGMA` là thiết lập **theo từng kết nối và không được lưu trong file**, nên phải áp lại mỗi lần mở. Đó là lý do chúng nằm trong `beforeOpen`:

```dart
// packages/core/database/lib/src/migration/drift_migration_strategy.dart
beforeOpen: (OpeningDetails details) async {
  // SQLite ships with foreign key enforcement OFF. Without this any
  // `references()` declared on a table is silently ignored, so broken
  // relations are only discovered as corrupt data much later.
  await database.customStatement('PRAGMA foreign_keys = ON');

  // Write-Ahead Logging lets readers run concurrently with a writer,
  // which is required once readPool > 1 and avoids "database is locked"
  // under contention.
  await database.customStatement('PRAGMA journal_mode = WAL');

  // Wait for a held lock instead of failing instantly with SQLITE_BUSY.
  await database.customStatement('PRAGMA busy_timeout = $busyTimeoutMs');
},
```

| Pragma | Vì sao quan trọng |
|---|---|
| `foreign_keys = ON` | **SQLite mặc định TẮT cái này.** Mọi `references()` bạn khai đều bị bỏ qua âm thầm nếu thiếu nó — một cái bẫy im lặng, chỉ lộ ra rất lâu sau dưới dạng quan hệ hỏng. |
| `journal_mode = WAL` | Cho phép reader chạy đồng thời với writer. Bắt buộc khi `readPool > 1`; tránh lỗi "database is locked" khi tranh chấp. |
| `busy_timeout = 5000` | Chờ khoá được nhả thay vì fail ngay với `SQLITE_BUSY`. Mặc định là `0`. |

WAL sinh thêm file sidecar `-wal` và `-shm` cạnh database. SQLite tự chuyển đổi file có sẵn, an toàn và đảo ngược được. Database in-memory (trong test) bỏ qua thiết lập này và ở nguyên journal mode `memory` — chính vì vậy test WAL trong `data_core` phải chạy trên **file thật**.

Tập trung hoá vì đúng một lý do: một package tự viết `MigrationStrategy` riêng mà quên `foreign_keys = ON` sẽ mất toàn vẹn tham chiếu mà không có lỗi nào báo.

---

## 6. Phục hồi khi hỏng: cách ly, không bao giờ xoá

Việc mở database được đăng ký với `@preResolve`, nên bất cứ thứ gì ném ra ở đó đều làm hỏng `configureDependencies()` và app không khởi động được. Một file hỏng đồng nghĩa vòng lặp crash vĩnh viễn.

`DriftDatabaseOpener.open` xử lý việc này — và thiết kế nghiêng hẳn về phía *không* đụng vào dữ liệu người dùng:

```dart
// packages/core/database/lib/src/opening/drift_database_opener.dart
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

Ba quyết định có chủ đích:

**Kết nối được verify, không phải giả định.** `createBackgroundExecutor` là lazy — nó không chạm vào file cho tới statement đầu tiên. `_openVerified` chạy một truy vấn thăm dò `SELECT 1` để database hỏng lộ ra *ngay tại đây* thay vì ở một call site vô can nào đó sau này.

**File được đổi tên, không bao giờ bị xoá.**

```dart
// packages/core/database/lib/src/connection/database_connection_factory.dart
/// The file is **renamed, never deleted** — if the corruption check ever
/// misfires the user's bytes are still recoverable from
/// `<fileName><CORRUPT_FILE_SUFFIX>`. Only one quarantined copy is kept;
/// an older one is replaced so repeated failures cannot fill the disk.
```

Các sidecar `-wal` / `-shm` cũng bị xoá — chúng thuộc về database đã bị cách ly và nếu để lại sẽ được áp vào database mới.

**Marker môi trường phủ quyết kết luận "hỏng file".**

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

| Coi là hỏng file → cách ly | Coi là lỗi môi trường → ném lại, không đụng |
|---|---|
| `database disk image is malformed` | `unable to open database file` |
| `file is not a database` | `disk i/o error` |
| `file is encrypted or is not a database` | `database or disk is full` |
| `malformed database schema` | `attempt to write a readonly database` |
| | `access denied` / `permission denied` / `operation not permitted` |

Predicate khớp theo chuỗi thông báo thay vì bắt `SqliteException` có kiểu, vì `sqlite3` không phải dependency được khai của `core_database` — import nó là thêm một dependency mà package này vốn không cần, trong khi mọi import đều phải được khai báo. Vì khớp chuỗi vốn mong manh, predicate được thiết kế **thiên về không phục hồi**: nếu xuất hiện marker môi trường thì database được để yên, kể cả khi marker hỏng file cũng khớp.

Mất dữ liệu người dùng tệ hơn là báo lỗi lúc khởi động.

---

## 7. Dùng `core_storage` hay `core_database`?

| Bạn cần | Dùng | Vì sao |
|---|---|---|
| Một token, một cờ, theme mode, locale | [`core_storage`](06_storage.md) | Một giá trị cho một key; có mã hoá; reactive qua `ChangeNotifier` / `Stream` |
| Một danh sách bản ghi cần truy vấn, lọc, sắp xếp | `core_database` | SQL, index, ordering |
| Quan hệ giữa các bản ghi | `core_database` | Khoá ngoại (nhớ: được bật bởi `PRAGMA` ở trên) |
| Dữ liệu mà hình dạng sẽ đổi qua các bản phát hành | `core_database` | Migration có version |
| Thứ nhỏ, đọc mỗi khung hình | `core_storage` | Cache trong RAM; không có vòng async |

Quy tắc ngón tay cái: nếu bạn định viết `WHERE`, `ORDER BY` hay `JOIN`, bạn cần database.

---

## 8. Testing

`CacheDatabase.forTesting()` cho bạn database in-memory chạy trên isolate hiện tại — không cần `path_provider`, không isolate, không file:

```dart
final database = CacheDatabase.forTesting();
```

Bộ test hiện có được chia theo đúng vị trí code:

| Package | File | Bao phủ |
|---|---|---|
| `core_database` | `migration_test.dart` | Kiểm tra runner (version < 2, trùng version, sắp xếp), replay khi nhảy version, downgrade giảm dần, khoảng trống, downgrade không đảo ngược được, registry rỗng |
| `core_database` | `drift_database_opener_test.dart` | Trực tiếp predicate phát hiện hỏng — gồm cả trường hợp marker môi trường phủ quyết marker hỏng file |
| `data_core` | `cache_database_test.dart` | Round-trip DAO, wiring migration, và hành vi trên **file thật** (WAL, khoá ngoại, dữ liệu sống sót qua close/reopen) |
| `data_core` | `database_handle_test.dart` | Accessor đọc/ghi, chung một kết nối, transaction commit / rollback / giá trị trả về |

Hai thói quen đáng học:

- **Test trực tiếp predicate phát hiện hỏng.** Nó quyết định database của người dùng có bị dời đi hay không — kiểm chứng gián tiếp qua một file hỏng thật là chưa đủ.
- **Test pragma trên file thật.** Database in-memory báo `journal_mode = memory`, nên không thể chứng minh WAL đang bật.

---

## 9. Chuỗi cache là code mẫu

> [!NOTE]
> Chuỗi cache — `CacheEntries` → `CacheEntriesDao` → `CacheEntryLocalDataSource` → `CacheEntryRepositoryImpl` → `ICacheEntryRepository` → `GetCacheEntryUseCase` / `SaveCacheEntryUseCase` / `GetAllCacheEntriesUseCase` — được wire trọn vẹn và đăng ký đầy đủ trong DI, nhưng **không feature nào trong template này tiêu thụ nó**. Nó tồn tại như một tham chiếu chạy được cho hình dạng ở trên, và là fixture để các test database chạy trên đó.
>
> Hãy copy hình dạng này cho bảng thật. Xoá cả chuỗi nếu bạn không cần cache — không gì khác tham chiếu tới nó.

---

## 10. Checklist

- [ ] Bảng, DAO, class database và data source đều nằm ở **package sở hữu**
- [ ] Tên file database là hằng số trong `utils/` của package đó, đặt theo tên package
- [ ] `migration` uỷ quyền cho `driftMigrationStrategy` (đừng tự viết `MigrationStrategy`)
- [ ] Migration được **truyền vào** database, không tra cứu bên trong
- [ ] `_registeredMigrations()` có guard `isRegistered` trước khi gọi `getAll`
- [ ] Data source nhận `IDatabaseHandle<TDb>`, không nhận database
- [ ] Chữ ký trả về **Model**; không có class row của Drift trong API công khai
- [ ] Bước schema mới = một `IDatabaseMigration` mới với `version >= 2`, đăng ký bằng `@LazySingleton(as: IDatabaseMigration)`; `schemaVersion` được bump cho khớp
- [ ] `downgrade` đã implement, hoặc ném lỗi có mô tả khi không đảo ngược được
- [ ] Đã chạy lại barrel và `build_runner`

## Xem thêm

- [`06_storage.md`](06_storage.md) — lưu trữ key-value, và khi nào nên chọn nó
- [`02_new_domain_data.md`](02_new_domain_data.md) — tầng repository và model phía trên DAO
- [`05_di.md`](05_di.md) — `@preResolve`, thứ tự module, `getAll` vs `getAllOrEmpty`
- [`../architecture/02_core.md`](../architecture/02_core.md) — vị trí của `core_database`
- [`../reference/01_rules.md`](../reference/01_rules.md) — toàn bộ luật sở hữu
