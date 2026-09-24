# Hướng dẫn: Lưu trữ Key-Value

**File này trả lời:** làm sao lưu một giá trị (token, cờ, tuỳ chọn) để nó sống sót qua các lần khởi động lại — và làm sao để không package nào khác đọc hay ghi đè được nó.

**Đọc xong bạn làm được:** thêm một giá trị lưu trữ mới từ đầu đến cuối, chọn đúng backend, chia sẻ nó qua ranh giới package, và giải thích được vì sao nó được mã hoá hai lớp.

---

## 1. `core_storage` cấp cơ chế, không phải chỗ đổ key

`core_storage` cố ý khai báo **zero key**. Nó chỉ cấp bộ máy; mỗi package tự khai giá trị của mình.

```dart
// platform/infra/storage/lib/core_storage.dart
/// Core Storage — encrypted key-value persistence layer.
///
/// Provides only the storage MECHANISM — no package/feature-specific keys
/// or presets are defined here. Each consumer (data layer, app shell, ...)
/// must declare its own [StorageValue] instances with its own keys via
/// [StorageManager], so no other feature can see or touch its data.
```

| Thành phần export | Loại | Dùng để làm gì |
|---|---|---|
| `StorageInterface` | abstract class | Hợp đồng cho mọi backend; đồng thời chứa helper AES và bộ chặn key dành riêng |
| `StorageManager` | `@singleton` | Phân giải backend theo `StorageType`; khởi tạo mọi backend một lần lúc boot |
| `StorageValue<T>` | class | Bọc **một** key: cache RAM + ghi đĩa + `ChangeNotifier` + `Stream` |
| `StorageType` | enum | `pref` \| `secure` |
| `ObfuscatedBytes` / `ObfuscatedString` | class | Che dữ liệu trong RAM bằng XOR (xem §3) |
| `PrefStorageImpl` | `@Named('Pref')` | Backend SharedPreferences — nội bộ, DI phân giải |
| `SecureStorageImpl` | `@Named('Secure')` | Backend FlutterSecureStorage — nội bộ, DI phân giải |

> [!NOTE]
> Không có object preset dùng chung và không có sổ đăng ký key tập trung — không `StorageValuePresets`, không `StorageKeyConstants`. Một object gom key của mọi domain sẽ cho phép bất kỳ ai inject nó đọc và ghi dữ liệu của feature khác, nên cơ chế cố ý không cung cấp thứ đó để bạn với tay tới.

---

## 2. Chọn backend nào?

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
| Token đăng nhập, refresh token | Theme mode, ngôn ngữ |
| Hồ sơ người dùng đã cache / PII | Cờ "đã xem onboarding" |
| Bất cứ thứ gì kẻ cầm được máy sẽ muốn lấy | Tuỳ chọn UI không nhạy cảm |

`secure` dựa trên Keychain (iOS) / KeyStore (Android), chậm hơn. `pref` dựa trên SharedPreferences. **Cả hai** đều đi qua lớp AES phần mềm mô tả bên dưới — `pref` không hề là plaintext trên đĩa.

---

## 3. Hai lớp mã hoá, cộng thêm che RAM

**Lớp 1 — AES-256-CBC phần mềm, IV ngẫu nhiên mỗi lần ghi.** Cài đặt một lần trên `StorageInterface` nên cả hai backend đều thừa hưởng:

```dart
// platform/infra/storage/lib/src/contracts/storage_interface.dart
/// Encrypt [data] using AES-CBC with a random IV.
///
/// Returns `"iv_base64:ciphertext_base64"`.
String encryptData(String data) {
  final rawBytes = _obfuscatedMasterKey!.reveal();
  final key = encrypter.Key(rawBytes);
  final aes = encrypter.AES(key, mode: encrypter.AESMode.cbc);
  final enc = encrypter.Encrypter(aes);

  final iv = encrypter.IV.fromSecureRandom(16);
  final encrypted = enc.encrypt(data, iv: iv);

  // Zero out key buffers immediately
  rawBytes.fillRange(0, rawBytes.length, 0);
  key.bytes.fillRange(0, key.bytes.length, 0);

  return '${iv.base64}:${encrypted.base64}';
}
```

IV ngẫu nhiên mỗi lần ghi nghĩa là ghi cùng một giá trị hai lần vẫn ra ciphertext khác nhau — người quan sát không thể biết giá trị có đổi hay không.

**Lớp 2 — phần cứng.** Master key 256-bit nằm trong Keychain/KeyStore dưới key `_internal_master_key`, sinh ra ở lần chạy đầu tiên:

