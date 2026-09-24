import 'dart:convert';

import 'package:dynamic_logger/dynamic_logger.dart';
import 'package:encrypt/encrypt.dart' as encrypter;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../contracts/storage_codec.dart';
import '../../contracts/storage_interface.dart';

/// Reserved key of this backend's master key (see
/// `StorageInterface.isValidKey`) — in secure storage, and in
/// SharedPreferences while the fallback key is in use.
const String _MASTER_KEY_ID = '_internal_pref_master_key';

/// AES-256.
const int _MASTER_KEY_BYTES = 32;

/// How often a failing master-key read is attempted before init gives up.
const int _MASTER_KEY_READ_ATTEMPTS = 3;

/// Base delay between those attempts.
const Duration _MASTER_KEY_RETRY_DELAY = Duration(milliseconds: 300);

/// How many stored values [PrefStorageImpl] tries when deciding which
/// candidate master key opens them.
const int _KEY_PROBE_SAMPLES = 3;

/// A class for managing shared preferences storage.
///
/// This class uses the `shared_preferences` package to store data on the
/// device. Every value is AES-encrypted with this backend's master key before
/// it is written.
///
/// Registered as [StorageInterface] with named qualifier 'Pref' via DI.
///
/// The master key lives in hardware-backed [FlutterSecureStorage]. Only when
/// secure storage cannot be read and there is nothing a new key could orphan
/// does it fall back to a key held in SharedPreferences — see [init].
@Injectable(as: StorageInterface)
@Named('Pref')
class PrefStorageImpl extends StorageInterface {
  /// Constructor – no singleton pattern, fully managed by DI.
  PrefStorageImpl(this._preferences)
    : _secureStorage = const FlutterSecureStorage(
        aOptions: AndroidOptions(
          keyCipherAlgorithm:
              KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
          storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
        ),
        iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
      ),
      _retryDelay = _MASTER_KEY_RETRY_DELAY;

  /// Over a given secure-storage backend, retrying after [retryDelay] — for
  /// tests that need a platform failure the real plugin cannot produce on
  /// demand.
  @visibleForTesting
  PrefStorageImpl.withSecureStorage(
    this._preferences,
    this._secureStorage, [
    this._retryDelay = Duration.zero,
  ]);

  /// SharedPreferences instance for storing data
  final SharedPreferences _preferences;

  /// Where the master key is kept.
  final FlutterSecureStorage _secureStorage;

  /// Base delay between master-key read attempts (grows linearly).
  final Duration _retryDelay;

