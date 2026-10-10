<!-- translated-from: docs/en/guides/06_storage.md@4b2b033 -->
# Hướng dẫn: Lưu trữ Key-Value

## Mục tiêu

Bạn lưu một giá trị — token, cờ, tuỳ chọn — sao cho nó sống sót qua các lần khởi động lại, và không package nào khác đọc hay ghi đè được nó. Bạn thêm giá trị đó từ đầu tới cuối, chọn backend cho nó, và phơi nó qua ranh giới package khi một package khác cần.

## Điều kiện cần

- Một package sẽ sở hữu giá trị (tầng data, hoặc app shell với tuỳ chọn UI).
- **`core_storage` hoạt động thế nào**: nó chỉ cấp cơ chế và không có key nào, nó mã hoá hai lần, nó che giá trị trong RAM (vệ sinh dữ liệu, không phải bảo vệ), và nó không bao giờ xoá sạch kho khi gặp lỗi platform — [`../architecture/02_core.md` § 7](../architecture/02_core.md#7-core_storage--lưu-trữ-keyvalue-có-mã-hoá). Các luật đứng sau: RULE-44 (không có key dùng chung), RULE-45 (owner là singleton).
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

`secure` dựa trên Keychain (iOS) / KeyStore (Android), chậm hơn. `pref` dựa trên SharedPreferences. Cả hai backend (`SecureStorageImpl`, `PrefStorageImpl`) đều kế thừa `EncryptedStorage`, thứ niêm phong mọi giá trị bằng AES-256-CBC trước khi ghi, nên `pref` không phải plaintext trên đĩa. Việc niêm phong chỉ là bảo mật nội dung — AES-CBC không có xác thực, nên một giá trị bị sửa không bị phát hiện là bị giả mạo; đừng dùng storage để chứng minh ai đã ghi một giá trị. Bạn không bao giờ chạm trực tiếp vào backend: bạn xin `StorageManager.getStorage(type)` một `StorageInterface` rồi bọc nó trong một `StorageValue`.

## 2. Phụ thuộc vào `core_storage`

Package sở hữu khai báo nó trong `dependencies` (trong Pub workspace, một import không khai báo vẫn compile được nhờ `package_config.json` dùng chung; `arch_check` R5 mới là thứ bắt được nó), kèm injectable cho phần đăng ký. Như `modules/auth/data/pubspec.yaml` làm:

```yaml
dependencies:
  core_storage:
    path: ../../../platform/infra/storage
  injectable:

dev_dependencies:
  build_runner:
  injectable_generator:
```

Chỉnh `path:` theo độ sâu của package bạn. Đừng ghi version: chúng chỉ nằm trong catalog `pubspec_dependencies.yaml` (RULE-74), và `dart tools/dependency_sync.dart` điền vào mục còn trống. Sau đó `flutter pub get`.

## 3. Khai key trong `utils/` của package sở hữu

Không bao giờ đặt ở `core_common`, không bao giờ ở `core_storage` (RULE-09, RULE-44). Ví dụ xuyên suốt là auth token, thứ thật sự có trong repo:

```dart
// modules/auth/data/lib/src/utils/auth_constants.dart
/// Physical storage keys owned by `data_auth` — no other package reads them.
class AuthStorageKeys {
  AuthStorageKeys._();

  static const String TOKEN = 'token';
}
```

Cùng file đó chứa `AuthApiConstants`, các endpoint của package: RULE-09 cho phép key và endpoint nằm chung một `<owner>_constants.dart`, hoặc mỗi loại một file. Quy ước: private constructor, `UPPER_SNAKE_CASE`, mỗi owner một class key. Các owner của shell theo đúng quy ước này trong `platform/shell/adapters/lib/src/utils/` (`ThemeStorageKeys`, `LanguageStorageKeys`, `AppBootStorageKeys`). Một key là tên vật lý đã được ghi trên máy người dùng: đổi tên nó là làm mồ côi những gì đang lưu dưới tên cũ.

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
```

Các field là `private` + `late final`: bên ngoài class không chạm được `StorageValue` thô, chỉ dùng được các method bạn chủ động phơi ra.

## 5. Đăng ký owner là singleton và nạp dữ liệu cho nó

```dart
  /// Hydrates the cache from disk at startup, so [getUserToken] is correct from
  /// the first read.
  @PostConstruct(preResolve: true)
  Future<void> initialize() => _token.readFromStorage();
```

Owner có nhiều giá trị thì nạp chúng cùng lúc: `await Future.wait([_a.readFromStorage(), _b.readFromStorage()])`.

> [!CAUTION]
> Đăng ký owner là `@singleton` / `@lazySingleton` — **tuyệt đối không `@injectable`** (RULE-45). `@injectable` là factory: mỗi điểm inject dựng một instance *mới* với cache RAM rỗng. Khi đó getter đồng bộ trả `null` dù giá trị vẫn nằm trên đĩa. Hãy đi kèm `@PostConstruct(preResolve: true)`, để DI chờ đọc đĩa xong rồi mới giao đồ thị cho app.

## 6. Sinh phần đăng ký

```bash
dart run build_runner build --workspace
```

Phần đăng ký — kể cả việc `await` `initialize()` mà `preResolve` yêu cầu — nằm trong `lib/di/module.module.dart` được sinh ra của package, và chỉ ở đó. Chưa sinh lại thì owner đơn giản là chưa được đăng ký, và lần inject đầu tiên hỏng lúc boot với *"… is not registered"* — `flutter analyze` không thấy được. File mới dưới `lib/` còn cần chạy `dart tools/barrel_generator/generate.dart modules/<module>/<layer>/lib` sau đó (RULE-75).

## 7. Đọc và ghi giá trị

| Thành phần | Hành vi |
|---|---|
| `value` (get) | Đọc cache trong RAM, decode ở mỗi lần truy cập. Đồng bộ. Trả `null` trước khi hydrate |
| `value = x` (set) | Cập nhật cache, đẩy vào stream và `notifyListeners()` ngay, và **bắt đầu** ghi xuống đĩa mà không chờ (`null` xoá key) |
| `save(x)` | Như trên, nhưng trả `Future<void>` hoàn tất khi giá trị đã nằm trên đĩa |
| `remove()` | Xoá cache và báo listener ngay; `Future<void>` hoàn tất khi key đã bị xoá khỏi đĩa |
| `readFromStorage()` | Nạp cache từ đĩa và báo listener. `await` nó trong `@PostConstruct` |
| `addListener(cb)` | `ChangeNotifier` — dùng với `Provider` / `ListenableBuilder` |
| `listen(cb)` | `Stream<T?>` broadcast — dùng trong BLoC hoặc Dart thuần |

```dart
_token.value = 'abc123';          // ghi: cache và listener ngay, đĩa theo kiểu fire-and-forget
await _token.save('abc123');      // như trên, và chờ đến khi đã nằm trên đĩa
final t = _token.value;           // đọc: tức thì, từ RAM
await _token.readFromStorage();   // hydrate lại từ đĩa
await _token.remove();            // xoá, và chờ đến khi đã xoá khỏi đĩa
```

Cache RAM cập nhật đồng bộ, nên đọc ngay sau khi ghi vẫn ra giá trị mới. Các lần ghi được **tuần tự hoá**: mỗi lần chỉ bắt đầu sau khi lần trước xong, nên giá trị được set sau cùng là giá trị còn lại trên đĩa. Một lần ghi hỏng được log qua `DynamicLogger` và không bao giờ bị ném — cache đã giữ giá trị mới, và một lỗi storage không được biến thành lỗi zone không bắt. Hãy dùng `save` / `remove` khi bên gọi cần biết giá trị đã được lưu bền (`AuthLocalDataSource.saveUserToken` trả về future); dùng setter khi chỉ cache mới quan trọng.

## 8. Lưu một enum hay một kiểu tuỳ biến

`StorageValue<T>` đọc lại trực tiếp `num`, `String`, `bool`, `Map<String, dynamic>` và list của các kiểu đó — `List<String>` được cast từng phần tử, không cần reviver. **Enum** được lưu bằng `name`, nên cần `reviver` để đổi tên về lại giá trị. **Mọi kiểu khác** được lưu qua `toJson()` và cần `reviver` để dựng lại; thiếu nó constructor ném `ArgumentError`. Mọi đường đọc/ghi dùng chung `StorageCodec` (`platform/infra/storage/lib/src/storage_codec.dart`), nên giá trị đọc ra đúng như lúc ghi.

**Enum:**

```dart
// platform/shell/adapters/lib/src/theme_storage_impl.dart
late final _themeMode = StorageValue<ThemeMode>(
  _storageManager.getStorage(StorageType.pref),
  ThemeStorageKeys.THEME_MODE,
  reviver: (key, value) {
    if (value == null) return _defaultMode;
    return ThemeMode.values.byName(value.toString());
  },
);
```

**Bool có giá trị mặc định rõ ràng**, giữ private và phơi ra qua một getter và một method (RULE-44):

```dart
// platform/shell/adapters/lib/src/app_boot_storage.dart
late final _viewedOnboard = StorageValue<bool>(
  _storageManager.getStorage(StorageType.pref),
  AppBootStorageKeys.VIEWED_ONBOARD,
  reviver: (key, value) {
    if (value == null) return false;
    return bool.tryParse(value.toString()) ?? false;
  },
);

// …

bool get viewedOnboard => _viewedOnboard.value ?? false;

/// Records that the entry location has been shown. The in-memory value
/// changes at once; the returned future completes when it is persisted.
Future<void> markOnboardViewed() => _viewedOnboard.save(true);
```

`reviver` được gọi **một lần cho mỗi lần decode**, với giá trị gốc đã decode — không phải cho từng nút của cây — và không bao giờ nhận `null`: giá trị không tồn tại được đọc thành `null` trước khi reviver chạy. Mỗi lần đọc `value` lại decode JSON trong cache một lần nữa, nên reviver chạy ở mỗi lần đọc cũng như ở `readFromStorage()`; hãy giữ nó không có side effect. Nhánh `value == null` ở trên chỉ là phòng thủ, không bắt buộc.

## 9. Chia sẻ giá trị qua ranh giới package

Một package không được phụ thuộc package khác chỉ để đọc giá trị lưu trữ của nó, và `StorageValue` luôn private trong owner của nó (RULE-44). Hãy phơi một interface ra, và implement nó ở nơi dữ liệu thuộc về. Interface đặt ở đâu tuỳ giá trị đó của ai:

- **Trung lập với sản phẩm** (app nào cũng có, không module nào sở hữu) — đặt trong `core_di`. `IThemeStorage` và `ILanguageStorage` do shell adapter implement và `core_base_ui` đọc.
- **Thuộc về một module** — đặt trong package `<id>_api` của chính module đó, cạnh navigator và action handler của nó, để `core_di` trung lập không bao giờ biết tới một module có thể gỡ (RULE-04, RULE-44).

Theme là ví dụ thật của loại thứ nhất:

```dart
// platform/foundation/contracts/lib/src/i_theme_storage.dart — không để lọt kiểu của tầng storage
abstract class IThemeStorage {
  /// Gets the current ThemeMode from storage.
  ThemeMode getThemeMode();
  /// Saves the given ThemeMode to storage.
  void saveThemeMode(ThemeMode mode);
}
```

```dart
// platform/shell/adapters/lib/src/theme_storage_impl.dart — owner implement nó
@Singleton(as: IThemeStorage)
class ThemeStorageImpl implements IThemeStorage {
  // ... constructor nhận StorageManager và ThemeProfile của app; _themeMode khai ở trên,
  // được nạp trong @PostConstruct(preResolve: true) ...

  @override
  ThemeMode getThemeMode() {
    return _themeMode.value ?? _defaultMode;
  }

  @override
  void saveThemeMode(ThemeMode mode) {
    _themeMode.save(mode);
  }
}
```

Bên tiêu thụ (ở đây là `ThemeProvider` trong `core_base_ui`) chỉ phụ thuộc `IThemeStorage`. Nó không thấy key, không thấy backend, không thấy `StorageValue`.

> [!WARNING]
> Đăng ký impl `as: IThemeStorage` khiến nó **chỉ** phân giải được dưới kiểu `IThemeStorage`. GetIt **không** đi ngược chuỗi supertype, nên nếu cần một interface thứ hai trỏ về cùng instance thì phải bind tường minh bằng `@module` (RULE-14); xem [`05_di.md`](05_di.md#4-bind-interface-thứ-hai-vào-cùng-một-instance).

## 10. Chọn key không nằm trong danh sách dành riêng

Các backend từ chối những key mà tầng storage dùng cho chính nó. `StorageInterface.isValidKey` là hợp đồng; `EncryptedStorage` implement nó cho cả hai backend từ các hằng số trong `StorageConstants`:

```dart
// platform/infra/storage/lib/src/impl/encrypted_storage.dart
@override
bool isValidKey(String key) =>
    key != StorageConstants.FIRST_TIME_OPEN_APP &&
    !key.startsWith(StorageConstants.INTERNAL_KEY_PREFIX);
```

`FIRST_TIME_OPEN_APP` là `firstTimeOpenApp` và `INTERNAL_KEY_PREFIX` là `_internal_` (các master key là `_internal_master_key` và `_internal_pref_master_key`), nên mọi key bắt đầu bằng `_internal_` đều bị từ chối. Constructor của `StorageValue` gọi `isValidKey` và ném `ArgumentError('Access to reserved key "..." is forbidden.')`, nên key sai sẽ lỗi **ngay lúc dựng object** chứ không âm thầm lúc chạy.

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
- [ ] Truy cập xuyên package đi qua một interface (`core_di` khi trung lập với sản phẩm, `<id>_api` của owner khi thuộc về một module), không bao giờ phụ thuộc trực tiếp
- [ ] Lần ghi mà bên gọi phải chắc chắn thì dùng `save` / `remove` và `await` nó
- [ ] Key không bắt đầu bằng `_internal_`

## Xử lý sự cố

| Triệu chứng | Nguyên nhân | Cách sửa |
|:--|:--|:--|
| Getter trả `null` dù giá trị có trên đĩa | Owner là `@injectable`, hoặc `readFromStorage()` không được await trong `@PostConstruct(preResolve: true)` | Đổi thành singleton và nạp dữ liệu cho nó (bước 5) |
| `ArgumentError: Access to reserved key "…" is forbidden.` | Key nằm trong danh sách dành riêng hoặc bắt đầu bằng `_internal_` | Đổi tên key (bước 10) |
| `ArgumentError` khi dựng `StorageValue` cho một kiểu tuỳ biến | Không có `reviver` | Thêm một `reviver` (bước 8) |
| Giá trị vừa set ngay trước khi app bị tắt biến mất ở lần mở sau | Setter (hoặc một `save` không được await) chỉ bắt đầu ghi và tiến trình đã kết thúc trước | `await` `save` / `remove` ở chỗ giá trị phải sống sót (bước 7) |
| `… is not registered` cho owner lúc boot | Chưa chạy codegen từ khi thêm annotation | `dart run build_runner build --workspace` (bước 6) |
| Một package khác import package data của bạn để đọc giá trị | Không có hợp đồng ở ranh giới | Khai một interface (`core_di`, hoặc `<id>_api` của owner) và implement nó trong owner (bước 9) |
| Mọi giá trị đã lưu biến mất sau khi nâng cấp từ `flutter_secure_storage` 9.x trở xuống | 11.x đã bỏ các cipher trước bản 10 | Phát hành một bản 10.x trước ([`../architecture/02_core.md` § 7](../architecture/02_core.md#tuỳ-chọn-cipher-của-plugin-được-ghim-cố-định)) |

## Liên quan

- Luật: RULE-09 (key trong `utils/`), RULE-44 (không có key dùng chung, vị trí đặt interface), RULE-45 (owner là singleton, được nạp sẵn), RULE-14 (interface thứ hai qua `@module`), RULE-74 (version chỉ nằm trong catalog) — [`../reference/01_rules.md`](../reference/01_rules.md)
- [`../architecture/02_core.md` § 7](../architecture/02_core.md#7-core_storage--lưu-trữ-keyvalue-có-mã-hoá) — mã hoá, che RAM, xử lý lỗi, các owner hiện tại
- [`05_di.md`](05_di.md) — singleton hay factory, `@PostConstruct`, thứ tự module
- [`07_database.md`](07_database.md) — khi nào bảng quan hệ tốt hơn cặp key-value
