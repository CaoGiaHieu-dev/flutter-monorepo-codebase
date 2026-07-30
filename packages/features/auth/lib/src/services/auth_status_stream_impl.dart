import 'dart:async';

import 'package:core_di/core_di.dart';
import 'package:domain_auth/domain_auth.dart';
import 'package:injectable/injectable.dart';

/// Implementation of [IAuthStatusStream] provided by `feature_auth`.
/// This implementation uses [StreamController] to expose the agnostic state.
@singleton
class AuthStatusStreamImpl implements IAuthStatusStream {
  final _controller = StreamController<UserEntity?>.broadcast();
  UserEntity? _currentUser;

  @override
  Stream<UserEntity?> get authStatusStream => _controller.stream;

  @override
  UserEntity? get currentUser => _currentUser;

  /// Internal method used by `feature_auth` to update the state.
  void updateAuthStatus(UserEntity? user) {
    _currentUser = user;
    _controller.add(user);
  }
}