  /// Establishes the master key the stored preferences are sealed with.
  ///
  /// **Never replaces a key that may still be good.** A new key orphans every
  /// value sealed with the old one, and [read] then deletes them — theme,
  /// locale and the onboarding flag reset. This used to happen on *any*
  /// secure-storage error: a locked Keychain before the first unlock after a
  /// reboot, or a busy KeyStore, made init generate a fresh key in
  /// SharedPreferences. The policy now matches `SecureStorageImpl`:
  ///
  /// * A failing read is retried. If it keeps failing, init uses the
  ///   SharedPreferences fallback key only when that key opens the stored
  ///   values, and creates one only when there are no stored values to lose;
  ///   otherwise it rethrows with nothing written or deleted.
  /// * A fallback key from a session without secure storage is moved into
  ///   secure storage once it is readable again — when it is the key that
  ///   opens the stored values.
  /// * Only a key that is absent or unusable (not a 256-bit base64 key) is
  ///   replaced; values sealed with a lost key then fail to decrypt and are
  ///   dropped one by one by [read].
  @override
  Future<void> init() async {
    final fallbackKey = _usableOrNull(_preferences.getString(_MASTER_KEY_ID));
    final sealed = _sealedValues();

    final String? secureKey;
    try {
      secureKey = await _readSecureKey();
    } catch (_) {
      if (fallbackKey != null &&
          (sealed.isEmpty || _opens(fallbackKey, sealed))) {
        setMasterKey(fallbackKey);
        return;
      }
      if (sealed.isEmpty) {
        DynamicLogger.log(
          'Secure storage is unavailable; keeping the pref master key in '
          'SharedPreferences until it is readable again.',
          tag: 'PrefStorageImpl',
          level: LogLevel.WARNING,
        );
        final newKey = _generateKey();
        await _preferences.setString(_MASTER_KEY_ID, newKey);
        setMasterKey(newKey);
        return;
      }
      DynamicLogger.log(
        'The pref master key cannot be read and stored preferences depend '
        'on it; giving up with every preference left intact.',
        tag: 'PrefStorageImpl',
        level: LogLevel.ERROR,
      );
      rethrow;
    }

    var storedKey = secureKey;
    if (storedKey != null && !_isUsableKey(storedKey)) {
      DynamicLogger.log(
        'Stored pref master key is corrupt; replacing it. Values sealed with '
        'it will be dropped as they are read.',
        tag: 'PrefStorageImpl',
        level: LogLevel.WARNING,
      );
      storedKey = null;
    }

    if (fallbackKey != null) {
      // Left by a session that could not read secure storage; whatever it
      // wrote is sealed with it. Keep whichever key opens the stored values.
      final useFallback = storedKey == null || _opens(fallbackKey, sealed);
      if (useFallback) {
        await _adoptFallbackKey(fallbackKey);
        setMasterKey(fallbackKey);
        return;
      }
      await _preferences.remove(_MASTER_KEY_ID);
    }

    if (storedKey != null) {
      setMasterKey(storedKey);
      return;
    }

    // No usable key anywhere: nothing stored can be opened by any key.
    final newKey = _generateKey();
    try {
      await _secureStorage.write(key: _MASTER_KEY_ID, value: newKey);
    } catch (e) {
      DynamicLogger.log(
        'Failed to write the pref master key to SecureStorage '
        '(${e.runtimeType}); keeping it in SharedPreferences.',
        tag: 'PrefStorageImpl',
        level: LogLevel.WARNING,
      );
      await _preferences.setString(_MASTER_KEY_ID, newKey);
    }
    setMasterKey(newKey);
  }

