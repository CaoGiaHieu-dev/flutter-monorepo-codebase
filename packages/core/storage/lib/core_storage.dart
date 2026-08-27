/// Core Storage — encrypted key-value persistence layer.
///
/// Provides only the storage MECHANISM — no package/feature-specific keys
/// or presets are defined here. Each consumer (data layer, app shell, ...)
/// must declare its own [StorageValue] instances with its own keys via
/// [StorageManager], so no other feature can see or touch its data.
///
/// Provides:
/// - [StorageInterface] — abstract contract for storage backends
/// - [StorageManager] — resolves the right backend by [StorageType]
/// - [StorageValue] — reactive wrapper for a single stored value
///
/// Implementations (internal, resolved via DI `@Named` qualifiers):
/// - `PrefStorageImpl` (`@Named('Pref')`) — SharedPreferences
/// - `SecureStorageImpl` (`@Named('Secure')`) — FlutterSecureStorage
library core_storage;

// Auto-generated exports, do not edit manually.
export 'di/di.dart';
export 'src/src.dart';
