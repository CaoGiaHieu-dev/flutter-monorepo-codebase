import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:platform_app_shell/platform_app_shell.dart';

import 'support/shell_fakes.dart';

/// K14: `AppMaterialWrapper` takes the languages it supports, and the way a
/// device locale resolves, from the app's `LanguageSet` — the one its
/// `LanguageProvider` owns — not from the template's list.
void main() {
  setUp(getIt.enableRegisteringMultipleInstancesOfOneType);
  tearDown(getIt.reset);

  Future<MaterialApp> pumpApp(
    WidgetTester tester,
    LocaleProfile profile, {
    Widget home = const SizedBox.shrink(),
  }) async {
    final router = AppRouter();
    getIt
      ..registerSingleton<ThemeProvider>(ThemeProvider(FakeThemeStorage()))
      ..registerSingleton<LanguageProvider>(
        LanguageProvider(FakeLanguageStorage(), profile),
      )
      ..registerSingleton<AppRouter>(router)
      ..registerSingleton<DeeplinkProvider>(FakeDeeplinkProvider(router));
    await tester.pumpWidget(
      ResponsiveInit(child: AppMaterialWrapper(home: home)),
    );
    await tester.pumpAndSettle();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    return app;
  }

  testWidgets('the default profile supports every shipped language', (
    tester,
  ) async {
    final app = await pumpApp(tester, const LocaleProfile());

    expect(app.supportedLocales, AppLocalizations.supportedLocales);
    expect(
      app.localeResolutionCallback!(const Locale('ja'), const []),
      const Locale('en'),
    );
    expect(
      app.localeResolutionCallback!(const Locale('vi', 'VN'), const []),
      const Locale('vi'),
    );
  });

  testWidgets('an app that offers one language supports that one alone, and '
      'a device locale it does not offer resolves to it', (tester) async {
    final app = await pumpApp(
      tester,
      const LocaleProfile(supported: ['en']),
    );

    expect(app.supportedLocales, const [Locale('en')]);
    expect(
      app.localeResolutionCallback!(const Locale('vi', 'VN'), const []),
      const Locale('en'),
    );
  });

  testWidgets('a Vietnamese app gets Vietnamese Material strings, not a '
      'missing-delegate error', (tester) async {
    String? ok;
    await pumpApp(
      tester,
      const LocaleProfile(supported: ['vi'], fallback: 'vi'),
      home: Builder(
        builder: (context) {
          ok = MaterialLocalizations.of(context).okButtonLabel;
          return const SizedBox.shrink();
        },
      ),
    );

    expect(tester.takeException(), isNull);
    expect(ok, 'OK');
    expect(
      Localizations.localeOf(tester.element(find.byType(SizedBox).first)),
      const Locale('vi'),
    );
  });
}
