---
name: implement_package_storage
description: Use when a value must survive app restarts as a key-value entry — "save a setting", "persist the login token", "remember a flag across launches", "add a storage key". Declares the key in the owning package's utils/, a StorageValue<T> inside the owning singleton hydrated at startup by @PostConstruct(preResolve), and a published interface when another package needs the value (core_di if product-neutral, the owner's <id>_api if module-owned).
---

# Skill: Implement a package-owned storage value

Use this skill to persist a key-value entry: "save a setting", "persist a token", "remember a flag across
launches".

> **There is no `StorageValuePresets` and no `StorageKeyConstants`.** `core_storage` ships the mechanism only
> (`StorageManager`, `StorageValue<T>`, `StorageType`); **you** declare the value in the class that owns it
> (RULE-44), registered as a singleton (RULE-45).

**Guide:** [`docs/en/guides/06_storage.md`](../../../docs/en/guides/06_storage.md).
**Rules** ([registry](../../../docs/en/reference/01_rules.md)): RULE-06, RULE-09, RULE-44, RULE-45, RULE-74.
Cite them; do not restate them.

## Decide the owner first

The owner is the package whose business logic reads and writes the value. **Never** put a key in `core_common`,
and never let another package import the owner's key class.

| Value | Owner | Keys file |
| :--- | :--- | :--- |
| Auth token / user payload | `data_auth` → `AuthLocalDataSource` | `modules/auth/data/lib/src/utils/auth_storage_keys.dart` |
| Theme mode (pure UI preference) | the shell → `ThemeStorageImpl` | `platform/shell/adapters/lib/src/utils/theme_storage_keys.dart` |
| Locale (pure UI preference) | the shell → `LanguageStorageImpl` | `platform/shell/adapters/lib/src/utils/language_storage_keys.dart` |
| Onboarding-seen boot flag | the shell → `AppBootStorage` | `platform/shell/adapters/lib/src/utils/app_boot_storage_keys.dart` |

**Key-value only.** Rows, relations or SQL belong in a Drift database —
[`implement_package_database`](../implement_package_database/SKILL.md).

## Steps

The examples add a `bioLocked` flag to a hypothetical `profile` data package.

### Step 1: Depend on `core_storage`

The owning package declares it (an undeclared import still compiles in a Pub workspace, but `arch_check` R5
fails it), with `injectable` for the registration. Leave the versions off — they live in the catalog
(RULE-74) and `dart tools/dependency_sync.dart` fills an empty entry — then `flutter pub get`:

```yaml
dependencies:
  core_storage:
    path: ../../../platform/infra/storage   # adjust to your package's depth
  injectable:

dev_dependencies:
  build_runner:
  injectable_generator:
```

### Step 2: Declare the key in the owning package's `utils/`

`<package>/lib/src/utils/<owner>_storage_keys.dart` — `UPPER_SNAKE_CASE`, private constructor (RULE-09):

```dart
/// Physical storage keys owned exclusively by `data_profile`.
class ProfileStorageKeys {
  ProfileStorageKeys._();

  static const String BIO_LOCKED = 'bioLocked';
}
```

Pick a key that does not start with `_internal_` and is not `firstTimeOpenApp` (the backends refuse them).

### Step 3: Declare the `StorageValue<T>` inside the owner, hydrate it, register a singleton

```dart
import 'package:core_storage/core_storage.dart';
import 'package:injectable/injectable.dart';

import '../../utils/profile_storage_keys.dart';

@lazySingleton
class ProfileLocalDataSource {
  ProfileLocalDataSource(this._storageManager);

  final StorageManager _storageManager;

  late final _bioLocked = StorageValue<bool>(
    _storageManager.getStorage(StorageType.pref),
    ProfileStorageKeys.BIO_LOCKED,
  );

  /// Fills the in-memory cache from disk before anything reads it.
  @PostConstruct(preResolve: true)
  Future<void> initialize() async {
    await Future.wait([_bioLocked.readFromStorage()]);
  }

  bool get isBioLocked => _bioLocked.value ?? false;

  Future<void> setBioLocked(bool locked) => _bioLocked.save(locked);

  Future<void> clearBioLock() => _bioLocked.remove();
}
```

`AuthLocalDataSource` (`modules/auth/data/lib/src/data_sources/local/auth_local_data_source.dart`) is the
real one, with two `secure` values. Storage types: `StorageType.pref` (SharedPreferences — settings, flags)
and `StorageType.secure` (Keychain / KeyStore — tokens, PII). Both seal every value with AES-256-CBC.

- `String`, `num`, `bool`, `Map<String, dynamic>` and typed lists read back without a `reviver`. An enum or a
  custom type needs `reviver: (key, value) { … }`, called **once** per decode with the decoded root, never with
  `null`, and kept free of side effects (`ThemeStorageImpl` revives a `ThemeMode` from its name).
