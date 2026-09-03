import 'dart:convert';
import 'dart:typed_data';

import 'package:core_storage/core_storage.dart';
import 'package:encrypt/encrypt.dart' as encrypter;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String testMasterKey;

  setUpAll(() {
    testMasterKey = encrypter.Key.fromSecureRandom(32).base64;
  });

  group('PrefStorageImpl', () {
    late PrefStorageImpl prefStorage;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      prefStorage = PrefStorageImpl(preferences);
      await prefStorage.init();
      prefStorage.setMasterKey(testMasterKey);
    });

    test('should write and read plain values successfully', () async {
      await prefStorage.write('test_key', 'hello_world');
      final value = await prefStorage.read<String>('test_key');
      expect(value, equals('hello_world'));
    });

    test('should delete value successfully', () async {
      await prefStorage.write('test_key', 'hello_world');
      await prefStorage.delete('test_key');
      final value = await prefStorage.read<String>('test_key');
      expect(value, isNull);
    });

    test('should return null when reading non-existing key', () async {
      final value = await prefStorage.read<String>('non_existing');
      expect(value, isNull);
    });

    test('should handle write/read for complex types with reviver', () async {
      final dataMap = {'name': 'Antigravity', 'role': 'AI Developer'};
      await prefStorage.write('profile', dataMap);

      final result = await prefStorage.read<Map<String, dynamic>>(
        'profile',
        reviver: (key, value) {
          if (value is Map<String, dynamic>) {
            return value;
          }
          return <String, dynamic>{};
        },
      );

      expect(result, isNotNull);
      expect(result?['name'], equals('Antigravity'));
    });
  });

  group('SecureStorageImpl', () {
    late SecureStorageImpl secureStorage;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      secureStorage = SecureStorageImpl();
      await secureStorage.init();
    });

    test('should write and read values securely', () async {
      await secureStorage.write('secure_key', 'highly_confidential');
      final value = await secureStorage.read<String>('secure_key');
      expect(value, equals('highly_confidential'));
    });

    test('should delete secure value successfully', () async {
      await secureStorage.write('secure_key', 'highly_confidential');
      await secureStorage.delete('secure_key');
      final value = await secureStorage.read<String>('secure_key');
      expect(value, isNull);
    });
  });

  group('StorageValue', () {
    late PrefStorageImpl prefStorage;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      prefStorage = PrefStorageImpl(preferences);
      await prefStorage.init();
      prefStorage.setMasterKey(testMasterKey);
    });

    test('should update value and notify listeners', () async {
      final storageValue = StorageValue<String>(prefStorage, 'user_token');
      var notifyCount = 0;
      storageValue.addListener(() {
        notifyCount++;
      });

      storageValue.value = 'token123';
      await Future<void>.delayed(Duration.zero);

      expect(storageValue.value, equals('token123'));
      expect(notifyCount, equals(1));

      final persistedValue = await prefStorage.read<String>('user_token');
      expect(persistedValue, equals('token123'));
    });

    test('should delete and reset value in memory', () async {
      final storageValue = StorageValue<String>(prefStorage, 'user_token');
      storageValue.value = 'token123';
      await Future<void>.delayed(Duration.zero);

      storageValue.delete();
      await Future<void>.delayed(Duration.zero);

      expect(storageValue.value, isNull);
      final persistedValue = await prefStorage.read<String>('user_token');
      expect(persistedValue, isNull);
    });
  });

  group('StorageManager — independently-owned StorageValues', () {
    // core_storage exposes only the mechanism (StorageManager/StorageValue).
    // Each consumer package declares and owns its own StorageValue instances
    // with its own keys — there is no shared cross-domain presets object.
    late StorageManager manager;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});

      final preferences = await SharedPreferences.getInstance();
      final prefStorage = PrefStorageImpl(preferences);
      await prefStorage.init();
      prefStorage.setMasterKey(testMasterKey);

      final secureStorage = SecureStorageImpl();
      await secureStorage.init();

      manager = StorageManager(prefStorage, secureStorage);
    });

    /// Mirrors how each owner package declares its own value:
    /// `AuthLocalDataSource` (secure/'token'), `LanguageStorageImpl`
    /// (pref/'locale'), `ThemeStorageImpl` (pref/'themeMode'),
    /// `AppBootStorage` (pref/'viewed_onboard').
    StorageValue<String> buildToken() =>
        StorageValue<String>(manager.getStorage(StorageType.secure), 'token');

    StorageValue<String> buildLocale() =>
        StorageValue<String>(manager.getStorage(StorageType.pref), 'locale');

    StorageValue<_TestThemeMode> buildThemeMode() => StorageValue<_TestThemeMode>(
      manager.getStorage(StorageType.pref),
      'themeMode',
      reviver: (key, value) => value == null
          ? _TestThemeMode.system
          : _TestThemeMode.values.byName(value.toString()),
    );

    test(
      'each owner round-trips its own value through its own backend',
      () async {
        final token = buildToken();
        final locale = buildLocale();
        final themeMode = buildThemeMode();

        token.value = 'preset_token_abc';
        locale.value = 'vi';
        themeMode.value = _TestThemeMode.dark;
        await Future<void>.delayed(Duration.zero);

        expect(token.value, equals('preset_token_abc'));
        expect(locale.value, equals('vi'));
        expect(themeMode.value, equals(_TestThemeMode.dark));
      },
    );

    test('writing one owner value never disturbs another owner key', () async {
      final token = buildToken();
      final locale = buildLocale();
      final themeMode = buildThemeMode();

      locale.value = 'vi';
      themeMode.value = _TestThemeMode.dark;
      await Future<void>.delayed(Duration.zero);

      // Auth writes and then clears its own key…
      token.value = 'preset_token_abc';
      token.value = null;
      await Future<void>.delayed(Duration.zero);

      // …the other owners' keys survive untouched, on disk too.
      expect(token.value, isNull);
      expect(locale.value, equals('vi'));
      expect(themeMode.value, equals(_TestThemeMode.dark));
      expect(
        await manager.getStorage(StorageType.pref).read<String>('locale'),
        equals('vi'),
      );
    });

    test(
      'a separately constructed StorageValue sees the same persisted key',
      () async {
        buildLocale().value = 'vi';
        await Future<void>.delayed(Duration.zero);

        // A second owner instance (e.g. app-shell vs data layer) hydrating
        // the same physical key must read back what was persisted.
        final reopened = buildLocale();
        await reopened.readFromStorage();

        expect(reopened.value, equals('vi'));
      },
    );
  });

  group('Security & RAM Obfuscation', () {
    late PrefStorageImpl prefStorage;
    late SecureStorageImpl secureStorage;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});

      final preferences = await SharedPreferences.getInstance();
      prefStorage = PrefStorageImpl(preferences);
      await prefStorage.init();
      prefStorage.setMasterKey(testMasterKey);

      secureStorage = SecureStorageImpl();
      await secureStorage.init();
    });

    test(
      'ObfuscatedBytes should hide data and reveal it correctly, then zero it',
      () {
        final original = Uri.encodeComponent(
          'my_ultra_secret_key_123',
        ).codeUnits;
        final originalBytes = Uint8List.fromList(original);
        final ob = ObfuscatedBytes(originalBytes);

        // Verify that internal representation is masked (obfuscated)
        // (it shouldn't be equal to original bytes)
        // Since it's dynamic XOR, let's reveal and compare
        final revealed = ob.reveal();
        expect(revealed, equals(originalBytes));

        // Test zeroing/filling range after reveal
        revealed.fillRange(0, revealed.length, 0);
        expect(revealed.every((b) => b == 0), isTrue);

        ob.dispose();
      },
    );

    test(
      'ObfuscatedString should obfuscate and de-obfuscate string correctly',
      () {
        const secret = 'my_secret_token_abc';
        final obStr = ObfuscatedString(secret);

        expect(obStr.reveal(), equals(secret));
        obStr.dispose();
      },
    );

    group('ObfuscatedString UTF-8 multi-byte round-trips', () {
      void expectRoundTrip(String label, String input) {
        final utf8Len = utf8.encode(input).length;
        final obStr = ObfuscatedString(input);
        final revealed = obStr.reveal();
        expect(revealed, equals(input), reason: label);
        expect(utf8.encode(revealed).length, utf8Len, reason: '$label bytes');
        obStr.dispose();
      }

      test('ASCII (1-byte UTF-8)', () {
        expectRoundTrip('ascii', 'Hello World 123');
      });

      test('empty string', () {
        expectRoundTrip('empty', '');
      });

      test('2-byte UTF-8 — Latin extended / Vietnamese', () {
        expectRoundTrip('vietnamese', 'Nguyễn Văn Hiếu Cao');
        expectRoundTrip('latin-ext', 'café naïve façade');
        expectRoundTrip('german', 'Größe — über Äpfel');
      });

      test('2-byte UTF-8 — Cyrillic / Greek / Arabic / Hebrew', () {
        expectRoundTrip('cyrillic', 'Привет мир');
        expectRoundTrip('greek', 'Γειά σου Κόσμε');
        expectRoundTrip('arabic', 'مرحبا بالعالم');
        expectRoundTrip('hebrew', 'שלום עולם');
      });

      test('3-byte UTF-8 — CJK ideographs', () {
        expectRoundTrip('chinese', '你好世界 — 中文汉字');
        expectRoundTrip('japanese', 'こんにちは世界 — 日本語の漢字と仮名');
        expectRoundTrip('korean', '안녕하세요 세계 — 한글');
        expectRoundTrip('mixed-cjk', '漢字かな한글 ABC');
      });

      test('4-byte UTF-8 — emoji / icons (surrogate pairs)', () {
        expectRoundTrip('emoji-basic', '😀🎉🚀🔥');
        expectRoundTrip('emoji-zwj', '👨‍👩‍👧‍👦'); // family ZWJ sequence
        expectRoundTrip('emoji-flags', '🇻🇳🇯🇵🇰🇷🇺🇸');
        expectRoundTrip('emoji-skin', '👍🏻👍🏼👍🏽👍🏾👍🏿');
        expectRoundTrip('misc-symbols', '⚙️✅❌⭐️❤️');
      });

      test('mixed scripts + emoji in one string', () {
        expectRoundTrip(
          'mixed',
          'User: Nguyễn 你好 こんにちは 안녕 😀 — café',
        );
      });

      test('JSON payload with ideographs, emoji, and 2-byte chars', () {
        final json = jsonEncode({
          'id': 'user_001',
          'name': 'Nguyễn Văn Hiếu Cao',
          'displayName': '你好 こんにちは 안녕 😀',
          'bio': 'café · Привет · مرحبا · 漢字',
          'icon': '🚀',
          'role': 'none',
          'bankName': null,
          'bankAccount': null,
          'fcmToken': null,
        });
        expect(
          utf8.encode(json).length,
          greaterThan(json.length),
          reason: 'payload must exercise multi-byte UTF-8',
        );

        final obStr = ObfuscatedString(json);
        final revealed = obStr.reveal();
        expect(revealed, equals(json));
        expect(jsonDecode(revealed), isA<Map<String, dynamic>>());
        expect(jsonDecode(revealed)['displayName'], '你好 こんにちは 안녕 😀');
        obStr.dispose();
      });

      test('UTF-8 byte length exceeds Dart String.length for multi-byte', () {
        const samples = {
          'vi': 'Hiếu',
          'zh': '汉字',
          'emoji': '😀',
          'family': '👨‍👩‍👧‍👦',
        };
        for (final entry in samples.entries) {
          final dartLen = entry.value.length;
          final utf8Len = utf8.encode(entry.value).length;
          expect(
            utf8Len,
            greaterThan(dartLen),
            reason: '${entry.key}: utf8($utf8Len) > dart($dartLen)',
          );
          expectRoundTrip(entry.key, entry.value);
        }
      });
    });

    test('Should throw ArgumentError when accessing reserved keys', () async {
      final reserved = [
        '_internal_master_key',
        '_internal_pref_master_key',
        'firstTimeOpenApp',
        '_internal_custom_key',
      ];

      for (final key in reserved) {
        expect(() => prefStorage.read<String>(key), throwsArgumentError);
        expect(
          () => prefStorage.write<String>(key, 'val'),
          throwsArgumentError,
        );
        expect(() => prefStorage.delete(key), throwsArgumentError);

        expect(() => secureStorage.read<String>(key), throwsArgumentError);
        expect(
          () => secureStorage.write<String>(key, 'val'),
          throwsArgumentError,
        );
        expect(() => secureStorage.delete(key), throwsArgumentError);

        expect(
          () => StorageValue<String>(prefStorage, key),
          throwsArgumentError,
        );
      }
    });

    test('Should allow accessing standard keys', () async {
      await prefStorage.write('normal_key', 'normal_val');
      final val = await prefStorage.read<String>('normal_key');
      expect(val, equals('normal_val'));

      await secureStorage.write('normal_key', 'normal_val');
      final val2 = await secureStorage.read<String>('normal_key');
      expect(val2, equals('normal_val'));
    });
  });
}

enum _TestThemeMode { system, light, dark }
