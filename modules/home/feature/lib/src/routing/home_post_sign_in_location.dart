import 'package:core_di/core_di.dart';
import 'package:injectable/injectable.dart';

import '../utils/home_path.dart';

/// Where the app shell sends a signed-in user (at boot with a restored session
/// and after every sign-in). Without this module it uses
/// `AppRouter.fallbackLocation`.
@LazySingleton(as: IPostSignInLocation)
class HomePostSignInLocation implements IPostSignInLocation {
  @override
  String get path => HomePath.HOME;
}
