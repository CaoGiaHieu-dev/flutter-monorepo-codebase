import 'dart:async';

import 'package:domain_auth/domain_auth.dart';

/// Neutral, state-management-agnostic view of the current authentication state.
///
/// Features that need to react to login / logout — `feature_home` (BLoC),
/// a Provider-based feature, or anything else — inject this interface and
/// listen to [authStatusStream]. They never import `feature_auth`, and never
/// learn which state management tool it uses.
///
/// ## Why [UserEntity] and not a generic `<T>`
///
/// This interface deliberately exposes the concrete [UserEntity] instead of a
/// generic parameter, so consumers keep full type safety with no casting.
/// Per `.agents/AGENTS.md` §8.4, when a neutral stream carries a domain entity
/// the `core_di` interface **must** name that type explicitly rather than fall
/// back to `<T>` — and `core_di` is *explicitly permitted* to declare a
/// dependency on `domain_*` micro-packages (here `domain_auth`) in its
/// `pubspec.yaml` to do so. `core_di` is the DI Hub, not business logic, so
/// this does not make it a domain layer.
///
/// ## Dual registration (owner side)
///
/// The owning feature registers its implementation twice — see
/// `packages/features/auth/lib/src/services/auth_status_stream_impl.dart`:
///
/// 1. The concrete class is a `@singleton`, so `feature_auth` can inject
///    `AuthStatusStreamImpl` directly and call its writer method
///    (`updateAuthStatus`) without a `getIt` lookup or an `as` cast.
/// 2. A DI `@module` binds this interface to that same instance:
///    ```dart
///    @module
///    abstract class AuthModule {
///      IAuthStatusStream bind(AuthStatusStreamImpl impl) => impl;
///    }
///    ```
///
/// Consumers depend only on [IAuthStatusStream] and stay decoupled.
abstract class IAuthStatusStream {
  /// Emits on every authentication state change; `null` means signed out.
  Stream<UserEntity?> get authStatusStream;

  /// The currently signed-in user, or `null` when signed out.
  ///
  /// Read this for the state at subscription time — [authStatusStream] is a
  /// broadcast stream and does not replay its last value to new listeners.
  UserEntity? get currentUser;
}
