<!-- translated-from: docs/en/guides/06_storage.md@b65f8b3 -->
# Hướng dẫn: Lưu trữ Key-Value

## Mục tiêu

Bạn lưu một giá trị — token, cờ, tuỳ chọn — sao cho nó sống sót qua các lần khởi động lại, và không package nào khác đọc hay ghi đè được nó. Bạn thêm giá trị đó từ đầu tới cuối, chọn backend cho nó, và phơi nó qua ranh giới package khi một package khác cần.

## Điều kiện cần

- Một package sẽ sở hữu giá trị (tầng data, hoặc app shell với tuỳ chọn UI).
- **`core_storage` hoạt động thế nào**: nó chỉ cấp cơ chế và không có key nào, nó mã hoá hai lần, nó che giá trị trong RAM, và nó không bao giờ xoá sạch kho khi gặp lỗi platform — [`../architecture/02_core.md` § 7](../architecture/02_core.md#7-core_storage--lưu-trữ-keyvalue-có-mã-hoá). Luật đứng sau: RULE-44.
- Cần bản ghi, truy vấn hay quan hệ thay vì một giá trị cho mỗi key? Hãy dùng database — [`07_database.md`](07_database.md).

---

## 1. Chọn backend

```dart
// platform/infra/storage/lib/src/contracts/storage_type.dart
enum StorageType {
  /// SharedPreferences storage (plain text with software-level encryption).
  pref,

  /// Hardware-backed secure storage.
  secure,
}
```

| Dùng `StorageType.secure` cho | Dùng `StorageType.pref` cho |
|---|---|
| Auth token, refresh token | Theme mode, locale |
| Profile người dùng được cache / dữ liệu cá nhân | Cờ "đã xem onboarding" |
| Mọi thứ kẻ tấn công cầm máy sẽ muốn lấy | Tuỳ chọn UI không nhạy cảm |

`secure` dựa trên Keychain (iOS) / KeyStore (Android), chậm hơn. `pref` dựa trên SharedPreferences. **Cả hai** đều áp lớp mã hoá AES bằng phần mềm, nên `pref` không phải plaintext trên đĩa.

## 2. Phụ thuộc vào `core_storage`

Package sở hữu khai báo nó trong `dependencies` (trong Pub workspace, một import không khai báo vẫn compile được nhờ `package_config.json` dùng chung; `arch_check` R5 mới là thứ bắt được nó), kèm injectable cho phần đăng ký. Như trong `modules/auth/data/pubspec.yaml`:

```yaml
dependencies:
  core_storage:
    path: ../../../platform/infra/storage
  injectable: ^3.0.0

dev_dependencies:
  build_runner: "^2.16.0"
  injectable_generator: "^3.1.3"
```

Chỉnh `path:` theo độ sâu của package bạn. Version lấy từ catalog `pubspec_dependencies.yaml` (`dart tools/dependency_sync.dart`). Sau đó `flutter pub get`.

## 3. Khai key trong `utils/` của package sở hữu

Không bao giờ đặt ở `core_common`, không bao giờ ở `core_storage` (RULE-09, RULE-44). Ví dụ xuyên suốt là auth token, thứ thật sự có trong repo:

```dart
// modules/auth/data/lib/src/utils/auth_storage_keys.dart
/// Physical storage keys owned exclusively by `feature_auth`'s data layer.
///
/// Package-internal by convention — no other package's pubspec declares a
/// dependency on `data_auth`, so nothing outside this package can reach
/// [AuthLocalDataSource] (or these keys) even though the barrel re-exports
/// them. Never reference these keys from another package.
class AuthStorageKeys {
  AuthStorageKeys._();

  static const String TOKEN = 'token';
  static const String AUTH_USER = 'auth_user';
}
```

Quy ước: private constructor, `UPPER_SNAKE_CASE`, mỗi package sở hữu một class.

## 4. Khai `StorageValue` bên trong class sở hữu

Inject `StorageManager`, chọn backend, trỏ vào key của bạn:

```dart
// modules/auth/data/lib/src/data_sources/local/auth_local_data_source.dart
@lazySingleton
class AuthLocalDataSource {
  AuthLocalDataSource(this._storageManager);

  final StorageManager _storageManager;

  late final _token = StorageValue<String>(
    _storageManager.getStorage(StorageType.secure),
    AuthStorageKeys.TOKEN,
  );

  late final _authUser = StorageValue<Map<String, dynamic>>(
    _storageManager.getStorage(StorageType.secure),
    AuthStorageKeys.AUTH_USER,
  );
```

Các field là `private` + `late final`: bên ngoài class không chạm được `StorageValue` thô, chỉ dùng được các method bạn chủ động phơi ra.

## 5. Đăng ký owner là singleton và nạp dữ liệu cho nó

```dart
  /// Hydrates the in-memory cache from disk at startup so synchronous
  /// getters below return correct values immediately.
  @PostConstruct(preResolve: true)
  Future<void> initialize() async {
    await Future.wait([_token.readFromStorage(), _authUser.readFromStorage()]);
  }
```

> [!CAUTION]
> Đăng ký owner là `@singleton` / `@lazySingleton` — **tuyệt đối không `@injectable`** (RULE-45). `@injectable` là factory: mỗi điểm inject dựng một instance *mới* với cache RAM rỗng. Khi đó getter đồng bộ trả `null` dù giá trị vẫn nằm trên đĩa. Hãy đi kèm `@PostConstruct(preResolve: true)`, để DI chờ đọc đĩa xong rồi mới giao đồ thị cho app.

## 6. Sinh phần đăng ký

```bash
dart run build_runner build --workspace
```

Phần đăng ký — kể cả việc `await` `initialize()` mà `preResolve` yêu cầu — nằm trong `lib/di/module.module.dart` được sinh ra của package, và chỉ ở đó. Chưa sinh lại thì owner đơn giản là chưa được đăng ký, và lần inject đầu tiên hỏng lúc boot với *"… is not registered"* — `flutter analyze` không thấy được. File mới còn cần chạy `dart tools/barrel_generator/generate.dart modules/<module>/<layer>/lib` sau đó.

## 7. Đọc và ghi giá trị

| Thành phần | Hành vi |
|---|---|
| `value` (get) | Đọc cache trong RAM. Đồng bộ. Trả `null` trước khi hydrate |
| `value = x` (set) | Cập nhật cache, đẩy vào stream, ghi xuống đĩa, `notifyListeners()` |
| `save(x)` | Bí danh của setter |
| `delete()` | Xoá cache và xoá key khỏi đĩa |
| `readFromStorage()` | Nạp cache từ đĩa. `await` nó trong `@PostConstruct` |
| `addListener(cb)` | `ChangeNotifier` — dùng với `Provider` / `ListenableBuilder` |
| `listen(cb)` | `Stream<T?>` broadcast — dùng trong BLoC hoặc Dart thuần |

```dart
_token.value = 'abc123';          // ghi: mã hoá, lưu đĩa, báo listener
final t = _token.value;           // đọc: tức thì, từ RAM
await _token.readFromStorage();   // hydrate lại từ đĩa
_token.delete();                  // xoá
```

Ghi xuống đĩa là fire-and-forget. Cache RAM cập nhật đồng bộ, nên đọc ngay sau khi ghi vẫn ra giá trị mới.

## 8. Lưu một enum hay một kiểu tuỳ biến

`StorageValue<T>` đọc lại trực tiếp `num`, `String`, `bool`, `Map<String, dynamic>` và list của các kiểu đó — `List<String>` được cast từng phần tử, không cần reviver. **Enum** được lưu bằng `name`, nên cần `reviver` để đổi tên về lại giá trị. **Mọi kiểu khác** được lưu qua `toJson()` và cần `reviver` để dựng lại; thiếu nó constructor ném `ArgumentError`. Mọi đường đọc/ghi dùng chung `StorageCodec` (`platform/infra/storage/lib/src/storage_codec.dart`), nên giá trị đọc ra đúng như lúc ghi.

**Enum:**

```dart
// platform/shell/adapters/lib/src/theme_storage_impl.dart
late final _themeMode = StorageValue<ThemeMode>(
  _storageManager.getStorage(StorageType.pref),
  ThemeStorageKeys.THEME_MODE,
  reviver: (key, value) {
    if (value == null) return ThemeMode.system;
    return ThemeMode.values.byName(value.toString());
  },
);
```

**Bool có giá trị mặc định rõ ràng:**

```dart
// platform/shell/adapters/lib/src/app_boot_storage.dart
late final viewedOnboard = StorageValue<bool>(
  _storageManager.getStorage(StorageType.pref),
  AppBootStorageKeys.VIEWED_ONBOARD,
  reviver: (key, value) {
    if (value == null) return false;
    return bool.tryParse(value.toString()) ?? false;
  },
);
```

`reviver` được gọi **một lần**, với giá trị gốc đã decode, và không bao giờ nhận `null` — giá trị không tồn tại được đọc thành `null` trước khi reviver chạy. Nhánh `value == null` ở trên chỉ là phòng thủ, không bắt buộc.

## 9. Chia sẻ giá trị qua ranh giới package

Một package không được phụ thuộc package khác chỉ để đọc giá trị lưu trữ của nó. Hãy khai một interface ở `core_di` và implement ở nơi dữ liệu thuộc về — đúng pattern đang dùng cho theme và ngôn ngữ:

```dart
// core_di khai hợp đồng (không để lọt kiểu của tầng storage)
abstract class IThemeStorage {
  ThemeMode getThemeMode();
  void saveThemeMode(ThemeMode mode);
}
```

```dart
// platform/shell/adapters/lib/src/theme_storage_impl.dart — owner implement nó
@Singleton(as: IThemeStorage)
class ThemeStorageImpl implements IThemeStorage {
  ThemeStorageImpl(this._storageManager);
  final StorageManager _storageManager;
  // ... _themeMode khai ở trên ...

  @override
  ThemeMode getThemeMode() {
    return _themeMode.value ?? ThemeMode.system;
  }

  @override
  void saveThemeMode(ThemeMode mode) {
    _themeMode.save(mode);
  }
}
```

Bên tiêu thụ (ở đây là `ThemeProvider` trong `core_base_ui`) chỉ phụ thuộc `IThemeStorage`. Nó không thấy key, không thấy backend, không thấy `StorageValue`.

> [!WARNING]
> Đăng ký impl `as: IThemeStorage` khiến nó **chỉ** phân giải được dưới kiểu `IThemeStorage`. GetIt **không** đi ngược chuỗi supertype, nên nếu cần một interface thứ hai trỏ về cùng instance thì phải bind tường minh bằng `@module`. Bỏ sót bước này thì SSL pinning âm thầm không hoạt động; xem [`08_networking.md`](08_networking.md#10-bật-ssl-pinning).

## 10. Chọn key không nằm trong danh sách dành riêng

`StorageInterface` từ chối những key mà tầng storage dùng cho chính nó:

```dart
// platform/infra/storage/lib/src/contracts/storage_interface.dart
static const _reservedKeys = {
  '_internal_master_key',
  '_internal_pref_master_key',
  'firstTimeOpenApp',
};

bool isValidKey(String key) {
  if (_reservedKeys.contains(key) || key.startsWith('_internal_')) {
    return false;
  }
  return true;
}
```

Mọi key bắt đầu bằng `_internal_` đều bị từ chối. Constructor của `StorageValue` gọi `isValidKey` và ném `ArgumentError('Access to reserved key "..." is forbidden.')`, nên key sai sẽ lỗi **ngay lúc dựng object** chứ không âm thầm lúc chạy.

---

## Kiểm tra

```bash
dart run build_runner build --workspace                  # phần đăng ký owner, kèm initialize() được await
flutter analyze                                          # No issues found!
cd platform/infra/storage && flutter test                # test của chính cơ chế storage
cd apps/mobile && flutter test test/di_smoke_test.dart   # owner resolve được và được nạp (storage trong bộ nhớ)
```

Trên thiết bị, hãy ghi giá trị, tắt hẳn app, rồi mở lại: giá trị phải đọc ra được một cách đồng bộ ngay ở frame đầu tiên. `grep -rn "_storageManager.getStorage" modules platform` liệt kê mọi owner, để bạn kiểm tra không có package thứ hai nào khai key của bạn.

Checklist review:

- [ ] Class key nằm trong `utils/` của package sở hữu, private constructor, `UPPER_SNAKE_CASE`
- [ ] Field `StorageValue` là private và `late final` bên trong owner
- [ ] Backend được chọn có chủ đích (`secure` cho mọi thứ nhạy cảm)
- [ ] Owner là **singleton**, không phải `@injectable`
- [ ] `@PostConstruct(preResolve: true)` có `await` `readFromStorage()`
- [ ] Có `reviver` cho enum hoặc kiểu tuỳ biến (kiểu nguyên thuỷ, `Map<String, dynamic>` và list có kiểu thì không cần)
- [ ] Truy cập xuyên package đi qua interface ở `core_di`, không bao giờ phụ thuộc trực tiếp
- [ ] Key không bắt đầu bằng `_internal_`

## Xử lý sự cố

| Triệu chứng | Nguyên nhân | Cách sửa |
|:--|:--|:--|
| Getter trả `null` dù giá trị có trên đĩa | Owner là `@injectable`, hoặc `readFromStorage()` không được await trong `@PostConstruct(preResolve: true)` | Đổi thành singleton và nạp dữ liệu cho nó (bước 5) |
| `ArgumentError: Access to reserved key "…" is forbidden.` | Key nằm trong danh sách dành riêng hoặc bắt đầu bằng `_internal_` | Đổi tên key (bước 10) |
| `ArgumentError` khi dựng `StorageValue` cho một kiểu tuỳ biến | Không có `reviver` | Thêm một `reviver` (bước 8) |
| `… is not registered` cho owner lúc boot | Chưa chạy codegen từ khi thêm annotation | `dart run build_runner build --workspace` (bước 6) |
| Một package khác import package data của bạn để đọc giá trị | Không có hợp đồng ở ranh giới | Khai một interface ở `core_di` và implement nó trong owner (bước 9) |
| Mọi giá trị đã lưu biến mất sau khi nâng cấp từ `flutter_secure_storage` 9.x trở xuống | 11.x đã bỏ các cipher trước bản 10 | Phát hành một bản 10.x trước ([`../architecture/02_core.md` § 7](../architecture/02_core.md#tuỳ-chọn-cipher-của-plugin-được-ghim-cố-định)) |

## Liên quan

- Luật: RULE-09 (key trong `utils/`), RULE-44 (không có key dùng chung), RULE-45 (owner là singleton, được nạp sẵn), RULE-14 (interface thứ hai qua `@module`) — [`../reference/01_rules.md`](../reference/01_rules.md)
- [`../architecture/02_core.md` § 7](../architecture/02_core.md#7-core_storage--lưu-trữ-keyvalue-có-mã-hoá) — mã hoá, che RAM, xử lý lỗi, các owner hiện tại
- [`05_di.md`](05_di.md) — singleton hay factory, `@PostConstruct`, thứ tự module
- [`07_database.md`](07_database.md) — khi nào bảng quan hệ tốt hơn cặp key-value
