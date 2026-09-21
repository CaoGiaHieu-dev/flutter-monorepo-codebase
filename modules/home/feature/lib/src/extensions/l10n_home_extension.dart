import 'package:flutter/widgets.dart';

import '../gen/language/app_localizations.dart';

export '../gen/language/app_localizations.dart';

extension ContextHomeExtension on BuildContext {
  FeatureHomeLocalizations get l10nHome => FeatureHomeLocalizations.of(this)!;
}
