import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_di/core_di.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('ThemeSystemExtension', () {
    const light = ThemeSystemExtension.light;
    const dark = ThemeSystemExtension.dark;

    test('copyWith replaces only what it is given', () {
      final copy = light.copyWith(primary: const Color(0xff123456));

      expect(copy.primary, const Color(0xff123456));
      expect(copy.surface, light.surface);
      expect(copy.primaryGradientColors, light.primaryGradientColors);
      expect(light.copyWith().textPrimary, light.textPrimary);
    });

    test('lerp runs from one palette to the other', () {
      expect(light.lerp(dark, 0).primary, light.primary);
      expect(light.lerp(dark, 1).primary, dark.primary);
      expect(light.lerp(null, 0.5), same(light));
    });

    test('the ColorScheme takes every slot from the palette', () {
      for (final (palette, brightness) in [
        (light, Brightness.light),
        (dark, Brightness.dark),
      ]) {
        final scheme = palette.toColorScheme(brightness);
        expect(scheme.brightness, brightness);
        expect(scheme.primary, palette.primary);
        expect(scheme.primaryContainer, palette.primaryContainer);
        expect(scheme.secondary, palette.secondary);
        expect(scheme.surface, palette.surface);
        expect(scheme.onSurface, palette.textPrimary);
        expect(scheme.onSurfaceVariant, palette.textSecondary);
        expect(scheme.outline, palette.border);
        expect(scheme.error, palette.error);
        expect(scheme.scrim, palette.scrim);
        expect(scheme.shadow, palette.shadow);
      }
    });
  });

  testWidgets('ThemeProvider themes agree with the palette', (tester) async {
    final provider = ThemeProvider(_MemoryThemeStorage());
    addTearDown(provider.dispose);
    late ThemeData lightTheme;
    late ThemeData darkTheme;
    await tester.pumpWidget(
      ResponsiveInit(
        child: Builder(
          builder: (context) {
            lightTheme = provider.lightTheme(context);
            darkTheme = provider.darkTheme(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(lightTheme.colorScheme.primary, ThemeSystemExtension.light.primary);
    expect(
      lightTheme.colorScheme.onSurfaceVariant,
      ThemeSystemExtension.light.textSecondary,
    );
    expect(darkTheme.colorScheme.brightness, Brightness.dark);
    expect(darkTheme.colorScheme.surface, ThemeSystemExtension.dark.surface);
    expect(
      darkTheme.extension<ThemeSystemExtension>(),
      ThemeSystemExtension.dark,
    );
  });

  group('AppLanguages.resolve', () {
    test('keeps a supported locale', () {
      expect(AppLanguages.resolve(const Locale('vi')), const Locale('vi'));
    });

    test('matches on the language code', () {
      expect(
        AppLanguages.resolve(const Locale('vi', 'VN')),
        const Locale('vi'),
      );
    });

    test('falls back for an unsupported or missing locale', () {
      expect(AppLanguages.resolve(const Locale('ja')), AppLanguages.fallback);
      expect(AppLanguages.resolve(null), AppLanguages.fallback);
      expect(AppLanguages.supported, contains(AppLanguages.fallback));
    });
  });

  group('LanguageProvider', () {
    test('resolves an unsupported stored locale to the fallback', () async {
      final provider = LanguageProvider(_MemoryLanguageStorage('ja'));
      addTearDown(provider.dispose);
      await provider.setDefaultLanguage();

      expect(provider.locale, AppLanguages.fallback);
    });

    test('persists a new locale and ignores a re-selection', () async {
      final storage = _MemoryLanguageStorage('en');
      final provider = LanguageProvider(storage);
      addTearDown(provider.dispose);
      await provider.setDefaultLanguage();
      var notified = 0;
      provider.addListener(() => notified++);

      provider.setLocale(const Locale('vi'));
      provider.setLocale(const Locale('vi'));

      expect(storage.getLanguage(), const Locale('vi'));
      expect(notified, 1);
    });
  });

  group('GlobalKey.showDropDown', () {
    Future<(GlobalKey, BuildContext)> pumpAnchor(WidgetTester tester) async {
      final key = GlobalKey();
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [ThemeSystemExtension.light]),
          home: ResponsiveInit(
            child: Scaffold(
              body: Builder(
                builder: (c) {
                  context = c;
                  return Center(
                    child: SizedBox(key: key, width: 100, height: 40),
                  );
                },
              ),
            ),
          ),
        ),
      );
      return (key, context);
    }

    testWidgets('returns the picked item and reports it', (tester) async {
      final (key, context) = await pumpAnchor(tester);
      String? reported;

      final future = key.showDropDown<String>(
        context,
        options: const ['one', 'two'],
        onTap: (value) => reported = value,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('two'));
      await tester.pumpAndSettle();

      expect(await future, 'two');
      expect(reported, 'two');
    });

    testWidgets('a dismissed menu returns null and reports nothing', (
      tester,
    ) async {
      final (key, context) = await pumpAnchor(tester);
      var reported = false;

      final future = key.showDropDown<String>(
        context,
        options: const ['one'],
        onTap: (_) => reported = true,
      );
      await tester.pumpAndSettle();
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      expect(await future, isNull);
      expect(reported, isFalse);
    });
  });
}

class _MemoryThemeStorage implements IThemeStorage {
  ThemeMode _mode = ThemeMode.light;

  @override
  ThemeMode getThemeMode() => _mode;

  @override
  void saveThemeMode(ThemeMode mode) => _mode = mode;
}

class _MemoryLanguageStorage implements ILanguageStorage {
  _MemoryLanguageStorage(String code) : _locale = Locale(code);

  Locale _locale;

  @override
  Locale getLanguage() => _locale;

  @override
  void saveLanguage(Locale mode) => _locale = mode;
}
