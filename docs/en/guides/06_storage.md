# Guide: Key-Value Storage

**What this answers:** how to persist a value (a token, a flag, a preference) so that it survives app restarts — and how to do it without letting any other package read or overwrite it.

**After reading you can:** add a new stored value end-to-end, choose the right backend for it, expose it across a package boundary, and explain why it is encrypted twice.

---

## 1. `core_storage` gives you a mechanism, not a place to dump keys

`core_storage` deliberately declares **zero keys**. It ships the machinery; every package declares its own values.

```dart
// platform/storage/lib/core_storage.dart
/// Core Storage — encrypted key-value persistence layer.
///
/// Provides only the storage MECHANISM — no package/feature-specific keys
/// or presets are defined here. Each consumer (data layer, app shell, ...)
/// must declare its own [StorageValue] instances with its own keys via
/// [StorageManager], so no other feature can see or touch its data.
```

| Export | Kind | What it is for |
|---|---|---|
| `StorageInterface` | abstract class | Contract every backend implements; also hosts the AES helpers and the reserved-key guard |
| `StorageManager` | `@singleton` | Resolves a backend from a `StorageType`; initialises all backends once at startup |
| `StorageValue<T>` | class | Reactive wrapper around **one** key: in-memory cache + persistence + `ChangeNotifier` + `Stream` |
| `StorageType` | enum | `pref` \| `secure` |
| `ObfuscatedBytes` / `ObfuscatedString` | class | RAM-level XOR masking (see §3) |
| `PrefStorageImpl` | `@Named('Pref')` | SharedPreferences backend — internal, resolved by DI |
| `SecureStorageImpl` | `@Named('Secure')` | FlutterSecureStorage backend — internal, resolved by DI |

> [!NOTE]
> There is no shared preset object and no central key registry — no `StorageValuePresets`, no `StorageKeyConstants`. A single object holding every domain's keys would let any injector read and write another feature's data, so the mechanism deliberately offers no such object to reach for.

---

## 2. Which backend?

```dart
// platform/storage/lib/src/contracts/storage_type.dart
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

`secure` is backed by Keychain (iOS) / KeyStore (Android) and is slower. `pref` is backed by SharedPreferences. **Both** apply the software AES layer described next — `pref` is not plaintext on disk.

---

## 3. Two encryption layers, plus RAM masking

**Layer 1 — software AES-256-CBC with a fresh IV per write.** Implemented once on `StorageInterface` so both backends inherit it:

```dart
// platform/storage/lib/src/contracts/storage_interface.dart
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

A random IV per write means writing the same value twice produces different ciphertext — an observer cannot tell that a value was unchanged.

**Layer 2 — hardware.** The 256-bit master key lives in Keychain/KeyStore under `_internal_master_key`, generated on first launch:

```dart
// platform/storage/lib/src/impl/secure/secure_storage_impl.dart
if (masterKey == null) {
  // Generate a new 32-byte (256-bit) random key for AES
  final newKey = encrypter.Key.fromSecureRandom(_MASTER_KEY_BYTES).base64;
  await _storage.write(key: _MASTER_KEY_ID, value: newKey); // rethrows on failure
  masterKey = newKey;
}
```

**Layer 3 (not advertised elsewhere) — RAM masking.** Neither the master key nor a cached value sits in memory as readable bytes. Both are XOR-masked with a random mask, and revealed only for the instant they are used:

