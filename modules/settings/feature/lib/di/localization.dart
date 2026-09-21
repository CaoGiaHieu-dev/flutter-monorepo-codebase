import 'package:core_di/core_di.dart';
import 'package:flutter/widgets.dart';
import 'package:injectable/injectable.dart';

import '../feature_settings.dart';

@Injectable(as: IFeatureLocalization)
class SettingsLocalizationImpl implements IFeatureLocalization {
  @override
  LocalizationsDelegate<dynamic> get delegate =>
      FeatureSettingsLocalizations.delegate;
}
