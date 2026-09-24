import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:platform_app_shell/platform_app_shell.dart';
import 'package:platform_shell_adapters/platform_shell_adapters.dart';

import 'support/shell_fakes.dart';

/// What `AppMaterialWrapper` resolves for its providers.
void _registerProviders(AppRouter router) {
  getIt
    ..registerSingleton<ThemeProvider>(ThemeProvider(FakeThemeStorage()))
    ..registerSingleton<LanguageProvider>(
      LanguageProvider(FakeLanguageStorage()),
    )
    ..registerSingleton<AppProvider>(AppProvider())
    ..registerSingleton<AppRouter>(router)
    ..registerSingleton<DeeplinkProvider>(FakeDeeplinkProvider(router));
}

/// `AppProvider` starts watching connectivity in its constructor, and the
/// connectivity checker's timer must not outlive the test.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  getIt<AppProvider>().dispose();
  await tester.pump();
}

/// The two app-wide accessibility settings the shell owns: tooltips stay in
/// the semantics tree, and the OS font size is honoured up to a cap.
void main() {
  setUp(getIt.enableRegisteringMultipleInstancesOfOneType);
  tearDown(getIt.reset);

  group('tooltips under the app theme', () {
    Future<void> pumpIconButton(WidgetTester tester) async {
      _registerProviders(AppRouter());
      await tester.pumpWidget(
        ResponsiveInit(
          designSize: AppConfig.design,
          child: AppMaterialWrapper(
            home: Scaffold(
              body: Center(
                child: IconButton(
                  tooltip: 'Show password',
                  icon: const Icon(Icons.visibility),
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('an icon-only button keeps its tooltip as its label', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpIconButton(tester);

      expect(
        tester.getSemantics(find.byType(IconButton)),
        isSemantics(tooltip: 'Show password', isButton: true),
      );
      semantics.dispose();
      await _unmount(tester);
    });

    testWidgets('a long press does not pop the tooltip up', (tester) async {
      await pumpIconButton(tester);

      await tester.longPress(find.byType(IconButton));
      await tester.pumpAndSettle();

      // The bubble is an overlay `Text` with the message.
      expect(find.text('Show password'), findsNothing);
      await _unmount(tester);
    });
  });

  group('text scaling in RootApp', () {
    Future<TextScaler> scalerSeenAt(WidgetTester tester, double osScale) async {
      tester.platformDispatcher.textScaleFactorTestValue = osScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      late TextScaler seen;
      final router = AppRouter();
      _registerProviders(router);
      getIt
        ..registerSingleton<AppBootStorage>(
          memoryBootStorage(viewedOnboard: true),
        )
        ..registerSingleton<HomeNavigator>(NoopHomeNavigator())
        ..registerSingleton<INavDestinationModule>(
          FakeDestination(
            path: '/home',
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, _) {
                  seen = MediaQuery.textScalerOf(context);
                  return const Text('home');
                },
              ),
            ],
          ),
        );

      await tester.pumpWidget(
        ResponsiveInit(designSize: AppConfig.design, child: const RootApp()),
      );
      await tester.pumpAndSettle();
      await _unmount(tester);
      return seen;
    }

    testWidgets('the OS setting passes through below the cap', (tester) async {
      final scaler = await scalerSeenAt(tester, 1.5);
      expect(scaler.scale(10), 15);
    });

    testWidgets('the OS setting is capped at MAX_TEXT_SCALE_FACTOR', (
      tester,
    ) async {
      final scaler = await scalerSeenAt(tester, 3.0);
      expect(scaler.scale(10), 10 * AppShellUiConstants.MAX_TEXT_SCALE_FACTOR);
    });

    testWidgets('the splash MaterialApp is capped too', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 3.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      _registerProviders(AppRouter());

      late TextScaler seen;
      await tester.pumpWidget(
        ResponsiveInit(
          designSize: AppConfig.design,
          child: AppMaterialWrapper(
            home: Builder(
              builder: (context) {
                seen = MediaQuery.textScalerOf(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      await _unmount(tester);

      expect(seen.scale(10), 10 * AppShellUiConstants.MAX_TEXT_SCALE_FACTOR);
    });

    testWidgets('a smaller-than-default setting is honoured too', (
      tester,
    ) async {
      final scaler = await scalerSeenAt(tester, 0.85);
      expect(scaler.scale(10), closeTo(8.5, 1e-9));
    });
  });
}
