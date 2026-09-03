# Guide: Key-Value Storage

**What this answers:** how to persist a value (a token, a flag, a preference) so that it survives app restarts — and how to do it without letting any other package read or overwrite it.

**After reading you can:** add a new stored value end-to-end, choose the right backend for it, expose it across a package boundary, and explain why it is encrypted twice.

---

## 1. `core_storage` gives you a mechanism, not a place to dump keys

`core_storage` deliberately declares **zero keys**. It ships the machinery; every package declares its own values.

```dart
// packages/core/storage/lib/core_storage.dart
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
// packages/core/storage/lib/src/contracts/storage_type.dart
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
// packages/core/storage/lib/src/contracts/storage_interface.dart
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
// packages/core/storage/lib/src/impl/secure/secure_storage_impl.dart
if (masterKey == null) {
  // Generate a new 32-byte (256-bit) random key for AES
  final newKey = encrypter.Key.fromSecureRandom(32).base64;
  await _storage.write(key: masterKeyId, value: newKey);
  masterKey = newKey;
}
```

**Layer 3 (not advertised elsewhere) — RAM masking.** Neither the master key nor a cached value sits in memory as readable bytes. Both are XOR-masked with a random mask, and revealed only for the instant they are used:

```dart
// packages/core/storage/lib/src/contracts/storage_interface.dart
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

### Self-healing when the Keychain breaks

A corrupted KeyStore/Keychain would otherwise brick the app on every launch. `SecureStorageImpl` detects it and resets rather than looping:

```dart
// packages/core/storage/lib/src/impl/secure/secure_storage_impl.dart
try {
  masterKey = await _storage.read(key: masterKeyId);
} catch (e) {
  // KeyStore corruption detected! Self-heal by clearing secure storage.
  DynamicLogger.log(
    'KeyStore/Keychain corruption detected during init. Resetting storage. Error: ${e.runtimeType}',
    tag: 'SecureStorageImpl',
    level: LogLevel.WARNING,
  );
  try {
    await _storage.deleteAll();
  } catch (_) {}
  masterKey = null;
}
```

`read()` applies the same idea per key: an undecryptable key is deleted and `null` returned, so one bad row cannot fail every launch.

---

## 4. How to add a new stored value (the main recipe)

Three steps. The worked example is the auth token, which really exists in the repo.

### Step 1 — declare the key in the **owning** package's `utils/`

Never in `core_common`, never in `core_storage`.

```dart
// packages/data/auth/lib/src/utils/auth_storage_keys.dart
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
// packages/data/auth/lib/src/data_sources/local/auth_local_data_source.dart
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

---

## 5. Who owns what today

| Owner | Package | Key(s) | Backend |
|---|---|---|---|
| `AuthLocalDataSource` | `data_auth` | `token`, `auth_user` | `secure` |
| `LanguageRepositoryImpl` | `data_language` | `locale` | `pref` |
| `ThemeStorageImpl` | app shell (`app/lib/di/`) | `themeMode` | `pref` |
| `LanguageStorageImpl` | app shell (`app/lib/di/`) | `locale` | `pref` |
| `AppBootStorage` | app shell (`app/lib/di/`) | `viewed_onboard` | `pref` |

App-shell key classes live in `app/lib/di/utils/`.

> [!NOTE]
> `locale` appears twice on purpose. `LanguageRepositoryImpl` is the Domain-path sample (`domain_language`), while `LanguageStorageImpl` is what the live Settings UI actually uses via `LanguageProvider`. They read the same physical key but are independent instances; see [`10_cross_feature.md`](10_cross_feature.md) for why the UI path bypasses Domain.

---

## 6. Non-primitive types need a `reviver`

`StorageValue<T>` supports primitives directly. For enums, JSON objects and lists you must supply `reviver`, otherwise the constructor throws `ArgumentError`.

**Enum:**

```dart
// app/lib/di/theme_storage_impl.dart
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
// app/lib/di/app_boot_storage.dart
late final viewedOnboard = StorageValue<bool>(
  _storageManager.getStorage(StorageType.pref),
  AppBootStorageKeys.VIEWED_ONBOARD,
  reviver: (key, value) {
    if (value == null) return false;
    return bool.tryParse(value.toString()) ?? false;
  },
);
```

Always handle `value == null` in a `reviver` — it is called on a cold cache too.

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
// app/lib/di/theme_storage_impl.dart — the owner implements it
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
// packages/core/storage/lib/src/contracts/storage_interface.dart
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
- [ ] `reviver` provided for enum / JSON / list, and handles `null`
- [ ] Cross-package access goes through a `core_di` interface, never a direct dependency
- [ ] Key does not start with `_internal_`

## See also

- [`../architecture/02_core.md`](../architecture/02_core.md) — where `core_storage` sits
- [`05_di.md`](05_di.md) — singleton vs factory, `@PostConstruct`, module ordering
- [`07_database.md`](07_database.md) — when a relational table beats a key-value pair
- [`../reference/01_rules.md`](../reference/01_rules.md) — the ownership rule in full
