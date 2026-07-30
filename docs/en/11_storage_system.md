# 11. Secure Data Storage System (Secure Storage System)

All local data storage logic, including Cache configuration and advanced Secure Storage, is completely encapsulated in the specialized Core package **`packages/core/storage`**. This system is designed according to a two-layer security standard combining software encryption and device hardware protection, with a clearly separated directory structure and highly automated mechanism.

---

## 📁 1. System Directory Structure (Directory Structure)

The source code of the `core_storage` package is separated to increase encapsulation and maintainability:
*   **`lib/src/contracts/`**: Defines interfaces, enums, and coordinators (`StorageInterface`, `StorageValue<T>`, `StorageType`, `StorageManager`).
*   **`lib/src/impl/`**: Physical storage backends (`pref` / SharedPreferences, `secure` / FlutterSecureStorage).
*   **`lib/src/presets/`**: Reactive business keys via `@Singleton class StorageValuePresets` with `@PostConstruct(preResolve: true) initialize()`.

**App Shell storage adapters** (`app/lib/di/`): `ThemeStorageImpl` and `LanguageStorageImpl` implement `IThemeStorage` / `ILanguageStorage` from `core_di` and delegate to `StorageValuePresets`. They are **not** inside `core_storage`.

---

## 🛡️ 2. Dual-Layer Hardened Security Architecture

All sensitive information (like JWT Access/Refresh Tokens, user info, secure personal config) when written down to the local disk undergoes two strict layers of protection:

```text
[ Raw data on RAM ]
         │
         ▼ (Layer 1: AES-256-CBC software encryption)
[ Master Key + Random IV ] ➔ [ Base64 Ciphertext ]
                                    │
                                    ▼ (Layer 2: OS Hardware Security)
                       [ Apple Keychain / Android KeyStore ] ➔ [ Written to Disk ]
```

### Layer 1: Software Cryptography
*   **Establish Unique Master Key**: Upon the first launch, both `PrefStorageImpl` and `SecureStorageImpl` backends automatically generate a unique 256-bit random Master Key representing that device. This Master Key is **never hardcoded** in the source code or saved in the `.env` config file to prevent decompilation.
*   **Random Initialization Vector (Random IV)**: For each data write, the system generates a random 16-byte IV string. The written data is formatted as `iv_base64:ciphertext_base64`. This ensures that even if the exact same data string (e.g., the word `admin`) is written 10 times, the ciphertext stored on Disk will produce **10 completely different strings**.

### Layer 2: Hardware Security (OS KeyStore Integration)
*   The Layer 1 ciphertext along with the device's Master Key is safely stored under the OS's hardware partition via Apple Keychain (on iOS) and Android KeyStore (on Android), using the `flutter_secure_storage` library wrapper.
*   **Benefits**: Completely prevents all data extraction attacks (jailbreak/root backup), ensuring absolute information safety.

---

## ⚡ 3. Reactive Memory Mechanism (Reactive Storage Values)

The `core_storage` package exposes **reactive `StorageValue<T>`** objects:

*   **RAM ↔ DISK**: Assigning `value` or calling `save()` updates RAM immediately and persists to disk asynchronously.
*   **Listening**: `StorageValue<T>` extends `ChangeNotifier` and exposes a `listen` stream for reactive UI or providers.

---

## 📘 4. Guide to Defining Keys & New Storage Values

Storage presets are registered on `@Singleton class StorageValuePresets` and hydrated at startup via `@PostConstruct(preResolve: true)`.

### Step 1: Declare Static Key at `core_common`
Open `packages/core/common/lib/src/constants/storage_key_constants.dart` and add the key in the `StorageKeyConstants` class:
```dart
class StorageKeyConstants {
  // ... other keys
  static const String USER_BIO_LOCKED = 'userBioLocked';
}
```

