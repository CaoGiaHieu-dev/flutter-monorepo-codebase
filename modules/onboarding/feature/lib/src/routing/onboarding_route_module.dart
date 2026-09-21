import 'package:core_common/core_common.dart';
import 'package:core_di/core_di.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../feature_onboarding.dart';

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
