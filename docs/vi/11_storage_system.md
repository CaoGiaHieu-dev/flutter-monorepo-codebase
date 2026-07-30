# 11. Hệ Thống Lưu Trữ Dữ Liệu Bảo Mật (Secure Storage System)

Toàn bộ logic lưu trữ dữ liệu cục bộ, bao gồm cấu hình lưu trữ đệm (Cache) và lưu trữ bảo mật cao cấp (Secure Storage), được đóng gói hoàn chỉnh trong gói Core chuyên biệt **`packages/core/storage`**. Hệ thống này được thiết kế theo tiêu chuẩn bảo mật hai lớp kết hợp giữa mã hóa phần mềm và bảo vệ phần cứng thiết bị, với cấu trúc thư mục phân tách rõ ràng và cơ chế tự động hóa cao.

---

## 📁 1. Cấu Trúc Thư Mục Hệ Thống (Directory Structure)

Mã nguồn của gói `core_storage` được phân tách nhằm tăng tính đóng gói và dễ bảo trì:
*   **`lib/src/contracts/`**: Giao diện, enum và bộ điều phối (`StorageInterface`, `StorageValue<T>`, `StorageType`, `StorageManager`).
*   **`lib/src/impl/`**: Backend vật lý (`pref` / SharedPreferences, `secure` / FlutterSecureStorage).
*   **`lib/src/presets/`**: Khóa nghiệp vụ reactive qua `@Singleton class StorageValuePresets` với `@PostConstruct(preResolve: true) initialize()`.

**Adapter lưu trữ App Shell** (`app/lib/di/`): `ThemeStorageImpl` và `LanguageStorageImpl` implement `IThemeStorage` / `ILanguageStorage` từ `core_di`, delegate sang `StorageValuePresets`. Chúng **không** nằm trong `core_storage`.

---

## 🛡️ 2. Kiến Trúc Bảo Mật Hai Lớp (Dual-Layer Hardened Security)

Mọi thông tin nhạy cảm (như JWT Access/Refresh Tokens, thông tin người dùng, cấu hình cá nhân bảo mật) khi được ghi xuống ổ đĩa cục bộ đều trải qua hai tầng bảo vệ nghiêm ngặt:

```text
[ Dữ liệu thô trên RAM ]
         │
         ▼ (Lớp 1: Mã hóa phần mềm AES-256-CBC)
[ Master Key + Random IV ] ➔ [ Bản mã hóa Base64 ]
                                    │
                                    ▼ (Lớp 2: Bảo mật phần cứng OS)
                       [ Apple Keychain / Android KeyStore ] ➔ [ Ghi xuống Disk ]
```

### Lớp 1: Mã hóa phần mềm (Software Cryptography)
*   **Thiết lập Master Key duy nhất**: Trong lần khởi chạy đầu tiên, cả hai backend `PrefStorageImpl` và `SecureStorageImpl` đều tự động sinh ra một Master Key ngẫu nhiên 256-bit duy nhất đại diện cho thiết bị đó. Master Key này **không bao giờ được viết cứng** trong mã nguồn hay lưu trong tệp cấu hình `.env` để ngăn ngừa dịch ngược.
*   **Initialization Vector ngẫu nhiên (Random IV)**: Với mỗi lần ghi dữ liệu, hệ thống sinh ra một chuỗi IV ngẫu nhiên dài 16 bytes. Dữ liệu ghi xuống có định dạng cấu trúc `iv_base64:ciphertext_base64`. Điều này đảm bảo ngay cả khi cùng một chuỗi dữ liệu (ví dụ: chữ `admin`) được ghi 10 lần, bản mã hóa lưu trên Disk sẽ tạo ra **10 chuỗi hoàn toàn khác nhau**.

### Lớp 2: Bảo mật phần cứng (OS KeyStore Integration)
*   Bản mã hóa lớp 1 cùng với Master Key của thiết bị được cất giữ an toàn bên dưới phân vùng phần cứng của hệ điều hành thông qua Apple Keychain (trên iOS) và Android KeyStore (trên Android), sử dụng lớp bọc thư viện `flutter_secure_storage`.
*   **Lợi ích**: Ngăn chặn hoàn toàn mọi cuộc tấn công trích xuất dữ liệu (jailbreak/root backup), đảm bảo an toàn thông tin tuyệt đối.

---

## ⚡ 3. Cơ Chế Bộ Nhớ Phản Ứng (Reactive Storage Values)

Gói `core_storage` cung cấp **`StorageValue<T>`** reactive:

