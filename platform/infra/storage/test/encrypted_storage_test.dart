import 'dart:convert';

import 'package:core_storage/core_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// The smallest backend: only what [EncryptedStorage] leaves abstract.
class _Vault extends EncryptedStorage {
  @override
  Future<void> init() async {}

  @override
  Future<T?> read<T>(
    String key, {
    T Function(Object? key, Object? value)? reviver,
  }) async => null;

  @override
  Future<void> write<T>(String key, T? value) async {}

  @override
  Future<void> delete(String key) async {}
}

/// A secure store whose `read` fails [failures] times, then answers.
class _FlakyRead extends FlutterSecureStorage {
  _FlakyRead({required this.failures, this.value});

  int failures;
  final String? value;
  int calls = 0;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    calls++;
    if (failures > 0) {
      failures--;
      throw PlatformException(code: 'locked');
    }
    return value;
  }
}

/// `EncryptedStorage` is what `PrefStorageImpl` and `SecureStorageImpl` share:
/// AES-CBC sealing with a random IV under a master key, the reserved-key
/// guard, key generation and the master-key read retry.
void main() {
  late _Vault vault;

  setUp(() {
    vault = _Vault()..setMasterKey(EncryptedStorage.generateKey());
  });

  group('encryptData / decryptData', () {
    test('round-trips text, including multi-byte characters', () {
      for (final text in ['hello', 'xin chào — ✓ 日本語', 'a' * 5000]) {
        expect(vault.decryptData(vault.encryptData(text)), text);
      }
    });

    test('seals as "iv:ciphertext", both base64, with a 16-byte IV', () {
      final sealed = vault.encryptData('secret');
      final parts = sealed.split(':');

      expect(parts, hasLength(2));
      expect(base64.decode(parts[0]), hasLength(16));
      expect(base64.decode(parts[1]), isNotEmpty);
      expect(sealed, isNot(contains('secret')));
    });

    test('the same text seals differently each time (random IV)', () {
      expect(vault.encryptData('same'), isNot(vault.encryptData('same')));
    });

    test('a value sealed under another key does not open', () {
      final sealed = vault.encryptData('secret');
      final other = _Vault()..setMasterKey(EncryptedStorage.generateKey());

      expect(() => other.decryptData(sealed), throwsA(anything));
    });

    test('setMasterKey replaces the previous key', () {
      final sealed = vault.encryptData('secret');

      vault.setMasterKey(EncryptedStorage.generateKey());

      expect(() => vault.decryptData(sealed), throwsA(anything));
      expect(vault.decryptData(vault.encryptData('again')), 'again');
    });

    test('the same key opens what another instance sealed', () {
      final key = EncryptedStorage.generateKey();
      final a = _Vault()..setMasterKey(key);
      final b = _Vault()..setMasterKey(key);

      expect(b.decryptData(a.encryptData('shared')), 'shared');
    });

    test('a value without exactly one separator is a FormatException', () {
      expect(() => vault.decryptData('no-separator'), throwsFormatException);
      expect(() => vault.decryptData('a:b:c'), throwsFormatException);
    });

    test('a tampered ciphertext does not decrypt to the original', () {
      final sealed = vault.encryptData('secret payload');
      final parts = sealed.split(':');
      final bytes = base64.decode(parts[1]);
      bytes[0] ^= 0xff;
      final tampered = '${parts[0]}:${base64.encode(bytes)}';

      String? result;
      try {
        result = vault.decryptData(tampered);
      } catch (_) {
        // Padding failure is the usual outcome; either way it is not plain.
      }
      expect(result, isNot('secret payload'));
    });
  });

  group('reserved keys', () {
    test('the first-launch flag and the internal prefix are not valid', () {
      expect(vault.isValidKey('firstTimeOpenApp'), isFalse);
      expect(vault.isValidKey('_internal_master_key'), isFalse);
      expect(vault.isValidKey('_internal_anything'), isFalse);
    });

    test('consumer keys are valid', () {
      expect(vault.isValidKey('token'), isTrue);
      expect(vault.isValidKey('my_internal_flag'), isTrue);
    });

    test('checkKey throws an ArgumentError for a reserved key only', () {
      expect(() => vault.checkKey('_internal_x'), throwsArgumentError);
      expect(() => vault.checkKey('token'), returnsNormally);
    });
  });

  group('master keys', () {
    test('generateKey is a fresh, usable 256-bit base64 key', () {
      final a = EncryptedStorage.generateKey();
      final b = EncryptedStorage.generateKey();

      expect(a, isNot(b));
      expect(base64.decode(a), hasLength(32));
      expect(EncryptedStorage.isUsableKey(a), isTrue);
    });

    test('isUsableKey rejects the wrong length and non-base64', () {
      expect(
        EncryptedStorage.isUsableKey(base64.encode(List.filled(16, 1))),
        isFalse,
      );
      expect(EncryptedStorage.isUsableKey(''), isFalse);
      expect(EncryptedStorage.isUsableKey('not base64 !!'), isFalse);
    });
  });

  group('readKeyWithRetry', () {
    Future<String?> read(FlutterSecureStorage storage) =>
        EncryptedStorage.readKeyWithRetry(
          storage,
          'k',
          retryDelay: Duration.zero,
          tag: 'test',
        );

    test('returns the stored value on the first try', () async {
      final storage = _FlakyRead(failures: 0, value: 'abc');

      expect(await read(storage), 'abc');
      expect(storage.calls, 1);
    });

    test('a missing key is null, not an error', () async {
      expect(await read(_FlakyRead(failures: 0)), isNull);
    });

    test('retries a platform failure until it succeeds', () async {
      final storage = _FlakyRead(failures: 2, value: 'abc');

      expect(await read(storage), 'abc');
      expect(storage.calls, 3);
    });

    test('rethrows the last error once the attempts run out', () async {
      final storage = _FlakyRead(failures: 100, value: 'abc');

      await expectLater(read(storage), throwsA(isA<PlatformException>()));
      expect(storage.calls, StorageConstants.MASTER_KEY_READ_ATTEMPTS);
    });
  });
}
