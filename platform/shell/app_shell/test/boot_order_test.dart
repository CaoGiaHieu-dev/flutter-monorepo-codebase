import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:platform_app_shell/platform_app_shell.dart';

import 'support/profile_fakes.dart';

/// The pins the test profile decides for every flavor.
const _pinned = SslPinning.pinned(
  'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
  'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=',
);

class _Splash implements IAppSplashScreen {
  @override
  Widget build() => const SizedBox.shrink();
}

/// Stands in for `feature_auth`'s tree wrapper, whose `AuthProvider` starts
/// its session-restore request as soon as the wrapper builds it — on the
/// splash, before `AppInitializer.init` has run.
class _ProbeWrapper extends IAppTreeWrapper {
  final overridesSeen = <HttpOverrides?>[];

  @override
  Widget wrap(BuildContext context, Widget child) {
    overridesSeen.add(HttpOverrides.current);
    return child;
  }
}

/// A contract implementation that is built when `checkAppContract` resolves
/// it — after DI, before the splash — and records which `HttpOverrides` were
/// in force at that moment. A future implementation that opens a connection in
/// its constructor would use whatever this saw.
class _ConstructedProbe implements IAppSplashScreen {
  _ConstructedProbe(this.seen);

  final List<HttpOverrides?> seen;

  @override
  Widget build() => const SizedBox.shrink();
}

/// Dio's `IOHttpClientAdapter` keeps the first `HttpClient` it creates, so
/// certificate pinning has to be the global `HttpOverrides` before any
/// widget — and any controller a widget creates — exists.
void main() {
  late HttpOverrides? testBindingOverrides;
  late bool Function(Object, StackTrace)? platformOnError;

  setUp(() {
    testBindingOverrides = HttpOverrides.current;
    platformOnError = PlatformDispatcher.instance.onError;
    AppInitializer.debugResetBeforeRunApp();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity'),
          (_) async => ['wifi'],
        );
  });

  tearDown(() async {
    HttpOverrides.global = testBindingOverrides;
    // `runShellApp` installs the shell's error hooks; the test binding puts
    // `FlutterError.onError` back itself, these two are ours to restore.
    PlatformDispatcher.instance.onError = platformOnError;
    ErrorHandler.onUnclassifiedError = null;
    AppInitializer.debugResetBeforeRunApp();
    await getIt.reset();
  });

  testWidgets('runShellApp installs pinning before the splash is wrapped', (
    tester,
  ) async {
    final probe = _ProbeWrapper();
    final errors = <Object>[];

    await tester.runAsync(() async {
      runShellApp(
        profile: testProfile(
          capabilities: declare(
            provided: const {'routes', 'splash', 'tree_wrappers'},
          ),
          sslPinning: const SslPinningPolicy({
            Flavor.dev: _pinned,
            Flavor.staging: _pinned,
            Flavor.prod: _pinned,
          }),
        ),
        hooks: ShellHooks(onError: (error, _) => errors.add(error)),
        configureDependencies: () async {
          getIt.enableRegisteringMultipleInstancesOfOneType();
          registerRequiredShell();
          getIt
            ..registerSingleton<IFeatureRouteModule>(aRoute())
            ..registerSingleton<IAppSplashScreen>(_Splash())
            ..registerSingleton<IAppTreeWrapper>(probe);
        },
      );

      // Let the zone reach `runApp(splash)` and build its first frame.
      for (var i = 0; i < 50 && probe.overridesSeen.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }
    });

    expect(probe.overridesSeen, isNotEmpty, reason: 'splash never built');
    expect(
      probe.overridesSeen.first,
      allOf(isNotNull, isNot(same(testBindingOverrides))),
      reason: 'the first IAppTreeWrapper ran before pinning was installed',
    );
    expect(errors, isEmpty);

    // Let MainScope finish initialising so nothing outlives the test.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('pinning is in force before a contract implementation is '
      'constructed, not only before the splash is wrapped', (tester) async {
    final constructedUnder = <HttpOverrides?>[];
    final errors = <Object>[];

    await tester.runAsync(() async {
      runShellApp(
        profile: testProfile(
          capabilities: declare(provided: const {'routes', 'splash'}),
          sslPinning: const SslPinningPolicy({
            Flavor.dev: _pinned,
            Flavor.staging: _pinned,
            Flavor.prod: _pinned,
          }),
        ),
        hooks: ShellHooks(onError: (error, _) => errors.add(error)),
        configureDependencies: () async {
          getIt.enableRegisteringMultipleInstancesOfOneType();
          registerRequiredShell();
          getIt
            ..registerSingleton<IFeatureRouteModule>(aRoute())
            // Lazy: built by `checkAppContract`'s lookup, not by DI.
            ..registerLazySingleton<IAppSplashScreen>(
              () => _ConstructedProbe(
                constructedUnder..add(HttpOverrides.current),
              ),
            );
        },
      );

      for (var i = 0; i < 50 && constructedUnder.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }
    });

    expect(constructedUnder, isNotEmpty, reason: 'never constructed');
    expect(
      constructedUnder.first,
      allOf(isNotNull, isNot(same(testBindingOverrides))),
      reason:
          'a contract implementation was constructed before certificate '
          'pinning was installed',
    );
    expect(errors, isEmpty);

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
