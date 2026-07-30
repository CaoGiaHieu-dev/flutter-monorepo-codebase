---
name: implement_storage_preset
description: Add a new Storage Key and register a reactive value preset to be loaded automatically at startup.
---

# 💾 Skill: Register Storage Preset (Implement Storage Preset)

Use this skill when requested to: "save new config settings", "persist login tokens", "create a new cache storage", etc.

---

## 📋 Detailed Steps

### Step 1: Declare Storage Key Constant
Open `packages/core/common/lib/src/constants/storage_key_constants.dart`. Add a static string constant:
```dart
class StorageKeyConstants {
  StorageKeyConstants._();
  // ... existing keys
  static const String USER_BIO_LOCKED = 'userBioLocked';
}
```

### Step 2: Define `StorageValue<T>` in `StorageValuePresets`
Open `packages/core/storage/lib/src/presets/storage_presets.dart`:

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
      isBioLocked, // add new preset here
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

**Storage types:**
* `StorageType.pref` — SharedPreferences (settings, flags)
* `StorageType.secure` — encrypted secure storage (tokens, sensitive data)

### Step 3: Run Build Runner
```bash
dart run build_runner build -d --workspace
```

### Step 4: Use in Features (constructor injection)
```dart
@injectable
class MyService {
  final StorageValuePresets _storage;

  MyService(this._storage);

  bool get isBioLocked => _storage.isBioLocked.value ?? false;

  void setBioLock(bool locked) {
    _storage.isBioLocked.save(locked);
  }
}
```

### Theme / Language adapters (App Shell only)
If a UI provider needs a DI interface (`IThemeStorage`, `ILanguageStorage`), implement it in `app/lib/di/` and delegate to `StorageValuePresets` — do **not** put those impls inside `core_storage`.
