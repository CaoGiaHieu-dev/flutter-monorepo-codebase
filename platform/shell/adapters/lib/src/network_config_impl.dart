import 'package:core_base_ui/core_base_ui.dart';
import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:core_network/core_network.dart';
import 'package:core_ui_kit/core_ui_kit.dart';
import 'package:injectable/injectable.dart';
import 'package:material_ui/material_ui.dart';

/// Concrete implementation of NetworkConfig, shared by every app. What differs
/// per app comes from the sections `runShellApp` registers before the graph is
/// built: the certificate pinning decision of each flavor — the app's
/// [SslPinningPolicy] (`flavors.<f>.ssl_pinning` in its manifest) — and the
/// languages it offers, its [LocaleProfile].
///
/// This fulfills dependencies of core_network, using core_ui_kit's
/// `RetryDialog` for the retry prompt — the only reason
/// `platform_shell_adapters` depends on the ui group. `core_network` itself
/// stays free of widgets: it only calls [onRetryCallback].
///
/// Credentials are never read from a shared storage object — this delegates
/// to the actual owners of each value ([ISessionGateway] for the session,
/// [ILanguageStorage] for the locale) so no cross-domain storage key leaks.
///
/// **This file imports no module.** It used to pull `AuthLocalDataSource` and
/// `RefreshTokenUseCase` straight out of `data_auth` / `domain_auth`, which
/// meant a build without the auth module did not compile — the composition
/// root was the one place breaking the removability the rest of the shell is
/// careful to preserve. A `getItOrNull` guard cannot fix that on its own: an
/// unresolved import fails at compile time, before any lookup happens.
/// Enforced now by `arch_check` rule **R10**.
///
/// The gateway is resolved at call time rather than injected, so this class
/// constructs fine whether or not a session owner is in the build, and no
/// module-initialisation ordering matters.
@LazySingleton(as: NetworkConfig)
class NetworkConfigImpl implements NetworkConfig {
  NetworkConfigImpl(
    this._languageStorage, [
    this._pinning = const SslPinningPolicy.none(),
    LocaleProfile locale = const LocaleProfile(),
  ]) : _languages = LanguageSet(locale);

  final ILanguageStorage _languageStorage;
  final SslPinningPolicy _pinning;
  final LanguageSet _languages;

  /// Null in a build that composes no session owner.
  ISessionGateway? get _session => getItOrNull<ISessionGateway>();

  /// Whether a session owner is composed — *without* resolving it.
  ///
  /// `ApiClient` reads [onRefreshToken] while `Dio` is being constructed, and
  /// the gateway's own dependency chain (`IAuthRepository` →
  /// `AuthRemoteDataSource`) needs that same `Dio`. Resolving the gateway
  /// here closed the loop: GetIt threw "Circular dependency detected" and
  /// the app booted to an error screen. The lookup itself stays lazy, inside
  /// the callbacks, which run long after construction.
  bool get _hasSession => getIt.isRegistered<ISessionGateway>();

  @override
  String? Function() get getToken =>
      () => _session?.readToken();

  /// The app's language, resolved like `LanguageProvider` resolves it — a
  /// stored choice, else the app's initial or the device's language when
  /// supported, else the profile's fallback — so the server always gets a
  /// language the app offers.
  @override
  String? Function() get getLocale =>
      () => _languages.resolve(_languageStorage.getLanguage()).languageCode;

  /// Returning null here is load-bearing: `ApiClient` adds
  /// `RefreshTokenInterceptor` **only** when this is non-null. With no auth
  /// module there is no session to renew, so a 401 should fail outright
  /// rather than pass through an interceptor that can never succeed.
  @override
  Future<String?> Function()? get onRefreshToken =>
      _hasSession ? _refreshSession : null;

  @override
  Future<void> Function()? get onRefreshFailed =>
      _hasSession ? _clearSession : null;

  /// Renews the session and hands the transport layer the refreshed token.
  ///
  /// Persisting the new credentials is the gateway's job, not this class's.
  Future<String?> _refreshSession() async => await _session?.refreshToken();

  /// Ends the session after the server refused to renew it.
  ///
  /// Two steps, because they belong to two owners: the gateway drops the
  /// stored credentials, and the session owner drops to signed-out — which is
  /// what `NavigatorWrapperWidget` listens to and routes to login on. Clearing
  /// storage alone changes nothing anyone observes.
  Future<void> _clearSession() async {
    await _session?.clearSession();
    getItOrNull<ISessionState>()?.onSessionLost();
  }

  @override
  void onRetryCallback({
    required VoidCallback onRetry,
    required VoidCallback onCancel,
  }) {
    // No `identity`: `RetryHandler` already keeps one prompt per batch of
    // failed requests, and an identity would drop a prompt raised while the
    // previous one is still animating out — leaving its requests pending.
    // RetryDialog closes itself before calling back.
    AppOverlay.showDialog<void>(
      builder: (context) => RetryDialog(onRetry: onRetry, onCancel: onCancel),
    );
  }

  /// The SPKI SHA-256 pins of the current flavor, as the app's manifest decided
  /// them (`flavors.<f>.ssl_pinning`).
  ///
  /// **Empty means this flavor does not pin** — the decision is `disabled` (its
  /// reason is logged at boot by `AppInitializer`), or the policy is the
  /// hand-built `SslPinningPolicy.none()`. Pins are set in the manifest, never
  /// here: `pins: ["<leaf>", "<backup>"]`, at least two so a certificate
  /// rotation does not lock every installed client out of the API. To read the
  /// pin for a host:
  /// ```sh
  /// openssl s_client -servername <host> -connect <host>:443 </dev/null \
  ///   | openssl x509 -pubkey -noout \
  ///   | openssl pkey -pubin -outform der \
  ///   | openssl dgst -sha256 -binary \
  ///   | openssl enc -base64
  /// ```
  @override
  List<String> get sslPinningHashes => _pinning.hashesFor(AppConfig.appFlavor);
}