```dart
// platform/storage/lib/src/contracts/storage_interface.dart
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

`ObfuscatedString` (in `storage_value.dart`) does the same for cached values. This raises the bar for a memory-dump attack; it is not a substitute for the layers above.

### When the Keychain misbehaves — retry, never wipe

Reading the master key can fail for reasons that pass: the Keychain before the first unlock after a reboot (a background launch), a busy KeyStore. `SecureStorageImpl` used to treat *any* such failure as corruption and call `deleteAll()` — which destroyed every secure value, including `PrefStorageImpl`'s master key, which lives in the same store. Now:

```dart
// platform/storage/lib/src/impl/secure/secure_storage_impl.dart
Future<String?> _readMasterKey() async {
  for (var attempt = 1; ; attempt++) {
    try {
      return await _storage.read(key: _MASTER_KEY_ID);
    } catch (e) {
      final lastAttempt = attempt >= _MASTER_KEY_READ_ATTEMPTS;
      // … logged: WARNING while retrying, ERROR on the last attempt …
      if (lastAttempt) rethrow; // nothing deleted, no new key generated
      await Future<void>.delayed(_retryDelay * attempt);
    }
  }
}
```

| Failure | What happens |
| :-- | :-- |
| Platform error reading the master key | retried (3 attempts); if it persists, `init` **rethrows** with the store untouched — generating a fresh key would orphan every value sealed with the unreadable one |
| Master key present but unusable (not a 256-bit base64 key) | only that key is replaced; values sealed with it fail to decrypt and are dropped one by one by `read()` |
| Corruption of the plugin's own storage | handled natively: on Android `AndroidOptions.resetOnError` (on by default) resets what it cannot decrypt before the call returns |
| Platform error in `read(key)` | returns `null` **and keeps the value** — it is still there for the next read |
| A value that fails to decrypt or decode in `read(key)` | that one key is deleted and `null` returned, so one bad row cannot fail every launch |

### The pref backend's master key — the same rule

`PrefStorageImpl` seals SharedPreferences values with a master key of its own, `_internal_pref_master_key`, kept in the same secure store. It used to fall back on *any* read error to a brand-new key in SharedPreferences — after a single transient Keychain error every stored preference (theme, locale, the onboarding flag) failed to decrypt and was deleted on its next read, and the next healthy launch orphaned whatever that session wrote. Now it never replaces a key that may still be good:

| Situation | What `PrefStorageImpl.init` does |
| :-- | :-- |
| Platform error reading the key | retried (3 attempts) before anything else is decided |
| Still failing, no stored preferences | a new key is kept in SharedPreferences — there is nothing it could orphan |
| Still failing, and a key in SharedPreferences opens the stored preferences | that key is used (a device where secure storage is unavailable) |
| Still failing, and the stored preferences depend on the unreadable key | **rethrows**, nothing written or deleted — the values open again once the platform recovers |
| Readable again while a SharedPreferences key exists | whichever key decrypts the stored values wins; a winning SharedPreferences key is moved into secure storage and removed from SharedPreferences |
| Key absent or unusable (not a 256-bit base64 key) | a new key is generated — in secure storage, or in SharedPreferences if secure storage refuses the write; values sealed with a lost key drop one by one in `read()` |

`StorageManager.initialize` runs the secure backend first, so a persistent Keychain failure normally surfaces there before the pref backend is asked. The tests (`platform/storage/test/storage_test.dart`) drive both backends through a flaky `FlutterSecureStorage` fake.

### The plugin's cipher options are pinned

Both backends open `flutter_secure_storage` (11.x) with the same explicit Android pair — `KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding` and `StorageCipherAlgorithm.AES_GCM_NoPadding` — and `KeychainAccessibility.first_unlock` on iOS. On Android the plugin records the pair it wrote with and, when the configured pair differs, re-encrypts the store (`migrateOnAlgorithmChange`, on by default) or, failing that, resets it (`resetOnError`, also on). Leave both options alone unless you mean to migrate every user's secure data.

This pair is what the template has written since its first release (10.x) and it is still the 11.x default, so the 10 → 11 upgrade reads existing values unchanged: same KeyStore alias, same wrapped key, no migration step. What 11.x dropped is the pre-10 ciphers (RSA-PKCS1, AES-CBC, EncryptedSharedPreferences). An app that ever shipped `flutter_secure_storage` 9.x or older must ship a 10.x release first — a device going straight from 9 to 11 loses its secure values, tokens and `PrefStorageImpl`'s master key included. On Android, `FlutterSecureStorage.checkUpgradeStatus()` (11.1+), called before the first read, reports whether that happened.

---

## 4. How to add a new stored value (the main recipe)

Three steps, framed by a dependency and a codegen run. The worked example is the auth token, which really exists in the repo.

### Step 0 — depend on `core_storage`

The owning package declares it in `dependencies` (an undeclared import still compiles in a Pub workspace, through the shared `package_config.json`; `arch_check` R5 is what flags it), plus injectable for the registration. As in `modules/auth/data/pubspec.yaml`:

```yaml
dependencies:
  core_storage:
    path: ../../../platform/storage
  injectable: ^3.0.0

