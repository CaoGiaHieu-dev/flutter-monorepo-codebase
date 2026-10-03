import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:core_network/core_network.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:platform_app_shell/platform_app_shell.dart';
import 'package:platform_shell_adapters/platform_shell_adapters.dart';

import 'shell_fakes.dart';

class FakeSplash implements IAppSplashScreen {
  FakeSplash([this.onBuild]);

  final void Function()? onBuild;

  @override
  Widget build() {
    onBuild?.call();
    return const SizedBox.shrink();
  }
}

class FakeReporter implements IErrorReporter {
  final recorded = <({Object error, bool fatal})>[];

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
    String? reason,
  }) async => recorded.add((error: error, fatal: fatal));

  @override
  void log(String message) {}
}

class FakeTreeWrapper extends IAppTreeWrapper {
  @override
  Widget wrap(BuildContext context, Widget child) => child;
}

/// What a platform declares in these tests: the template's own behaviour,
/// with the splash chosen per test.
PlatformFacts platformFacts({
  SplashMode splash = SplashMode.dart,
  WindowFacts? window,
}) => PlatformFacts(
  runner: RunnerKind.committed,
  splash: splash,
  orientation: OrientationPolicy.phonesPortrait,
  deepLinks: true,
  push: true,
  window: window,
);

/// The `capabilities:` declaration for every optional catalog row: the ids in
/// [provided] are `provided`, every other one `absent`. [overrides] replace a
/// row, and [omit] leaves one out entirely.
Map<String, CapabilityExpectation> declare({
  Set<String> provided = const {},
  Map<String, CapabilityExpectation> overrides = const {},
  Set<String> omit = const {},
}) => {
  for (final contract in SHELL_CONTRACTS)
    if (contract.need == ShellNeed.optional && !omit.contains(contract.id))
      contract.id:
          overrides[contract.id] ??
          (provided.contains(contract.id)
              ? const CapabilityExpectation.provided()
              : const CapabilityExpectation.absent('not used by this test')),
};

AppProfile testProfile({
  Map<AppPlatform, PlatformFacts>? platforms,
  Map<String, CapabilityExpectation>? capabilities,
  SslPinningPolicy? sslPinning,
  DisplayProfile display = const DisplayProfile(),
}) => AppProfile(
  display: display,
  facts: AppFacts(
    id: 'test_app',
    name: 'Test App',
    flavors: const {Flavor.dev, Flavor.staging, Flavor.prod},
    platforms:
        platforms ??
        {
          AppPlatform.android: platformFacts(),
          AppPlatform.ios: platformFacts(splash: SplashMode.native),
        },
    capabilities: capabilities ?? declare(provided: const {'routes'}),
    sslPinning:
        sslPinning ??
        const SslPinningPolicy({
          Flavor.dev: SslPinning.disabled('test'),
          Flavor.staging: SslPinning.disabled('test'),
          Flavor.prod: SslPinning.disabled('test'),
        }),
  ),
);

/// Registers what the shell's own packages register — the 7 required rows —
/// plus the [DioFailureClassifier] hook `core_network` installs, in
/// [getIt]. [skip] leaves some out, by catalog id.
///
/// Needs `getIt.enableRegisteringMultipleInstancesOfOneType()`, like the
/// generated `configureDependencies`.
AppRouter registerRequiredShell({Set<String> skip = const {}}) {
  final router = AppRouter();
  void register<T extends Object>(String id, T Function() create) {
    if (!skip.contains(id)) getIt.registerSingleton<T>(create());
  }

  register<ILanguageStorage>('language_storage', FakeLanguageStorage.new);
  register<IThemeStorage>('theme_storage', FakeThemeStorage.new);
  register<AppBootStorage>('boot_storage', memoryBootStorage);
  register<AppRouter>('app_router', () => router);
  register<DeeplinkProvider>(
    'deeplink_provider',
    () => FakeDeeplinkProvider(router),
  );
  register<ThemeProvider>(
    'theme_provider',
    () => ThemeProvider(FakeThemeStorage()),
  );
  register<LanguageProvider>(
    'language_provider',
    () => LanguageProvider(FakeLanguageStorage()),
  );
  DioFailureClassifier.ensureRegistered();
  return router;
}

/// A route a feature contributes, so the app has a screen.
FakeFeatureRoutes aRoute([String path = '/home']) => FakeFeatureRoutes([
  GoRoute(path: path, builder: (_, _) => const SizedBox.shrink()),
]);
