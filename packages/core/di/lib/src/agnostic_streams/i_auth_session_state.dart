import 'dart:async';

import 'package:domain_auth/domain_auth.dart';

import 'auth_session_failure.dart';

/// Everything the app shell needs to drive its boot redirect and react to
/// later sign-in / sign-out, without naming a single `feature_auth` type.
///
/// The shell must decide where a cold start lands (onboarding → login → home)
/// and must follow the user out of the app on logout. Doing that against
/// `AuthProvider` directly meant importing `feature_auth` for the *type* —
/// something `getItOrNull` cannot soften, because an unresolved import fails
/// at compile time, not at lookup time. This contract is the seam.
///
/// Resolve it optionally:
///
/// ```dart
/// final session = getItOrNull<IAuthSessionState>();
/// await session?.ensureInitialized();
/// if (session?.signedInUser == null) { /* go to login */ }
/// ```
///
/// With no auth feature in the build the lookup returns `null`, the shell
/// treats the app as signed out, and boot falls through to whatever entry
/// location is registered.
///
/// ## Relationship to [IAuthStatusStream]
///
/// [IAuthStatusStream] is the *feature-facing* view — other features listen to
/// it to refresh their own data. This interface is the *shell-facing* view: it
/// adds boot sequencing ([ensureInitialized], [hasRestoredSession]) and a
/// failure channel the shell needs for toasts. They are kept separate so a
/// feature that only wants to observe the signed-in user is not handed the
/// shell's boot machinery.
///
/// ## Owner side
///
/// Implemented by the auth feature's global controller and dual-registered via
/// a DI `@module`, the same pattern [IAuthStatusStream] uses.
abstract class IAuthSessionState {
  /// Resolves once the first session restore has finished.
  ///
  /// The shell awaits this before its first redirect so it never routes to
  /// login while a stored session is still being validated.
  Future<void> ensureInitialized();

  /// Whether the first session restore has completed.
  ///
  /// Guards the transition listener: the boot redirect owns the *first*
  /// navigation, so session events before this flips are ignored.
  bool get hasRestoredSession;

  /// The signed-in user, or `null` when signed out.
  UserEntity? get signedInUser;

  /// Emits after every settled session transition; `null` means signed out.
  ///
  /// Broadcast and non-replaying — read [signedInUser] for the value at
  /// subscription time.
  Stream<UserEntity?> get sessionChanges;

  /// Emits whenever a session operation fails, already classified.
  ///
  /// Broadcast. The shell renders these as toasts using global strings.
  Stream<AuthSessionFailure> get sessionFailures;
}
