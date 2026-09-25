import 'package:core_di/core_di.dart';
import 'package:flutter/widgets.dart';
import 'package:injectable/injectable.dart';

import '../extensions/l10n_onboarding_extension.dart';

/// Hands this feature's translations to the app shell, which collects every
/// `IFeatureLocalization` into `MaterialApp.localizationsDelegates`.
@Injectable(as: IFeatureLocalization)
class OnboardingLocalizationImpl implements IFeatureLocalization {
  @override
  LocalizationsDelegate<dynamic> get delegate =>
      FeatureOnboardingLocalizations.delegate;
}