```dart
// platform/infra/storage/lib/src/impl/secure/secure_storage_impl.dart
if (masterKey == null) {
  // Generate a new 32-byte (256-bit) random key for AES
  final newKey = encrypter.Key.fromSecureRandom(_MASTER_KEY_BYTES).base64;
  await _storage.write(key: _MASTER_KEY_ID, value: newKey); // lỗi thì ném lại
  masterKey = newKey;
}
```

**Lớp 3 (ít nơi nhắc tới) — che trong RAM.** Cả master key lẫn giá trị đã cache đều không nằm trong bộ nhớ dưới dạng byte đọc được. Chúng bị XOR với mask ngẫu nhiên, và chỉ lộ ra đúng khoảnh khắc được dùng:

```dart
// platform/infra/storage/lib/src/contracts/storage_interface.dart
/// Container that obfuscates bytes in RAM using dynamic XOR masking.
class ObfuscatedBytes {
  ObfuscatedBytes(Uint8List originalBytes)
    : _mask = _generateRandomMask(originalBytes.length),
      _maskedBytes = Uint8List(originalBytes.length) {
    for (int i = 0; i < originalBytes.length; i++) {
      _maskedBytes[i] = originalBytes[i] ^ _mask[i];
    }
  }
```

`ObfuscatedString` (trong `storage_value.dart`) làm điều tương tự cho giá trị đã cache. Việc này nâng độ khó của tấn công memory-dump; nó **không** thay thế được hai lớp trên.

### Khi Keychain trục trặc — thử lại, không bao giờ xoá sạch

Việc đọc master key có thể lỗi vì những lý do nhất thời: Keychain trước lần mở khoá đầu tiên sau khi khởi động lại máy (app được mở nền), KeyStore đang bận. Trước đây `SecureStorageImpl` coi *mọi* lỗi như vậy là hỏng dữ liệu và gọi `deleteAll()` — xoá sạch mọi giá trị bảo mật, kể cả master key của `PrefStorageImpl` vốn nằm trong cùng kho. Giờ thì:

```dart
// platform/infra/storage/lib/src/impl/secure/secure_storage_impl.dart
Future<String?> _readMasterKey() async {
  for (var attempt = 1; ; attempt++) {
    try {
      return await _storage.read(key: _MASTER_KEY_ID);
    } catch (e) {
      final lastAttempt = attempt >= _MASTER_KEY_READ_ATTEMPTS;
      // … ghi log: WARNING khi thử lại, ERROR ở lần cuối …
      if (lastAttempt) rethrow; // không xoá gì, không sinh key mới
      await Future<void>.delayed(_retryDelay * attempt);
    }
  }
}
```

| Lỗi | Điều xảy ra |
| :-- | :-- |
| Lỗi platform khi đọc master key | thử lại (3 lần); nếu vẫn lỗi, `init` **ném lại lỗi** và kho giữ nguyên — sinh key mới sẽ bỏ rơi mọi giá trị đã mã hoá bằng key không đọc được |
| Master key có nhưng không dùng được (không phải key base64 256-bit) | chỉ thay key đó; các giá trị mã hoá bằng nó sẽ giải mã lỗi và bị `read()` xoá từng cái một |
| Hỏng dữ liệu trong chính storage của plugin | xử lý ở tầng native: trên Android `AndroidOptions.resetOnError` (bật mặc định) reset phần không giải mã được trước khi trả kết quả |
| Lỗi platform trong `read(key)` | trả `null` **và giữ nguyên giá trị** — lần đọc sau vẫn còn |
| Giá trị giải mã hoặc decode lỗi trong `read(key)` | chỉ xoá đúng key đó và trả `null`, để một dòng hỏng không làm chết mọi lần mở app |

### Master key của backend pref — cùng một quy tắc

`PrefStorageImpl` mã hoá giá trị SharedPreferences bằng master key riêng, `_internal_pref_master_key`, cất trong cùng kho bảo mật. Trước đây gặp *bất kỳ* lỗi đọc nào nó cũng lùi về một key hoàn toàn mới trong SharedPreferences — chỉ sau một lỗi Keychain nhất thời, mọi preference đã lưu (theme, ngôn ngữ, cờ onboarding) giải mã lỗi và bị xoá ở lần đọc kế tiếp, còn lần khởi động bình thường sau đó lại bỏ rơi những gì phiên lỗi kia đã ghi. Giờ nó không bao giờ thay một key có thể vẫn còn tốt:

