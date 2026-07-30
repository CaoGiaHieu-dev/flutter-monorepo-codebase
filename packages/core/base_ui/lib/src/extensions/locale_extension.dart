import 'package:flutter/material.dart';

import '../../core_base_ui.dart';

/// Extension methods for Locale objects
///
/// This extension is currently commented out but provides functionality
/// for getting localized language names.
///
/// Example usage:
/// ```dart
/// Locale locale = Locale('vi');
/// String displayName = locale.languageName(context); // "Tiếng Việt"
/// ```

extension LocaleExtension on Locale {
  /// Returns the localized display name for this locale
  ///
  /// [context] The build context for accessing localization
  /// Returns the localized language name or language tag as fallback
  String languageName(BuildContext context) {
    return switch (languageCode) {
      'vi' => context.l10n.language_vi,
      'en' => context.l10n.language_en,
      _ => toLanguageTag(),
    };
  }
}
