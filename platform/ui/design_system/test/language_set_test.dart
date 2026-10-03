import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_di/core_di.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:platform_kernel/platform_kernel.dart';

/// K14: the languages an app offers are its `LocaleProfile` meeting what the
/// template ships. An empty profile is what the template always did.
void main() {
  group('the default profile is what the template did before', () {
    final set = LanguageSet();

    test('every shipped language is supported', () {
      expect(set.supported, AppLocalizations.supportedLocales);
    });

    test('English is the fallback', () {
      expect(set.fallback, const Locale('en'));
    });

    test('a device locale resolves by language code, else to the fallback', () {
      expect(set.resolve(const Locale('vi', 'VN')), const Locale('vi'));
      expect(set.resolve(const Locale('ja')), const Locale('en'));
      expect(set.resolve(null), const Locale('en'));
    });

    test('AppLanguages answers for the template set', () {
      expect(AppLanguages.supported, set.supported);
      expect(AppLanguages.fallback, set.fallback);
      expect(AppLanguages.resolve(const Locale('vi')), const Locale('vi'));
    });
  });

  group('an app value changes the set', () {
    const vietnamese = LocaleProfile(supported: ['vi'], fallback: 'vi');

    test('supported is the profile list, and only that', () {
      final set = LanguageSet(vietnamese);

      expect(set.supported, const [Locale('vi')]);
      expect(set.fallback, const Locale('vi'));
    });

    test('a language outside it resolves to the app fallback', () {
      final set = LanguageSet(vietnamese);

      expect(set.resolve(const Locale('en')), const Locale('vi'));
      expect(set.resolve(null), const Locale('vi'));
    });

    test('the profile order is the picker order', () {
      final set = LanguageSet(
        const LocaleProfile(supported: ['vi', 'en']),
      );

      expect(set.supported, const [Locale('vi'), Locale('en')]);
    });

    test('a code the template does not ship is ignored', () {
      final set = LanguageSet(
        const LocaleProfile(supported: ['xx', 'vi'], fallback: 'vi'),
      );

      expect(set.supported, const [Locale('vi')]);
    });

    test('a language added to the template is offered to an app that names '
        'none', () {
      final set = LanguageSet(const LocaleProfile(), const [
        Locale('en'),
        Locale('vi'),
        Locale('ja'),
      ]);

      expect(set.supported.map((l) => l.languageCode), ['en', 'vi', 'ja']);
      expect(set.resolve(const Locale('ja', 'JP')), const Locale('ja'));
    });
  });

  group('a profile that cannot be honoured is refused', () {
    test('no shipped language is left', () {
      expect(
        () => LanguageSet(const LocaleProfile(supported: ['xx'])),
        throwsArgumentError,
      );
    });

    test('an empty list', () {
      expect(
        () => LanguageSet(const LocaleProfile(supported: [])),
        throwsArgumentError,
      );
    });

    test('a fallback the app does not offer', () {
      expect(
        () => LanguageSet(const LocaleProfile(supported: ['vi'])),
        throwsArgumentError,
      );
    });
  });

  group('LanguageProvider', () {
    const vietnamese = LocaleProfile(supported: ['vi'], fallback: 'vi');

    test('the default profile starts at the fallback, as before', () {
      final provider = LanguageProvider(_MemoryLanguageStorage('en'));
      addTearDown(provider.dispose);

      expect(provider.locale, const Locale('en'));
      expect(provider.languageSet.supported, AppLocalizations.supportedLocales);
    });

    test(
      'a stored language the app does not offer opens in its fallback',
      () async {
        final provider = LanguageProvider(
          _MemoryLanguageStorage('en'),
          vietnamese,
        );
        addTearDown(provider.dispose);
        await provider.setDefaultLanguage();

        expect(provider.locale, const Locale('vi'));
      },
    );

    test('picking a language the app does not offer changes nothing', () async {
      final storage = _MemoryLanguageStorage('vi');
      final provider = LanguageProvider(storage, vietnamese);
      addTearDown(provider.dispose);
      await provider.setDefaultLanguage();
      var notified = 0;
      provider.addListener(() => notified++);

      provider.setLocale(const Locale('en'));

      expect(provider.locale, const Locale('vi'));
      expect(notified, 0);
    });

    test('the settings picker lists the app set, not the template', () {
      final provider = LanguageProvider(
        _MemoryLanguageStorage('vi'),
        vietnamese,
      );
      addTearDown(provider.dispose);

      expect(provider.languageSet.supported, const [Locale('vi')]);
    });
  });
}

class _MemoryLanguageStorage implements ILanguageStorage {
  _MemoryLanguageStorage(String code) : _locale = Locale(code);

  Locale _locale;

  @override
  Locale getLanguage() => _locale;

  @override
  void saveLanguage(Locale mode) => _locale = mode;
}
