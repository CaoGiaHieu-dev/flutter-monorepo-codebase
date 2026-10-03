import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:core_storage/core_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:platform_shell_adapters/platform_shell_adapters.dart';

/// K14 and K15: what a first launch opens in, and the language the server is
/// told, come from the app's `LocaleProfile` and `ThemeProfile`. With an empty
/// profile each is what the adapter did before (`adapters_test.dart`).
void main() {
  const vietnamese = LocaleProfile(supported: ['vi'], fallback: 'vi');

  group('NetworkConfigImpl.getLocale follows the LocaleProfile', () {
    NetworkConfigImpl config(ILanguageStorage storage, LocaleProfile locale) =>
        NetworkConfigImpl(storage, const SslPinningPolicy.none(), locale);

    test('a language the app does not offer is sent as its fallback', () async {
      final storage = await _languageStorage();
      storage.saveLanguage(const Locale('en'));

      expect(config(storage, vietnamese).getLocale(), 'vi');
    });

    test('an offered language is sent as it is', () async {
      final storage = await _languageStorage();
      storage.saveLanguage(const Locale('vi'));

      expect(
        config(storage, const LocaleProfile()).getLocale(),
        'vi',
      );
    });

    test('the default profile still falls back to English', () async {
      final storage = await _languageStorage();
      storage.saveLanguage(const Locale('ja'));

      expect(config(storage, const LocaleProfile()).getLocale(), 'en');
    });
  });

  group('LanguageStorageImpl opens in the profile\'s initial language', () {
    test('when nothing is stored', () async {
      final storage = await _languageStorage(
        profile: const LocaleProfile(initial: 'vi'),
      );

      expect(storage.getLanguage(), const Locale('vi'));
    });

    test('but a language the user chose wins', () async {
      final backend = _MemoryStorage();
      final first = await _languageStorage(backend: backend);
      first.saveLanguage(const Locale('en'));
      await _settle();

      final reopened = await _languageStorage(
        backend: backend,
        profile: const LocaleProfile(initial: 'vi'),
      );
      expect(reopened.getLanguage(), const Locale('en'));
    });

    test('with no initial language it is the device\'s, as before', () async {
      final storage = await _languageStorage();

      expect(storage.getLanguage(), AppConfig.defaultLanguage);
    });
  });

  group('ThemeStorageImpl opens in the profile\'s mode', () {
    Future<ThemeStorageImpl> storage(
      ThemeProfile profile, [
      StorageInterface? backend,
    ]) async {
      final impl = ThemeStorageImpl(
        StorageManager(
          backend ?? _MemoryStorage(),
          backend ?? _MemoryStorage(),
        ),
        profile,
      );
      await impl.initialize();
      return impl;
    }

    test('dark, until the user picks one', () async {
      final impl = await storage(
        const ThemeProfile(mode: ThemeModeSetting.dark),
      );

      expect(impl.getThemeMode(), ThemeMode.dark);
    });

    test('light', () async {
      final impl = await storage(
        const ThemeProfile(mode: ThemeModeSetting.light),
      );

      expect(impl.getThemeMode(), ThemeMode.light);
    });

    test('the default profile is the system mode, as before', () async {
      final impl = await storage(const ThemeProfile());

      expect(impl.getThemeMode(), ThemeMode.system);
    });

    test('a mode the user chose wins', () async {
      final backend = _MemoryStorage();
      final first = await storage(const ThemeProfile(), backend);
      first.saveThemeMode(ThemeMode.light);
      await _settle();

      final reopened = await storage(
        const ThemeProfile(mode: ThemeModeSetting.dark),
        backend,
      );
      expect(reopened.getThemeMode(), ThemeMode.light);
    });
  });
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

Future<LanguageStorageImpl> _languageStorage({
  StorageInterface? backend,
  LocaleProfile profile = const LocaleProfile(),
}) async {
  final store = backend ?? _MemoryStorage();
  final storage = LanguageStorageImpl(StorageManager(store, store), profile);
  await storage.initialize();
  return storage;
}

/// A key-value backend held in memory, encoding like the real backends.
class _MemoryStorage implements StorageInterface {
  final _values = <String, String>{};

  @override
  Future<void> init() async {}

  @override
  bool isValidKey(String key) => true;

  @override
  Future<T?> read<T>(
    String key, {
    T Function(Object? key, Object? value)? reviver,
  }) async {
    final json = _values[key];
    return json == null
        ? null
        : StorageCodec.decode<T>(json, key, reviver: reviver);
  }

  @override
  Future<void> write<T>(String key, T? value) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = StorageCodec.encode(value);
    }
  }

  @override
  Future<void> delete(String key) async => _values.remove(key);
}
