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

  Future<FeatureSettingsLocalizations> pumpSettings(
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ResponsiveInit(
        child: Builder(
          builder: (context) => MaterialApp(
            theme: theme.lightTheme(context),
            localizationsDelegates: [
              ...FeatureSettingsLocalizations.localizationsDelegates,
              ...AppLocalizations.localizationsDelegates,
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
    return FeatureSettingsLocalizations.of(
      tester.element(find.byType(SettingsPage)),
    )!;
  }

  testWidgets('the theme row cycles the mode, shows it and saves it', (
    tester,
  ) async {
    final l10n = await pumpSettings(tester);
    expect(find.text(l10n.themeSystem), findsOneWidget);

    await tester.tap(find.text(l10n.changeTheme));
    await tester.pump();

    expect(theme.themeMode, ThemeMode.light);
    expect(find.text(l10n.themeLight), findsOneWidget);
    expect(storage.savedThemes, [ThemeMode.light]);
  });

  testWidgets('picking a language changes the locale and saves it', (
    tester,
  ) async {
    final l10n = await pumpSettings(tester);

    await tester.tap(find.text(l10n.changeLanguage));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tiếng Việt'));
    await tester.pumpAndSettle();

    expect(languages.locale, const Locale('vi'));
    expect(storage.savedLanguages, [const Locale('vi')]);
  });

  testWidgets('the logout row exists only when an auth handler is '
      'registered, and calls it', (tester) async {
    var l10n = await pumpSettings(tester);
    expect(find.text(l10n.logout), findsNothing);

    final auth = _FakeAuthActions();
    getIt.registerSingleton<IAuthActionHandler>(auth);
    await tester.pumpWidget(const SizedBox.shrink());
    l10n = await pumpSettings(tester);
    await tester.tap(find.text(l10n.logout));
    await tester.pumpAndSettle();

    expect(auth.logouts, 1);
  });
}
