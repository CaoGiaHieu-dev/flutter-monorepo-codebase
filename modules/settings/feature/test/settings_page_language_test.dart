import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:feature_settings/feature_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// K14: the language picker lists what the app's `LanguageProvider` offers —
/// the app's `LocaleProfile` — not every language the template ships.
void main() {
  Future<void> openPicker(WidgetTester tester, LocaleProfile profile) async {
    final languages = LanguageProvider(_EnglishStorage(), profile);
    final theme = ThemeProvider(_LightThemeStorage());
    addTearDown(languages.dispose);
    addTearDown(theme.dispose);

    await tester.pumpWidget(
      ResponsiveInit(
        child: Builder(
          builder: (context) => MaterialApp(
            theme: theme.lightTheme(context),
            localizationsDelegates: [
              ...FeatureSettingsLocalizations.localizationsDelegates,
              ...AppLocalizations.localizationsDelegates,
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
    await tester.tap(find.byIcon(Icons.language));
    await tester.pumpAndSettle();
  }

  testWidgets('the default profile offers every shipped language', (
    tester,
  ) async {
    await openPicker(tester, const LocaleProfile());

    expect(find.text('English'), findsWidgets);
    expect(find.text('Tiếng Việt'), findsOneWidget);
  });

  testWidgets('an app that offers English alone lists English alone', (
    tester,
  ) async {
    await openPicker(tester, const LocaleProfile(supported: ['en']));

    expect(find.text('English'), findsOneWidget);
    expect(find.text('Tiếng Việt'), findsNothing);
  });
}

class _EnglishStorage implements ILanguageStorage {
  @override
  Locale getLanguage() => const Locale('en');

  @override
  void saveLanguage(Locale locale) {}
}

class _LightThemeStorage implements IThemeStorage {
  @override
  ThemeMode getThemeMode() => ThemeMode.light;

  @override
  void saveThemeMode(ThemeMode mode) {}
}
