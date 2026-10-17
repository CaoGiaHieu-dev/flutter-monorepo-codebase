import 'package:dynamic_logger/dynamic_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';
import 'package:platform_kernel/platform_kernel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../contracts/storage_interface.dart';
import '../storage_codec.dart';
import '../utils/storage_constants.dart';
import 'encrypted_storage.dart';

const String _TAG = 'SecureStorageImpl';

/// A class for managing secure storage.
///
/// This class uses the `flutter_secure_storage` package to store data securely on the device.
/// The data is encrypted using AES-CBC encryption with a key and initialization vector (IV).
///
/// Registered as [StorageInterface] with named qualifier 'Secure' via DI.
///
/// What happens when the platform offers no secure store at all is the
/// app's decision per platform ([PlatformFacts.secureStorage], from
/// `platforms.<p>.secure_storage` in its manifest): stop the boot with
/// nothing deleted, or keep secure values in memory for the run.
@Injectable(as: StorageInterface)
@Named('Secure')
class SecureStorageImpl extends EncryptedStorage {
  /// Constructor – no singleton pattern, fully managed by DI. [platform] is
  /// the running platform's facts (`registerAppProfile` registers them
  /// before DI starts).
  SecureStorageImpl([PlatformFacts platform = const PlatformFacts.today()])
    : _platform = platform,
      _storage = EncryptedStorage.secureStorage,
      _retryDelay = StorageConstants.MASTER_KEY_RETRY_DELAY;

  /// Over a given storage backend, retrying after `retryDelay`, on the
  /// `platform` given — for tests that need a platform failure the real
  /// plugin cannot produce on demand.
  @visibleForTesting
  SecureStorageImpl.withStorage(
    this._storage, {
    this._retryDelay = Duration.zero,
    this._platform = const PlatformFacts.today(),
  });

  /// FlutterSecureStorage instance for storing data
  final FlutterSecureStorage _storage;

  /// Base delay between master-key read attempts (grows linearly).
  final Duration _retryDelay;

  /// The running platform's facts: [PlatformFacts.secureStorage] decides
  /// what [init] does when the secure store cannot be reached.
  final PlatformFacts _platform;

  /// This run's secure values, sealed as in the store, when the platform has
  /// no secure store and the policy is [SecureStoragePolicy.memoryFallback].
  /// `null` while the real store is in use.
  Map<String, String>? _volatile;

  /// Initializes the storage: first-launch cleanup, then the master key.
  ///
  /// **Never wipes the store on a platform error.** Reading the master key
  /// can fail for reasons that pass — the Keychain before the first unlock
  /// after a reboot (a background launch), a busy KeyStore. Treating that as
  /// corruption and calling `deleteAll()` destroyed every secure value,
  /// including `PrefStorageImpl`'s master key, which lives in this same
  /// store. The read is now retried, and a failure that persists is
  /// rethrown with nothing deleted.
  ///
  /// Real corruption of the plugin's own storage is handled natively: on
  /// Android `AndroidOptions.resetOnError` (on by default) resets what it
  /// cannot decrypt before the call returns. The one corruption this layer
  /// can see is a master key that is present but unusable (not a 256-bit
  /// base64 key); only that key is replaced — values sealed with it then
  /// fail to decrypt and are dropped one by one by [read].
  ///
  /// **A platform with no secure store** (a Linux session without a Secret
  /// Service) fails the master-key read or write for good. What happens then
  /// is [PlatformFacts.secureStorage]: [SecureStoragePolicy.required]
  /// rethrows, with nothing deleted, and the boot stops (B01);
  /// [SecureStoragePolicy.memoryFallback] keeps this run's secure values in
  /// memory under a fresh key, writes nothing secure to disk, and logs one
  /// WARNING.
  @override
  Future<void> init() async {
    final preferences = await SharedPreferences.getInstance();

    // 1. Handle first time open cleanup
    if (preferences.getBool(StorageConstants.FIRST_TIME_OPEN_APP) ?? true) {
      await preferences.setBool(StorageConstants.FIRST_TIME_OPEN_APP, false);
      await _deleteUnnecessaryKeepAlive();
    }

    // 2. Initialize Master Key for software-level encryption
    final String masterKey;
    try {
      masterKey = await _establishMasterKey();
    } catch (e) {
      if (_platform.secureStorage == SecureStoragePolicy.required) rethrow;
      _volatile = <String, String>{};
      setMasterKey(EncryptedStorage.generateKey());
      DynamicLogger.log(
        'Secure storage is unavailable (${e.runtimeType}): secure values are '
        'kept in memory for this run only and nothing secure is written to '
        'disk. On Linux, start and unlock a Secret Service (gnome-keyring, '
        'KWallet) — or decide `platforms.<p>.secure_storage` in '
        'apps/<id>/app_manifest.yaml.',
        tag: _TAG,
        level: LogLevel.WARNING,
      );
      return;
    }

    setMasterKey(masterKey);
  }

