import 'dart:async';

import 'auth_principal.dart';

/// Neutral, state-management-agnostic view of the current authentication state.
///
/// Features that need to react to sign-in / sign-out inject this interface and
/// listen to [authStatusStream]. They never import the auth feature, never
/// learn which state management tool it uses, and never see its domain entity —
/// see [AuthPrincipal] for why the contract carries its own type.
///
/// ## Dual registration (owner side)
///
/// The owning feature registers its implementation twice:
///
/// 1. the concrete class as a `@singleton`, so the feature can inject it
///    directly and call its writer method without a `getIt` lookup or a cast;
/// 2. a DI `@module` binding this interface to that same instance:
///    ```dart
///    @module
///    abstract class AuthModule {
///      IAuthStatusStream bind(AuthStatusStreamImpl impl) => impl;
///    }
///    ```
///
/// Consumers depend only on [IAuthStatusStream] and stay decoupled. Resolve it
/// with `getItOrNull` — the implementer is removable (`arch_check` R8).
abstract class IAuthStatusStream {
  /// Emits on every authentication state change; `null` means signed out.
  Stream<AuthPrincipal?> get authStatusStream;

  /// The currently signed-in principal, or `null` when signed out.
  ///
  /// Read this for the state at subscription time — [authStatusStream] is a
  /// broadcast stream and does not replay its last value to new listeners.
  AuthPrincipal? get currentUser;
}
