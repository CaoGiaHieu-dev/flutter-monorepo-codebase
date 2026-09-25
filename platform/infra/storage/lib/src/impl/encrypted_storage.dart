import 'dart:convert';

import 'package:dynamic_logger/dynamic_logger.dart';
import 'package:encrypt/encrypt.dart' as encrypter;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../contracts/storage_interface.dart';
import '../obfuscated_bytes.dart';
import '../utils/storage_constants.dart';

/// What both backends share: an AES-256 master key held obfuscated in RAM,
/// AES-CBC sealing with a random IV, the reserved-key guard, and the
/// secure-storage plumbing their master keys live in.
///
/// A backend implements [init] (establishing the key with [setMasterKey])
/// and the storage calls, sealing through [encryptData] / [decryptData].
abstract class EncryptedStorage implements StorageInterface {
  /// Options of every `FlutterSecureStorage` this package opens.
  ///
  /// Pinned explicitly, never left to the plugin's defaults: the plugin
  /// records the pair it wrote with and re-encrypts (or, failing that,
  /// resets) the whole store when the configured pair differs. RSA-OAEP key
  /// wrapping + AES-GCM storage is what every release of this template has
  /// written (flutter_secure_storage 10.x) and is still 11.x's default, so
  /// the 10 → 11 upgrade reads existing values as they are. Both backends
  /// open the same store, so both must use this same pair.
  static const AndroidOptions androidOptions = AndroidOptions(
    keyCipherAlgorithm:
        KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
    storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
  );

  /// iOS options: readable once the device has been unlocked after boot.
  static const IOSOptions iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
  );

  /// The secure store both backends keep their master keys in.
  static const FlutterSecureStorage secureStorage = FlutterSecureStorage(
    aOptions: androidOptions,
    iOptions: iosOptions,
  );

  ObfuscatedBytes? _masterKey;

  /// Installs [base64Key] as the master key, replacing any previous one.
  void setMasterKey(String base64Key) {
    _masterKey?.dispose();
    final rawBytes = base64.decode(base64Key);
    _masterKey = ObfuscatedBytes(rawBytes);
    rawBytes.fillRange(0, rawBytes.length, 0);
  }

  /// Encrypts [data] with AES-CBC and a random IV; returns
  /// `"iv_base64:ciphertext_base64"`.
  String encryptData(String data) {
    return _withKey((enc) {
      final iv = encrypter.IV.fromSecureRandom(StorageConstants.IV_BYTES);
      return '${iv.base64}:${enc.encrypt(data, iv: iv).base64}';
    });
  }

  /// Decrypts what [encryptData] produced. Throws on a malformed value or
  /// the wrong key.
  String decryptData(String combinedData) {
    final parts = combinedData.split(':');
    if (parts.length != 2) {
      throw const FormatException('Invalid encrypted data format');
    }
    return _withKey(
      (enc) => enc.decrypt64(parts[1], iv: encrypter.IV.fromBase64(parts[0])),
    );
  }

  /// Runs [body] with an AES encrypter over the revealed master key, zeroing
  /// the key bytes straight after.
  T _withKey<T>(T Function(encrypter.Encrypter enc) body) {
    final masterKey = _masterKey;
    assert(masterKey != null, 'Master key must be set before use');
    final rawBytes = masterKey!.reveal();
    final key = encrypter.Key(rawBytes);
    try {
      return body(
        encrypter.Encrypter(encrypter.AES(key, mode: encrypter.AESMode.cbc)),
      );
    } finally {
      rawBytes.fillRange(0, rawBytes.length, 0);
      key.bytes.fillRange(0, key.bytes.length, 0);
    }
  }

  @override
  bool isValidKey(String key) =>
      key != StorageConstants.FIRST_TIME_OPEN_APP &&
      !key.startsWith(StorageConstants.INTERNAL_KEY_PREFIX);

  /// Throws an [ArgumentError] for a reserved [key].
  void checkKey(String key) {
    if (!isValidKey(key)) {
      throw ArgumentError('Access to reserved key "$key" is forbidden.');
    }
  }

  /// A new random master key, base64.
  static String generateKey() =>
      encrypter.Key.fromSecureRandom(StorageConstants.MASTER_KEY_BYTES).base64;

  /// Whether [base64Key] decodes to a 256-bit key.
  static bool isUsableKey(String base64Key) {
    try {
      return base64.decode(base64Key).length ==
          StorageConstants.MASTER_KEY_BYTES;
    } on FormatException {
      return false;
    }
  }

  /// Reads [keyId] from [storage], retrying a platform failure — a locked
  /// Keychain before the first unlock, a busy KeyStore — after [retryDelay]
  /// times the attempt number. Rethrows the last error once
  /// [StorageConstants.MASTER_KEY_READ_ATTEMPTS] run out: replacing or
  /// wiping a key that merely could not be read would orphan every value
  /// sealed with it.
  static Future<String?> readKeyWithRetry(
    FlutterSecureStorage storage,
    String keyId, {
    required Duration retryDelay,
    required String tag,
  }) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await storage.read(key: keyId);
      } catch (e) {
        final lastAttempt =
            attempt >= StorageConstants.MASTER_KEY_READ_ATTEMPTS;
        DynamicLogger.log(
          'Reading the master key failed (attempt $attempt of '
          '${StorageConstants.MASTER_KEY_READ_ATTEMPTS}): ${e.runtimeType}. '
          '${lastAttempt ? 'Giving up; storage is left intact.' : 'Retrying.'}',
          tag: tag,
          level: lastAttempt ? LogLevel.ERROR : LogLevel.WARNING,
        );
        if (lastAttempt) rethrow;
        await Future<void>.delayed(retryDelay * attempt);
      }
    }
  }
}
