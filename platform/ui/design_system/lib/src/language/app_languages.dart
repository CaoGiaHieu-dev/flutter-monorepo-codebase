import 'package:material_ui/material_ui.dart';

import '../gen/language/app_localizations.dart';
import 'language_set.dart';

/// Language helpers that do not depend on an app: the template's own
/// [LanguageSet] and the display names.
///
/// The statics answer for the template defaults — every shipped language,
/// `en` as the fallback — **not** for an app's `LocaleProfile`; code that runs
/// inside an app asks the app's set instead (`LanguageProvider.languageSet`),
/// so an app that offers `vi` alone is never shown a language it did not
/// choose. [nameOf] is the same for every app.
///
/// [supported] is generated from the ARB files in `assets/language/`, so
/// adding `ja.arb` adds Japanese here; [nameOf] then needs its display name.
abstract final class AppLanguages {
  static final LanguageSet _template = LanguageSet();

  /// Every locale the template has translations for.
  static List<Locale> get supported => _template.supported;

  /// The template's fallback language, `en`.
  static Locale get fallback => _template.fallback;

  /// [LanguageSet.resolve] for the template's set.
  static Locale resolve(Locale? locale) => _template.resolve(locale);

  /// [locale]'s display name in the current language, or its language tag
  /// when no name is translated for it.
  static String nameOf(Locale locale, AppLocalizations l10n) {
    return switch (locale.languageCode) {
      'en' => l10n.languageEn,
      'vi' => l10n.languageVi,
      _ => locale.toLanguageTag(),
    };
  }
}
