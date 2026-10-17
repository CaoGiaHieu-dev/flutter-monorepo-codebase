/// Core Storage — encrypted key-value persistence layer.
///
/// Provides only the storage MECHANISM — no package/feature-specific keys
/// or presets are defined here. Each consumer (data layer, app shell, ...)
/// must declare its own [StorageValue] instances with its own keys via
/// [StorageManager], so no other feature can see or touch its data.
///
/// Provides:
/// - [StorageInterface] / [StorageType] (`src/contracts/`) — the backend
///   contract and its kinds
/// - [StorageManager] — resolves the right backend by [StorageType]
/// - [StorageValue] — reactive wrapper for a single stored value, with
///   serialized, awaitable writes (`save` / `remove`)
///
/// Implementations (`src/impl/`, resolved via DI `@Named` qualifiers), both
/// on the shared AES base `EncryptedStorage`:
/// - `PrefStorageImpl` (`@Named('Pref')`) — SharedPreferences
/// - `SecureStorageImpl` (`@Named('Secure')`) — FlutterSecureStorage
library core_storage;

// Auto-generated exports, do not edit manually.
export 'di/module.dart';
export 'di/module.module.dart';
export 'src/contracts/storage_interface.dart';
export 'src/contracts/storage_type.dart';
export 'src/impl/encrypted_storage.dart';
export 'src/impl/pref_storage_impl.dart';
export 'src/impl/secure_storage_impl.dart';
export 'src/obfuscated_bytes.dart';
export 'src/storage_codec.dart';
export 'src/storage_manager.dart';
export 'src/storage_value.dart';
export 'src/utils/storage_constants.dart';
