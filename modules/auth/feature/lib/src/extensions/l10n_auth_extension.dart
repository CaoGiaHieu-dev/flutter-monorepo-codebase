import 'package:flutter/widgets.dart';

import '../gen/language/app_localizations.dart';

export '../gen/language/app_localizations.dart';

extension ContextAuthExtension on BuildContext {
  FeatureAuthLocalizations get l10nAuth => FeatureAuthLocalizations.of(this)!;
}
