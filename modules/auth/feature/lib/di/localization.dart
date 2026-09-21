import 'package:core_di/core_di.dart';
import 'package:flutter/widgets.dart';
import 'package:injectable/injectable.dart';

import '../feature_auth.dart';

@Injectable(as: IFeatureLocalization)
class AuthLocalizationImpl implements IFeatureLocalization {
  @override
  LocalizationsDelegate<dynamic> get delegate =>
      FeatureAuthLocalizations.delegate;
}
