import 'package:core_di/core_di.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';

import '../utils/onboarding_path.dart';
import 'onboarding_route_module.dart';

@LazySingleton(as: IFeatureRouteModule)
class OnboardingFeatureRouteModule implements IFeatureRouteModule {
  @override
  List<RouteBase> get routes => [$onboardingRoute];
}

@LazySingleton(as: IAppEntryLocation)
class OnboardingAppEntryLocation implements IAppEntryLocation {
  @override
  String get path => OnboardingPath.ONBOARDING;
}
