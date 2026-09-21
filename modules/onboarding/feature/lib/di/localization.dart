import 'package:core_di/core_di.dart';
import 'package:flutter/widgets.dart';
import 'package:injectable/injectable.dart';

import '../feature_onboarding.dart';

@Injectable(as: IFeatureLocalization)
class OnboardingLocalizationImpl implements IFeatureLocalization {
  @override
  LocalizationsDelegate<dynamic> get delegate =>
      FeatureOnboardingLocalizations.delegate;
}
