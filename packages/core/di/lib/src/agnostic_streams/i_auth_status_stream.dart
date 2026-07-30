import 'dart:async';

/// A pure Dart interface for exposing the authentication state neutrally.
/// Features like `feature_home` (using BLoC) or `feature_profile` (using Provider)
/// can inject this interface and listen to [authStatusStream], without needing
/// to depend on `feature_auth` or its specific State Management tool (BLoC/Provider).
///
/// [T] is usually the UserEntity type. We use a generic here so that `core_di`
/// doesn't need to depend on the `domain_auth` package.
import 'package:domain_auth/domain_auth.dart';

abstract class IAuthStatusStream {
  Stream<UserEntity?> get authStatusStream;
  UserEntity? get currentUser;
}
