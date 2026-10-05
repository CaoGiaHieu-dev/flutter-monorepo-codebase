import 'dart:async';

import 'package:core_di/core_di.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:injectable/injectable.dart';

/// [ISessionStatusStream] provided by `feature_auth`: the neutral stream other
/// features listen to (home's BLoC), whatever state library the owner uses.
///
/// Registered as the concrete `@singleton`; `AuthDiModule` binds the interface
/// to this same instance, so the owner writes through [updateAuthStatus] and
/// everyone else reads the read-only interface.
@singleton
class AuthStatusStreamImpl implements ISessionStatusStream {
  final _controller = StreamController<SessionPrincipal?>.broadcast();
  SessionPrincipal? _currentUser;

  @override
  Stream<SessionPrincipal?> get sessionStatusStream => _controller.stream;

  @override
  SessionPrincipal? get currentUser => _currentUser;

  /// The one place [UserEntity] is narrowed to the shared [SessionPrincipal],
  /// so the entity can grow without leaking to consumers.
  void updateAuthStatus(UserEntity? user) {
    _currentUser = user == null
        ? null
        : SessionPrincipal(
            id: user.id,
            displayName: user.name,
            email: user.email,
          );
    _controller.add(_currentUser);
  }

  /// GetIt calls it when the singleton is disposed.
  @disposeMethod
  Future<void> dispose() => _controller.close();
}