| Tình huống | `PrefStorageImpl.init` làm gì |
| :-- | :-- |
| Lỗi platform khi đọc key | thử lại (3 lần) trước khi quyết định bất cứ điều gì |
| Vẫn lỗi, chưa có preference nào được lưu | giữ một key mới trong SharedPreferences — không có gì để bỏ rơi |
| Vẫn lỗi, và key trong SharedPreferences mở được các preference đã lưu | dùng key đó (thiết bị không có kho bảo mật dùng được) |
| Vẫn lỗi, và các preference đã lưu phụ thuộc vào key không đọc được | **ném lại lỗi**, không ghi hay xoá gì — các giá trị mở lại được khi platform hồi phục |
| Đọc được lại trong khi vẫn còn key trong SharedPreferences | key nào giải mã được các giá trị đã lưu thì thắng; nếu key trong SharedPreferences thắng, nó được chuyển vào kho bảo mật và xoá khỏi SharedPreferences |
| Key không có hoặc không dùng được (không phải key base64 256-bit) | sinh key mới — trong kho bảo mật, hoặc trong SharedPreferences nếu kho bảo mật từ chối ghi; giá trị mã hoá bằng key đã mất sẽ bị `read()` xoá từng cái một |

`StorageManager.initialize` chạy backend secure trước, nên một lỗi Keychain kéo dài thường lộ ra ở đó trước khi tới lượt backend pref. Test (`platform/infra/storage/test/storage_test.dart`) chạy cả hai backend qua một bản giả `FlutterSecureStorage` chập chờn.

### Tuỳ chọn cipher của plugin được ghim cố định

Cả hai backend mở `flutter_secure_storage` (11.x) với cùng một cặp Android tường minh — `KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding` và `StorageCipherAlgorithm.AES_GCM_NoPadding` — và `KeychainAccessibility.first_unlock` trên iOS. Trên Android, plugin ghi lại cặp nó đã dùng để ghi và, khi cặp được cấu hình khác đi, sẽ mã hoá lại toàn bộ store (`migrateOnAlgorithmChange`, mặc định bật) hoặc, nếu không được, reset nó (`resetOnError`, cũng bật). Đừng đổi hai tuỳ chọn này trừ khi bạn thật sự muốn migrate dữ liệu bảo mật của mọi người dùng.

Cặp này là thứ template đã ghi từ bản phát hành đầu tiên (10.x) và vẫn là mặc định của 11.x, nên nâng cấp 10 → 11 đọc được giá trị cũ nguyên vẹn: cùng alias KeyStore, cùng khoá đã bọc, không có bước migrate. Cái 11.x bỏ đi là các cipher trước 10 (RSA-PKCS1, AES-CBC, EncryptedSharedPreferences). App nào từng phát hành `flutter_secure_storage` 9.x trở xuống phải phát hành một bản 10.x trước — thiết bị nhảy thẳng từ 9 lên 11 sẽ mất giá trị bảo mật, gồm cả token và master key của `PrefStorageImpl`. Trên Android, `FlutterSecureStorage.checkUpgradeStatus()` (11.1+), gọi trước lần đọc đầu tiên, báo cho bạn biết điều đó có xảy ra hay không.

---

## 4. Cách thêm một giá trị lưu trữ mới (công thức chính)

Ba bước, mở đầu bằng khai dependency và kết thúc bằng chạy codegen. Ví dụ minh hoạ là auth token — có thật trong repo.

### Bước 0 — phụ thuộc vào `core_storage`

Package sở hữu khai nó trong `dependencies` (trong Pub workspace, một import không khai báo vẫn compile được nhờ `package_config.json` dùng chung; `arch_check` R5 mới là thứ bắt được nó), kèm injectable cho phần đăng ký. Như trong `modules/auth/data/pubspec.yaml`:

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

### Bước 1 — khai key trong `utils/` của package **SỞ HỮU**

Không bao giờ đặt ở `core_common`, không bao giờ ở `core_storage`.

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

### Bước 2 — khai `StorageValue` bên trong class owner

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

### Bước 3 — đăng ký singleton và hydrate

```dart
  /// Hydrates the in-memory cache from disk at startup so synchronous
  /// getters below return correct values immediately.
  @PostConstruct(preResolve: true)
  Future<void> initialize() async {
    await Future.wait([_token.readFromStorage(), _authUser.readFromStorage()]);
  }
```

> [!CAUTION]
> Đăng ký owner là `@singleton` / `@lazySingleton` — **tuyệt đối không `@injectable`**. `@injectable` là factory: mỗi chỗ inject sẽ dựng một instance *mới* với cache RAM **rỗng**, nên getter đồng bộ trả `null` dù giá trị vẫn nằm trên đĩa. Đi kèm `@PostConstruct(preResolve: true)` để DI **chờ** đọc đĩa xong rồi mới trao đồ thị phụ thuộc cho app.

### Bước 4 — sinh code

```bash
dart run build_runner build --workspace
```

