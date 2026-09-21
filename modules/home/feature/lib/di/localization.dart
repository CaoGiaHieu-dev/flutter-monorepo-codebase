import 'package:core_di/core_di.dart';
import 'package:flutter/widgets.dart';
import 'package:injectable/injectable.dart';

import '../feature_home.dart';

@Injectable(as: IFeatureLocalization)
class HomeLocalizationImpl implements IFeatureLocalization {
  @override
  LocalizationsDelegate<dynamic> get delegate =>
      FeatureHomeLocalizations.delegate;
}