  /// The stored master key, or a new one written to the store: a key that
  /// is missing, or present but unusable, is replaced. Throws when the store
  /// cannot be read (after the retries) or written.
  Future<String> _establishMasterKey() async {
    final stored = await _readMasterKey();
    if (stored != null && EncryptedStorage.isUsableKey(stored)) return stored;

    if (stored != null) {
      DynamicLogger.log(
        'Stored master key is corrupt; replacing it. Values sealed with it '
        'will be dropped as they are read.',
        tag: _TAG,
        level: LogLevel.WARNING,
      );
    }

    // Generate a new 32-byte (256-bit) random key for AES
    final newKey = EncryptedStorage.generateKey();
    try {
      await _storage.write(
        key: StorageConstants.SECURE_MASTER_KEY_ID,
        value: newKey,
      );
    } catch (e) {
      DynamicLogger.log(
        'Failed to write master key to SecureStorage: ${e.runtimeType}',
        tag: _TAG,
        level: LogLevel.ERROR,
      );
      rethrow;
    }
    return newKey;
  }

  /// Reads the master key, retrying a platform failure before giving up.
  ///
  /// Rethrows the last error once the attempts run out: generating a fresh
  /// key here would orphan every value sealed with the one that could not be
  /// read, and wiping would destroy them.
  Future<String?> _readMasterKey() => EncryptedStorage.readKeyWithRetry(
    _storage,
    StorageConstants.SECURE_MASTER_KEY_ID,
    retryDelay: _retryDelay,
    tag: _TAG,
  );

  /// Delete unnecessary data from secure storage
  Future<void> _deleteUnnecessaryKeepAlive() async {
    try {
      await _storage.deleteAll();
    } catch (_) {
      // Best effort: this only clears what a previous install left behind
      // (the iOS Keychain survives an uninstall). Failing it must not stop
      // the first launch — the flag is already set, so it is not retried,
      // and the app starts with those leftovers still present.
    }
  }

  /// Write a value to secure storage.
  ///
  /// Now uses software-level encryption with RANDOM IV on ALL platforms.
  @override
  Future<void> write<T>(String key, T? value) async {
    checkKey(key);

    if (value == null) {
      await delete(key);
      return;
    }

    final dataString = StorageCodec.encode(value);

    // Encrypt using our software layer (with dynamic IV)
    // before passing to the hardware-backed secure storage.
    final encryptedData = encryptData(dataString);

    final volatile = _volatile;
    if (volatile != null) {
      volatile[key] = encryptedData;
      return;
    }
    await _storage.write(key: key, value: encryptedData);
  }

  /// Read a value from secure storage.
  @override
  Future<T?> read<T>(
    String key, {
    T Function(Object? key, Object? value)? reviver,
  }) async {
    checkKey(key);

    // A platform failure says nothing about the stored bytes — the Keychain
    // may simply be locked — so it must never delete them. The value reads
    // as absent this time and is still there for the next read.
    final volatile = _volatile;
    final String? encryptedData;
    try {
      encryptedData = volatile != null
          ? volatile[key]
          : await _storage.read(key: key);
    } catch (e) {
      DynamicLogger.log(
        'Failed to read key: $key (platform error, value kept). '
        'Error: ${e.runtimeType}',
        tag: _TAG,
        level: LogLevel.ERROR,
      );
      return null;
    }
    if (encryptedData == null) return null;

    try {
      // Decrypt using software layer (extracts IV from the string)
      final decryptedData = decryptData(encryptedData);

      return StorageCodec.decode<T>(decryptedData, key, reviver: reviver);
    } catch (e) {
      DynamicLogger.log(
        'Failed to decrypt or decode key: $key. Error: ${e.runtimeType}',
        tag: _TAG,
        level: LogLevel.ERROR,
      );
      // The bytes are unreadable with this key: drop them so the read does
      // not fail the same way forever.
      try {
        if (volatile != null) {
          volatile.remove(key);
        } else {
          await _storage.delete(key: key);
        }
      } catch (_) {
        // Best effort: the read already returns null for these bytes, and
        // the next read retries the delete.
      }
      return null;
    }
  }

  /// Delete a value from secure storage.
  ///
  /// Args:
  ///   key: The key to delete the value from.
  @override
  Future<void> delete(String key) async {
    checkKey(key);
    final volatile = _volatile;
    if (volatile != null) {
      volatile.remove(key);
      return;
    }
    return _storage.delete(key: key); // Delete the value from storage
  }
}
