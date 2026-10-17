import 'dart:async';

import 'session_failure.dart';
import 'session_principal.dart';

/// Everything the app shell needs to drive its boot redirect and react to
/// later sign-in / sign-out, without naming a single module type.
///
/// The shell must decide where a cold start lands (entry location → sign-in
/// location → post-sign-in location) and must follow the user out of the app
/// on sign-out. Doing that against `AuthProvider` directly meant importing
/// `feature_auth` for the *type* — something `getItOrNull` cannot soften,
/// because an unresolved import fails at compile time, not at lookup time.
/// This contract is the seam; *where* each case lands is the business of
/// [ISignInLocation] / [IPostSignInLocation].
///
/// Resolve it optionally:
///
/// ```dart
/// final session = getItOrNull<ISessionState>();
/// await session?.ensureInitialized();
/// if (session?.signedInUser == null) { /* go to the sign-in location */ }
/// ```
///
/// With no session owner in the build the lookup returns `null`, the shell
/// treats the app as signed out, and boot falls through to whatever entry
/// location is registered.
///
/// ## Relationship to [ISessionStatusStream]
///
/// [ISessionStatusStream] is the *feature-facing* view — other features listen
/// to it to refresh their own data. This interface is the *shell-facing* view:
/// it adds boot sequencing ([ensureInitialized], [hasRestoredSession]) and a
/// failure channel the shell needs for toasts. They are kept separate so a
/// feature that only wants to observe the signed-in user is not handed the
/// shell's boot machinery.
///
/// ## Owner side
///
/// Implemented by the session owner's global controller (`AuthProvider` in the
/// `auth` sample) and dual-registered via a DI `@module`, the same pattern
/// [ISessionStatusStream] uses.
abstract class ISessionState {
  /// Resolves once the first session restore has finished.
  ///
  /// The shell awaits this before its first redirect so it never routes to
  /// the sign-in location while a stored session is still being validated.
  Future<void> ensureInitialized();

  /// Whether the first session restore has completed.
  ///
  /// Guards the transition listener: the boot redirect owns the *first*
  /// navigation, so session events before this flips are ignored.
  bool get hasRestoredSession;

  /// The signed-in principal, or `null` when signed out.
  SessionPrincipal? get signedInUser;

  /// Emits after every settled session transition; `null` means signed out.
  ///
  /// Broadcast and non-replaying — read [signedInUser] for the value at
  /// subscription time.
  Stream<SessionPrincipal?> get sessionChanges;

  /// Emits whenever a session operation fails, already classified.
  ///
  /// Broadcast. The shell renders these as toasts using global strings.
  Stream<SessionFailure> get sessionFailures;

  /// The transport cleared a session the server refused to renew.
  ///
  /// Clearing stored credentials changes nothing anyone listens to, so the
  /// owner must drop to signed-out here — which emits on [sessionChanges] and
  /// sends the shell to the sign-in location. Without it the user stays on
  /// screen, "signed in", while every request goes out without a token.
  void onSessionLost();
}
