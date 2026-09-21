import 'package:flutter/widgets.dart';

import '../gen/language/app_localizations.dart';

export '../gen/language/app_localizations.dart';

extension ContextOnboardingExtension on BuildContext {
  FeatureOnboardingLocalizations get l10nOnboarding =>
      FeatureOnboardingLocalizations.of(this)!;
}
