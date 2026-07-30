import 'package:flutter/widgets.dart';

import '../gen/language/app_localizations.dart';

export '../gen/language/app_localizations.dart';

extension ContextSplashExtension on BuildContext {
  FeatureSplashLocalizations get l10nSplash =>
      FeatureSplashLocalizations.of(this)!;
}
