/// What the transport layer needs from whichever module owns the session.
///
/// ## Why this exists
///
/// `NetworkConfigImpl` in the app shell used to import `data_auth` and
/// `domain_auth` directly, to read the token from `AuthLocalDataSource` and
/// renew it through `RefreshTokenUseCase`. That made the auth module
/// **not removable** — the shell failed to compile without it — while the
/// template's own rules promised the opposite. A `getItOrNull` guard cannot
/// help there: an unresolved import fails at compile time, long before any
/// lookup runs.
///
/// Three methods, because three are what `NetworkConfig` asks for. It is not a
/// general-purpose auth API: a module needing to *log someone in* has its own
/// contract for that.
///
/// Resolve it with `getItOrNull<IAuthSessionGateway>()`. When no module
/// registers one, requests simply go out unauthenticated and no refresh
/// interceptor is installed — which is the correct behaviour for a build with
/// no auth in it.
abstract class IAuthSessionGateway {
  /// The current bearer token, or null when nobody is signed in.
  ///
  /// Synchronous: the interceptor calls it on every request, so the owner is
  /// expected to serve it from memory rather than touching disk here.
  String? readToken();

  /// Renews the session after a 401 and returns the fresh token.
  ///
  /// Returns null when renewal fails, which is the transport's signal to give
  /// up rather than retry. The implementation is responsible for persisting
  /// the new credentials before returning.
  Future<String?> refreshToken();

  /// Drops the stored session after an unrecoverable refresh failure.
  ///
  /// Navigation is deliberately not part of this: clearing credentials is
  /// enough, because whoever listens to the session state reacts to the
  /// change. Routing from here would need a `BuildContext`, which the
  /// transport layer has no business holding.
  Future<void> clearSession();
}
