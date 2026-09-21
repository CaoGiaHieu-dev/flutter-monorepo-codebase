import 'package:core_di/core_di.dart';
import 'package:flutter/widgets.dart';
import 'package:injectable/injectable.dart';

import '../feature_splash.dart';

@Injectable(as: IFeatureLocalization)
class SplashLocalizationImpl implements IFeatureLocalization {
  @override
  LocalizationsDelegate<dynamic> get delegate =>
      FeatureSplashLocalizations.delegate;
}
