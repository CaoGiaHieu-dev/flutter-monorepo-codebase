/// Contract of a key-value storage backend.
///
/// Implementations: `PrefStorageImpl` (SharedPreferences) and
/// `SecureStorageImpl` (FlutterSecureStorage), both sealing every value with
/// AES through `EncryptedStorage`. Consumers never talk to a backend
/// directly: they declare a `StorageValue` over the one `StorageManager`
/// hands out for a `StorageType`.
abstract interface class StorageInterface {
  /// Initializes the backend. Called once, by `StorageManager`, before any
  /// read or write.
  Future<void> init();

  /// Reads the value stored under [key], or `null`.
  ///
  /// [reviver] converts the decoded JSON into `T` (enums, models).
  Future<T?> read<T>(
    String key, {
    T Function(Object? key, Object? value)? reviver,
  });

  /// Stores [value] under [key]; `null` deletes it.
  Future<void> write<T>(String key, T? value);

  /// Deletes the value stored under [key].
  Future<void> delete(String key);

  /// Whether [key] may be used by a consumer — `false` for the backend's
  /// reserved keys (master keys, first-launch flag).
  bool isValidKey(String key);
}
