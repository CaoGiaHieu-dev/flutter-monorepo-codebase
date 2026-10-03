# Guide: Key-Value Storage

## Goal

You persist a value — a token, a flag, a preference — so that it survives app restarts, and so that no other package can read or overwrite it. You add the value end to end, choose its backend, and expose it across a package boundary when another package needs it.

## Prerequisites

- A package that will own the value (data layer, or the app shell for UI preferences).
- **How `core_storage` works**: it ships a mechanism and no keys, it encrypts twice, it masks values in RAM, and it never wipes the store on a platform error — [`../architecture/02_core.md` § 7](../architecture/02_core.md#7-core_storage--encrypted-keyvalue-storage). The rules behind it: RULE-44 (no shared keys), RULE-45 (singleton owner).
- Need rows, queries or relations rather than one value per key? Use a database instead — [`07_database.md`](07_database.md).

---

## 1. Choose a backend

```dart
// platform/infra/storage/lib/src/contracts/storage_type.dart
enum StorageType {
  /// SharedPreferences storage (plain text with software-level encryption).
  pref,

  /// Hardware-backed secure storage.
  secure,
}
```

| Use `StorageType.secure` for | Use `StorageType.pref` for |
|---|---|
| Auth tokens, refresh tokens | Theme mode, locale |
| Cached user profile / PII | "Has seen onboarding" flags |
| Anything an attacker with the device would want | Non-sensitive UI preferences |

`secure` is backed by Keychain (iOS) / KeyStore (Android) and is slower. `pref` is backed by SharedPreferences. Both backends (`SecureStorageImpl`, `PrefStorageImpl`) extend `EncryptedStorage`, which seals every value with AES-256-CBC before it is written, so `pref` is not plaintext on disk. You never touch a backend directly: you ask `StorageManager.getStorage(type)` for the `StorageInterface` and wrap it in a `StorageValue`.

## 2. Depend on `core_storage`

The owning package declares it in `dependencies` (an undeclared import still compiles in a Pub workspace, through the shared `package_config.json`; `arch_check` R5 is what flags it), plus injectable for the registration. As `modules/auth/data/pubspec.yaml` does:

```yaml
dependencies:
  core_storage:
    path: ../../../platform/infra/storage
  injectable:

dev_dependencies:
  build_runner:
  injectable_generator:
```

Adjust the `path:` to your package's depth. Leave the versions off: they live only in the catalog `pubspec_dependencies.yaml` (RULE-74), and `dart tools/dependency_sync.dart` fills in an empty one. Then `flutter pub get`.

## 3. Declare the key in the owning package's `utils/`

Never in `core_common`, never in `core_storage` (RULE-09, RULE-44). The worked example is the auth token, which really exists in the repo:

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

Conventions: private constructor, `UPPER_SNAKE_CASE`, one class per owner. The shell's own owners follow it in `platform/shell/adapters/lib/src/utils/` (`ThemeStorageKeys`, `LanguageStorageKeys`, `AppBootStorageKeys`). A key is a physical name already written on users' devices: renaming one orphans what is stored under it.

## 4. Declare the `StorageValue` inside the owner

Inject `StorageManager`, pick the backend, point at your key:

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

The fields are `private` + `late final`: nobody outside the class can reach the raw `StorageValue`, only the methods you choose to expose.

## 5. Register the owner as a singleton and hydrate it

```dart
  /// Hydrates the in-memory cache from disk at startup so synchronous
  /// getters below return correct values immediately.
  @PostConstruct(preResolve: true)
  Future<void> initialize() async {
    await Future.wait([_token.readFromStorage(), _authUser.readFromStorage()]);
  }
```

> [!CAUTION]
> Register the owner as `@singleton` / `@lazySingleton` — **never `@injectable`** (RULE-45). `@injectable` is a factory: every injection point builds a *new* instance whose in-memory cache is empty. Synchronous getters then return `null` even though the value is on disk. Pair it with `@PostConstruct(preResolve: true)`, so DI awaits the disk read before the graph is handed to the app.

## 6. Generate the registration

```bash
dart run build_runner build --workspace
```

The registration — including the `await` of `initialize()` that `preResolve` asks for — lands in the package's generated `lib/di/module.module.dart`, and only there. Until it is regenerated the owner is simply not registered, and the first injection fails at boot with *"… is not registered"*, which `flutter analyze` cannot see. A new file under `lib/` also needs `dart tools/barrel_generator/generate.dart modules/<module>/<layer>/lib` afterwards (RULE-75).

## 7. Read and write the value

| Member | Behaviour |
|---|---|
| `value` (get) | Reads the in-memory cache, decoded on every access. Synchronous. Returns `null` before hydration |
| `value = x` (set) | Updates the cache, pushes to the stream and `notifyListeners()` at once, and **starts** the disk write without waiting for it (`null` removes the key) |
| `save(x)` | The same, returning a `Future<void>` that completes when the value is on disk |
| `remove()` | Clears the cache and notifies at once; the `Future<void>` completes when the key is deleted from disk |
| `readFromStorage()` | Hydrates the cache from disk and notifies. `await` this in `@PostConstruct` |
| `addListener(cb)` | `ChangeNotifier` — use with `Provider` / `ListenableBuilder` |
| `listen(cb)` | Broadcast `Stream<T?>` — use in BLoC or plain Dart |

```dart
_token.value = 'abc123';          // write: cache and listeners now, disk fire-and-forget
await _token.save('abc123');      // the same, and wait until it is on disk
final t = _token.value;           // read: instant, from RAM
await _token.readFromStorage();   // re-hydrate from disk
await _token.remove();            // clear, and wait until it is deleted
```

The in-memory cache updates synchronously, so a read immediately after a write returns the new value. Writes are **serialized**: each starts after the previous one finished, so the last value set is the one left on disk. A failed write is logged through `DynamicLogger` and never thrown — the cache already holds the new value, and a storage error must not become an uncaught zone error. Use `save` / `remove` where the caller must know the value is persisted (`AuthLocalDataSource.saveUserToken` returns the future); use the setter where the cache is what matters.

## 8. Store an enum or a custom type

`StorageValue<T>` reads `num`, `String`, `bool`, `Map<String, dynamic>` and lists of those back directly — a `List<String>` is cast element-wise, no reviver needed. An **enum** is stored by `name`, so it needs a `reviver` to turn the name back into a value. Any **other type** is stored through its `toJson()` and needs a `reviver` to rebuild it; without one the constructor throws `ArgumentError`. All paths share `StorageCodec` (`platform/infra/storage/lib/src/storage_codec.dart`), so a value reads back the way it was written.

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

**Bool with an explicit default**, kept private and exposed through a getter and a method (RULE-44):

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

bool get viewedOnboard => _viewedOnboard.value ?? false;

Future<void> markOnboardViewed() => _viewedOnboard.save(true);
```

A `reviver` is called **once per decode**, with the decoded root value — not for every node of the tree — and never with `null`: a missing value reads as `null` before it runs. Every read of `value` decodes the cached JSON again, so it runs on each read as well as on `readFromStorage()`; keep it free of side effects. The `value == null` branches above are defensive, not required.

## 9. Share the value across a package boundary

A package must not depend on another package just to read its stored value, and the `StorageValue` stays private to its owner (RULE-44). Publish an interface instead, and implement it where the data lives. Where the interface goes depends on whose value it is:

- **Product-neutral** (every app has it, no module owns it) — in `core_di`. `IThemeStorage` and `ILanguageStorage` are implemented by the shell adapters and read by `core_base_ui`.
- **Belongs to a module** — in that module's own `<id>_api` package, next to its navigator and action handlers, so the neutral `core_di` never learns about a removable module (RULE-04, RULE-44).

The theme is the live example of the first kind:

```dart
// platform/foundation/contracts/lib/src/i_theme_storage.dart — no storage types leak through it
abstract class IThemeStorage {
  ThemeMode getThemeMode();
  void saveThemeMode(ThemeMode mode);
}
```

```dart
// platform/shell/adapters/lib/src/theme_storage_impl.dart — the owner implements it
@Singleton(as: IThemeStorage)
class ThemeStorageImpl implements IThemeStorage {
  // ... constructor over StorageManager and the app's ThemeProfile; _themeMode declared above,
  // hydrated in @PostConstruct(preResolve: true) ...

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

Consumers (here `ThemeProvider` in `core_base_ui`) depend on `IThemeStorage` only. They cannot see the key, the backend, or the `StorageValue`.

> [!WARNING]
> Registering an impl `as: IThemeStorage` makes it resolvable **only** as `IThemeStorage`. GetIt does not walk the supertype chain, so if a second interface must resolve to the same instance you need an explicit `@module` binding (RULE-14); see [`05_di.md`](05_di.md#4-bind-a-second-interface-to-one-instance).

## 10. Pick a key that is not reserved

The backends refuse the keys the storage layer uses for itself. `StorageInterface.isValidKey` is the contract; `EncryptedStorage` implements it for both backends from the constants in `StorageConstants`:

```dart
// platform/infra/storage/lib/src/impl/encrypted_storage.dart
@override
bool isValidKey(String key) =>
    key != StorageConstants.FIRST_TIME_OPEN_APP &&
    !key.startsWith(StorageConstants.INTERNAL_KEY_PREFIX);
```

`FIRST_TIME_OPEN_APP` is `firstTimeOpenApp` and `INTERNAL_KEY_PREFIX` is `_internal_` (the master keys are `_internal_master_key` and `_internal_pref_master_key`), so any key starting with `_internal_` is rejected. `StorageValue`'s constructor calls `isValidKey` and throws `ArgumentError('Access to reserved key "..." is forbidden.')`, so a bad key fails loudly at construction — not silently at runtime.

---

## Verify

```bash
dart run build_runner build --workspace                  # the owner's registration, with its awaited initialize()
flutter analyze                                          # No issues found!
cd platform/infra/storage && flutter test                # the mechanism's own tests
cd apps/mobile && flutter test test/di_smoke_test.dart   # the owner resolves and hydrates (storage in memory)
```

On a device, write the value, kill the app, and start it again: the value must read back synchronously on the first frame. `grep -rn "_storageManager.getStorage" modules platform` lists every owner, so you can check no second package declares your key.

Review checklist:

- [ ] Key class lives in the owning package's `utils/`, private constructor, `UPPER_SNAKE_CASE`
- [ ] `StorageValue` field is private and `late final` inside the owner
- [ ] Backend chosen deliberately (`secure` for anything sensitive)
- [ ] Owner is a **singleton**, not `@injectable`
- [ ] `@PostConstruct(preResolve: true)` awaits `readFromStorage()`
- [ ] `reviver` provided for an enum or a custom type (primitives, `Map<String, dynamic>` and typed lists need none)
- [ ] Cross-package access goes through an interface (`core_di` when product-neutral, the owner's `<id>_api` when it belongs to a module), never a direct dependency
- [ ] A write the caller must be sure of uses `save` / `remove` and awaits it
- [ ] Key does not start with `_internal_`

## Troubleshooting

| Symptom | Cause | Fix |
|:--|:--|:--|
| A getter returns `null` although the value is on disk | The owner is `@injectable`, or `readFromStorage()` is not awaited in `@PostConstruct(preResolve: true)` | Make it a singleton and hydrate it (step 5) |
| `ArgumentError: Access to reserved key "…" is forbidden.` | The key is reserved or starts with `_internal_` | Rename the key (step 10) |
| `ArgumentError` when constructing a `StorageValue` of a custom type | No `reviver` | Add one (step 8) |
| A value set just before the app was killed is missing on the next launch | The setter (or an un-awaited `save`) starts the write and the process ended first | `await` `save` / `remove` where the value must survive (step 7) |
| `… is not registered` at boot for the owner | Codegen has not run since the annotation was added | `dart run build_runner build --workspace` (step 6) |
| Another package imports your data package to read the value | No boundary contract | Declare an interface (`core_di`, or the owner's `<id>_api`) and implement it in the owner (step 9) |
| Every stored value is gone after upgrading from `flutter_secure_storage` 9.x or older | 11.x dropped the pre-10 ciphers | Ship a 10.x release first ([`../architecture/02_core.md` § 7](../architecture/02_core.md#the-plugins-cipher-options-are-pinned)) |

## Related

- Rules: RULE-09 (keys in `utils/`), RULE-44 (no shared keys, interface placement), RULE-45 (singleton owner, hydrated), RULE-14 (second interface via `@module`), RULE-74 (versions only in the catalog) — [`../reference/01_rules.md`](../reference/01_rules.md)
- [`../architecture/02_core.md` § 7](../architecture/02_core.md#7-core_storage--encrypted-keyvalue-storage) — encryption, RAM masking, failure handling, current owners
- [`05_di.md`](05_di.md) — singleton vs factory, `@PostConstruct`, module ordering
- [`07_database.md`](07_database.md) — when a relational table beats a key-value pair
