---
name: implement_package_storage
description: Add a package-owned persisted value — declare its key in the owning package's utils/ folder and its StorageValue in the class that owns it, hydrated at startup.
---

# 💾 Skill: Implement a Package-Owned Storage Value

Use this skill when requested to: "save new config settings", "persist login tokens", "create a new cache storage", "remember a flag across launches", etc.

> [!IMPORTANT]
> **There is no `StorageValuePresets` and no `StorageKeyConstants`.** Both were deleted.
> A single shared object holding every domain's keys let any injector read and write another
> feature's data. `core_storage` now ships the **mechanism only** (`StorageManager`,
> `StorageValue<T>`, `StorageType`) — **you** declare the value in the class that owns it.

---

## 🧭 Decide the owner first

Before writing code, answer: **which package owns this value?**

| Value | Owner | Keys file |
| :--- | :--- | :--- |
| Auth token / user payload | `data_auth` → `AuthLocalDataSource` | `packages/data/auth/lib/src/utils/auth_storage_keys.dart` |
| Locale (business path) | `data_language` → `LanguageRepositoryImpl` | `packages/data/language/lib/src/utils/language_storage_keys.dart` |
| Theme mode (pure UI pref) | app shell → `ThemeStorageImpl` | `app/lib/di/utils/theme_storage_keys.dart` |
| Locale (pure UI pref) | app shell → `LanguageStorageImpl` | `app/lib/di/utils/language_storage_keys.dart` |
| Onboarding-seen boot flag | app shell → `AppBootStorage` | `app/lib/di/utils/app_boot_storage_keys.dart` |

The owner is the package whose business logic reads/writes the value. **Never** put a key in
`core_common`, and never let another package import the owner's key class.

> [!NOTE]
> **Key-value only.** For rows, relations, or SQL queries use a Drift database instead —
> see `implement_domain_data_flow` and `docs/{en,vi}/guides/07_database.md`. `core_storage`
> and `core_database` are separate mechanisms; neither owns your keys or your tables.

---

## 📋 Detailed Steps

### Step 1: Declare the key in the owning package's `utils/`

Create or extend `<owning_package>/lib/src/utils/<owner>_storage_keys.dart`:

```dart
/// Physical storage keys owned exclusively by `feature_auth`'s data layer.
class AuthStorageKeys {
  AuthStorageKeys._();

  static const String TOKEN = 'token';
  static const String AUTH_USER = 'auth_user';
  static const String USER_BIO_LOCKED = 'userBioLocked'; // new key
}
```

Constants are `UPPER_SNAKE_CASE` with a private constructor (AGENTS.md § 16).

### Step 2: Declare the `StorageValue<T>` inside the owner

Inject `StorageManager`, then declare a `late final` field per value:

```dart
@lazySingleton
class AuthLocalDataSource {
  AuthLocalDataSource(this._storageManager);

  final StorageManager _storageManager;

  late final _token = StorageValue<String>(
    _storageManager.getStorage(StorageType.secure),
    AuthStorageKeys.TOKEN,
  );

  late final _isBioLocked = StorageValue<bool>(
    _storageManager.getStorage(StorageType.pref),
    AuthStorageKeys.USER_BIO_LOCKED,
    reviver: (key, value) {
      if (value == null) return false;
      return bool.tryParse(value.toString()) ?? false;
    },
  );
}
```

**Storage types:**
* `StorageType.pref` — SharedPreferences (settings, flags)
* `StorageType.secure` — encrypted secure storage (tokens, sensitive data)

Use a `reviver` callback for anything that is not a plain `String`/`num`/`bool`/`Map`/`List` — Enums, nested objects, typed lists.

### Step 3: Hydrate at startup — and register as a **singleton**

Add the new value to the owner's `@PostConstruct(preResolve: true)` method so its in-memory cache is filled from disk before anything reads it:

```dart
  @PostConstruct(preResolve: true)
  Future<void> initialize() async {
    await Future.wait([
      _token.readFromStorage(),
      _authUser.readFromStorage(),
      _isBioLocked.readFromStorage(),
    ]);
  }
```

> [!CAUTION]
> The owner **MUST** be registered as a singleton — `@singleton`, `@lazySingleton`, or
> `@Singleton(as: IFoo)`. **Never `@injectable` (factory):** each injection would build a fresh
> instance with an empty cache, so synchronous getters would silently return `null`.

### Step 4: Run Build Runner

```bash
dart run build_runner build -d --workspace
```

If you created a new file, refresh the barrels first:

```bash
dart tools/barrel_generator/generate.dart packages/<layer>/<package>/lib
```

### Step 5: Expose it — through the owner's own API

Consumers inside the owning package use the field directly:

```dart
  bool get isBioLocked => _isBioLocked.value ?? false;

  void setBioLock(bool locked) => _isBioLocked.save(locked);
```

**Reactive access:**

```dart
_isBioLocked.value = true;              // Write (auto-encrypted, async to disk)
final locked = _isBioLocked.value;      // Read (instant from RAM, de-obfuscated)
_isBioLocked.addListener(() { ... });   // Listen (ChangeNotifier)
_isBioLocked.listen((val) { ... });     // Stream
await _isBioLocked.readFromStorage();   // Re-hydrate from disk
```

---

## 🌉 Crossing a package boundary

**Never** hand another package your `StorageValue` or your keys class. Publish a narrow interface on `core_di`, implement it in the owner, and let the consumer depend on the interface only — the pattern already used for theme and language:

```dart
// 1. Interface in core_di (packages/core/di/lib/src/theme/i_theme_storage.dart)
abstract class IThemeStorage {
  ThemeMode getThemeMode();
  void saveThemeMode(ThemeMode mode);
}

// 2. Implementation owns the StorageValue (app/lib/di/theme_storage_impl.dart)
@Singleton(as: IThemeStorage)
class ThemeStorageImpl implements IThemeStorage {
  ThemeStorageImpl(this._storageManager);
  final StorageManager _storageManager;

  late final _themeMode = StorageValue<ThemeMode>(
    _storageManager.getStorage(StorageType.pref),
    ThemeStorageKeys.THEME_MODE,
    reviver: (key, value) {
      if (value == null) return ThemeMode.system;
      return ThemeMode.values.byName(value.toString());
    },
  );

  @PostConstruct(preResolve: true)
  Future<void> initialize() async {
    await _themeMode.readFromStorage();
  }

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

`ThemeProvider` / `LanguageProvider` (in `core_base_ui`) inject only `IThemeStorage` / `ILanguageStorage` — they never see a key or a backend. These impls live in `app/lib/di/`, **not** in `core_storage`.

---

## ✅ Checklist

- [ ] Key lives in the **owning package's** `utils/` folder — not `core_common`
- [ ] `StorageValue` is declared inside the class that owns the data
- [ ] Correct `StorageType` (`secure` for tokens/PII, `pref` for settings/flags)
- [ ] `reviver` supplied for Enums / objects / lists
- [ ] Added to `@PostConstruct(preResolve: true)` hydration
- [ ] Owner registered as a **singleton**, never `@injectable`
- [ ] Cross-package access goes through a `core_di` interface, never the raw `StorageValue`
- [ ] Barrels regenerated + `build_runner` run

---

## 🔗 Related

- `docs/{en,vi}/guides/06_storage.md` — the full storage guide (backends, AES-256 + RAM
  obfuscation, `reviver` recipes)
- `docs/{en,vi}/reference/01_rules.md` — the `utils/` mandate and the core-never-depends-on-feature rule
- `implement_dependency_injection` — singleton scopes and `@PostConstruct(preResolve: true)`
