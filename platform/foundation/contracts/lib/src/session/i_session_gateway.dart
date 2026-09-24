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
/// general-purpose auth API: a module needing to *log someone in* talks to the
/// session owner through that module's own API package.
///
/// Resolve it with `getItOrNull<ISessionGateway>()`. When no module registers
/// one, requests simply go out unauthenticated and no refresh interceptor is
/// installed — which is the correct behaviour for a build with no session
/// owner in it.
abstract class ISessionGateway {
  /// The current bearer token, or null when nobody is signed in.
  ///
  /// Synchronous: the interceptor calls it on every request, so the owner is
  /// expected to serve it from memory rather than touching disk here.
  String? readToken();

  /// Renews the session after a 401 and returns the fresh token.
  ///
  /// Three outcomes:
  ///
  /// - **a token** — renewed; the implementation has already persisted the
  ///   new credentials.
  /// - **null** — the server **answered and refused**: a 401/403, another
  ///   4xx, or a 200 whose envelope reports an error. The session is over and
  ///   the transport clears it.
  /// - **throws** — renewal got no verdict: no network, a real HTTP 5xx, a
  ///   cancelled request. The session may still be valid, so it is kept and
  ///   only the waiting requests fail.
  ///
  /// Only the throw keeps the session, so an implementation must throw for
  /// nothing but those transient cases. A refusal misread as transient keeps
  /// a dead session forever: every later 401 retries the same renewal.
  Future<String?> refreshToken();

  /// Drops the stored credentials after the server rejected renewal.
  ///
  /// Only the stored credentials: the signed-in *state* is the session
  /// owner's, which the transport tells separately through
  /// [ISessionState.onSessionLost]. Routing is neither's job here — it
  /// would need a `BuildContext`, which the transport has no business holding.
  Future<void> clearSession();
}
