import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:feature_splash/feature_splash.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The splash is shown by `MainScope` before the router exists, so it is
/// pumped here with no `GoRouter`, no `Provider` and no `getIt` — if the page
/// ever reached for one of them this test would throw.
void main() {
  testWidgets('SplashScreenImpl hands the shell a page with a spinner', (
    tester,
  ) async {
    await tester.pumpWidget(
      ResponsiveInit(child: MaterialApp(home: SplashScreenImpl().build())),
    );

    expect(find.byType(SplashPage), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('the spinner tells a screen reader it is loading', (
    tester,
  ) async {
    await tester.pumpWidget(
      ResponsiveInit(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SplashScreenImpl().build(),
        ),
      ),
    );

    final page = tester.element(find.byType(SplashPage));
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .semanticsLabel,
      AppLocalizations.of(page)!.loading,
    );
  });
}