  /// Reads the master key from secure storage, retrying a platform failure
  /// before giving up. Rethrows the last error once the attempts run out.
  Future<String?> _readSecureKey() async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await _secureStorage.read(key: _MASTER_KEY_ID);
      } catch (e) {
        final lastAttempt = attempt >= _MASTER_KEY_READ_ATTEMPTS;
        DynamicLogger.log(
          'Reading the pref master key failed (attempt $attempt of '
          '$_MASTER_KEY_READ_ATTEMPTS): ${e.runtimeType}. '
          '${lastAttempt ? 'Giving up.' : 'Retrying.'}',
          tag: 'PrefStorageImpl',
          level: lastAttempt ? LogLevel.ERROR : LogLevel.WARNING,
        );
        if (lastAttempt) rethrow;
        await Future<void>.delayed(_retryDelay * attempt);
      }
    }
  }

  /// Moves [key] from SharedPreferences into secure storage. If secure
  /// storage refuses the write, the key stays where it is — still usable.
  Future<void> _adoptFallbackKey(String key) async {
    try {
      await _secureStorage.write(key: _MASTER_KEY_ID, value: key);
      await _preferences.remove(_MASTER_KEY_ID);
    } catch (e) {
      DynamicLogger.log(
        'Could not move the pref master key into SecureStorage '
        '(${e.runtimeType}); it stays in SharedPreferences for now.',
        tag: 'PrefStorageImpl',
        level: LogLevel.WARNING,
      );
    }
  }

  /// The stored values sealed by [write] (`iv:ciphertext`), excluding the
  /// reserved keys — the data a wrong master key would cost.
  List<String> _sealedValues() => [
    for (final key in _preferences.getKeys())
      if (isValidKey(key))
        if (_preferences.get(key) case final String value
            when _looksSealed(value))
          value,
  ];

  /// Whether [value] has the shape [encryptData] produces: a base64 16-byte
  /// IV, a colon, and base64 ciphertext. Keeps an unrelated plain string
  /// some other code stored in SharedPreferences out of the key decision.
  static bool _looksSealed(String value) {
    final parts = value.split(':');
    if (parts.length != 2 || parts[1].isEmpty) return false;
    try {
      return base64.decode(parts[0]).length == 16;
    } on FormatException {
      return false;
    }
  }

  /// Whether [key] decrypts at least one of the first few [sealed] values.
  ///
  /// A wrong AES-CBC key still passes the padding check about once in 256
  /// tries, so a value only counts as opened when it also decodes as the
  /// JSON [write] stores.
  ///
  /// Leaves [key] installed as the master key; [init] sets the final one.
  bool _opens(String key, List<String> sealed) {
    setMasterKey(key);
    for (final value in sealed.take(_KEY_PROBE_SAMPLES)) {
      try {
        jsonDecode(decryptData(value));
        return true;
      } catch (_) {
        // Expected while probing: this sample does not open with [key]
        // (bad padding or not JSON). Try the next one; none → `false`.
      }
    }
    return false;
  }

  static String _generateKey() =>
      encrypter.Key.fromSecureRandom(_MASTER_KEY_BYTES).base64;

  static String? _usableOrNull(String? base64Key) =>
      base64Key != null && _isUsableKey(base64Key) ? base64Key : null;

  /// Whether [base64Key] decodes to a 256-bit key.
  static bool _isUsableKey(String base64Key) {
    try {
      return base64.decode(base64Key).length == _MASTER_KEY_BYTES;
    } on FormatException {
      return false;
    }
  }

  /// Write a value to shared preferences.
  ///
  /// The value can be any type, but it will be encoded as JSON before being stored.
  ///
  /// Args:
  ///   key: The key to store the value under.
  ///   value: The value to store.
  @override
  Future<void> write<T>(String key, T? value) async {
    if (!isValidKey(key)) {
      throw ArgumentError('Access to reserved key "$key" is forbidden.');
    }

    if (value == null) {
      await delete(key); // Delete the value if it's null
      return;
    }
    final dataStorage = StorageCodec.encode(value);

    await _preferences.setString(key, encryptData(dataStorage)); // Store data
  }

  /// Read a value from shared preferences.
  ///
  /// The value will be decoded from JSON.
  ///
  /// Args:
  ///   key: The key to read the value from.
  ///   reviver: A function that can be used to customize the decoding of JSON.
  ///
  /// Returns:
  ///   The value stored under the given key.
  @override
  Future<T?> read<T>(
    String key, {
    T Function(Object? key, Object? value)?
    reviver, // Reviver function for custom decoding
  }) async {
    if (!isValidKey(key)) {
      throw ArgumentError('Access to reserved key "$key" is forbidden.');
    }

    try {
      final data = _preferences.get(key)?.toString(); // Read data from storage
      if (data == null) return null; // Return null if data is not found

      final decrypted = decryptData(data);
      return StorageCodec.decode<T>(decrypted, key, reviver: reviver);
    } catch (e) {
      DynamicLogger.log(
        'Failed to read or decrypt key: $key. Error: ${e.runtimeType}',
        tag: 'PrefStorageImpl',
        level: LogLevel.ERROR,
      );
      await delete(key); // Delete value on error
      return null;
    }
  }

  /// Delete a value from shared preferences.
  ///
  /// Args:
  ///   key: The key to delete the value from.
  @override
  Future<void> delete(String key) async {
    if (!isValidKey(key)) {
      throw ArgumentError('Access to reserved key "$key" is forbidden.');
    }
    await _preferences.remove(key); // Delete the value from storage
  }

  /// Delete all values from shared preferences.
  Future<void> deleteAll() async {
    await _preferences.clear(); // Delete all values from storage
  }
}
