import 'dart:convert';

import 'package:core_common/core_common.dart';
import 'package:dynamic_logger/dynamic_logger.dart';
import 'package:encrypt/encrypt.dart' as encrypter;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../contracts/storage_interface.dart';

// ---------------------------------------------------------------------------
// App State Keys
// ---------------------------------------------------------------------------
const String _FIRST_TIME_OPEN_APP = 'firstTimeOpenApp';

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
  SecureStorageImpl();

  /// FlutterSecureStorage instance for storing data
  late final FlutterSecureStorage _storage;

  /// Android options for FlutterSecureStorage
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

  /// Initialize the secure storage, clearing the storage if it's the first time the app is opened.
  /// Handles KeyStore/Keychain corruption gracefully by resetting storage if necessary.
  @override
  Future<void> init() async {
    _storage = FlutterSecureStorage(aOptions: aOptions, iOptions: iOptions);

    final preferences = await SharedPreferences.getInstance();

    // 1. Handle first time open cleanup
    if (preferences.getBool(_FIRST_TIME_OPEN_APP) ?? true) {
      await preferences.setBool(_FIRST_TIME_OPEN_APP, false);
      await _deleteUnnecessaryKeepAlive();
    }

    // 2. Initialize Master Key for software-level encryption
    const masterKeyId = '_internal_master_key';
    String? masterKey;
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

    if (masterKey == null) {
      // Generate a new 32-byte (256-bit) random key for AES
      final newKey = encrypter.Key.fromSecureRandom(32).base64;
      try {
        await _storage.write(key: masterKeyId, value: newKey);
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

  /// Delete unnecessary data from secure storage
  Future<void> _deleteUnnecessaryKeepAlive() async {
    try {
      await _storage.deleteAll();
    } catch (_) {}
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

    final dataString = jsonEncode(
      value,
      toEncodable: (nonEncodable) {
        if (nonEncodable is Enum) {
          return nonEncodable.name;
        }
        return jsonEncode(nonEncodable);
      },
    );

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

    try {
      final encryptedData = await _storage.read(key: key);
      if (encryptedData == null) return null;

      // Decrypt using software layer (extracts IV from the string)
      final decryptedData = decryptData(encryptedData);

      var tType = TypeHelper<T>();

      if (tType is TypeHelper<List>) {
        final decoded = json.decode(decryptedData);
        if (decoded is List) {
          if (reviver != null) {
            return reviver.call(key, decoded);
          }
          return decoded as T;
        }
      }

      return jsonDecode(
        decryptedData,
        reviver: (key, value) {
          if (TypeHelper.supportType(tType)) {
            if (tType is TypeHelper<Enum>) {
              return reviver?.call(key, value);
            }
            return value;
          }
          return reviver?.call(key, value);
        },
      );
    } catch (e) {
      DynamicLogger.log(
        'Failed to read or decrypt key: $key. Error: ${e.runtimeType}',
        tag: 'SecureStorageImpl',
        level: LogLevel.ERROR,
      );
      // Safe self-healing: delete corrupted key so it doesn't loop failing
      try {
        await _storage.delete(key: key);
      } catch (_) {}
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
