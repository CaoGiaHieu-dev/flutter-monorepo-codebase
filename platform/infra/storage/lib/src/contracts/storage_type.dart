/// Defines the types of storage backends available in the system.
enum StorageType {
  /// SharedPreferences storage (plain text with software-level encryption).
  pref,

  /// Hardware-backed secure storage.
  secure,
}
