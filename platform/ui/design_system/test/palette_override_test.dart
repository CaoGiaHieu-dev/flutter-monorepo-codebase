import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_di/core_di.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:platform_kernel/platform_kernel.dart';

/// K15: the palette is the template's with the app's `ThemeProfile` applied
/// once, and everything that reads a colour reads that one palette — so
/// `context.colors`, the `ColorScheme`, the gradients and the system bars
/// cannot disagree.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const brand = 0xFF1D4ED8;
  const brandDark = 0xFFF97316;
  const rebrand = ThemeProfile(
    light: {PaletteToken.primary: brand, PaletteToken.background: 0xFFFAFAFA},
    dark: {PaletteToken.primary: brandDark},
  );

  /// Pumps [provider]'s theme for [mode] and reports what `context.colors`
  /// sees, next to the `ThemeData` it was built from.
  Future<(ThemeSystemExtension, ThemeData)> pump(
    WidgetTester tester,
    ThemeProvider provider,
    ThemeMode mode,
  ) async {
    late ThemeData theme;
    late ThemeSystemExtension seen;
    await tester.pumpWidget(
      ResponsiveInit(
        child: Builder(
          builder: (context) {
            theme = mode == ThemeMode.dark
                ? provider.darkTheme(context)
                : provider.lightTheme(context);
            return MaterialApp(
              theme: theme,
              home: Builder(
                builder: (context) {
                  seen = context.colors;
                  return const SizedBox.shrink();
                },
              ),
            );
          },
        ),
      ),
    );
    return (seen, theme);
  }

  group('the default profile is the template palette', () {
    testWidgets('light and dark are the template instances', (tester) async {
      final provider = ThemeProvider(_MemoryThemeStorage());
      addTearDown(provider.dispose);

      final (_, light) = await pump(tester, provider, ThemeMode.light);
      expect(
        light.extension<ThemeSystemExtension>(),
        same(ThemeSystemExtension.light),
      );
      final (_, dark) = await pump(tester, provider, ThemeMode.dark);
      expect(
        dark.extension<ThemeSystemExtension>(),
        same(ThemeSystemExtension.dark),
      );
    });

    test('withOverrides with nothing returns the palette itself', () {
      expect(
        ThemeSystemExtension.light.withOverrides(const {}),
        same(ThemeSystemExtension.light),
      );
    });
  });

  group('a palette override reaches every reader', () {
    testWidgets('context.colors, colorScheme and the gradients agree', (
      tester,
    ) async {
      final provider = ThemeProvider(_MemoryThemeStorage(), rebrand);
      addTearDown(provider.dispose);

      final (colors, theme) = await pump(tester, provider, ThemeMode.light);

      expect(colors.primary, const Color(brand));
      expect(theme.colorScheme.primary, const Color(brand));
      expect(theme.primaryColor, const Color(brand));
      expect(colors.primaryGradientColors, [
        const Color(brand),
        colors.primaryContainer,
      ]);
      expect(colors.liquidOnboardingColors, [
        colors.info,
        colors.primaryContainer,
        colors.error,
      ]);
      expect(theme.scaffoldBackgroundColor, const Color(0xFFFAFAFA));
      expect(theme.colorScheme.surface, colors.surface);
    });

    testWidgets('textPrimary reaches every text style, not only the palette', (
      tester,
    ) async {
      const red = 0xFFFF0000;
      final provider = ThemeProvider(
        _MemoryThemeStorage(),
        const ThemeProfile(
          light: {PaletteToken.textPrimary: red},
          dark: {PaletteToken.textPrimary: red},
        ),
      );
      addTearDown(provider.dispose);

      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        final (colors, theme) = await pump(tester, provider, mode);
        final text = theme.textTheme;

        expect(colors.textPrimary, const Color(red));
        for (final style in [
          text.displayLarge,
          text.headlineMedium,
          text.titleLarge,
          text.titleMedium,
          text.bodyLarge,
          text.bodyMedium,
          text.bodySmall,
          text.labelLarge,
          text.labelSmall,
          theme.appBarTheme.titleTextStyle,
        ]) {
          expect(style?.color, const Color(red), reason: '$mode');
        }
      }
    });

    testWidgets('a token not listed keeps the template value', (tester) async {
      final provider = ThemeProvider(_MemoryThemeStorage(), rebrand);
      addTearDown(provider.dispose);

      final (colors, _) = await pump(tester, provider, ThemeMode.light);

      expect(colors.secondary, ThemeSystemExtension.light.secondary);
      expect(colors.textPrimary, ThemeSystemExtension.light.textPrimary);
    });

    testWidgets('light and dark are overridden independently', (tester) async {
      final provider = ThemeProvider(_MemoryThemeStorage(), rebrand);
      addTearDown(provider.dispose);

      final (dark, darkTheme) = await pump(tester, provider, ThemeMode.dark);

      expect(dark.primary, const Color(brandDark));
      expect(darkTheme.colorScheme.primary, const Color(brandDark));
      expect(dark.background, ThemeSystemExtension.dark.background);
    });

    testWidgets('shadow and scrim stay the template\'s', (tester) async {
      final provider = ThemeProvider(_MemoryThemeStorage(), rebrand);
      addTearDown(provider.dispose);

      final (colors, theme) = await pump(tester, provider, ThemeMode.light);

      expect(colors.shadow, ThemeSystemExtension.light.shadow);
      expect(colors.scrim, ThemeSystemExtension.light.scrim);
      expect(theme.colorScheme.scrim, ThemeSystemExtension.light.scrim);
    });

    test('the system bars are painted in the app palette', () async {
      final provider = ThemeProvider(_MemoryThemeStorage(), rebrand);
      addTearDown(provider.dispose);
      await provider.initialize();

      expect(
        provider.systemUiOverlayStyle.systemNavigationBarColor,
        const Color(0xFFFAFAFA),
      );
      expect(
        provider.paletteFor(Brightness.light).primary,
        const Color(brand),
      );
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
