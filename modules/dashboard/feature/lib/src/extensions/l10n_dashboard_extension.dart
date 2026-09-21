import 'package:flutter/widgets.dart';

import '../gen/language/app_localizations.dart';

export '../gen/language/app_localizations.dart';

extension ContextDashboardExtension on BuildContext {
  FeatureDashboardLocalizations get l10nDashboard =>
      FeatureDashboardLocalizations.of(this)!;
}
