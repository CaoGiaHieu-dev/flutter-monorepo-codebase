import 'package:core_di/core_di.dart';
import 'package:injectable/injectable.dart';

import '../utils/auth_path.dart';

/// Where the shell sends a signed-out user: at boot with no session and
/// whenever the session ends. The shell calls `context.go(path)` itself.
@LazySingleton(as: ISignInLocation)
class AuthSignInLocation implements ISignInLocation {
  @override
  String get path => AuthPath.LOGIN;
}
