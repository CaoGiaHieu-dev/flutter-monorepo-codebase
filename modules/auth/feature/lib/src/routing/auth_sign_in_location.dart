import 'package:core_di/core_di.dart';
import 'package:injectable/injectable.dart';

import '../utils/auth_path.dart';

/// Tells the app shell where a signed-out user goes: the login screen.
///
/// The shell resolves `ISignInLocation` with `getItOrNull` and calls
/// `context.go(path)` itself — at boot with no session, and whenever the
/// session ends. It used to call `AuthNavigator.toLogin`, which made the
/// platform depend on this module's navigation API.
@LazySingleton(as: ISignInLocation)
class AuthSignInLocation implements ISignInLocation {
  @override
  String get path => AuthPath.LOGIN;
}
