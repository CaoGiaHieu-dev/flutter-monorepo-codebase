import 'package:platform_kernel/platform_kernel.dart';

const PlatformFacts androidFacts = PlatformFacts(
  runner: RunnerKind.committed,
  splash: SplashMode.dart,
  orientation: OrientationPolicy.phonesPortrait,
  deepLinks: true,
  push: true,
);

const PlatformFacts iosFacts = PlatformFacts(
  runner: RunnerKind.committed,
  splash: SplashMode.native,
  orientation: OrientationPolicy.phonesPortrait,
  deepLinks: true,
  push: true,
);

const PlatformFacts linuxFacts = PlatformFacts(
  runner: RunnerKind.scaffold,
  splash: SplashMode.native,
  orientation: OrientationPolicy.free,
  deepLinks: true,
  push: false,
);

const PlatformFacts webFacts = PlatformFacts(
  runner: RunnerKind.scaffold,
  splash: SplashMode.native,
  orientation: OrientationPolicy.phonesPortrait,
  deepLinks: true,
  push: false,
);

/// A phone app, like `apps/mobile`: android + ios, three flavors, an explicit
/// pin decision on each flavor.
AppFacts mobileFacts({
  Map<AppPlatform, PlatformFacts> platforms = const {
    AppPlatform.android: androidFacts,
    AppPlatform.ios: iosFacts,
  },
  Set<Flavor> flavors = const {Flavor.dev, Flavor.staging, Flavor.prod},
  List<EnvRule> env = const <EnvRule>[],
  SslPinningPolicy sslPinning = const SslPinningPolicy({
    Flavor.dev: SslPinning.disabled('development flavor'),
    Flavor.staging: SslPinning.disabled('template placeholder'),
    Flavor.prod: SslPinning.disabled('template placeholder'),
  }),
  Map<String, CapabilityExpectation> capabilities =
      const <String, CapabilityExpectation>{},
}) => AppFacts(
  id: 'mobile',
  name: 'Codebase',
  flavors: flavors,
  platforms: platforms,
  env: env,
  capabilities: capabilities,
  sslPinning: sslPinning,
);

AppProfile mobileProfile({
  Map<AppPlatform, PlatformFacts> platforms = const {
    AppPlatform.android: androidFacts,
    AppPlatform.ios: iosFacts,
  },
  Set<Flavor> flavors = const {Flavor.dev, Flavor.staging, Flavor.prod},
  List<EnvRule> env = const <EnvRule>[],
  SslPinningPolicy sslPinning = const SslPinningPolicy({
    Flavor.dev: SslPinning.disabled('development flavor'),
    Flavor.staging: SslPinning.disabled('template placeholder'),
    Flavor.prod: SslPinning.disabled('template placeholder'),
  }),
}) => AppProfile(
  facts: mobileFacts(
    platforms: platforms,
    flavors: flavors,
    env: env,
    sslPinning: sslPinning,
  ),
);