dev_dependencies:
  build_runner: "^2.16.0"
  injectable_generator: "^3.1.3"
```

Adjust the `path:` to your package's depth. Versions come from the catalog `pubspec_dependencies.yaml` (`dart tools/dependency_sync.dart`). Then `flutter pub get`.

### Step 1 — declare the key in the **owning** package's `utils/`

Never in `core_common`, never in `core_storage`.

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

Conventions: private constructor, `UPPER_SNAKE_CASE`, one class per owning package.

### Step 2 — declare the `StorageValue` inside the owner class

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

### Step 3 — register as a singleton and hydrate

```dart
  /// Hydrates the in-memory cache from disk at startup so synchronous
  /// getters below return correct values immediately.
  @PostConstruct(preResolve: true)
  Future<void> initialize() async {
    await Future.wait([_token.readFromStorage(), _authUser.readFromStorage()]);
  }
```

> [!CAUTION]
> Register the owner as `@singleton` / `@lazySingleton` — **never `@injectable`**. `@injectable` is a factory: every injection point builds a *new* instance whose in-memory cache is empty, so synchronous getters return `null` even though the value is on disk. Pair it with `@PostConstruct(preResolve: true)` so DI awaits the disk read before the graph is handed to the app.

### Step 4 — generate

```bash
dart run build_runner build --workspace
```

The registration — including the `await` of `initialize()` that `preResolve` asks for — lands in the package's generated `lib/di/module.module.dart`, and only there. Until it is regenerated the owner is simply not registered, and the first injection fails at boot with *"… is not registered"*, which `flutter analyze` cannot see. A new file also needs `dart tools/barrel_generator/generate.dart modules/<module>/<layer>/lib` afterwards.

---

## 5. Who owns what today

| Owner | Package | Key(s) | Backend |
|---|---|---|---|
| `AuthLocalDataSource` | `data_auth` | `token`, `auth_user` | `secure` |
| `ThemeStorageImpl` | app shell (`platform/app_shell/lib/di/`) | `themeMode` | `pref` |
| `LanguageStorageImpl` | app shell (`platform/app_shell/lib/di/`) | `locale` | `pref` |
| `AppBootStorage` | app shell (`platform/app_shell/lib/di/`) | `viewed_onboard` | `pref` |

App-shell key classes live in `platform/app_shell/lib/di/utils/`.


---

## 6. Non-primitive types need a `reviver`

`StorageValue<T>` reads `num`, `String`, `bool`, `Map<String, dynamic>` and lists of those back directly — a `List<String>` is cast element-wise, no reviver needed. An **enum** is stored by `name`, so it needs a `reviver` to turn the name back into a value. Any **other type** is stored through its `toJson()` and needs a `reviver` to rebuild it; without one the constructor throws `ArgumentError`. All paths share `StorageCodec` (`platform/storage/lib/src/contracts/storage_codec.dart`), so a value reads back the way it was written.

**Enum:**

```dart
// platform/app_shell/lib/di/theme_storage_impl.dart
late final _themeMode = StorageValue<ThemeMode>(
  _storageManager.getStorage(StorageType.pref),
  ThemeStorageKeys.THEME_MODE,
  reviver: (key, value) {
    if (value == null) return ThemeMode.system;
    return ThemeMode.values.byName(value.toString());
  },
);
```

**Bool with an explicit default:**

```dart
// platform/app_shell/lib/di/app_boot_storage.dart
late final viewedOnboard = StorageValue<bool>(
  _storageManager.getStorage(StorageType.pref),
  AppBootStorageKeys.VIEWED_ONBOARD,
  reviver: (key, value) {
    if (value == null) return false;
    return bool.tryParse(value.toString()) ?? false;
  },
);
```

A `reviver` is called **once**, with the decoded root value, and never with `null` — a missing value reads as `null` before it runs. The `value == null` branches above are defensive, not required.

---

## 7. `StorageValue` API

| Member | Behaviour |
|---|---|
| `value` (get) | Reads the in-memory cache. Synchronous. Returns `null` before hydration |
| `value = x` (set) | Updates cache, pushes to the stream, writes to disk, `notifyListeners()` |
| `save(x)` | Alias for the setter |
| `delete()` | Clears cache and removes the key from disk |
| `readFromStorage()` | Hydrates the cache from disk. `await` this in `@PostConstruct` |
| `addListener(cb)` | `ChangeNotifier` — use with `Provider` / `ListenableBuilder` |
| `listen(cb)` | Broadcast `Stream<T?>` — use in BLoC or plain Dart |

```dart
_token.value = 'abc123';          // write: encrypted, persisted, listeners notified
final t = _token.value;           // read: instant, from RAM
await _token.readFromStorage();   // re-hydrate from disk
_token.delete();                  // remove
```

Writes are fire-and-forget to disk; the in-memory cache updates synchronously, so a read immediately after a write returns the new value.

---

## 8. Crossing a package boundary

A package must not depend on another package just to read its stored value. Declare an interface in `core_di` and implement it where the data lives — the same pattern used for theme and locale:

```dart
// core_di declares the contract (no storage types leak through it)
abstract class IThemeStorage {
  ThemeMode getThemeMode();
  void saveThemeMode(ThemeMode mode);
}
```

```dart
// platform/app_shell/lib/di/theme_storage_impl.dart — the owner implements it
@Singleton(as: IThemeStorage)
class ThemeStorageImpl implements IThemeStorage {
  ThemeStorageImpl(this._storageManager);
  final StorageManager _storageManager;
  // ... _themeMode declared above ...

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

Consumers (here `ThemeProvider` in `core_base_ui`) depend on `IThemeStorage` only. They cannot see the key, the backend, or the `StorageValue`.

> [!WARNING]
> Registering an impl `as: IThemeStorage` makes it resolvable **only** as `IThemeStorage`. GetIt does not walk the supertype chain, so if a second interface must resolve to the same instance you need an explicit `@module` binding. Miss it and SSL pinning silently no-ops; see [`08_networking.md`](08_networking.md#5-ssl-pinning).

---

## 9. Reserved keys

`StorageInterface` refuses keys the storage layer uses for itself:

```dart
// platform/storage/lib/src/contracts/storage_interface.dart
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

Any key starting with `_internal_` is rejected. `StorageValue`'s constructor calls `isValidKey` and throws `ArgumentError('Access to reserved key "..." is forbidden.')`, so a bad key fails loudly at construction — not silently at runtime.

---

## 10. Checklist

- [ ] Key class lives in the owning package's `utils/`, private constructor, `UPPER_SNAKE_CASE`
- [ ] `StorageValue` field is private and `late final` inside the owner
- [ ] Backend chosen deliberately (`secure` for anything sensitive)
- [ ] Owner is a **singleton**, not `@injectable`
- [ ] `@PostConstruct(preResolve: true)` awaits `readFromStorage()`
- [ ] `reviver` provided for an enum or a custom type (primitives, `Map<String, dynamic>` and typed lists need none)
- [ ] Cross-package access goes through a `core_di` interface, never a direct dependency
- [ ] Key does not start with `_internal_`

## See also

- [`../architecture/02_core.md`](../architecture/02_core.md) — where `core_storage` sits
- [`05_di.md`](05_di.md) — singleton vs factory, `@PostConstruct`, module ordering
- [`07_database.md`](07_database.md) — when a relational table beats a key-value pair
- [`../reference/01_rules.md`](../reference/01_rules.md) — the ownership rule in full
