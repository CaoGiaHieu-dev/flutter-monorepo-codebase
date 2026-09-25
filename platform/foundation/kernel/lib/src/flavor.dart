/// Application build flavors/environments.
enum Flavor {
  /// Development environment
  dev,

  /// Staging environment
  staging,

  /// Production environment
  prod;

  /// The flavor's name as `--flavor` and the DI environments spell it.
  String toValue() => name;
}
