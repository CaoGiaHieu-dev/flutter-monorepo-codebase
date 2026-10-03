import 'package:platform_kernel/platform_kernel.dart';
import 'package:test/test.dart';

import 'support/profile_fixtures.dart';

/// The sections of K14-K16: what the shell did before an app could say
/// anything is what an empty section says, and each section reaches the
/// profile.
void main() {
  group('LocaleProfile defaults are what the shell did before', () {
    const locale = LocaleProfile();

    test('every shipped language is offered', () {
      expect(locale.supported, isNull);
    });

    test('English is the one fallback', () {
      expect(locale.fallback, 'en');
    });

    test('a first launch opens in the device language', () {
      expect(locale.initial, isNull);
    });
  });

  group('LocaleProfile refuses what it cannot honour', () {
    test('an empty fallback or initial language', () {
      expect(
        () => LocaleProfile(fallback: ''.trim()),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => LocaleProfile(initial: ''.trim()),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('ThemeProfile defaults are what the shell did before', () {
    const theme = ThemeProfile();

    test('the system mode, until the user picks one', () {
      expect(theme.mode, ThemeModeSetting.system);
    });

    test('the template palettes: nothing overridden', () {
      expect(theme.light, isEmpty);
      expect(theme.dark, isEmpty);
    });

    test('every token an app may override is named, shadow and scrim not', () {
      expect(PaletteToken.values, hasLength(17));
      expect(
        PaletteToken.values.map((token) => token.name),
        isNot(anyOf(contains('shadow'), contains('scrim'))),
      );
    });
  });

  group('NetworkProfile defaults are what ApiClient did before', () {
    const network = NetworkProfile();

    test('20 seconds each for connect, receive and send', () {
      expect(network.connectTimeout, const Duration(seconds: 20));
      expect(network.receiveTimeout, const Duration(seconds: 20));
      expect(network.sendTimeout, const Duration(seconds: 20));
    });

    test('no extra header and no followed redirect', () {
      expect(network.headers, isEmpty);
      expect(network.followRedirects, isFalse);
      expect(network.refusedHeaders, isEmpty);
    });
  });

  group('NetworkProfile.refusedHeaders (RULE-66)', () {
    test('names a credential or shell-owned header, whatever its case', () {
      const network = NetworkProfile(
        headers: {
          'Authorization': 'Bearer x',
          'COOKIE': 'a=b',
          'set-cookie': 'a=b',
          'Proxy-Authorization': 'x',
          'Content-Type': 'text/plain',
          'x-client': 'reports',
        },
      );

      expect(network.refusedHeaders, [
        'Authorization',
        'COOKIE',
        'set-cookie',
        'Proxy-Authorization',
        'Content-Type',
      ]);
    });

    test('lets an app header through', () {
      const network = NetworkProfile(headers: {'x-client': 'reports'});

      expect(network.refusedHeaders, isEmpty);
    });
  });

  group('AppProfile carries the sections', () {
    test('an app that sets none is the template', () {
      final profile = mobileProfile();

      expect(profile.locale.supported, isNull);
      expect(profile.theme.mode, ThemeModeSetting.system);
      expect(profile.network.connectTimeout, const Duration(seconds: 20));
    });

    test('an app that sets one is read back', () {
      final profile = AppProfile(
        facts: mobileFacts(),
        locale: const LocaleProfile(supported: ['vi'], fallback: 'vi'),
        theme: const ThemeProfile(
          mode: ThemeModeSetting.dark,
          dark: {PaletteToken.primary: 0xFFF97316},
        ),
        network: const NetworkProfile(connectTimeout: Duration(seconds: 5)),
      );

      expect(profile.locale.fallback, 'vi');
      expect(profile.theme.dark[PaletteToken.primary], 0xFFF97316);
      expect(profile.network.connectTimeout, const Duration(seconds: 5));
    });
  });
}
