import 'dart:convert';

import 'package:core_common/core_common.dart';
import 'package:dynamic_logger/dynamic_logger.dart';
import 'package:encrypt/encrypt.dart' as encrypter;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../contracts/storage_interface.dart';

/// A class for managing shared preferences storage.
///
/// This class uses the `shared_preferences` package to store data on the device.
/// The data is stored as plain text.
///
/// Registered as [StorageInterface] with named qualifier 'Pref' via DI.
///
/// Master key is stored in hardware-backed [FlutterSecureStorage] for security,
/// falling back to SharedPreferences if secure storage is unavailable.
@Injectable(as: StorageInterface)
@Named('Pref')
class PrefStorageImpl extends StorageInterface {
  /// Constructor – no singleton pattern, fully managed by DI.
  PrefStorageImpl(this._preferences);

  /// SharedPreferences instance for storing data
  final SharedPreferences _preferences;

  /// Initialize the shared preferences instance and establish master key.
  /// Uses [FlutterSecureStorage] to protect the master key.
  @override
  Future<void> init() async {
    const masterKeyId = '_internal_pref_master_key';
    const secureStorage = FlutterSecureStorage(
      aOptions: AndroidOptions(
        keyCipherAlgorithm:
            KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
        storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
      ),
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    );

    String? masterKey;
    try {
      masterKey = await secureStorage.read(key: masterKeyId);
      if (masterKey == null) {
        // Generate a new 32-byte (256-bit) random key for AES
        final newKey = encrypter.Key.fromSecureRandom(32).base64;
        await secureStorage.write(key: masterKeyId, value: newKey);
        masterKey = newKey;
      }
    } catch (e) {
      // Safe fallback if secure storage is corrupted or unavailable
      DynamicLogger.log(
        'Failed to read pref master key from SecureStorage. Falling back to Prefs. Error: ${e.runtimeType}',
        tag: 'PrefStorageImpl',
        level: LogLevel.WARNING,
      );
      masterKey = _preferences.getString(masterKeyId);
      if (masterKey == null) {
        final newKey = encrypter.Key.fromSecureRandom(32).base64;
        await _preferences.setString(masterKeyId, newKey);
        masterKey = newKey;
      }
    }

    setMasterKey(masterKey);
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
    final dataStorage = jsonEncode(
      value,
      toEncodable: (nonEncodable) {
        if (nonEncodable is Enum) {
          return nonEncodable.name; // Encode enum as string
        } else if (nonEncodable is List) {
          return nonEncodable.map((e) => e.toString()).toList();
        }
        return jsonEncode(nonEncodable); // Encode other non-encodable types
      },
    );

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
      var tType = TypeHelper<T>(); // Get type helper for type T

      if (tType is TypeHelper<List>) {
        final decoded = json.decode(decrypted);
        if (decoded is List) {
          if (reviver != null) {
            return reviver.call(key, decoded);
          }
          return decoded as T;
        }
      }

      return json.decode(
        decrypted,
        reviver: (key, value) {
          if (TypeHelper.supportType(tType)) {
            if (tType is TypeHelper<Enum>) {
              return reviver?.call(key, value); // Use reviver for enums
            }
            return value; // Return value for supported types
          }
          return reviver?.call(key, value); // Use reviver for other types
        },
      ); // Decode data
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
