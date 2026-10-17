<!-- translated-from: docs/en/guides/07_database.md@8240431 -->
# Hướng dẫn: Cơ sở dữ liệu quan hệ (Drift + SQLite)

## Mục tiêu

Bạn cho một package database quan hệ của riêng nó: bảng, DAO, một data source trả về model, và migration có phiên bản. Xoá package là xoá luôn database của nó, mà không làm vỡ package nào khác. Ví dụ xuyên suốt là phần nối dây thật của `data_cache`; hãy thay tên package của bạn vào mọi chỗ.

## Điều kiện cần

- Một package data — [`02_new_domain_data.md`](02_new_domain_data.md).
- **Vì sao không có `AppDatabase` dùng chung**, `core_database` export những gì, runner migration replay thế nào, các `PRAGMA` nó áp dụng và file hỏng được cách ly ra sao — [`../architecture/02_core.md` § 8](../architecture/02_core.md#8-core_database--lưu-trữ-quan-hệ-drift--sqlite). Các luật: RULE-46, RULE-47.

> [!NOTE]
> Chuỗi — `CacheEntries` → `CacheEntriesDao` → `CacheEntryLocalDataSource` → `CacheEntryRepositoryImpl` → `ICacheEntryRepository` — chính là module `cache` (`modules/cache/domain` + `modules/cache/data`), được wire tới tận hợp đồng repository, nhưng **không feature và không use case nào trong template này tiêu thụ nó**: `domain_cache` chỉ là một entity và một repository interface, không hơn. Nó tồn tại như một tham chiếu chạy được cho hình dạng ở trên, và là fixture để các test database chạy trên đó.
>
> Đây là một module gỡ được như mọi module khác: `apps/mobile` ghép nó, `apps/admin` thì không — nên chỉ mobile mở file SQLite lúc boot. Hãy copy hình dạng này cho bảng thật, hoặc gỡ nó bằng `dart tools/sample_cleanup/remove_sample.dart cache --apply` (thiếu `--apply` thì chỉ xem trước). Hai test database đi theo nó; các test của chính `core_database` vẫn bao phủ `DatabaseHandle` và migration runner.

---

## 1. Chọn: lưu trữ key-value hay database

| Bạn cần | Dùng | Vì sao |
|---|---|---|
| Một token, một cờ, theme mode, locale | [`core_storage`](06_storage.md) | Một giá trị cho một key; có mã hoá; reactive qua `ChangeNotifier` / `Stream` |
| Một danh sách bản ghi cần truy vấn, lọc, sắp xếp | `core_database` | SQL, index, ordering |
| Quan hệ giữa các bản ghi | `core_database` | Khoá ngoại (được ràng buộc vì migration strategy dùng chung chạy `PRAGMA foreign_keys = ON` khi database mở) |
| Dữ liệu mà hình dạng sẽ đổi qua các bản phát hành | `core_database` | Migration có version |
| Thứ nhỏ, đọc mỗi khung hình | `core_storage` | Cache trong RAM; không có vòng async |

Quy tắc ngón tay cái: nếu bạn định viết `WHERE`, `ORDER BY` hay `JOIN`, bạn cần database.

## 2. Khai dependency

`pubspec.yaml` của package cần những gì `modules/cache/data/pubspec.yaml` thật khai cho database của nó. Hãy viết các mục bên thứ ba không kèm version:

```yaml
dependencies:
  flutter:
    sdk: flutter              # `visibleForTesting` trong class database
  core_database:
    path: ../../../platform/infra/database
  platform_kernel:
    path: ../../../platform/foundation/kernel   # getAllOrEmpty, cho module DI
  drift:
  injectable:

dev_dependencies:
  build_runner:
  drift_dev:                  # sinh `<name>_database.g.dart`
  injectable_generator:
  flutter_test:
    sdk: flutter              # cho test database in-memory (bước 12)
```

Phần còn lại của một package data thì thêm như thường lệ (`domain_core`, `data_core`, `domain_*` của bạn, `freezed_annotation` / `freezed` cho model). `sqlite3` và `path_provider` là dependency riêng của `core_database` — đừng khai lại, và đừng bao giờ import chúng, `package:drift/native.dart` hay `dart:ffi` từ `lib/` của bạn: package khi đó làm hỏng mọi bản build web của app link nó, trong khi `flutter analyze` vẫn sạch. `arch_check` R22 từ chối điều đó (RULE-82); import có điều kiện của `core_database` là nơi duy nhất chạm tới chúng ([§ 13](#13-trên-web)). Version chỉ nằm trong catalog `pubspec_dependencies.yaml` (RULE-74): `dart tools/dependency_sync.dart` điền vào mục viết không kèm version (`drift:`) và ghi đè mục bị lệch. Sau đó `flutter pub get`.

## 3. Định nghĩa bảng

Class kế thừa `Table` là độc lập: nó không tham chiếu database nào, nên nằm ở package của bạn được.

```dart
// modules/cache/data/lib/src/database/tables/cache_entries_table.dart
import 'package:drift/drift.dart';

/// Example table — string payloads keyed by a unique id.
class CacheEntries extends Table {
  TextColumn get key => text()();

  TextColumn get value => text()();

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

  /// Reads the row for [key], or `null` when missing.
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
/// Constants owned exclusively by `data_cache`.
class CacheConstants {
  CacheConstants._();

  /// SQLite file of this package's [CacheDatabase], named after its owner:
  /// each package that persists data opens its own file.
  static const String DATABASE_FILE_NAME = 'cache.sqlite';
}
```

> [!CAUTION]
> Đặt tên file theo **package sở hữu**, không theo tên app. Nhiều database cùng tồn tại trong thư mục riêng của app — thư mục documents trên Android và iOS, thư mục application-support trên macOS, Windows và Linux (trên desktop "documents" là thư mục dùng chung của người dùng), vùng lưu trữ của trình duyệt cho origin trên web; một cái tên chung chung kiểu `app_database.sqlite` sẽ đụng nhau. Đổi chuỗi này sau khi đã phát hành sẽ khiến dữ liệu cũ trên máy người dùng không còn truy cập được.

## 6. Khai class database

```dart
// modules/cache/data/lib/src/database/cache_database.dart
import 'package:core_database/core_database.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../utils/cache_constants.dart';
import 'tables/cache_entries_table.dart';

part 'cache_database.g.dart';
part 'dao/cache_entries_dao.dart';

/// SAMPLE — the database owned by `data_cache`, holding only its own tables.
///
/// Drift binds tables at compile time and a DAO must be a `part of` its
/// database, so each package that persists data declares its own database
/// next to its tables, DAO and data source; deleting the package deletes the
/// database with it. `core_database` supplies only the mechanism
/// ([DriftDatabaseOpener], [driftMigrationStrategy], [IDatabaseMigration],
/// [IDatabaseHandle]).
@DriftDatabase(tables: [CacheEntries], daos: [CacheEntriesDao])
class CacheDatabase extends _$CacheDatabase {
  CacheDatabase._(super.e, this._migrations, [this.schemaVersion = 1]);

  /// Schema steps contributed for this database, collected by the DI module.
  final Iterable<IDatabaseMigration> _migrations;

  /// Bump it together with a new [IDatabaseMigration] whose `version` is the
  /// new number; nothing else in this file changes.
  @override
  final int schemaVersion;

  /// Opens the database — on a background isolate natively, in drift's wasm
  /// worker on the web — with corruption recovery ([DriftDatabaseOpener]).
  static Future<CacheDatabase> open({
    Iterable<IDatabaseMigration> migrations = const <IDatabaseMigration>[],
  }) {
    return DriftDatabaseOpener.open(
      (executor) => CacheDatabase._(executor, migrations),
      fileName: CacheConstants.DATABASE_FILE_NAME,
    );
  }

  /// A database over [executor], for tests — `NativeDatabase.memory()` for
  /// an in-memory one. The test passes the executor, so this library never
  /// imports `drift/native` (`dart:ffi`), which no web build can compile.
  /// [schemaVersion] lets an upgrade test reopen a hand-written old file so
  /// the [migrations] run.
  @visibleForTesting
  factory CacheDatabase.forTesting(
    QueryExecutor executor, [
    Iterable<IDatabaseMigration> migrations = const <IDatabaseMigration>[],
    int schemaVersion = 1,
  ]) {
    return CacheDatabase._(executor, migrations, schemaVersion);
  }

  @override
  MigrationStrategy get migration =>
      driftMigrationStrategy(database: this, migrations: _migrations);
}
```

Phần import quan trọng không kém class: **bảng** là một `import` bình thường (nó độc lập), còn **DAO** là một `part` — Drift bắt accessor phải nằm trong library của database — đặt cạnh `part '<name>_database.g.dart';` do `build_runner` sinh ra.

Hai điểm cần copy nguyên xi:

- **Migration được truyền vào, không bao giờ tra cứu bên trong class.** Nhờ vậy database không dính service-locator và dựng trực tiếp được trong test.
- **`migration` uỷ quyền cho `driftMigrationStrategy`.** Tự viết `MigrationStrategy` riêng nghĩa là phải tự suy ra lại các `PRAGMA` — và một package quên `foreign_keys = ON` sẽ âm thầm mất toàn vẹn tham chiếu.
- **`forTesting` nhận executor; thư viện không bao giờ import `drift/native`.** Test truyền `NativeDatabase.memory()` (hoặc một file) từ `test/`, nên class database cũng biên dịch được cho web (R22).

## 7. Đăng ký database trong module DI của bạn

```dart
// modules/cache/data/lib/di/module.dart
@module
abstract class DataCacheDiModule {
  /// Opens [CacheDatabase] while the module initialises, which runs the
  /// collected migrations — so every step must be registered by then.
  /// `@Order(1)` makes a step declared in this package (default order 0)
  /// register before the open; a step from another package needs an earlier
  /// DI group. The collection is typed to [CacheDatabase], so another
  /// package's steps never reach it.
  @Order(1)
  @preResolve
  @lazySingleton
  Future<CacheDatabase> cacheDatabase() => CacheDatabase.open(
    migrations: getAllOrEmpty<IDatabaseMigration<CacheDatabase>>(),
  );

  /// Data sources take this handle instead of [CacheDatabase], so each gets
  /// only the DAO it asks for.
  @lazySingleton
  IDatabaseHandle<CacheDatabase> cacheDatabaseHandle(CacheDatabase database) =>
      DatabaseHandle<CacheDatabase>(database);
}
```

`getAllOrEmpty` (từ `platform_kernel`, [`05_di.md`](05_di.md#5-resolve-đóng-góp-tuỳ-chọn-một-cách-an-toàn)) chính là guard: `getAll<T>()` trần **ném lỗi** khi chưa có gì đăng ký cho `T`, nên một bản build không có migration nào sẽ crash ngay trong `configureDependencies()`. Hãy truyền cho nó `IDatabaseMigration<YourDatabase>` — đúng kiểu mà các bước migration đăng ký.

> [!WARNING]
> **Thứ tự đăng ký.** `@preResolve` mở database — tức là chạy migration — đúng lúc injectable tới lượt đăng ký đó, nên mọi bước migration phải được đăng ký trước thời điểm ấy. Bước nào chưa có thì bị bỏ qua mà không báo lỗi: `schemaVersion` tăng nhưng schema thì không đổi.
>
> - **Bước nằm trong chính package sở hữu** (ở đây là `data_cache`) được thu thập **miễn là hàm mở vẫn giữ `@Order(1)`**. Injectable đăng ký các mục của một package theo `@Order` tăng dần, còn migration khai báo `@LazySingleton(as: IDatabaseMigration<CacheDatabase>)` mang order mặc định 0 — nên nó được đăng ký trước hàm mở.
> - Bỏ `@Order(1)` đi thì hàm mở có thể được đăng ký trước; đó chính là lỗi mà `@Order(1)` được thêm vào để sửa.
> - **Bước đến từ package khác** phải nằm ở **nhóm DI sớm hơn** package sở hữu trong `app_manifest.yaml` của app. `@Order` chỉ sắp xếp bên trong module của một package; nó không thể đẩy một đăng ký sang trước module khác. Hiện template chưa có trường hợp này, nhưng nó sẽ cắn ngay khi feature đầu tiên thêm migration cho database của package khác.
>
> **Sao chép pattern này cho database của riêng bạn? Hãy đặt `@Order(1)` lên hàm mở `@preResolve` của bạn** — thiếu nó, một bước migration viết y hệt bước 11 sẽ không bao giờ được thu thập. (RULE-47). Xem [`05_di.md`](05_di.md) về thứ tự module và [`../architecture/06_app_shell.md` § 3](../architecture/06_app_shell.md#database-mở-sau-khi-các-migration-của-nó-đã-đăng-ký) về lý do nó không với qua các nhóm được.

## 8. Dùng qua `IDatabaseHandle`, không dùng thẳng database

```dart
// modules/cache/data/lib/src/data_sources/local/cache_entry_local_data_source.dart
/// SAMPLE — takes [IDatabaseHandle] rather than [CacheDatabase] (only the one
/// DAO it asks for) and converts Drift rows to models here.
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

Nhận `IDatabaseHandle` thay vì `CacheDatabase` nghĩa là class chỉ nhận đúng accessor nó xin, và ranh giới hiện rõ ngay trên constructor.

`IDatabaseHandle` cũng expose `transaction`, để một package gộp nhiều lệnh ghi thành nguyên tử mà không cần cầm database:

```dart
await _handle.transaction(() async {
  await _dao.upsert('a', '1');
  await _dao.upsert('b', '2');
});
```

> [!NOTE]
> Đây là **thu hẹp bề mặt API, không phải cô lập cưỡng chế** — `DatabaseAccessor` của Drift cần database, nên callback factory vẫn nhận được nó và một người cố tình vẫn có thể giữ lại. Cô lập thật đến từ tầng trên: mỗi package một database riêng (RULE-46). Doc comment trong `i_database_handle.dart` nói thẳng điều này thay vì hứa quá lời.

## 9. Trả về model, không bao giờ trả row của Drift

```dart
// modules/cache/data/lib/src/data_sources/local/cache_entry_local_data_source.dart
/// Signatures speak in [CacheEntryModel], never in Drift's generated row
/// class, so Drift stays an implementation detail of `data_cache`.
abstract class ICacheEntryLocalDataSource {
  Future<void> save(String key, String value);

  Future<CacheEntryModel?> getEntry(String key);
}
```

`CacheEntry` — class Drift sinh cho một row — không xuất hiện trong bất kỳ chữ ký nào. Việc chuyển đổi diễn ra ngay tại biên:

```dart
// modules/cache/data/lib/src/models/cache_entry_model.dart
/// Data-layer form of a `cache_entries` row. The generated Drift [CacheEntry]
/// is converted here, at the boundary, so Drift never leaks past `data_cache`.
/// Not `json_serializable`: rows come from SQLite, not an API payload.
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

`build_runner` ghi `<name>_database.g.dart` (database, mixin của DAO, các class row và companion) và `module.module.dart` của package. Chạy barrel generator sau đó, và chạy lại mỗi khi bạn thêm, đổi tên hay xoá một file dưới `lib/` (RULE-75); nó export các file generated đang có trên đĩa.

## 11. Thêm một migration schema

Bạn không bao giờ sửa file database của package khác để đổi schema của mình. Bạn implement một hợp đồng và đăng ký nó.

```dart
// platform/infra/database/lib/src/migration/i_database_migration.dart
abstract class IDatabaseMigration<TDb extends GeneratedDatabase> {
  /// Schema version produced by [upgrade]; must be `>= 2` and unique.
  ///
  /// Version 1 is the initial schema created by `Migrator.createAll()`, so
  /// there is nothing to migrate *to* it.
  int get version;

  /// Moves the schema from `version - 1` to [version].
  Future<void> upgrade(Migrator m);

  /// Reverses [upgrade], moving the schema from [version] back to
  /// `version - 1`.
  ///
  /// Drift has no dedicated downgrade callback — it routes both directions
  /// through `onUpgrade` — so this is invoked when a user installs an older
  /// build over a newer one. Implement it whenever the change is reversible;
  /// throw a descriptive error when it is not, so the failure is explicit
  /// instead of leaving a schema that no longer matches the running code.
  Future<void> downgrade(Migrator m);
}
```

Một thay đổi schema là **ba chỗ sửa đi cùng nhau** — thiếu một chỗ thì bản nâng cấp lặng lẽ không làm gì, hoặc bản cài mới và bản đã nâng cấp có schema khác nhau:

1. **Thêm cột vào class bảng** — Drift sinh schema từ nó, và `Migrator.createAll()` dựng bản cài mới từ nó. Cột thêm vào bảng đã có phải `nullable()` hoặc có `withDefault(...)`: SQLite không thêm được cột `NOT NULL` không có default vào những row đã tồn tại.

   ```dart
   // tables/cache_entries_table.dart — bên trong `CacheEntries`
   DateTimeColumn get expiresAt => dateTime().nullable()();
   ```

2. **Tăng số phiên bản schema** trong class database (constructor private của sample đặt mặc định cho nó, `[this.schemaVersion = 1]` → `2`; đó là giá trị `schemaVersion` trả về). Nó phải bằng `version` cao nhất trong các bước của bạn: Drift chỉ gọi `onUpgrade` khi `user_version` đang lưu nhỏ hơn `schemaVersion`, nên không tăng thì không bước nào chạy trên máy đã cài, và các query hỏng với *"no such column"*. `forTesting` thì nhận số phiên bản làm tham số — test nâng cấp truyền `2` cùng với file cũ viết tay của nó.

   ```dart
   CacheDatabase._(super.e, this._migrations, [this.schemaVersion = 2]);
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
- **Version trùng bị từ chối**, không âm thầm chọn một trong số chúng.
- **Cả lần upgrade là một transaction.** `driftMigrationStrategy` chạy mọi bước bên trong `database.transaction`, nên một bước ném lỗi sẽ rollback cả các bước trước đó: file giữ nguyên version và schema cũ, và lần khởi động sau thử lại upgrade từ đầu. Hãy viết bước nào cũng chạy lại an toàn từ schema cũ, và đừng bao giờ dựa vào trạng thái áp dụng dở dang.

## 12. Test database

`CacheDatabase.forTesting(NativeDatabase.memory())` cho bạn database in-memory chạy trên isolate hiện tại — không cần `path_provider`, không isolate, không file. Chính test import `package:drift/native.dart`; `test/` là nơi duy nhất một package có thể chạy web được phép làm vậy:

```dart
    final database = CacheDatabase.forTesting(NativeDatabase.memory());
```

Bộ test hiện có được chia theo đúng vị trí code:

| Package | File | Bao phủ |
|---|---|---|
| `core_database` | `migration_test.dart` | Kiểm tra runner (version < 2, trùng version, sắp xếp), replay khi nhảy version, downgrade giảm dần, khoảng trống, downgrade không đảo ngược được, downgrade không có bước tương ứng bị từ chối (và version đã lưu được giữ nguyên, trên file thật), registry rỗng, và upgrade trên file thật: mọi bước được replay và giữ nguyên các row, một bước lỗi làm các bước trước đó bị rollback, và file đã mở có `foreign_keys` bật cùng journal WAL |
| `core_database` | `drift_database_opener_test.dart` | Phục hồi khi hỏng — một file bị cách ly được mở lại rỗng; khi không dời được gì, lỗi gốc được giữ nguyên và không mở lại — và trực tiếp predicate phát hiện hỏng, gồm cả trường hợp marker môi trường phủ quyết marker hỏng file |
| `core_database` | `database_connection_factory_test.dart` | Các kết nối trong read pool mang busy timeout, thứ mà `beforeOpen` chỉ đặt cho writer; thư mục database theo từng platform (documents trên Android và iOS, application support trên desktop); việc cách ly một file cùng các file phụ của nó, và `false` khi không có gì để dời |
| `core_database` | `database_handle_test.dart` | `DatabaseHandle.transaction` commit khối của nó và trả về giá trị của khối; một khối ném lỗi thì rollback những gì nó đã ghi |
| `data_cache` | `cache_database_test.dart` | Một lần nâng cấp trên **file thật**: một file version cũ viết tay (`user_version = 1`) mở lại như version 2 chạy lại bước của nó và giữ nguyên row |
| `data_cache` | `cache_entry_repository_test.dart` | Repository trên một database in-memory thật (`DatabaseHandle` → DAO → model → entity): giá trị đã lưu quay về thành entity và key không có thành `null`; một data source ném lỗi trở thành `Failure`, không bao giờ là exception |

Hai thói quen đáng học:

- **Test trực tiếp predicate phát hiện hỏng.** Nó quyết định database của người dùng có bị dời đi hay không — kiểm chứng gián tiếp qua một file hỏng thật là chưa đủ.
- **Test pragma trên file thật.** Database in-memory báo `journal_mode = memory`, nên không thể chứng minh WAL đang bật. `migration_test.dart` mở một file thật vì lý do đó.

## 13. Trên web

Không có gì trong package của bạn đổi cho web: `DriftDatabaseOpener.open` và `CacheDatabase.open` là cùng những lời gọi. `core_database` chọn kết nối qua một import có điều kiện trong `database_connection_factory.dart` (được allow-list cho R17, là mẫu chuẩn cho R22):

```dart
import 'connection/native_connection.dart'
    if (dart.library.js_interop) 'connection/web_connection.dart'
    as connection;
```

Trên native, `connection/native_connection.dart` mở file trên các drift isolate nền. Trên web, `connection/web_connection.dart` mở bản wasm của SQLite do drift build trong một worker (`WasmDatabase.open`), lưu ở vùng lưu trữ nào của trình duyệt mà nó có — lúc boot log nói vùng nào, ở mức `INFO`, kèm các tính năng trình duyệt mà nó thiếu. Barrel không export đích nào, chỉ export factory (RULE-75).

**Hai asset** phải nằm cạnh `index.html` của app: `sqlite3.wasm` và `drift_worker.js`. Chúng được mở bằng URI tương đối, nên trình duyệt phân giải chúng theo `<base href>` và một app phục vụ dưới sub-path vẫn tìm thấy. `dart tools/composer/composer.dart runners` ghi cả hai vào runner web được sinh của app khi app link `core_database` — được ghép, hoặc chạm tới qua `dependencies:` của một package được ghép:

- **`sqlite3.wasm`** là binary của bản phát hành mà package `sqlite3` *đã resolve* nêu tên, được kiểm theo sha256 mà package đó đi kèm trong `lib/src/hook/asset_hashes.dart`. Nó được tải một lần từ bản phát hành GitHub của `sqlite3.dart` và cache dưới `$XDG_CACHE_HOME` (nếu không có thì `~/.cache`; `%LOCALAPPDATA%` trên Windows), rồi `flutter_monorepo/sqlite3/<tag>/`. Mọi bản sao đều bị giữ theo hash: bản tải về khác hash bị từ chối, bản cache khác hash bị xoá, và file đã có sẵn mà khớp thì không bao giờ bị ghi lại. Khi offline (hoặc với `--offline`, và không có bản cache), lần chạy cảnh báo và bản build web không có database: hãy chạy `dart tools/composer/composer.dart runners --app <id> --platform web` khi có mạng, hoặc tự đặt file khớp vào. Nếu `sqlite3` đã resolve không đi kèm bảng hash, không gì kiểm chứng được: hãy tự đặt `sqlite3.wasm` được phát hành cho phiên bản đó vào runner web, và `runners` dùng nó kèm cảnh báo *not verified* ở mỗi lần chạy.
- **`drift_worker.js`** được biên dịch bằng `dart compile js -O4` từ `platform/infra/database/web/drift_worker.dart` (`WasmDatabase.workerMainForOpen()`), trong một thư mục tạm, và chỉ được chép vào khi byte của nó khác. Nguồn nằm ngoài `lib/`, nên barrel của package không bao giờ export nó.

**Không cách ly trên web.** Một database ở đó không phải là một file có thể dời đi: `DatabaseConnectionFactory.quarantineDatabaseFile` trả về `false`, và opener ném lại lỗi gốc — không mở lại, không log "data is lost" — cho đến khi dữ liệu của site bị xoá.

**Chỉ được chứng minh trên Chromium.** Boot test web chạy Chrome headless; các trình duyệt khác không được thử ở đây.

---

## Kiểm tra

```bash
dart run build_runner build --workspace   # <name>_database.g.dart, mixin của DAO, module.module.dart
flutter analyze                           # No issues found!
cd modules/cache/data && flutter test     # test tham chiếu: nâng cấp file cũ và round-trip repository
cd platform/infra/database && flutter test
cd apps/mobile && flutter test test/di_smoke_test.dart   # lệnh mở @preResolve thành công trong graph thật
```

Chạy test của package bạn theo cùng cách. Một migration mới cần một test mở schema cũ, chạy bước migration và đọc lại cột mới.

Checklist review:

- [ ] Bảng, DAO, class database và data source đều nằm trong **package sở hữu**
- [ ] Tên file database là hằng số trong `utils/` của package đó, đặt theo tên package
- [ ] `migration` uỷ quyền cho `driftMigrationStrategy` (đừng tự viết `MigrationStrategy`)
- [ ] Migration được **truyền vào** database, không bao giờ tự tra bên trong
- [ ] Hàm mở thu thập bước migration bằng `getAllOrEmpty<IDatabaseMigration<YourDatabase>>()`, không bao giờ dùng `getAll` trần
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
| Boot sập trong `configureDependencies()` khi không có migration nào | `getAll<T>()` ném lỗi khi không có gì được đăng ký | Thu thập bằng `getAllOrEmpty<IDatabaseMigration<YourDatabase>>()` (bước 7) |
| `UnsupportedError: Cannot downgrade the schema…` lúc khởi động | Một bản build cũ được cài đè lên schema mới hơn | Phát hành bước downgrade trước, hoặc cài lại bản mới hơn |
| Quan hệ không được ràng buộc | Một `MigrationStrategy` viết tay đã bỏ `foreign_keys = ON` | Uỷ quyền cho `driftMigrationStrategy` (bước 6) |
| File bị đổi tên thành `<name>.corrupt` | Lệnh mở phát hiện database hỏng và cách ly nó | Dữ liệu vẫn được giữ để phục hồi; xem [`../architecture/02_core.md` § 8](../architecture/02_core.md#phục-hồi-khi-hỏng-cách-ly-không-bao-giờ-xoá) |
| Test không chứng minh được WAL đang bật | Database in-memory báo `journal_mode = memory` | Test pragma trên một file thật (bước 12) |
| `arch_check` R22: *imports package:drift/native.dart, which uses dart:ffi …* | Một file `lib/` của package có thể chạy web import một thư viện chỉ-native | Chuyển import sang `test/`, hoặc nhận một executor như `forTesting` làm (bước 6) |
| Bản build web boot được, rồi database không mở được | Thiếu `sqlite3.wasm` hoặc `drift_worker.js` cạnh `index.html`, hoặc server gửi wasm không kèm `application/wasm` | Chạy `composer runners --app <id> --platform web`; phục vụ `.wasm` với `application/wasm` ([§ 13](#13-trên-web)) |
| Một database hỏng trên web cứ fail lúc boot | Web không cách ly được | Xoá dữ liệu của site trong trình duyệt ([§ 13](#13-trên-web)) |

## Liên quan

- Luật: RULE-41 (trả model, không trả row), RULE-46 (mỗi package sở hữu database của nó), RULE-47 (migration gắn kiểu với database của nó), RULE-82 (không thư viện chỉ-native trong `lib/` có thể chạy web, R22) — [`../reference/01_rules.md`](../reference/01_rules.md)
- [`../architecture/02_core.md` § 8](../architecture/02_core.md#8-core_database--lưu-trữ-quan-hệ-drift--sqlite) — thiết kế đứng sau cơ chế
- [`06_storage.md`](06_storage.md) — lưu trữ key-value, và khi nào nên dùng nó
- [`02_new_domain_data.md`](02_new_domain_data.md) — tầng repository và model phía trên DAO
- [`05_di.md`](05_di.md) — `@preResolve`, thứ tự module, `getAll` so với `getAllOrEmpty`
