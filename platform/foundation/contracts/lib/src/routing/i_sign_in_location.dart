/// Where the app shell sends a signed-out user.
///
/// Used on a cold start with no session (after the entry location, if any, has
/// been shown) and whenever a session ends — sign-out, or the transport losing
/// a session the server refused to renew ([ISessionState.onSessionLost]).
///
/// A plain [path], like [IAppEntryLocation]: the shell calls `context.go(path)`
/// itself, so the contract stays router-neutral and carries no `BuildContext`.
/// It replaces the shell's use of `AuthNavigator`, which tied the platform to
/// one product module's navigation API.
///
/// Contributed by the module that owns sign-in (the `auth` sample's
/// `AuthSignInLocation`). Resolve it with `getItOrNull`: with none registered
/// the shell never redirects to a sign-in screen, which is right for a build
/// with no session owner.
abstract class ISignInLocation {
  String get path;
}