### Step 2: Define the reactive value in `storage_presets.dart`
Open [storage_presets.dart](file:///c:/Users/PC/Desktop/codebase/packages/core/storage/lib/src/presets/storage_presets.dart) and add a `late final` `StorageValue<T>`:

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
      isBioLocked, // <-- add new preset here
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

GetIt resolves `StorageValuePresets.initialize()` before the app graph is ready (`preResolve: true`). **Do not** call hydration manually from `main.dart`.

---

## 🛠️ 5. Practical Usage Syntax in Code

To use storage values, you inject `StorageValuePresets` into the desired class via the GetIt DI container.

### Read & Write values (Synchronous, high speed due to retrieving directly from RAM):
```dart
@injectable
class MyController {
  final StorageValuePresets _storagePresets;

  MyController(this._storagePresets);

  void setBioLock(bool isLocked) {
    // Write data: The record is automatically AES-256 encrypted with a random IV and pushed down to Disk in the background
    _storagePresets.isBioLocked.value = isLocked;
  }

  bool checkBioLock() {
    // Read data: Returns instantaneous status from RAM cache without needing to await a Future
    return _storagePresets.isBioLocked.value ?? false;
  }
}
```

### Listen to real-time data changes (Reactive):
```dart
// Listen to changes via ChangeNotifier structure (ValueListenable):
_storagePresets.isBioLocked.addListener(() {
  final currentStatus = _storagePresets.isBioLocked.value;
  // Trigger reactive logic
});

// Or use a Stream (listen) data flow for business logics (Especially useful when using BLoC):
_storagePresets.isBioLocked.listen((status) {
  // Execute security task when lock status changes
});
```

---

## 🧬 6. Parsing Complex Data Types & Lists

For advanced data types like **Enum** or **Custom Object (Class)**, the system saves them as JSON Strings. When reading them up, you are required to pass a reverse mapping `reviver` function to instruct how to transform from JSON back to an Object.

### For singular data types or Enums:
```dart
// Define ThemeMode Enum storage
late final themeMode = StorageValue<ThemeMode>(
  _storageManager.getStorage(StorageType.pref),
  StorageKeyConstants.THEME_MODE,
  reviver: (key, value) {
    return ThemeMode.values.byName(value?.toString() ?? ThemeMode.light.name);
  },
);
```

### For List data types:
The system supports automatically decoding raw `List` structures. When you use basic `List`s, you can read them directly without providing a `reviver`. If you need to transform elements inside the list (e.g., from a JSON Map list to an Object list), the `reviver` function will receive the `value` parameter as an already decoded `List` object (not a raw JSON String):

```dart
// Example of loading a list of strings
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

## 🔌 7. Guide to Integrating A New Storage Backend (Example: SQLite)

Thanks to the Open-Closed (SOLID) principle-based architecture of `StorageManager`, adding a new storage backend is extremely simple and does not affect the rest of the application:

### Step 1: Declare new type in `StorageType`
Open [storage_type.dart](file:///c:/Users/PC/Desktop/codebase/packages/core/storage/lib/src/contracts/storage_type.dart) and add the new value:
```dart
enum StorageType {
  pref,
  secure,
  sqlite, // <-- Add here
}
```

### Step 2: Create implementation class inheriting `StorageInterface`
Create a new file `lib/src/impl/sqlite/sqlite_storage_impl.dart` and inherit `StorageInterface`. Mark the class with `@Injectable(as: StorageInterface)` and set the identifier name `@Named('Sqlite')` for DI:
```dart
@Injectable(as: StorageInterface)
@Named('Sqlite')
class SqliteStorageImpl extends StorageInterface {
  @override
  Future<void> init() async {
    // Connect to SQLite database, create tables, and generate master key for software encryption layer...
  }

  @override
  Future<void> write<T>(String key, T? value) async {
    // Perform SQL INSERT / UPDATE of encrypted data (encryptData)...
  }

  @override
  Future<T?> read<T>(String key, {T Function(Object? key, Object? value)? reviver}) async {
    // Query SQL SELECT, decrypt data (decryptData), and return parsed object...
  }

  @override
  Future<void> delete(String key) async {
    // Perform SQL DELETE...
  }
}
```

### Step 3: Register new backend to `StorageManager`
Open [storage_manager.dart](file:///c:/Users/PC/Desktop/codebase/packages/core/storage/lib/src/contracts/storage_manager.dart), inject the new backend via constructor and map the enum:
```dart
  StorageManager(
    @Named('Pref') StorageInterface pref,
    @Named('Secure') StorageInterface secure,
    @Named('Sqlite') StorageInterface sqlite, // <-- Inject SQLite here
  ) : _backends = {
          StorageType.pref: pref,
          StorageType.secure: secure,
          StorageType.sqlite: sqlite, // <-- Map here
        };
```

### Step 4: Configure business key using SQLite
At the [storage_presets.dart](file:///c:/Users/PC/Desktop/codebase/packages/core/storage/lib/src/presets/storage_presets.dart) file, specify `StorageType.sqlite` for the desired key:
```dart
  /// Transaction history data stored via SQLite
  late final transactionHistory = StorageValue<List<Map<String, dynamic>>>(
    _storageManager.getStorage(StorageType.sqlite), // <-- Use SQLite
    'transaction_history',
  );
```

### Step 5: Recompile DI
Run the build_runner compilation to finish DI registration:
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

---

## 🔗 Related Docs

- [14. Database System](./14_database_system.md) — Drift + isolate setup and Local DataSource example
- [11. Storage System](./11_storage_system.md) — encrypted key-value storage

---
*Copyright (c) 2026 CaoGiaHieu-dev. All rights reserved.*
