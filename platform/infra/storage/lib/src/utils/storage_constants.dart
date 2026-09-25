/// Constants owned by `core_storage`'s backends.
///
/// Reserved keys are physical identifiers already written on users'
/// devices: renaming one orphans what is stored under it.
class StorageConstants {
  StorageConstants._();

  /// `SecureStorageImpl`'s master key, in secure storage.
  static const String SECURE_MASTER_KEY_ID = '_internal_master_key';

  /// `PrefStorageImpl`'s master key — in secure storage, and in
  /// SharedPreferences while the fallback key is in use.
  static const String PREF_MASTER_KEY_ID = '_internal_pref_master_key';

  /// SharedPreferences flag `SecureStorageImpl` clears a previous install's
  /// Keychain leftovers on.
  static const String FIRST_TIME_OPEN_APP = 'firstTimeOpenApp';

  /// Prefix of every internal key; a consumer key may not start with it.
  static const String INTERNAL_KEY_PREFIX = '_internal_';

  /// Master key length: AES-256.
  static const int MASTER_KEY_BYTES = 32;

  /// AES-CBC initialisation vector length.
  static const int IV_BYTES = 16;

  /// How often a failing master-key read is attempted before init gives up.
  static const int MASTER_KEY_READ_ATTEMPTS = 3;

  /// Base delay between those attempts (grows linearly).
  static const Duration MASTER_KEY_RETRY_DELAY = Duration(milliseconds: 300);

  /// How many stored values `PrefStorageImpl` tries when deciding which
  /// candidate master key opens them.
  static const int KEY_PROBE_SAMPLES = 3;
}
