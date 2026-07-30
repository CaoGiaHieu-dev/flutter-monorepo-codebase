/// Core Storage — encrypted key-value persistence layer.
///
/// Provides:
/// - [StorageInterface] — abstract contract for storage backends
/// - [StorageValue] — reactive wrapper for a single stored value
/// - [StorageValuePresets] — pre-defined storage values (token, locale, etc.)
///   with `@PostConstruct(preResolve: true) initialize()` for startup hydration
///
/// Implementations (internal, resolved via DI `@Named` qualifiers):
/// - `PrefStorageImpl` (`@Named('Pref')`) — SharedPreferences
/// - `SecureStorageImpl` (`@Named('Secure')`) — FlutterSecureStorage
library core_storage;

// Auto-generated exports, do not edit manually.
export 'di/di.dart';
export 'src/src.dart';
