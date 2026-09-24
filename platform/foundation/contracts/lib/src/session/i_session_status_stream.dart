import 'dart:async';

import 'session_principal.dart';

/// Neutral, state-management-agnostic view of the current session.
///
/// Features that need to react to sign-in / sign-out inject this interface and
/// listen to [sessionStatusStream]. They never import the module that owns the
/// session, never learn which state management tool it uses, and never see its
/// domain entity — see [SessionPrincipal] for why the contract carries its own
/// type.
///
/// ## Dual registration (owner side)
///
/// The owning module registers its implementation twice:
///
/// 1. the concrete class as a `@singleton`, so the module can inject it
///    directly and call its writer method without a `getIt` lookup or a cast;
/// 2. a DI `@module` binding this interface to that same instance:
///    ```dart
///    @module
///    abstract class AuthModule {
///      ISessionStatusStream bind(AuthStatusStreamImpl impl) => impl;
///    }
///    ```
///
/// Consumers depend only on [ISessionStatusStream] and stay decoupled. Resolve
/// it with `getItOrNull` — the implementer is removable (`arch_check` R8).
abstract class ISessionStatusStream {
  /// Emits on every session change; `null` means signed out.
  Stream<SessionPrincipal?> get sessionStatusStream;

  /// The currently signed-in principal, or `null` when signed out.
  ///
  /// Read this for the state at subscription time — [sessionStatusStream] is a
  /// broadcast stream and does not replay its last value to new listeners.
  SessionPrincipal? get currentUser;
}
