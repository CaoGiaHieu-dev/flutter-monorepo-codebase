/// The certificate pins `AppInitializer` installs through `HttpOverrides`.
///
/// Declared in the kernel rather than `core_di`: `core_network`'s
/// `NetworkConfig` implements it, and `core_network` depends on the kernel,
/// not on `core_di`.
abstract class SslPinningConfig {
  List<String> get sslPinningHashes;
}
