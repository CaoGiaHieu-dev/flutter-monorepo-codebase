import 'package:material_ui/material_ui.dart';

import '../language/app_languages.dart';
import 'context_extension.dart';

/// Display helpers for a [Locale].
extension LocaleExtension on Locale {
  /// This locale's name in the current language (`Tiếng Việt`, `English`);
  /// see [AppLanguages.nameOf].
  String languageName(BuildContext context) =>
      AppLanguages.nameOf(this, context.l10n);
}
