import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as encrypter;

/// Container that obfuscates bytes in RAM using dynamic XOR masking.
class ObfuscatedBytes {
  final Uint8List _maskedBytes;
  final Uint8List _mask;

  ObfuscatedBytes(Uint8List originalBytes)
    : _mask = _generateRandomMask(originalBytes.length),
      _maskedBytes = Uint8List(originalBytes.length) {
    for (int i = 0; i < originalBytes.length; i++) {
      _maskedBytes[i] = originalBytes[i] ^ _mask[i];
    }
  }

  /// Temporarily reconstructs the original bytes.
  /// Caller MUST zero out/fill the returned Uint8List with 0 after use.
  Uint8List reveal() {
    final originalBytes = Uint8List(_maskedBytes.length);
    for (int i = 0; i < _maskedBytes.length; i++) {
      originalBytes[i] = _maskedBytes[i] ^ _mask[i];
    }
    return originalBytes;
  }

  /// Disposes of the obfuscated buffers.
  void dispose() {
    _maskedBytes.fillRange(0, _maskedBytes.length, 0);
    _mask.fillRange(0, _mask.length, 0);
  }

  static Uint8List _generateRandomMask(int length) {
    final random = math.Random.secure();
    return Uint8List.fromList(
      List.generate(length, (_) => random.nextInt(256)),
    );
  }
}

/// Abstract contract for key-value storage backends.
///
/// Implementations include:
/// - [PrefStorageImpl] — SharedPreferences (plain text, web-friendly)
/// - [SecureStorageImpl] — FlutterSecureStorage (hardware-backed, mobile)
///
/// Both implementations apply software-level AES-CBC encryption on top
/// of their native storage mechanism for an extra layer of security.
abstract class StorageInterface {
  /// The master encryption key stored securely in memory using XOR obfuscation.
  ObfuscatedBytes? _obfuscatedMasterKey;

  /// Sets the master key for encryption/decryption.
  void setMasterKey(String base64Key) {
    if (_obfuscatedMasterKey != null) {
      _obfuscatedMasterKey!.dispose();
    }
    final rawBytes = base64.decode(base64Key);
    _obfuscatedMasterKey = ObfuscatedBytes(rawBytes);
    rawBytes.fillRange(0, rawBytes.length, 0);
  }

  /// Initialize the storage backend.
  ///
  /// Must be called once before any read/write operations.
  Future<void> init();

  /// Read a value from storage.
  ///
  /// [reviver] is an optional function for custom JSON decoding.
  Future<T?> read<T>(
    String key, {
    T Function(Object? key, Object? value)? reviver,
  });

  /// Write a value to storage.
  Future<void> write<T>(String key, T? value);

  /// Delete a single value from storage.
  Future<void> delete(String key);

  /// Encrypt [data] using AES-CBC with a random IV.
  ///
  /// Returns `"iv_base64:ciphertext_base64"`.
  String encryptData(String data) {
    assert(
      _obfuscatedMasterKey != null,
      'Master key must be initialized before encryption',
    );
    final rawBytes = _obfuscatedMasterKey!.reveal();
    final key = encrypter.Key(rawBytes);
    final aes = encrypter.AES(key, mode: encrypter.AESMode.cbc);
    final enc = encrypter.Encrypter(aes);

    final iv = encrypter.IV.fromSecureRandom(16);
    final encrypted = enc.encrypt(data, iv: iv);

    // Zero out key buffers immediately
    rawBytes.fillRange(0, rawBytes.length, 0);
    key.bytes.fillRange(0, key.bytes.length, 0);

    return '${iv.base64}:${encrypted.base64}';
  }

  /// Decrypt data produced by [encryptData].
  String decryptData(String combinedData) {
    assert(
      _obfuscatedMasterKey != null,
      'Master key must be initialized before decryption',
    );
    final parts = combinedData.split(':');
    if (parts.length != 2) throw Exception('Invalid encrypted data format');

    final rawBytes = _obfuscatedMasterKey!.reveal();
    final key = encrypter.Key(rawBytes);
    final aes = encrypter.AES(key, mode: encrypter.AESMode.cbc);
    final enc = encrypter.Encrypter(aes);

    final iv = encrypter.IV.fromBase64(parts[0]);
    final ciphertext = parts[1];
    final decrypted = enc.decrypt64(ciphertext, iv: iv);

    // Zero out key buffers immediately
    rawBytes.fillRange(0, rawBytes.length, 0);
    key.bytes.fillRange(0, key.bytes.length, 0);

    return decrypted;
  }

  /// List of reserved keys that cannot be accessed or modified via public APIs.
  static const _reservedKeys = {
    '_internal_master_key',
    '_internal_pref_master_key',
    'firstTimeOpenApp',
  };

  /// Check if the key is valid (not reserved).
  bool isValidKey(String key) {
    if (_reservedKeys.contains(key) || key.startsWith('_internal_')) {
      return false;
    }
    return true;
  }
}
