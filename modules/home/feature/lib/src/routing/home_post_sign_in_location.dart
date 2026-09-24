import 'package:core_di/core_di.dart';
import 'package:injectable/injectable.dart';

import '../utils/home_path.dart';

/// Tells the app shell where a signed-in user lands: the home tab.
///
/// The shell resolves `IPostSignInLocation` with `getItOrNull` and calls
/// `context.go(path)` itself — at boot with a restored session, and after
/// every sign-in. Without this module it goes to
/// `AppRouter.fallbackLocation` instead.
@LazySingleton(as: IPostSignInLocation)
class HomePostSignInLocation implements IPostSignInLocation {
  @override
  String get path => HomePath.HOME;
}
