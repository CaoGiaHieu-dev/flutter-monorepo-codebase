<!-- translated-from: docs/en/guides/07_database.md@b65f8b3 -->
# Hướng dẫn: Cơ sở dữ liệu quan hệ (Drift + SQLite)

## Mục tiêu

Bạn cho một package database quan hệ của riêng nó: bảng, DAO, một data source trả về model, và migration có phiên bản. Xoá package là xoá luôn database của nó, mà không làm vỡ package nào khác. Ví dụ xuyên suốt là phần nối dây thật của `data_cache`; hãy thay tên package của bạn vào mọi chỗ.

## Điều kiện cần

- Một package data — [`02_new_domain_data.md`](02_new_domain_data.md).
- **Vì sao không có `AppDatabase` dùng chung**, `core_database` export những gì, runner migration replay thế nào, các `PRAGMA` nó áp dụng và file hỏng được cách ly ra sao — [`../architecture/02_core.md` § 8](../architecture/02_core.md#8-core_database--lưu-trữ-quan-hệ-drift--sqlite). Các luật: RULE-46, RULE-47.

> [!NOTE]
> Chuỗi — `CacheEntries` → `CacheEntriesDao` → `CacheEntryLocalDataSource` → `CacheEntryRepositoryImpl` → `ICacheEntryRepository` → `GetCacheEntryUseCase` / `SaveCacheEntryUseCase` — chính là module `cache` (`modules/cache/domain` + `modules/cache/data`), được wire trọn vẹn, nhưng **không feature nào trong template này tiêu thụ nó**. Nó tồn tại như một tham chiếu chạy được cho hình dạng ở trên, và là fixture để các test database chạy trên đó.
>
> Đây là một module gỡ được như mọi module khác: `apps/mobile` ghép nó, `apps/admin` thì không — nên chỉ mobile mở file SQLite lúc boot. Hãy copy hình dạng này cho bảng thật, hoặc gỡ nó bằng `dart tools/sample_cleanup/remove_sample.dart cache --apply` (thiếu `--apply` thì chỉ xem trước). Các test database đi theo nó; chúng kiểm tra `DatabaseHandle` và `driftMigrationStrategy` của `core_database` qua fixture này, nên muốn giữ phần kiểm tra đó thì hãy cho chúng một fixture khác trước khi xoá.

---

## 1. Chọn: lưu trữ key-value hay database

| Bạn cần | Dùng | Vì sao |
|---|---|---|
| Một token, một cờ, theme mode, locale | [`core_storage`](06_storage.md) | Một giá trị cho một key; có mã hoá; reactive qua `ChangeNotifier` / `Stream` |
| Một danh sách bản ghi cần truy vấn, lọc, sắp xếp | `core_database` | SQL, index, ordering |
| Quan hệ giữa các bản ghi | `core_database` | Khoá ngoại (được ràng buộc vì mọi kết nối đều chạy `PRAGMA foreign_keys = ON`) |
| Dữ liệu mà hình dạng sẽ đổi qua các bản phát hành | `core_database` | Migration có version |
| Thứ nhỏ, đọc mỗi khung hình | `core_storage` | Cache trong RAM; không có vòng async |

Quy tắc ngón tay cái: nếu bạn định viết `WHERE`, `ORDER BY` hay `JOIN`, bạn cần database.

## 2. Khai dependency

`pubspec.yaml` của package cần những gì `modules/cache/data/pubspec.yaml` thật khai cho database của nó:

```yaml
dependencies:
  flutter:
    sdk: flutter              # `visibleForTesting` trong class database
  core_database:
    path: ../../../platform/infra/database
  drift: "^2.34.3"
  get_it: ^9.2.1              # module DI thu thập migration qua GetIt
  injectable: ^3.0.0

dev_dependencies:
  build_runner: "^2.16.0"
  drift_dev: "^2.34.5"        # sinh `<name>_database.g.dart`
  injectable_generator: "^3.1.3"
  flutter_test:
    sdk: flutter              # cho test database in-memory (bước 12)
```

Phần còn lại của một package data thì thêm như thường lệ (`domain_core`, `data_core`, `domain_*` của bạn, `freezed_annotation` / `freezed` cho model). `sqlite3` và `path_provider` là dependency riêng của `core_database` — đừng khai lại. Version lấy từ catalog `pubspec_dependencies.yaml`: dependency viết không kèm version (`drift:`) sẽ được `dart tools/dependency_sync.dart` điền vào, còn version lệch sẽ bị ghi đè. Sau đó `flutter pub get`.

## 3. Định nghĩa bảng

Class kế thừa `Table` là độc lập: nó không tham chiếu database nào, nên nằm ở package của bạn được.

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

## 4. Định nghĩa DAO dưới dạng `part of` database của bạn

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

Dòng `part of` là bắt buộc — đó là yêu cầu của Drift, và là lý do DAO không thể nằm ở package khác.

## 5. Đặt tên file database trong `utils/` của chính package

Theo luật chung của repo, constants nằm ở `utils/` của package sở hữu:

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
> Đặt tên file theo **package sở hữu**, không theo tên app. Nhiều database cùng tồn tại trong thư mục documents; một cái tên chung chung kiểu `app_database.sqlite` sẽ đụng nhau. Đổi chuỗi này sau khi đã phát hành sẽ khiến dữ liệu cũ trên máy người dùng không còn truy cập được.

## 6. Khai class database

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

Phần import quan trọng không kém class: **bảng** là một `import` bình thường (nó độc lập), còn **DAO** là một `part` — Drift bắt accessor phải nằm trong library của database — đặt cạnh `part '<name>_database.g.dart';` do `build_runner` sinh ra.

Hai điểm cần copy nguyên xi:

- **Migration được truyền vào, không bao giờ tra cứu bên trong class.** Nhờ vậy database không dính service-locator và dựng trực tiếp được trong test.
- **`migration` uỷ quyền cho `driftMigrationStrategy`.** Tự viết `MigrationStrategy` riêng nghĩa là phải tự suy ra lại các `PRAGMA` — và một package quên `foreign_keys = ON` sẽ âm thầm mất toàn vẹn tham chiếu.

## 7. Đăng ký database trong module DI của bạn

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

Cái guard `isRegistered` rất quan trọng: `getAll<T>()` **ném lỗi** khi chưa có gì đăng ký cho `T`. Không có guard này, một bản build không có migration nào sẽ crash ngay trong `configureDependencies()`.

> [!WARNING]
> **Thứ tự đăng ký.** `@preResolve` mở database — tức là chạy migration — đúng lúc injectable tới lượt đăng ký đó, nên mọi bước migration phải được đăng ký trước thời điểm ấy. Bước nào chưa có thì bị bỏ qua mà không báo lỗi: `schemaVersion` tăng nhưng schema thì không đổi.
>
> - **Bước nằm trong chính package sở hữu** (ở đây là `data_cache`) được thu thập **miễn là hàm mở vẫn giữ `@Order(1)`**. Injectable đăng ký các mục của một package theo `@Order` tăng dần, còn migration khai báo `@LazySingleton(as: IDatabaseMigration<CacheDatabase>)` mang order mặc định 0 — nên nó được đăng ký trước hàm mở.
> - Bỏ `@Order(1)` đi thì hàm mở có thể được đăng ký trước; đó chính là lỗi mà `@Order(1)` được thêm vào để sửa.
> - **Bước đến từ package khác** phải nằm ở **nhóm DI sớm hơn** package sở hữu trong `app_manifest.yaml` của app. `@Order` chỉ sắp xếp bên trong module của một package; nó không thể đẩy một đăng ký sang trước module khác. Hiện template chưa có trường hợp này, nhưng nó sẽ cắn ngay khi feature đầu tiên thêm migration cho database của package khác.
>
> **Sao chép pattern này cho database của riêng bạn? Hãy đặt `@Order(1)` lên hàm mở `@preResolve` của bạn** — thiếu nó, một bước migration viết y hệt bước 11 sẽ không bao giờ được thu thập. Xem [`05_di.md`](05_di.md) về thứ tự module.

## 8. Dùng qua `IDatabaseHandle`, không dùng thẳng database

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

## 9. Trả về model, không bao giờ trả row của Drift

```dart
// modules/cache/data/lib/src/data_sources/local/cache_entry_local_data_source.dart
abstract class ICacheEntryLocalDataSource {
  Future<void> save(String key, String value);

  Future<CacheEntryModel?> getEntry(String key);
}
```

`CacheEntry` — class Drift sinh cho một row — không xuất hiện trong bất kỳ chữ ký nào. Việc chuyển đổi diễn ra ngay tại biên:

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

Nó cố ý **không** dùng `json_serializable`: dữ liệu đến từ SQLite chứ không phải payload API, nên không có hợp đồng JSON nào để tuân theo.

## 10. Sinh code và barrel

```bash
dart run build_runner build --workspace
dart tools/barrel_generator/generate.dart modules/cache/data/lib
```

## 11. Thêm một migration schema

Bạn không bao giờ sửa file database của package khác để đổi schema của mình. Bạn implement một hợp đồng và đăng ký nó.

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

Một thay đổi schema là **ba chỗ sửa đi cùng nhau** — thiếu một chỗ thì bản nâng cấp lặng lẽ không làm gì, hoặc bản cài mới và bản đã nâng cấp có schema khác nhau:

1. **Thêm cột vào class bảng** — Drift sinh schema từ nó, và `Migrator.createAll()` dựng bản cài mới từ nó. Cột thêm vào bảng đã có phải `nullable()` hoặc có `withDefault(...)`: SQLite không thêm được cột `NOT NULL` không có default vào những row đã tồn tại.

   ```dart
   // tables/cache_entries_table.dart — bên trong `CacheEntries`
   DateTimeColumn get expiresAt => dateTime().nullable()();
   ```

2. **Tăng `schemaVersion`** trong class database (`1` → `2`). Nó phải bằng `version` cao nhất trong các bước của bạn: Drift chỉ gọi `onUpgrade` khi `user_version` đang lưu nhỏ hơn `schemaVersion`, nên không tăng thì không bước nào chạy trên máy đã cài, và các query hỏng với *"no such column"*.

   ```dart
   @override
   int get schemaVersion => 2;
   ```

3. **Đăng ký bước migration** — bên dưới. Rồi chạy `dart run build_runner build --workspace` (class bảng được sinh có thêm cột).

Đăng ký như một route module, nhưng gắn kiểu với database mà nó thuộc về — GetIt định danh một đăng ký theo đúng kiểu của nó, nên `CacheDatabase` chỉ thu về `IDatabaseMigration<CacheDatabase>` và bước migration của package khác không bao giờ tới được nó. Khai báo trong chính package sở hữu, nó được thu thập vì hàm mở mang `@Order(1)` ([bước 7](#7-đăng-ký-database-trong-module-di-của-bạn)):

```dart
@LazySingleton(as: IDatabaseMigration<CacheDatabase>)
class AddExpiresAtToCacheEntries
    implements IDatabaseMigration<CacheDatabase> {
  @override
  int get version => 2;

  @override
  Future<void> upgrade(Migrator m) {
    // `Migrator.database` là database đang được migrate; ép kiểu để dùng
    // các getter bảng được sinh ra. `expiresAt` là cột mà bước này thêm vào.
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

### Tuân thủ hợp đồng

- **`version` là version mà bước này *tạo ra*.** `version == 2` nghĩa là "lấy database ở version 1 và đưa nó lên version 2". Do đó `upgrade` phải chạy được trên `version - 1`, và `downgrade` phải đưa nó về đúng hình dạng đó.
- **Version 1 không migrate được** — đó là thứ `Migrator.createAll()` tạo ra. Runner từ chối `version < 2` ngay lúc khởi tạo.
- **Trùng version bị từ chối**, không âm thầm chọn đại một cái.

## 12. Test database

`CacheDatabase.forTesting()` cho bạn database in-memory chạy trên isolate hiện tại — không cần `path_provider`, không isolate, không file:

```dart
final database = CacheDatabase.forTesting();
```

Bộ test hiện có được chia theo đúng vị trí code:

| Package | File | Bao phủ |
|---|---|---|
| `core_database` | `migration_test.dart` | Kiểm tra runner (version < 2, trùng version, sắp xếp), replay khi nhảy version, downgrade giảm dần, khoảng trống, downgrade không đảo ngược được, downgrade không có bước tương ứng bị từ chối (và version đã lưu được giữ nguyên, trên file thật), registry rỗng |
| `core_database` | `drift_database_opener_test.dart` | Trực tiếp predicate phát hiện hỏng — gồm cả trường hợp marker môi trường phủ quyết marker hỏng file |
| `data_cache` | `cache_database_test.dart` | Round-trip DAO, wiring migration, và hành vi trên **file thật** (WAL, khoá ngoại, dữ liệu sống sót qua close/reopen) |
| `data_cache` | `database_handle_test.dart` | Accessor đọc/ghi, chung một kết nối, transaction commit / rollback / giá trị trả về |

Hai thói quen đáng học:

- **Test trực tiếp predicate phát hiện hỏng.** Nó quyết định database của người dùng có bị dời đi hay không — kiểm chứng gián tiếp qua một file hỏng thật là chưa đủ.
- **Test pragma trên file thật.** Database in-memory báo `journal_mode = memory`, nên không thể chứng minh WAL đang bật.

---

## Kiểm tra

```bash
dart run build_runner build --workspace   # <name>_database.g.dart, mixin của DAO, module.module.dart
flutter analyze                           # No issues found!
cd modules/cache/data && flutter test     # test tham chiếu: DAO, migration, WAL trên file thật
cd platform/infra/database && flutter test
cd apps/mobile && flutter test test/di_smoke_test.dart   # lệnh mở @preResolve thành công trong graph thật
```

Chạy test của package bạn theo cùng cách. Một migration mới cần một test mở schema cũ, chạy bước migration và đọc lại cột mới.

Checklist review:

- [ ] Bảng, DAO, class database và data source đều nằm trong **package sở hữu**
- [ ] Tên file database là hằng số trong `utils/` của package đó, đặt theo tên package
- [ ] `migration` uỷ quyền cho `driftMigrationStrategy` (đừng tự viết `MigrationStrategy`)
- [ ] Migration được **truyền vào** database, không bao giờ tự tra bên trong
- [ ] `_registeredMigrations()` kiểm tra `isRegistered` trước khi `getAll`
- [ ] Lệnh mở `@preResolve` mang `@Order(1)`, để migration của chính package đăng ký trước nó; bước migration từ package khác nằm ở một nhóm DI sớm hơn
- [ ] Data source nhận `IDatabaseHandle<TDb>`, không nhận database
- [ ] Chữ ký hàm trả **Model**; không có class row của Drift trong API công khai
- [ ] Bước schema mới = một `IDatabaseMigration` mới với `version >= 2`, đăng ký qua `@LazySingleton(as: IDatabaseMigration<YourDatabase>)`; `schemaVersion` được tăng cho khớp
- [ ] Đã hiện thực `downgrade`, hoặc ném lỗi mô tả rõ khi không đảo ngược được
- [ ] Đã sinh lại barrel và chạy `build_runner`

## Xử lý sự cố

| Triệu chứng | Nguyên nhân | Cách sửa |
|:--|:--|:--|
| `no such column` sau khi nâng cấp | Chưa tăng `schemaVersion`, hoặc bước migration chưa từng được thu thập | Tăng `schemaVersion` và đăng ký bước migration gắn kiểu với database của bạn (bước 11) |
| Bước migration có đó nhưng không bao giờ chạy | Lệnh mở thiếu `@Order(1)`, bước được đăng ký dạng `IDatabaseMigration` không kiểu, hoặc nằm ở nhóm DI muộn hơn | Thêm `@Order(1)` (bước 7); đăng ký `as: IDatabaseMigration<YourDatabase>` (bước 11) |
| Boot sập trong `configureDependencies()` khi không có migration nào | `getAll<T>()` ném lỗi khi không có gì được đăng ký | Giữ phần kiểm tra `isRegistered` (bước 7) |
| `UnsupportedError: Cannot downgrade the schema…` lúc khởi động | Một bản build cũ được cài đè lên schema mới hơn | Phát hành bước downgrade trước, hoặc cài lại bản mới hơn |
| Quan hệ không được ràng buộc | Một `MigrationStrategy` viết tay đã bỏ `foreign_keys = ON` | Uỷ quyền cho `driftMigrationStrategy` (bước 6) |
| File bị đổi tên thành `<name>.corrupt` | Lệnh mở phát hiện database hỏng và cách ly nó | Dữ liệu vẫn được giữ để phục hồi; xem [`../architecture/02_core.md` § 8](../architecture/02_core.md#phục-hồi-khi-hỏng-cách-ly-không-bao-giờ-xoá) |
| Test không chứng minh được WAL đang bật | Database in-memory báo `journal_mode = memory` | Test pragma trên một file thật (bước 12) |

## Liên quan

- Luật: RULE-41 (trả model, không trả row), RULE-46 (mỗi package sở hữu database của nó), RULE-47 (migration gắn kiểu với database của nó) — [`../reference/01_rules.md`](../reference/01_rules.md)
- [`../architecture/02_core.md` § 8](../architecture/02_core.md#8-core_database--lưu-trữ-quan-hệ-drift--sqlite) — thiết kế đứng sau cơ chế
- [`06_storage.md`](06_storage.md) — lưu trữ key-value, và khi nào nên dùng nó
- [`02_new_domain_data.md`](02_new_domain_data.md) — tầng repository và model phía trên DAO
- [`05_di.md`](05_di.md) — `@preResolve`, thứ tự module, `getAll` so với `getAllOrEmpty`