Phần đăng ký — kể cả việc `await` `initialize()` mà `preResolve` yêu cầu — nằm trong `lib/di/module.module.dart` được sinh ra của package, và chỉ ở đó. Chưa sinh lại thì owner đơn giản là chưa được đăng ký, và lần inject đầu tiên hỏng lúc boot với *"… is not registered"* — `flutter analyze` không thấy được. File mới còn cần chạy `dart tools/barrel_generator/generate.dart modules/<module>/<layer>/lib` sau đó.

---

## 5. Ai đang sở hữu cái gì

| Owner | Package | Key | Backend |
|---|---|---|---|
| `AuthLocalDataSource` | `data_auth` | `token`, `auth_user` | `secure` |
| `ThemeStorageImpl` | app shell (`platform/shell/adapters/lib/src/`) | `themeMode` | `pref` |
| `LanguageStorageImpl` | app shell (`platform/shell/adapters/lib/src/`) | `locale` | `pref` |
| `AppBootStorage` | app shell (`platform/shell/adapters/lib/src/`) | `viewed_onboard` | `pref` |

Class key của app shell nằm ở `platform/shell/adapters/lib/src/utils/`.


---

## 6. Kiểu phức tạp cần `reviver`

`StorageValue<T>` đọc lại trực tiếp `num`, `String`, `bool`, `Map<String, dynamic>` và list của các kiểu đó — `List<String>` được cast từng phần tử, không cần reviver. **Enum** được lưu bằng `name`, nên cần `reviver` để đổi tên về lại giá trị. **Mọi kiểu khác** được lưu qua `toJson()` và cần `reviver` để dựng lại; thiếu nó constructor ném `ArgumentError`. Mọi đường đọc/ghi dùng chung `StorageCodec` (`platform/infra/storage/lib/src/contracts/storage_codec.dart`), nên giá trị đọc ra đúng như lúc ghi.

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

---

## 7. API của `StorageValue`

| Thành phần | Hành vi |
|---|---|
| `value` (get) | Đọc cache RAM. Đồng bộ. Trả `null` khi chưa hydrate |
| `value = x` (set) | Cập nhật cache, đẩy vào stream, ghi đĩa, `notifyListeners()` |
| `save(x)` | Tương đương setter |
| `delete()` | Xoá cache và xoá key khỏi đĩa |
| `readFromStorage()` | Hydrate cache từ đĩa. Phải `await` trong `@PostConstruct` |
| `addListener(cb)` | `ChangeNotifier` — dùng với `Provider` / `ListenableBuilder` |
| `listen(cb)` | Broadcast `Stream<T?>` — dùng trong BLoC hoặc Dart thuần |

```dart
_token.value = 'abc123';          // ghi: mã hoá, lưu đĩa, báo listener
final t = _token.value;           // đọc: tức thì, từ RAM
await _token.readFromStorage();   // hydrate lại từ đĩa
_token.delete();                  // xoá
```

Ghi xuống đĩa là fire-and-forget; cache RAM cập nhật đồng bộ, nên đọc ngay sau khi ghi vẫn ra giá trị mới.

---

## 8. Vượt ranh giới package

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
> Đăng ký impl `as: IThemeStorage` khiến nó **chỉ** phân giải được dưới kiểu `IThemeStorage`. GetIt **không** đi ngược chuỗi supertype, nên nếu cần một interface thứ hai trỏ về cùng instance thì phải bind tường minh bằng `@module`. Bỏ sót bước này thì SSL pinning âm thầm không hoạt động; xem [`08_networking.md`](08_networking.md#5-ssl-pinning).

---

## 9. Key dành riêng

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

## 10. Checklist

- [ ] Class key nằm trong `utils/` của package sở hữu, private constructor, `UPPER_SNAKE_CASE`
- [ ] Field `StorageValue` là private và `late final` bên trong owner
- [ ] Backend được chọn có cân nhắc (`secure` cho mọi thứ nhạy cảm)
- [ ] Owner là **singleton**, không phải `@injectable`
- [ ] `@PostConstruct(preResolve: true)` có `await readFromStorage()`
- [ ] Có `reviver` cho enum hoặc kiểu tuỳ biến (kiểu nguyên thuỷ, `Map<String, dynamic>` và list có kiểu thì không cần)
- [ ] Truy cập xuyên package đi qua interface ở `core_di`, không phụ thuộc trực tiếp
- [ ] Key không bắt đầu bằng `_internal_`

## Xem thêm

- [`../architecture/02_core.md`](../architecture/02_core.md) — vị trí của `core_storage`
- [`05_di.md`](05_di.md) — singleton vs factory, `@PostConstruct`, thứ tự module
- [`07_database.md`](07_database.md) — khi nào cần bảng quan hệ thay vì key-value
- [`../reference/01_rules.md`](../reference/01_rules.md) — luật sở hữu đầy đủ
