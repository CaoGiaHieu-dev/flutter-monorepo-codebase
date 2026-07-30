import 'package:core_di/core_di.dart';
import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';

import 'onboarding_route_module.dart';

@Singleton(as: OnboardingNavigator)
class OnboardingNavigatorImpl implements OnboardingNavigator {
  @override
  void toOnboarding(BuildContext context) =>
      const OnboardingRoute().go(context);
}
