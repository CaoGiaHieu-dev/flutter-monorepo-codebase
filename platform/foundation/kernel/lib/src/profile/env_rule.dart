import '../flavor.dart';

/// One `--dart-define` key an app declares, and where it must be set.
///
/// [value] is `String.fromEnvironment(key)` written with a literal key — the
/// generated facts emit it inside a `const`, so the define stays a
/// compile-time constant while the *list* of keys belongs to the app, not to
/// `platform_kernel`.
final class EnvRule {
  const EnvRule({
    required this.key,
    required this.value,
    this.requiredIn = const <Flavor>{},
  });

  /// The define's name, `UPPER_SNAKE` (`BASE_URL`).
  final String key;

  /// What the build defined for [key]; empty when it defined nothing.
  final String value;

  /// The flavors in which an empty [value] stops the boot.
  final Set<Flavor> requiredIn;
}
