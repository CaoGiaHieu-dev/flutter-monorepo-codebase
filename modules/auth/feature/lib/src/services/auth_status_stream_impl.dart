import 'dart:async';

import 'package:core_di/core_di.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:injectable/injectable.dart';

/// Implementation of [ISessionStatusStream] provided by `feature_auth`.
///
/// This is the boundary where the auth feature's own [UserEntity] becomes the
/// shared [SessionPrincipal]. Nothing outside this module sees the entity, so it
/// can grow whatever fields this module needs without a cross-module release,
/// and none of them leak to consumers that only asked who is signed in.
@singleton
class AuthStatusStreamImpl implements ISessionStatusStream {
  final _controller = StreamController<SessionPrincipal?>.broadcast();
  SessionPrincipal? _currentUser;

  @override
  Stream<SessionPrincipal?> get sessionStatusStream => _controller.stream;

  @override
  SessionPrincipal? get currentUser => _currentUser;

  /// Called by `feature_auth` when the session settles.
  void updateAuthStatus(UserEntity? user) {
    final principal = toPrincipal(user);
    _currentUser = principal;
    _controller.add(principal);
  }

  /// The one place `UserEntity` is narrowed for the outside world.
  static SessionPrincipal? toPrincipal(UserEntity? user) {
    if (user == null) return null;
    return SessionPrincipal(
      id: user.id,
      displayName: user.name,
      email: user.email,
      roles: {if (user.role != null) user.role!.name},
    );
  }
}
