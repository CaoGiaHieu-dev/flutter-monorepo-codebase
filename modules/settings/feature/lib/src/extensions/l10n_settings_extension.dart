import 'package:flutter/widgets.dart';

import '../gen/language/app_localizations.dart';

export '../gen/language/app_localizations.dart';

extension ContextSettingsExtension on BuildContext {
  FeatureSettingsLocalizations get l10nSettings =>
      FeatureSettingsLocalizations.of(this)!;
}
