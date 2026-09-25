import 'dart:convert';

import 'package:dynamic_logger/dynamic_logger.dart';
import 'package:encrypt/encrypt.dart' as encrypter;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../contracts/storage_codec.dart';
import '../contracts/storage_interface.dart';

// ---------------------------------------------------------------------------
// App State Keys
// ---------------------------------------------------------------------------
const String _FIRST_TIME_OPEN_APP = 'firstTimeOpenApp';

/// Reserved key of the master key (see `StorageInterface.isValidKey`).
const String _MASTER_KEY_ID = '_internal_master_key';

/// AES-256.
const int _MASTER_KEY_BYTES = 32;

/// How often a failing master-key read is attempted before init gives up.
const int _MASTER_KEY_READ_ATTEMPTS = 3;

/// Base delay between those attempts.
const Duration _MASTER_KEY_RETRY_DELAY = Duration(milliseconds: 300);

/// A class for managing secure storage.
///
/// This class uses the `flutter_secure_storage` package to store data securely on the device.
/// The data is encrypted using AES-CBC encryption with a key and initialization vector (IV).
///
/// Registered as [StorageInterface] with named qualifier 'Secure' via DI.
@Injectable(as: StorageInterface)
@Named('Secure')
class SecureStorageImpl extends StorageInterface {
  /// Constructor – no singleton pattern, fully managed by DI.
  SecureStorageImpl()
    : _storage = FlutterSecureStorage(aOptions: aOptions, iOptions: iOptions),
      _retryDelay = _MASTER_KEY_RETRY_DELAY;

  /// Over a given [storage] backend, retrying after [retryDelay] — for tests
  /// that need a platform failure the real plugin cannot produce on demand.
  @visibleForTesting
  SecureStorageImpl.withStorage(
    this._storage, [
    this._retryDelay = Duration.zero,
  ]);

  /// FlutterSecureStorage instance for storing data
  final FlutterSecureStorage _storage;

  /// Base delay between master-key read attempts (grows linearly).
  final Duration _retryDelay;

  /// Android options for FlutterSecureStorage.
  ///
  /// Pinned explicitly, never left to the plugin's defaults: the plugin
  /// records the pair it wrote with and re-encrypts (or, failing that,
  /// resets) the whole store when the configured pair differs. RSA-OAEP key
  /// wrapping + AES-GCM storage is what every release of this template has
  /// written (flutter_secure_storage 10.x) and is still 11.x's default, so
  /// the 10 → 11 upgrade reads existing values as they are — no migration.
  /// `PrefStorageImpl` opens the same store and must use the same pair.
  static AndroidOptions get aOptions => const AndroidOptions(
    keyCipherAlgorithm: KeyCipherAlgorithm
        .RSA_ECB_OAEPwithSHA_256andMGF1Padding, // RSA encryption for key
    storageCipherAlgorithm:
        StorageCipherAlgorithm.AES_GCM_NoPadding, // AES encryption for data
  );

  /// iOS options for FlutterSecureStorage
  static IOSOptions get iOptions => const IOSOptions(
    accessibility: KeychainAccessibility
        .first_unlock, // Data accessible when device is unlocked
  );

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
  @override
  Future<void> init() async {
    final preferences = await SharedPreferences.getInstance();

    // 1. Handle first time open cleanup
    if (preferences.getBool(_FIRST_TIME_OPEN_APP) ?? true) {
      await preferences.setBool(_FIRST_TIME_OPEN_APP, false);
      await _deleteUnnecessaryKeepAlive();
    }

    // 2. Initialize Master Key for software-level encryption
    var masterKey = await _readMasterKey();

    if (masterKey != null && !_isUsableKey(masterKey)) {
      DynamicLogger.log(
        'Stored master key is corrupt; replacing it. Values sealed with it '
        'will be dropped as they are read.',
        tag: 'SecureStorageImpl',
        level: LogLevel.WARNING,
      );
      masterKey = null;
    }

    if (masterKey == null) {
      // Generate a new 32-byte (256-bit) random key for AES
      final newKey = encrypter.Key.fromSecureRandom(_MASTER_KEY_BYTES).base64;
      try {
        await _storage.write(key: _MASTER_KEY_ID, value: newKey);
        masterKey = newKey;
      } catch (e) {
        DynamicLogger.log(
          'Failed to write master key to SecureStorage: ${e.runtimeType}',
          tag: 'SecureStorageImpl',
          level: LogLevel.ERROR,
        );
        rethrow;
      }
    }

    setMasterKey(masterKey);
  }

  /// Reads the master key, retrying a platform failure before giving up.
  ///
  /// Rethrows the last error once the attempts run out: generating a fresh
  /// key here would orphan every value sealed with the one that could not be
  /// read, and wiping would destroy them.
  Future<String?> _readMasterKey() async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await _storage.read(key: _MASTER_KEY_ID);
      } catch (e) {
        final lastAttempt = attempt >= _MASTER_KEY_READ_ATTEMPTS;
        DynamicLogger.log(
          'Reading the master key failed (attempt $attempt of '
          '$_MASTER_KEY_READ_ATTEMPTS): ${e.runtimeType}. '
          '${lastAttempt ? 'Giving up; secure storage is left intact.' : 'Retrying.'}',
          tag: 'SecureStorageImpl',
          level: lastAttempt ? LogLevel.ERROR : LogLevel.WARNING,
        );
        if (lastAttempt) rethrow;
        await Future<void>.delayed(_retryDelay * attempt);
      }
    }
  }

  /// Whether [base64Key] decodes to a 256-bit key.
  static bool _isUsableKey(String base64Key) {
    try {
      return base64.decode(base64Key).length == _MASTER_KEY_BYTES;
    } on FormatException {
      return false;
    }
  }

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
    if (!isValidKey(key)) {
      throw ArgumentError('Access to reserved key "$key" is forbidden.');
    }

    if (value == null) {
      await delete(key);
      return;
    }

    final dataString = StorageCodec.encode(value);

    // Encrypt using our software layer (with dynamic IV)
    // before passing to the hardware-backed secure storage.
    final encryptedData = encryptData(dataString);

    await _storage.write(key: key, value: encryptedData);
  }

  /// Read a value from secure storage.
  @override
  Future<T?> read<T>(
    String key, {
    T Function(Object? key, Object? value)? reviver,
  }) async {
    if (!isValidKey(key)) {
      throw ArgumentError('Access to reserved key "$key" is forbidden.');
    }

    // A platform failure says nothing about the stored bytes — the Keychain
    // may simply be locked — so it must never delete them. The value reads
    // as absent this time and is still there for the next read.
    final String? encryptedData;
    try {
      encryptedData = await _storage.read(key: key);
    } catch (e) {
      DynamicLogger.log(
        'Failed to read key: $key (platform error, value kept). '
        'Error: ${e.runtimeType}',
        tag: 'SecureStorageImpl',
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
        tag: 'SecureStorageImpl',
        level: LogLevel.ERROR,
      );
      // The bytes are unreadable with this key: drop them so the read does
      // not fail the same way forever.
      try {
        await _storage.delete(key: key);
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
    if (!isValidKey(key)) {
      throw ArgumentError('Access to reserved key "$key" is forbidden.');
    }
    return _storage.delete(key: key); // Delete the value from storage
  }

  /// Delete all values from secure storage.
  Future<void> deleteAll() async {
    return _storage.deleteAll(); // Delete all values from storage
  }
}
