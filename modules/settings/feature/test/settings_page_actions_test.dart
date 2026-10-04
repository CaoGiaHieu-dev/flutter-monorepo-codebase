import 'package:auth_api/auth_api.dart';
import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:feature_settings/feature_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

class _RecordingStorage implements IThemeStorage, ILanguageStorage {
  final savedThemes = <ThemeMode>[];
  final savedLanguages = <Locale>[];

  @override
  ThemeMode getThemeMode() => ThemeMode.system;

  @override
  void saveThemeMode(ThemeMode mode) => savedThemes.add(mode);

  @override
  Locale getLanguage() => const Locale('en');

  @override
  void saveLanguage(Locale locale) => savedLanguages.add(locale);
}

class _FakeAuthActions implements IAuthActionHandler {
  int logouts = 0;

  @override
  Future<void> logout(BuildContext context) async => logouts++;
}

/// What each row of the settings page does when tapped: the theme row cycles
/// the app theme, the language row changes the locale, and the logout row
/// exists only when an auth module registered a handler for it.
void main() {
  late _RecordingStorage storage;
  late ThemeProvider theme;
  late LanguageProvider languages;

  setUp(() {
    storage = _RecordingStorage();
    theme = ThemeProvider(storage);
    languages = LanguageProvider(storage);
  });

  tearDown(() async {
    theme.dispose();
    languages.dispose();
    await getIt.reset();
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      ResponsiveInit(
        child: Builder(
          builder: (context) => MaterialApp(
            theme: theme.lightTheme(context),
            localizationsDelegates: [
              ...FeatureSettingsLocalizations.localizationsDelegates,
              ...AppLocalizations.localizationsDelegates,
              // material_ui reads its own localization types (see the shell's
              // AppMaterialWrapper), which have English alone without these.
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: languages.languageSet.supported,
            locale: const Locale('en'),
            home: MultiProvider(
              providers: [
                ChangeNotifierProvider<LanguageProvider>.value(
                  value: languages,
                ),
                ChangeNotifierProvider<ThemeProvider>.value(value: theme),
              ],
              child: const SettingsPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  FeatureSettingsLocalizations l10nOf(WidgetTester tester) =>
      FeatureSettingsLocalizations.of(
        tester.element(find.byType(SettingsPage)),
      )!;

  testWidgets('the theme row cycles system, light, dark, system', (
    tester,
  ) async {
    await pumpSettings(tester);
    final row = find.text(l10nOf(tester).changeTheme);
    expect(theme.themeMode, ThemeMode.system);

    await tester.tap(row);
    expect(theme.themeMode, ThemeMode.light);
    await tester.tap(row);
    expect(theme.themeMode, ThemeMode.dark);
    await tester.tap(row);
    expect(theme.themeMode, ThemeMode.system);

    expect(storage.savedThemes, [
      ThemeMode.light,
      ThemeMode.dark,
      ThemeMode.system,
    ]);
  });

  testWidgets('picking a language changes the locale and saves it', (
    tester,
  ) async {
    await pumpSettings(tester);
    expect(languages.locale, const Locale('en'));

    await tester.tap(find.text(l10nOf(tester).changeLanguage));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tiếng Việt'));
    await tester.pumpAndSettle();

    expect(languages.locale, const Locale('vi'));
    expect(storage.savedLanguages, [const Locale('vi')]);
  });

  testWidgets('dismissing the language picker changes nothing', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text(l10nOf(tester).changeLanguage));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();

    expect(languages.locale, const Locale('en'));
    expect(storage.savedLanguages, isEmpty);
  });

  testWidgets('without an auth module there is no logout row', (tester) async {
    await pumpSettings(tester);

    expect(find.text(l10nOf(tester).logout), findsNothing);
    expect(find.byIcon(Icons.logout), findsNothing);
  });

  testWidgets('with an auth module the logout row calls its handler', (
    tester,
  ) async {
    final auth = _FakeAuthActions();
    getIt.registerSingleton<IAuthActionHandler>(auth);
    await pumpSettings(tester);

    await tester.tap(find.text(l10nOf(tester).logout));
    await tester.pumpAndSettle();

    expect(auth.logouts, 1);
  });

  test('settings is the second tab, after home, on its own path', () {
    final destination = SettingsNavDestination();

    expect(destination.order, 1);
    expect(destination.path, SettingsPath.SETTINGS);
    expect(const SettingsRoute().location, SettingsPath.SETTINGS);
    expect(destination.routes, hasLength(1));
  });
}
