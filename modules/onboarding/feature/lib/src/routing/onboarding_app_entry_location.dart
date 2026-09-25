import 'package:core_di/core_di.dart';
import 'package:injectable/injectable.dart';

import '../utils/onboarding_path.dart';

/// Tells the app shell where a first launch starts: the onboarding screen.
///
/// The shell resolves `IAppEntryLocation` with `getItOrNull` and shows it
/// once, before any sign-in redirect. Without this module the first launch
/// goes straight to the sign-in check.
@LazySingleton(as: IAppEntryLocation)
class OnboardingAppEntryLocation implements IAppEntryLocation {
  @override
  String get path => OnboardingPath.ONBOARDING;
}
