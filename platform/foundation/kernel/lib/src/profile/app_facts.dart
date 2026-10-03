import '../flavor.dart';
import 'app_platform.dart';
import 'capability_expectation.dart';
import 'env_rule.dart';
import 'platform_facts.dart';
import 'ssl_pinning.dart';

/// What an app *is* and where it runs — the facts `composer` reads from
/// `apps/<id>/app_manifest.yaml` and writes, as const Dart, into the `facts`
/// region of `apps/<id>/lib/app/app_profile.dart`.
///
/// Facts are the part of the declaration a tool must see before any code
/// compiles: identity, flavors, environment keys, platforms and what each one
/// enables, which optional contracts the app provides, and the certificate
/// pinning decision per flavor. How the shell *behaves* is tuning, and lives
/// in `AppProfile`.
final class AppFacts {
  const AppFacts({
    required this.id,
    required this.name,
    required this.flavors,
    required this.platforms,
    required this.sslPinning,
    this.env = const <EnvRule>[],
    this.capabilities = const <String, CapabilityExpectation>{},
  });

  /// The app's package-style id (`mobile`, `admin`) — the folder under `apps/`.
  final String id;

  /// The app's display name.
  final String name;

  /// The flavors the app is built for.
  final Set<Flavor> flavors;

  /// The platforms the app runs on, each with what it enables. A platform
  /// missing here is a platform this app does not run on.
  final Map<AppPlatform, PlatformFacts> platforms;

  /// The environment keys the app reads, and where each is required.
  final List<EnvRule> env;

  /// The app's declaration for every optional contract the shell resolves,
  /// keyed by the catalog id (`SHELL_CONTRACTS`): provided, or absent with a
  /// reason.
  final Map<String, CapabilityExpectation> capabilities;

  /// The certificate pinning decision of each flavor.
  final SslPinningPolicy sslPinning;

  /// What [platform] enables for this app, or `null` when the app does not
  /// declare it.
  PlatformFacts? platformFor(AppPlatform platform) => platforms[platform];
}
