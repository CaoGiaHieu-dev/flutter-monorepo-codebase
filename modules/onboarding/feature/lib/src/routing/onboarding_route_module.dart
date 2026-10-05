import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';
import 'package:material_ui/material_ui.dart';

import '../pages/onboarding_page.dart';
import '../utils/onboarding_path.dart';

part 'onboarding_route_module.g.dart';

@TypedGoRoute<OnboardingRoute>(path: OnboardingPath.ONBOARDING)
class OnboardingRoute extends GoRouteDataCustom with $OnboardingRoute {
  const OnboardingRoute();

  static final $parentNavigatorKey = NavigatorKeys.appKey;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const OnboardingPage();
  }
}

/// Contributes the route to the app shell's router (RULE-20).
@LazySingleton(as: IFeatureRouteModule)
class OnboardingFeatureRouteModule implements IFeatureRouteModule {
  @override
  List<RouteBase> get routes => [$onboardingRoute];
}

/// Where a first launch starts. The shell resolves `IAppEntryLocation` with
/// `getItOrNull` and shows it once, before any sign-in redirect.
@LazySingleton(as: IAppEntryLocation)
class OnboardingAppEntryLocation implements IAppEntryLocation {
  @override
  String get path => OnboardingPath.ONBOARDING;
}