- **Singleton, never `@injectable`** (RULE-45): a factory builds a fresh instance with an empty cache, and the
  synchronous getters return `null` although the value is on disk. A second value goes into the same
  `readFromStorage` list.

### Step 4: Read and write

| Member | Behaviour |
| :--- | :--- |
| `value` (get) | the in-memory cache, synchronous; `null` before hydration |
| `value = x` | updates the cache and listeners at once, **starts** the disk write without waiting |
| `save(x)` | the same, returning a `Future<void>` that completes when the value is on disk |
| `remove()` | clears the cache and notifies at once; the `Future<void>` completes when the key is deleted |
| `readFromStorage()` | hydrates from disk; `await` it in `@PostConstruct` |
| `addListener(cb)` / `listen(cb)` | `ChangeNotifier` / broadcast `Stream<T?>` |

Writes are serialised and a failed write is logged, never thrown. Where the caller must know the value is
persisted, return and await the `save` / `remove` `Future` (`AuthLocalDataSource.saveUserToken` does).

### Step 5: Codegen

```bash
dart run build_runner build --workspace
```

The registration, including the awaited `initialize()`, lands in the package's generated
`lib/di/module.module.dart`; until it is regenerated the owner is not registered and the first injection fails
at boot. Barrels: [`run_repo_tooling`](../run_repo_tooling/SKILL.md#barrel-generator).

## Crossing a package boundary

**Never** hand another package your `StorageValue` or your keys class (RULE-44). Publish a narrow interface,
implement it in the owner, and let the consumer depend on the interface only. Where it goes depends on whose
value it is:

- **Product-neutral** (every app has it, no module owns it): an interface in `core_di`
  (`platform/foundation/contracts/lib/src/`). `IThemeStorage` / `ILanguageStorage` are implemented by the shell
  adapters and read by `core_base_ui`'s `ThemeProvider` / `LanguageProvider`, which never see a key or a backend.
- **Belongs to a module:** an interface in that module's own `<id>_api` package, next to its navigator and
  action handlers, so the neutral `core_di` never learns about a removable module (RULE-04, RULE-08). The
  consumer lists `<id>_api` in its `dependencies:` and resolves it with `getItOrNull` ([`create_api_package`](../create_api_package/SKILL.md)).

The theme is the live example of the first kind (`platform/shell/adapters/lib/src/theme_storage_impl.dart`; the
interface is `platform/foundation/contracts/lib/src/i_theme_storage.dart`):

```dart
abstract class IThemeStorage {
  ThemeMode getThemeMode();
  void saveThemeMode(ThemeMode mode);
}

@Singleton(as: IThemeStorage)
class ThemeStorageImpl implements IThemeStorage {
  // constructor over StorageManager and the app's ThemeProfile; `_themeMode` is a StorageValue<ThemeMode>
  // with a reviver, hydrated in @PostConstruct(preResolve: true)

  @override
  ThemeMode getThemeMode() => _themeMode.value ?? _defaultMode;

  @override
  void saveThemeMode(ThemeMode mode) => _themeMode.save(mode);
}
```

Registering an implementation `as: IThemeStorage` makes it resolvable only as that interface; a second interface
on the same instance needs a `@module` binding ([`implement_dependency_injection`](../implement_dependency_injection/SKILL.md)).
These implementations live in `platform/shell/adapters`, shared by every app — not in `core_storage`.

## Checklist

- [ ] Key lives in the owning package's `utils/`, not `core_common`
- [ ] `StorageValue` is private and declared inside the class that owns the data
- [ ] `secure` for tokens and PII, `pref` for settings and flags
- [ ] `reviver` for enums and custom types
- [ ] Added to the `@PostConstruct(preResolve: true)` hydration
- [ ] Owner registered as a singleton, never `@injectable`
- [ ] A write the caller must be sure of returns and awaits `save` / `remove`
- [ ] Cross-package access goes through an interface (`core_di` or the owner's `<id>_api`), never the raw `StorageValue`

## Related

- [`docs/en/guides/06_storage.md`](../../../docs/en/guides/06_storage.md) — backends, AES-256 and RAM obfuscation, `reviver` recipes
- [`implement_dependency_injection`](../implement_dependency_injection/SKILL.md) — singleton scopes and `@PostConstruct(preResolve: true)`

## Verify

```bash
dart run build_runner build --workspace                  # the owner's registration with its awaited initialize()
flutter analyze                                          # 0 issues (RULE-70)
dart tools/arch_check/check.dart                         # R5 core_storage declared
dart tools/composer/composer.dart verify
cd modules/<module>/<layer> && flutter test              # a test of the owner over in-memory storage (setup: platform/infra/storage/test/storage_test.dart)
cd apps/mobile && flutter test test/di_smoke_test.dart   # the owner resolves and hydrates (storage mocked in memory)
cd apps/mobile && flutter build apk --flavor dev --debug --dart-define-from-file=env.dev   # RULE-77
```