*   **RAM ↔ DISK**: Gán `value` hoặc gọi `save()` cập nhật RAM ngay và ghi disk bất đồng bộ.
*   **Lắng nghe**: `StorageValue<T>` kế thừa `ChangeNotifier` và có stream `listen` cho UI/provider.

---

## 📘 4. Hướng Dẫn Định Nghĩa Key & Giá Trị Lưu Trữ Mới

Preset được đăng ký trên `@Singleton class StorageValuePresets` và hydrate lúc startup qua `@PostConstruct(preResolve: true)`.

### Bước 1: Khai báo Key tĩnh tại `core_common`
Mở `packages/core/common/lib/src/constants/storage_key_constants.dart` và thêm key trong lớp `StorageKeyConstants`:
```dart
class StorageKeyConstants {
  // ... các keys khác
  static const String USER_BIO_LOCKED = 'userBioLocked';
}
```

### Bước 2: Định nghĩa `StorageValue<T>` trong `storage_presets.dart`
Mở [storage_presets.dart](file:///c:/Users/PC/Desktop/codebase/packages/core/storage/lib/src/presets/storage_presets.dart):

```dart
@Singleton()
class StorageValuePresets {
  final StorageManager _storageManager;

  StorageValuePresets(this._storageManager);

  @PostConstruct(preResolve: true)
  Future<void> initialize() async {
    final storages = [
      token,
      refreshToken,
      authUser,
      locale,
      themeMode,
      viewedOnboard,
      isBioLocked, // thêm preset mới tại đây
    ];
    await Future.wait(storages.map((storage) => storage.readFromStorage()));
  }

  late final isBioLocked = StorageValue<bool>(
    _storageManager.getStorage(StorageType.pref),
    StorageKeyConstants.USER_BIO_LOCKED,
    reviver: (key, value) {
      if (value is bool) return value;
      if (value is String) return value.toLowerCase() == 'true';
      return false;
    },
  );
}
```

GetIt resolve `StorageValuePresets.initialize()` trước khi graph sẵn sàng (`preResolve: true`). **Không** gọi hydrate thủ công từ `main.dart`.

---

## 🛠️ 5. Cú Pháp Sử Dụng Thực Tế Trong Code

Để sử dụng các giá trị lưu trữ, bạn thực hiện tiêm (inject) `StorageValuePresets` vào lớp mong muốn thông qua container DI GetIt.

### Đọc & Ghi giá trị (Đồng bộ, tốc độ cao do lấy trực tiếp từ RAM):
```dart
@injectable
class MyController {
  final StorageValuePresets _storagePresets;

  MyController(this._storagePresets);

  void setBioLock(bool isLocked) {
    // Ghi dữ liệu: Bản ghi được tự động mã hóa AES-256 ngẫu nhiên IV và đẩy xuống Disk ngầm
    _storagePresets.isBioLocked.value = isLocked;
  }

  bool checkBioLock() {
    // Đọc dữ liệu: Trả về trạng thái tức thì từ bộ nhớ đệm RAM mà không cần đợi Future
    return _storagePresets.isBioLocked.value ?? false;
  }
}
```

### Lắng nghe thay đổi dữ liệu thời gian thực (Reactive):
```dart
// Lắng nghe thay đổi qua cấu trúc ChangeNotifier (ValueListenable):
_storagePresets.isBioLocked.addListener(() {
  final currentStatus = _storagePresets.isBioLocked.value;
  // Kích hoạt logic phản ứng
});

// Hoặc sử dụng luồng dữ liệu Stream (listen) cho các logic nghiệp vụ (Đặc biệt hữu ích khi dùng BLoC):
_storagePresets.isBioLocked.listen((status) {
  // Thực thi tác vụ bảo mật khi trạng thái khóa thay đổi
});
```

---

## 🧬 6. Phân Tích Các Kiểu Dữ Liệu Phức Tạp & Danh Sách (Lists)

Đối với các kiểu dữ liệu nâng cao như **Enum** hoặc **Custom Object (Class)**, hệ thống lưu dưới dạng JSON String. Khi đọc lên, bạn bắt buộc phải truyền thêm hàm ánh xạ ngược `reviver` để chỉ dẫn cách chuyển hóa từ JSON ngược lại Object.

### Đối với các kiểu dữ liệu đơn hoặc Enum:
```dart
// Định nghĩa lưu trữ Enum ThemeMode
late final themeMode = StorageValue<ThemeMode>(
  _storageManager.getStorage(StorageType.pref),
  StorageKeyConstants.THEME_MODE,
  reviver: (key, value) {
    return ThemeMode.values.byName(value?.toString() ?? ThemeMode.light.name);
  },
);
```

### Đối với kiểu dữ liệu Danh sách (List):
Hệ thống hỗ trợ tự động giải mã cấu trúc `List` thô. Khi bạn sử dụng `List` cơ bản, bạn có thể đọc trực tiếp mà không cần cung cấp `reviver`. Nếu cần biến đổi các phần tử bên trong danh sách (Ví dụ: từ danh sách JSON Map sang danh sách Object), hàm `reviver` sẽ nhận được tham số `value` dưới dạng một đối tượng `List` đã được decode (chứ không phải chuỗi JSON String thô):

```dart
// Ví dụ nạp danh sách chuỗi
late final selectedTags = StorageValue<List<String>>(
  _storageManager.getStorage(StorageType.pref),
  'selected_tags',
  reviver: (key, value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return [];
  },
);
```

---

## 🔌 7. Hướng Dẫn Tích Hợp Thêm Storage Backend Mới (Ví dụ: SQLite)

Nhờ kiến trúc dựa trên nguyên lý Open-Closed (SOLID) của `StorageManager`, việc bổ sung thêm một backend lưu trữ mới vô cùng đơn giản và không ảnh hưởng đến phần còn lại của ứng dụng:

### Bước 1: Khai báo type mới trong `StorageType`
Mở [storage_type.dart](file:///c:/Users/PC/Desktop/codebase/packages/core/storage/lib/src/contracts/storage_type.dart) và thêm giá trị mới:
```dart
enum StorageType {
  pref,
  secure,
  sqlite, // <-- Thêm ở đây
}
```

### Bước 2: Tạo lớp hiện thực kế thừa `StorageInterface`
Tạo tệp mới `lib/src/impl/sqlite/sqlite_storage_impl.dart` và kế thừa `StorageInterface`. Đánh dấu lớp bằng `@Injectable(as: StorageInterface)` và đặt tên định danh `@Named('Sqlite')` cho DI:
```dart
@Injectable(as: StorageInterface)
@Named('Sqlite')
class SqliteStorageImpl extends StorageInterface {
  @override
  Future<void> init() async {
    // Kết nối database SQLite, tạo bảng và sinh master key cho lớp mã hóa phần mềm...
  }

  @override
  Future<void> write<T>(String key, T? value) async {
    // Thực hiện SQL INSERT / UPDATE dữ liệu đã mã hóa (encryptData)...
  }

  @override
  Future<T?> read<T>(String key, {T Function(Object? key, Object? value)? reviver}) async {
    // Truy vấn SQL SELECT, giải mã dữ liệu (decryptData) và trả về đối tượng đã parse...
  }

  @override
  Future<void> delete(String key) async {
    // Thực hiện SQL DELETE...
  }
}
```

### Bước 3: Đăng ký backend mới vào `StorageManager`
Mở [storage_manager.dart](file:///c:/Users/PC/Desktop/codebase/packages/core/storage/lib/src/contracts/storage_manager.dart), tiêm (inject) backend mới qua constructor và ánh xạ enum:
```dart
  StorageManager(
    @Named('Pref') StorageInterface pref,
    @Named('Secure') StorageInterface secure,
    @Named('Sqlite') StorageInterface sqlite, // <-- Tiêm SQLite ở đây
  ) : _backends = {
          StorageType.pref: pref,
          StorageType.secure: secure,
          StorageType.sqlite: sqlite, // <-- Ánh xạ ở đây
        };
```

### Bước 4: Cấu hình key nghiệp vụ sử dụng SQLite
Tại tệp [storage_presets.dart](file:///c:/Users/PC/Desktop/codebase/packages/core/storage/lib/src/presets/storage_presets.dart), chỉ định `StorageType.sqlite` cho key mong muốn:
```dart
  /// Dữ liệu lịch sử giao dịch lưu trữ qua SQLite
  late final transactionHistory = StorageValue<List<Map<String, dynamic>>>(
    _storageManager.getStorage(StorageType.sqlite), // <-- Sử dụng SQLite
    'transaction_history',
  );
```

### Bước 5: Biên dịch lại DI
Chạy biên dịch build_runner để hoàn thành việc đăng ký DI:
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

---

## 🔗 Tài Liệu Liên Quan

- [14. Hệ Thống Database](./14_database_system.md) — Drift + isolate và ví dụ Local DataSource
- [11. Hệ Thống Storage](./11_storage_system.md) — lưu trữ key-value có mã hóa

---
*Copyright (c) 2026 CaoGiaHieu-dev. All rights reserved.*
