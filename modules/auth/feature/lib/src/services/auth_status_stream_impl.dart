import 'dart:async';

import 'package:core_di/core_di.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:injectable/injectable.dart';

/// Implementation of [IAuthStatusStream] provided by `feature_auth`.
///
/// This is the boundary where the auth feature's own [UserEntity] becomes the
/// shared [AuthPrincipal]. Nothing outside this package sees the entity, so
/// fields like `bankAccount` and `fcmToken` stay where they belong and the
/// entity can change shape without a cross-module release.
@singleton
class AuthStatusStreamImpl implements IAuthStatusStream {
  final _controller = StreamController<AuthPrincipal?>.broadcast();
  AuthPrincipal? _currentUser;

  @override
  Stream<AuthPrincipal?> get authStatusStream => _controller.stream;

  @override
  AuthPrincipal? get currentUser => _currentUser;

  /// Called by `feature_auth` when the session settles.
  void updateAuthStatus(UserEntity? user) {
    final principal = toPrincipal(user);
    _currentUser = principal;
    _controller.add(principal);
  }

  /// The one place `UserEntity` is narrowed for the outside world.
  static AuthPrincipal? toPrincipal(UserEntity? user) {
    if (user == null) return null;
    return AuthPrincipal(
      id: user.id,
      displayName: user.name,
      email: user.email,
      roles: {if (user.role != null) user.role!.name},
    );
  }
}
