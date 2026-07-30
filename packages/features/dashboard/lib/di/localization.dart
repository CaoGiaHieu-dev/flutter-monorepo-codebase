import 'package:core_di/core_di.dart';
import 'package:flutter/widgets.dart';
import 'package:injectable/injectable.dart';

import '../feature_dashboard.dart';

@Injectable(as: IFeatureLocalization)
class DashboardLocalizationImpl implements IFeatureLocalization {
  @override
  LocalizationsDelegate<dynamic> get delegate =>
      FeatureDashboardLocalizations.delegate;
}
