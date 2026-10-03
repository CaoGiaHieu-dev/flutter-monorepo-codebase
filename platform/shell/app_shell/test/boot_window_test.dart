import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:core_responsive/core_responsive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:platform_app_shell/platform_app_shell.dart';

import 'support/boot_harness.dart';
import 'support/profile_fakes.dart';
import 'support/shell_fakes.dart';

const _window = WindowFacts(
  initial: SizeSpec(1280, 800),
  min: SizeSpec(800, 600),
);

/// K12 and the boot wiring of K6/K13 — `platforms.<p>.window` is delivered to
/// `ShellHooks.configureWindow`; a declared window with no hook is `P05`, never
/// a silent no-op; and `profile.display` reaches the tree `runShellApp` builds.
void main() {
  final harness = BootHarness();
  setUp(harness.setUp);
  tearDown(harness.tearDown);

  Future<void> graph() async {
    getIt.enableRegisteringMultipleInstancesOfOneType();
    registerRequiredShell();
    getIt.registerSingleton<IFeatureRouteModule>(aRoute());
  }

  group('a declared window', () {
    testWidgets('with no configureWindow hook stops at P05 before DI', (
      tester,
    ) async {
      var diCalls = 0;

      runShellApp(
        profile: testProfile(
          platforms: {AppPlatform.android: platformFacts(window: _window)},
        ),
        configureDependencies: () async => diCalls++,
      );
      await pumpUntil(
        tester,
        () => find.byType(BootErrorApp).evaluate().isNotEmpty,
      );

      expect(find.textContaining('[P05]'), findsOneWidget);
      expect(find.textContaining('declares a `window`'), findsOneWidget);
      expect(diCalls, 0, reason: 'a declared window is never a silent no-op');
    });

    testWidgets('with a hook is delivered the declared sizes, in order', (
      tester,
    ) async {
      final log = <String>[];
      WindowFacts? delivered;
      AppRuntime? runtime;

      runShellApp(
        profile: testProfile(
          platforms: {AppPlatform.android: platformFacts(window: _window)},
        ),
        hooks: ShellHooks(
          beforeDependencies: (_) async => log.add('beforeDependencies'),
          configureWindow: (rt, window) async {
            log.add('configureWindow');
            runtime = rt;
            delivered = window;
          },
          afterBoot: (_) async => log.add('afterBoot'),
        ),
        configureDependencies: () async {
          log.add('configureDependencies');
          await graph();
        },
      );
      await pumpUntil(tester, () => log.contains('afterBoot'));

      expect(log, [
        'beforeDependencies',
        'configureDependencies',
        'configureWindow',
        'afterBoot',
      ]);
      expect(delivered, same(_window));
      expect(runtime?.platform, AppPlatform.android);
      expect(find.byType(BootErrorApp), findsNothing);

      await settleAndTearDown(tester);
    });

    testWidgets('a platform that declares none never calls the hook', (
      tester,
    ) async {
      var called = false;
      var booted = false;

      runShellApp(
        profile: testProfile(),
        hooks: ShellHooks(
          configureWindow: (_, _) async => called = true,
          afterBoot: (_) async => booted = true,
        ),
        configureDependencies: graph,
      );
      await pumpUntil(tester, () => booted);

      expect(booted, isTrue);
      expect(called, isFalse);

      await settleAndTearDown(tester);
    });
  });

  group('the router hooks reach AppRouter', () {
    testWidgets('the runtime is registered beside the hooks, before DI', (
      tester,
    ) async {
      AppRuntime? seenInDi;
      ShellHooks? hooksInDi;
      var booted = false;
      final hooks = ShellHooks(afterBoot: (_) async => booted = true);

      runShellApp(
        profile: testProfile(),
        hooks: hooks,
        configureDependencies: () async {
          seenInDi = getItOrNull<AppRuntime>();
          hooksInDi = getItOrNull<ShellHooks>();
          await graph();
        },
      );
      await pumpUntil(tester, () => booted);

      expect(seenInDi?.platform, AppPlatform.android);
      expect(seenInDi?.flavor, AppConfig.appFlavor);
      expect(hooksInDi, same(hooks));

      await settleAndTearDown(tester);
    });
  });

  group('the profile\'s display reaches the tree', () {
    Future<double> widthFactorSeen(
      WidgetTester tester, {
      DisplayProfile? display,
    }) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(300, 812);
      addTearDown(tester.view.reset);

      double? w;
      runShellApp(
        profile: testProfile(
          capabilities: declare(provided: const {'tabs'}),
          display: display ?? const DisplayProfile(),
        ),
        configureDependencies: () async {
          getIt.enableRegisteringMultipleInstancesOfOneType();
          registerRequiredShell();
          // The first destination is the router's fallback, so the app opens
          // on it.
          getIt.registerSingleton<INavDestinationModule>(
            FakeDestination(
              path: '/home',
              routes: [
                GoRoute(
                  path: '/home',
                  builder: (context, _) {
                    w = context.w(100);
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
          );
        },
      );
      await pumpUntil(tester, () => w != null);
      await settleAndTearDown(tester);
      return w!;
    }

    testWidgets('the default artboard shrinks to a 300 dp window', (
      tester,
    ) async {
      expect(await widthFactorSeen(tester), closeTo(100 * 300 / 375, 1e-6));
    });

    testWidgets('an app artboard is what runShellApp scales by', (
      tester,
    ) async {
      final w = await widthFactorSeen(
        tester,
        display: const DisplayProfile(designSize: SizeSpec(300, 812)),
      );
      expect(w, 100);
    });
  });
}
