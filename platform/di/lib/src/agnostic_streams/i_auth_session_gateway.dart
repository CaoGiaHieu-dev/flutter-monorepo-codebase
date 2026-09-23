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
  /// Returns null when the server **rejected** renewal — the session is over,
  /// and the transport clears it. Throws when renewal could not be attempted
  /// (no network, a 5xx): the session may still be valid, so it is kept and
  /// only the waiting requests fail. The implementation is responsible for
  /// persisting the new credentials before returning.
  Future<String?> refreshToken();

  /// Drops the stored credentials after the server rejected renewal.
  ///
  /// Only the stored credentials: the signed-in *state* is the session
  /// owner's, which the transport tells separately through
  /// [IAuthSessionState.onSessionLost]. Routing is neither's job here — it
  /// would need a `BuildContext`, which the transport has no business holding.
  Future<void> clearSession();
}
