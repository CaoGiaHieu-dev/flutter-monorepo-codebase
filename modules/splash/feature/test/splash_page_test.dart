import 'dart:math' as math;

import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_di/core_di.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:feature_splash/feature_splash.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _ThemeStorage implements IThemeStorage {
  _ThemeStorage(this.mode);

  final ThemeMode mode;

  @override
  ThemeMode getThemeMode() => mode;

  @override
  void saveThemeMode(ThemeMode mode) {}
}

/// The splash is shown by `MainScope` before the router exists, so it is
/// pumped here with no `GoRouter`, no `Provider` and no `getIt` — if the page
/// ever reached for one of them these tests would throw.
void main() {
  Future<void> pumpSplash(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    double textScale = 1.0,
    Size window = const Size(375, 812),
    bool dark = false,
  }) async {
    tester.view
      ..physicalSize = window
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final theme = ThemeProvider(
      _ThemeStorage(dark ? ThemeMode.dark : ThemeMode.light),
    );
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ResponsiveInit(
        child: Builder(
          builder: (context) => MaterialApp(
            theme: theme.lightTheme(context),
            darkTheme: theme.darkTheme(context),
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            localizationsDelegates: [
              ...FeatureSplashLocalizations.localizationsDelegates,
              ...AppLocalizations.localizationsDelegates,
              // material_ui reads its own localization types, which have
              // English alone without these (see the shell's AppMaterialWrapper).
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: FeatureSplashLocalizations.supportedLocales,
            locale: locale,
            home: SplashScreenImpl().build(),
          ),
        ),
      ),
    );
    // The spinner never settles, so advance one frame instead of settling.
    await tester.pump();
  }

  FeatureSplashLocalizations l10nOf(WidgetTester tester) =>
      FeatureSplashLocalizations.of(
        tester.element(find.byType(SplashPage)),
      )!;

  testWidgets('SplashScreenImpl hands the shell a SplashPage', (tester) async {
    await pumpSplash(tester);

    expect(find.byType(SplashPage), findsOneWidget);
  });

  testWidgets('shows the app name, tagline, logo and a progress spinner', (
    tester,
  ) async {
    await pumpSplash(tester);
    final l10n = l10nOf(tester);

    expect(find.text(l10n.appName), findsOneWidget);
    expect(find.text(l10n.tagline), findsOneWidget);
    expect(find.byType(FlutterLogo), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('the tagline follows the locale', (tester) async {
    await pumpSplash(tester, locale: const Locale('vi'));
    final vi = l10nOf(tester);

    expect(find.text(vi.tagline), findsOneWidget);

    await pumpSplash(tester);
    final en = l10nOf(tester);

    expect(en.tagline, isNot(vi.tagline));
    expect(find.text(en.tagline), findsOneWidget);
  });

  testWidgets('the logo stays square', (tester) async {
    await pumpSplash(tester, window: const Size(800, 600));

    final size = tester.getSize(find.byType(FlutterLogo));
    expect(size.width, size.height);
    expect(size.width, greaterThan(0));
  });

  testWidgets('lays out at the 2x text-scale cap without overflow', (
    tester,
  ) async {
    await pumpSplash(tester, textScale: 2.0, window: const Size(320, 480));

    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('lays out on a square window with 2x Vietnamese text', (
    tester,
  ) async {
    await pumpSplash(
      tester,
      locale: const Locale('vi'),
      textScale: 2.0,
      window: const Size(400, 400),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  for (final dark in [false, true]) {
    testWidgets('the text and spinner read on the gradient '
        '(${dark ? 'dark' : 'light'})', (tester) async {
      await pumpSplash(tester, dark: dark);
      final l10n = l10nOf(tester);
      final palette = dark
          ? ThemeSystemExtension.dark
          : ThemeSystemExtension.light;

      double contrast(Color a, Color b) {
        final la = a.computeLuminance();
        final lb = b.computeLuminance();
        return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
      }

      final texts = [
        tester.widget<Text>(find.text(l10n.appName)),
        tester.widget<Text>(find.text(l10n.tagline)),
      ];
      final spinner = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      final colours = [
        for (final text in texts) text.style!.color!,
        spinner.color!,
      ];
      // Every stop of the gradient the screen paints, for each colour drawn
      // on it.
      for (final colour in colours) {
        for (final stop in palette.liquidOnboardingColors) {
          expect(contrast(colour, stop), greaterThanOrEqualTo(4.5));
        }
      }
    });
  }

  test('SplashLocalizationImpl publishes the feature delegate', () {
    expect(
      SplashLocalizationImpl().delegate,
      same(FeatureSplashLocalizations.delegate),
    );
  });
}
